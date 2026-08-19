create or replace function public.complete_pos_sale(
  target_store uuid,
  raw_token text,
  table_name text,
  customer_name text,
  guest_count integer,
  lines jsonb,
  payment_method text,
  received_amount integer default null,
  debtor_name text default null,
  receivable_memo text default '',
  due_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  new_check_id uuid;
  selected_table_id uuid;
  next_number bigint;
  subtotal_value integer;
  tax_value integer;
  line jsonb;
  selected_staff_id uuid;
  method_value public.payment_method;
begin
  if not public.validate_pos_session(target_store, raw_token) then
    raise exception 'invalid or expired device session';
  end if;
  if guest_count < 1 or jsonb_typeof(lines) <> 'array' or jsonb_array_length(lines) = 0 then
    raise exception 'invalid check data';
  end if;

  method_value := case payment_method
    when 'cash' then 'cash'::public.payment_method
    when 'qr' then 'qr'::public.payment_method
    when 'receivable' then 'receivable'::public.payment_method
    when 'other' then 'other'::public.payment_method
    else null end;
  if method_value is null then raise exception 'invalid payment method'; end if;

  select id into selected_table_id from public.bar_tables
  where store_id=target_store and name=table_name and enabled limit 1;

  select coalesce(sum(
    greatest(0,(item->>'price')::integer) * greatest(1,(item->>'qty')::integer)
  ),0)::integer into subtotal_value from jsonb_array_elements(lines) item;
  if subtotal_value <= 0 then raise exception 'total must be positive'; end if;
  tax_value := floor(subtotal_value / 11.0);

  select next_check_number into next_number from public.store_settings
  where store_id=target_store for update;
  update public.store_settings set next_check_number=next_check_number+1,updated_at=now()
  where store_id=target_store;

  insert into public.checks(store_id,table_id,check_number,business_date,status,customer_name,guest_count,subtotal,tax_amount,total_amount,paid_at)
  values(target_store,selected_table_id,next_number,public.business_date_for(target_store),'paid',left(coalesce(customer_name,''),120),guest_count,subtotal_value,tax_value,subtotal_value,now())
  returning id into new_check_id;

  for line in select value from jsonb_array_elements(lines)
  loop
    selected_staff_id := null;
    if nullif(trim(line->>'staff'),'') is not null then
      insert into public.staff(store_id,name) values(target_store,left(trim(line->>'staff'),80))
      on conflict(store_id,name) do update set updated_at=now()
      returning id into selected_staff_id;
    end if;
    insert into public.check_lines(check_id,kind,staff_id,product_name,category_name,staff_name,unit_price,tax_rate,quantity)
    values(new_check_id,case when selected_staff_id is null then 'product'::public.line_kind else 'staff_drink'::public.line_kind end,
      selected_staff_id,left(line->>'name',120),left(coalesce(line->>'category','その他'),80),
      case when selected_staff_id is null then null else left(trim(line->>'staff'),80) end,
      greatest(0,(line->>'price')::integer),10,greatest(1,(line->>'qty')::integer));
  end loop;

  insert into public.payments(check_id,method,amount,received_amount,change_amount)
  values(new_check_id,method_value,subtotal_value,
    case when method_value='cash' then greatest(subtotal_value,coalesce(received_amount,subtotal_value)) else null end,
    case when method_value='cash' then greatest(0,coalesce(received_amount,subtotal_value)-subtotal_value) else 0 end);

  if method_value='receivable' then
    if nullif(trim(debtor_name),'') is null then raise exception 'debtor name required'; end if;
    insert into public.receivables(store_id,check_id,debtor_name,amount,memo,due_date)
    values(target_store,new_check_id,left(trim(debtor_name),120),subtotal_value,left(coalesce(receivable_memo,''),500),due_date);
  end if;

  insert into public.audit_logs(store_id,actor_type,actor_id,action,entity_type,entity_id,after_data)
  values(target_store,'device','pos-session','check_paid','check',new_check_id::text,jsonb_build_object('total',subtotal_value,'method',method_value));
  return jsonb_build_object('check_id',new_check_id,'check_number',next_number,'total',subtotal_value);
end;
$$;

revoke all on function public.complete_pos_sale(uuid,text,text,text,integer,jsonb,text,integer,text,text,date) from public;
grant execute on function public.complete_pos_sale(uuid,text,text,text,integer,jsonb,text,integer,text,text,date) to anon, authenticated;

create or replace function public.update_store_pin(target_store uuid,new_pin text,pin_kind text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_store_owner(target_store) then raise exception 'owner authentication required'; end if;
  if new_pin !~ '^[0-9]{4}$' or pin_kind not in ('staff','admin') then raise exception 'PIN must be four digits'; end if;
  update public.store_secrets set
    staff_pin_hash=case when pin_kind='staff' then extensions.crypt(new_pin,extensions.gen_salt('bf',12)) else staff_pin_hash end,
    admin_pin_hash=case when pin_kind='admin' then extensions.crypt(new_pin,extensions.gen_salt('bf',12)) else admin_pin_hash end,
    updated_at=now() where store_id=target_store;
  insert into public.audit_logs(store_id,actor_type,actor_id,action,entity_type,entity_id)
  values(target_store,'owner',auth.uid()::text,'pin_updated','store_secrets',target_store::text);
end;
$$;
