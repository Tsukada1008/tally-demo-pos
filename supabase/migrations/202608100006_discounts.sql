-- Discount preset editor (admin-gated, same shape as other catalog editors)
create or replace function public.update_discount_presets(target_store uuid, items jsonb, admin_token text default null)
returns void language plpgsql security definer set search_path=public as $$
declare item jsonb; keep_names text[]:=array[]::text[]; item_name text; item_kind text;
begin
  if not public.is_store_owner(target_store) and not public.validate_admin_session(target_store,admin_token) then raise exception 'admin authentication required'; end if;
  if jsonb_typeof(items)<>'array' then raise exception 'invalid discount data'; end if;
  for item in select value from jsonb_array_elements(items) loop
    item_name:=left(trim(item->>'name'),80); if item_name='' then continue; end if;
    item_kind:=coalesce(item->>'kind','amount'); if item_kind not in ('amount','percent','service') then item_kind:='amount'; end if;
    keep_names:=array_append(keep_names,item_name);
    insert into public.discount_presets(store_id,name,kind,value,display_order,enabled)
    values(target_store,item_name,item_kind,greatest(0,coalesce((item->>'value')::numeric,0)),array_length(keep_names,1)*10,true)
    on conflict(store_id,name) do update set kind=excluded.kind,value=excluded.value,display_order=excluded.display_order,enabled=true;
  end loop;
  update public.discount_presets set enabled=false where store_id=target_store and not(name=any(keep_names));
  insert into public.audit_logs(store_id,actor_type,actor_id,action,entity_type,after_data) values(target_store,'owner',coalesce(auth.uid()::text,'admin-session'),'catalog_updated','discounts',jsonb_build_object('count',coalesce(array_length(keep_names,1),0)));
end; $$;
revoke all on function public.update_discount_presets(uuid,jsonb,text) from public;
grant execute on function public.update_discount_presets(uuid,jsonb,text) to anon,authenticated;

-- Record which discount (if any) was applied to a check, for receipts/history
alter table public.checks add column if not exists discount_name text;

-- Expose enabled discount presets on the dashboard payload
create or replace function public.get_pos_dashboard(target_store uuid,raw_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb; target_day date;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  target_day:=public.business_date_for(target_store);
  select jsonb_build_object(
    'businessDate',target_day,
    'tables',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'tableNumber',t.table_number,'checkId',oc.id,'guest',oc.customer_name,'people',oc.guest_count,'total',oc.total_amount,'memo',oc.memo,'lines',coalesce((select jsonb_agg(jsonb_build_object('id',cl.id,'name',cl.product_name,'category',cl.category_name,'price',cl.unit_price,'qty',cl.quantity,'staff',cl.staff_name) order by cl.created_at) from public.check_lines cl where cl.check_id=oc.id),'[]'::jsonb)) order by t.display_order),'[]'::jsonb) from public.bar_tables t left join public.checks oc on oc.table_id=t.id and oc.status='open' where t.store_id=target_store and t.enabled),
    'categories',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'color',c.color) order by c.display_order),'[]'::jsonb) from public.categories c where c.store_id=target_store and c.enabled),
    'products',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'category',c.name,'price',p.price,'color',c.color,'staffDrink',p.staff_drink_enabled,'backAmount',p.back_amount) order by c.display_order,p.display_order),'[]'::jsonb) from public.products p join public.categories c on c.id=p.category_id where p.store_id=target_store and p.enabled),
    'staff',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'hourlyWage',s.hourly_wage) order by s.display_order,s.name),'[]'::jsonb) from public.staff s where s.store_id=target_store and s.enabled),
    'onShift',(select coalesce(jsonb_agg(jsonb_build_object('staffName',a.staff_name,'clockIn',a.clock_in,'onBreak',exists(select 1 from public.attendance_breaks b where b.attendance_id=a.id and b.break_end is null)) order by a.clock_in),'[]'::jsonb) from public.attendance_records a where a.store_id=target_store and a.clock_out is null),
    'payrollRounding',(select coalesce(jsonb_build_object('unitMinutes',ss.payroll_round_unit_minutes,'mode',ss.payroll_round_mode),jsonb_build_object('unitMinutes',15,'mode','ceil')) from public.store_settings ss where ss.store_id=target_store),
    'discounts',(select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'kind',d.kind,'value',d.value) order by d.display_order),'[]'::jsonb) from public.discount_presets d where d.store_id=target_store and d.enabled),
    'history',(select coalesce(jsonb_agg(x.item order by x.paid_at desc),'[]'::jsonb) from (select c.paid_at,jsonb_build_object('id',c.id,'number',c.check_number,'table',coalesce(t.name,''),'customer',c.customer_name,'guests',c.guest_count,'total',c.total_amount,'paidAt',c.paid_at,'method',p.method) item from public.checks c left join public.bar_tables t on t.id=c.table_id left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.status='paid' order by c.paid_at desc limit 50)x),
    'summary',(select jsonb_build_object('sales',coalesce(sum(c.total_amount),0),'checks',count(*),'guests',coalesce(sum(c.guest_count),0),'cash',coalesce(sum(c.total_amount) filter(where p.method='cash'),0),'qr',coalesce(sum(c.total_amount) filter(where p.method='qr'),0),'receivable',coalesce(sum(c.total_amount) filter(where p.method='receivable'),0),'other',coalesce(sum(c.total_amount) filter(where p.method='other'),0)) from public.checks c left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.business_date=target_day and c.status='paid')
  ) into result; return result;
end; $$;
revoke all on function public.get_pos_dashboard(uuid,text) from public;
grant execute on function public.get_pos_dashboard(uuid,text) to anon,authenticated;

-- Adding params changes the signature, so `create or replace` would leave the old
-- overload behind as dead/ambiguous code (bit us before with update_pos_catalog) — drop it first.
drop function if exists public.complete_pos_sale(uuid,text,text,text,integer,jsonb,text,integer,text,text,date);
drop function if exists public.complete_saved_pos_sale(uuid,text,text,text,integer,jsonb,text,integer,text,text,date);

-- Apply a discount at checkout (client sends the already-computed yen amount; server clamps it)
create or replace function public.complete_pos_sale(
  target_store uuid, raw_token text, table_name text, customer_name text, guest_count integer,
  lines jsonb, payment_method text, received_amount integer default null, debtor_name text default null,
  receivable_memo text default '', due_date date default null,
  discount_name text default null, discount_amount integer default 0
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  new_check_id uuid; selected_table_id uuid; next_number bigint; subtotal_value integer; discount_value integer; tax_value integer; total_value integer;
  line jsonb; selected_staff_id uuid; method_value public.payment_method;
begin
  if not public.validate_pos_session(target_store, raw_token) then raise exception 'invalid or expired device session'; end if;
  if guest_count < 1 or jsonb_typeof(lines) <> 'array' or jsonb_array_length(lines) = 0 then raise exception 'invalid check data'; end if;
  method_value := case payment_method when 'cash' then 'cash'::public.payment_method when 'qr' then 'qr'::public.payment_method when 'receivable' then 'receivable'::public.payment_method when 'other' then 'other'::public.payment_method else null end;
  if method_value is null then raise exception 'invalid payment method'; end if;
  select id into selected_table_id from public.bar_tables where store_id=target_store and name=table_name and enabled limit 1;
  select coalesce(sum(greatest(0,(item->>'price')::integer) * greatest(1,(item->>'qty')::integer)),0)::integer into subtotal_value from jsonb_array_elements(lines) item;
  if subtotal_value <= 0 then raise exception 'total must be positive'; end if;
  discount_value := least(subtotal_value, greatest(0, coalesce(discount_amount,0)));
  total_value := subtotal_value - discount_value;
  tax_value := floor(total_value / 11.0);
  select next_check_number into next_number from public.store_settings where store_id=target_store for update;
  update public.store_settings set next_check_number=next_check_number+1,updated_at=now() where store_id=target_store;
  insert into public.checks(store_id,table_id,check_number,business_date,status,customer_name,guest_count,subtotal,discount_amount,discount_name,tax_amount,total_amount,paid_at)
  values(target_store,selected_table_id,next_number,public.business_date_for(target_store),'paid',left(coalesce(customer_name,''),120),guest_count,subtotal_value,discount_value,nullif(left(coalesce(discount_name,''),80),''),tax_value,total_value,now())
  returning id into new_check_id;
  for line in select value from jsonb_array_elements(lines) loop
    selected_staff_id := null;
    if nullif(trim(line->>'staff'),'') is not null then
      insert into public.staff(store_id,name) values(target_store,left(trim(line->>'staff'),80)) on conflict(store_id,name) do update set updated_at=now() returning id into selected_staff_id;
    end if;
    insert into public.check_lines(check_id,kind,staff_id,product_name,category_name,staff_name,unit_price,tax_rate,quantity,back_amount)
    values(new_check_id,case when selected_staff_id is null then 'product'::public.line_kind else 'staff_drink'::public.line_kind end,
      selected_staff_id,left(line->>'name',120),left(coalesce(line->>'category','その他'),80),
      case when selected_staff_id is null then null else left(trim(line->>'staff'),80) end,
      greatest(0,(line->>'price')::integer),10,greatest(1,(line->>'qty')::integer),greatest(0,coalesce((line->>'backAmount')::integer,0)));
  end loop;
  insert into public.payments(check_id,method,amount,received_amount,change_amount)
  values(new_check_id,method_value,total_value,
    case when method_value='cash' then greatest(total_value,coalesce(received_amount,total_value)) else null end,
    case when method_value='cash' then greatest(0,coalesce(received_amount,total_value)-total_value) else 0 end);
  if method_value='receivable' then
    if nullif(trim(debtor_name),'') is null then raise exception 'debtor name required'; end if;
    insert into public.receivables(store_id,check_id,debtor_name,amount,memo,due_date)
    values(target_store,new_check_id,left(trim(debtor_name),120),total_value,left(coalesce(receivable_memo,''),500),due_date);
  end if;
  insert into public.audit_logs(store_id,actor_type,actor_id,action,entity_type,entity_id,after_data)
  values(target_store,'device','pos-session','check_paid','check',new_check_id::text,jsonb_build_object('total',total_value,'method',method_value,'discount',discount_value));
  return jsonb_build_object('check_id',new_check_id,'check_number',next_number,'total',total_value);
end;
$$;
revoke all on function public.complete_pos_sale(uuid,text,text,text,integer,jsonb,text,integer,text,text,date,text,integer) from public;
grant execute on function public.complete_pos_sale(uuid,text,text,text,integer,jsonb,text,integer,text,text,date,text,integer) to anon, authenticated;

-- complete_saved_pos_sale wraps complete_pos_sale; pass the discount through
create or replace function public.complete_saved_pos_sale(
  target_store uuid, raw_token text, table_name text, customer_name text, guest_count integer,
  lines jsonb, payment_method text, received_amount integer default null, debtor_name text default null,
  receivable_memo text default '', due_date date default null,
  discount_name text default null, discount_amount integer default 0
) returns jsonb language plpgsql security definer set search_path=public as $$
declare selected_table_id uuid;
begin
  if not public.validate_pos_session(target_store, raw_token) then raise exception 'invalid or expired device session'; end if;
  select id into selected_table_id from public.bar_tables where store_id=target_store and name=table_name and enabled limit 1;
  delete from public.checks where store_id=target_store and table_id=selected_table_id and status='open';
  return public.complete_pos_sale(target_store,raw_token,table_name,customer_name,guest_count,lines,payment_method,received_amount,debtor_name,receivable_memo,due_date,discount_name,discount_amount);
end; $$;
revoke all on function public.complete_saved_pos_sale(uuid,text,text,text,integer,jsonb,text,integer,text,text,date,text,integer) from public;
grant execute on function public.complete_saved_pos_sale(uuid,text,text,text,integer,jsonb,text,integer,text,text,date,text,integer) to anon,authenticated;

-- Receipt detail: include the discount that was applied
create or replace function public.get_pos_check_detail(target_store uuid, raw_token text, target_check uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  select jsonb_build_object(
    'id',c.id,'number',c.check_number,'table',coalesce(t.name,''),'customer',c.customer_name,'guests',c.guest_count,
    'subtotal',c.subtotal,'discountName',c.discount_name,'discountAmount',c.discount_amount,'tax',c.tax_amount,'total',c.total_amount,'status',c.status,'openedAt',c.opened_at,'paidAt',c.paid_at,
    'method',pay.method,'receivedAmount',pay.received_amount,'changeAmount',pay.change_amount,
    'receivable',(select jsonb_build_object('debtorName',r.debtor_name,'dueDate',r.due_date,'memo',r.memo,'status',r.status) from public.receivables r where r.check_id=c.id),
    'lines',(select coalesce(jsonb_agg(jsonb_build_object('name',cl.product_name,'category',cl.category_name,'staff',cl.staff_name,'price',cl.unit_price,'qty',cl.quantity,'backAmount',cl.back_amount) order by cl.created_at),'[]'::jsonb) from public.check_lines cl where cl.check_id=c.id)
  ) into result
  from public.checks c left join public.bar_tables t on t.id=c.table_id left join public.payments pay on pay.check_id=c.id
  where c.id=target_check and c.store_id=target_store;
  if result is null then raise exception 'check not found'; end if;
  return result;
end; $$;
revoke all on function public.get_pos_check_detail(uuid,text,uuid) from public;
grant execute on function public.get_pos_check_detail(uuid,text,uuid) to anon,authenticated;
