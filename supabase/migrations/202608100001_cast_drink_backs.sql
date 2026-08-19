-- Unify "従業員ドリンク" into "キャストドリンク" (merge duplicate empty category if present)
do $$
declare r record; dup_id uuid;
begin
  for r in select id, store_id from public.categories where name='従業員ドリンク' loop
    select id into dup_id from public.categories where store_id=r.store_id and name='キャストドリンク';
    if dup_id is not null and dup_id<>r.id then
      update public.products set category_id=r.id where category_id=dup_id;
      delete from public.categories where id=dup_id;
    end if;
    update public.categories set name='キャストドリンク', updated_at=now() where id=r.id;
  end loop;
end $$;

-- Let the product catalog editor manage staff_drink_enabled / back_amount per product
create or replace function public.update_pos_catalog(target_store uuid,catalog_kind text,items jsonb,admin_token text default null)
returns void language plpgsql security definer set search_path=public as $$
declare item jsonb; keep_names text[]:=array[]::text[]; category_id uuid; item_name text;
begin
  if not public.is_store_owner(target_store) and not public.validate_admin_session(target_store,admin_token) then raise exception 'admin authentication required'; end if;
  if catalog_kind not in ('categories','products','tables','staff') or jsonb_typeof(items)<>'array' then raise exception 'invalid catalog data'; end if;
  for item in select value from jsonb_array_elements(items) loop
    item_name:=left(trim(item->>'name'),120);if item_name='' then continue;end if;keep_names:=array_append(keep_names,item_name);
    if catalog_kind='categories' then insert into public.categories(store_id,name,color,display_order,enabled) values(target_store,item_name,left(coalesce(nullif(item->>'color',''),'#6b7280'),20),array_length(keep_names,1)*10,true) on conflict(store_id,name) do update set color=excluded.color,display_order=excluded.display_order,enabled=true,updated_at=now();
    elsif catalog_kind='products' then select id into category_id from public.categories where store_id=target_store and name=coalesce(nullif(trim(item->>'category'),''),'その他') limit 1;if category_id is null then select id into category_id from public.categories where store_id=target_store order by display_order limit 1;end if;insert into public.products(store_id,category_id,name,price,display_order,enabled,staff_drink_enabled,back_amount) values(target_store,category_id,item_name,greatest(0,coalesce((item->>'price')::integer,0)),array_length(keep_names,1)*10,true,coalesce((item->>'staffDrink')::boolean,false),greatest(0,coalesce((item->>'backAmount')::integer,0))) on conflict(store_id,name) do update set category_id=excluded.category_id,price=excluded.price,display_order=excluded.display_order,enabled=true,staff_drink_enabled=excluded.staff_drink_enabled,back_amount=excluded.back_amount,updated_at=now();
    elsif catalog_kind='tables' then insert into public.bar_tables(store_id,name,table_number,display_order,enabled) values(target_store,item_name,left(coalesce(item->>'tableNumber',''),40),array_length(keep_names,1)*10,true) on conflict(store_id,name) do update set table_number=excluded.table_number,display_order=excluded.display_order,enabled=true,updated_at=now();
    else insert into public.staff(store_id,name,display_order,enabled) values(target_store,left(item_name,80),array_length(keep_names,1)*10,true) on conflict(store_id,name) do update set display_order=excluded.display_order,enabled=true,updated_at=now();end if;
  end loop;
  if catalog_kind='categories' then update public.categories c set enabled=false,updated_at=now() where c.store_id=target_store and not(c.name=any(keep_names)) and not exists(select 1 from public.products p where p.category_id=c.id and p.enabled);
  elsif catalog_kind='products' then update public.products set enabled=false,updated_at=now() where store_id=target_store and not(name=any(keep_names));
  elsif catalog_kind='tables' then update public.bar_tables t set enabled=false,updated_at=now() where t.store_id=target_store and not(t.name=any(keep_names)) and not exists(select 1 from public.checks c where c.table_id=t.id and c.status='open');
  else update public.staff set enabled=false,updated_at=now() where store_id=target_store and not(name=any(keep_names));end if;
  insert into public.audit_logs(store_id,actor_type,actor_id,action,entity_type,after_data) values(target_store,'owner',coalesce(auth.uid()::text,'admin-session'),'catalog_updated',catalog_kind,jsonb_build_object('count',coalesce(array_length(keep_names,1),0)));
end; $$;
revoke all on function public.update_pos_catalog(uuid,text,jsonb,text) from public;
grant execute on function public.update_pos_catalog(uuid,text,jsonb,text) to anon,authenticated;

-- Persist drink-back amount per line when a check is saved/completed
create or replace function public.save_pos_open_check(
  target_store uuid, raw_token text, table_name text,
  customer_name text, guest_count integer, lines jsonb, check_memo text default ''
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare selected_table_id uuid; open_id uuid; next_number bigint; subtotal_value integer; line jsonb; selected_staff_id uuid; input_guests integer:=guest_count;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  if guest_count < 1 or jsonb_typeof(lines) <> 'array' then raise exception 'invalid check data'; end if;
  select id into selected_table_id from public.bar_tables where store_id=target_store and name=table_name and enabled limit 1;
  if selected_table_id is null then raise exception 'table not found'; end if;
  select id into open_id from public.checks where store_id=target_store and table_id=selected_table_id and status='open' for update;
  if open_id is null then
    select next_check_number into next_number from public.store_settings where store_id=target_store for update;
    update public.store_settings set next_check_number=next_check_number+1,updated_at=now() where store_id=target_store;
    insert into public.checks(store_id,table_id,check_number,business_date,status,customer_name,guest_count,memo)
    values(target_store,selected_table_id,next_number,public.business_date_for(target_store),'open',left(coalesce(customer_name,''),120),guest_count,left(coalesce(check_memo,''),500)) returning id into open_id;
  end if;
  select coalesce(sum(greatest(0,(item->>'price')::integer)*greatest(1,(item->>'qty')::integer)),0)::integer
    into subtotal_value from jsonb_array_elements(lines) item;
  update public.checks c set customer_name=left(coalesce(save_pos_open_check.customer_name,''),120),guest_count=input_guests,memo=left(coalesce(check_memo,''),500),subtotal=subtotal_value,tax_amount=floor(subtotal_value/11.0),total_amount=subtotal_value,updated_at=now() where c.id=open_id;
  delete from public.check_lines where check_id=open_id;
  for line in select value from jsonb_array_elements(lines) loop
    selected_staff_id:=null;
    if nullif(trim(line->>'staff'),'') is not null then
      insert into public.staff(store_id,name) values(target_store,left(trim(line->>'staff'),80)) on conflict(store_id,name) do update set updated_at=now() returning id into selected_staff_id;
    end if;
    insert into public.check_lines(check_id,kind,staff_id,product_name,category_name,staff_name,unit_price,tax_rate,quantity,back_amount)
    values(open_id,case when selected_staff_id is null then 'product'::public.line_kind else 'staff_drink'::public.line_kind end,selected_staff_id,left(line->>'name',120),left(coalesce(line->>'category','その他'),80),case when selected_staff_id is null then null else left(trim(line->>'staff'),80) end,greatest(0,(line->>'price')::integer),10,greatest(1,(line->>'qty')::integer),greatest(0,coalesce((line->>'backAmount')::integer,0)));
  end loop;
  return jsonb_build_object('checkId',open_id,'total',subtotal_value);
end; $$;
revoke all on function public.save_pos_open_check(uuid,text,text,text,integer,jsonb,text) from public;
grant execute on function public.save_pos_open_check(uuid,text,text,text,integer,jsonb,text) to anon,authenticated;

create or replace function public.complete_pos_sale(
  target_store uuid, raw_token text, table_name text, customer_name text, guest_count integer,
  lines jsonb, payment_method text, received_amount integer default null, debtor_name text default null,
  receivable_memo text default '', due_date date default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  new_check_id uuid; selected_table_id uuid; next_number bigint; subtotal_value integer; tax_value integer;
  line jsonb; selected_staff_id uuid; method_value public.payment_method;
begin
  if not public.validate_pos_session(target_store, raw_token) then raise exception 'invalid or expired device session'; end if;
  if guest_count < 1 or jsonb_typeof(lines) <> 'array' or jsonb_array_length(lines) = 0 then raise exception 'invalid check data'; end if;
  method_value := case payment_method when 'cash' then 'cash'::public.payment_method when 'qr' then 'qr'::public.payment_method when 'receivable' then 'receivable'::public.payment_method when 'other' then 'other'::public.payment_method else null end;
  if method_value is null then raise exception 'invalid payment method'; end if;
  select id into selected_table_id from public.bar_tables where store_id=target_store and name=table_name and enabled limit 1;
  select coalesce(sum(greatest(0,(item->>'price')::integer) * greatest(1,(item->>'qty')::integer)),0)::integer into subtotal_value from jsonb_array_elements(lines) item;
  if subtotal_value <= 0 then raise exception 'total must be positive'; end if;
  tax_value := floor(subtotal_value / 11.0);
  select next_check_number into next_number from public.store_settings where store_id=target_store for update;
  update public.store_settings set next_check_number=next_check_number+1,updated_at=now() where store_id=target_store;
  insert into public.checks(store_id,table_id,check_number,business_date,status,customer_name,guest_count,subtotal,tax_amount,total_amount,paid_at)
  values(target_store,selected_table_id,next_number,public.business_date_for(target_store),'paid',left(coalesce(customer_name,''),120),guest_count,subtotal_value,tax_value,subtotal_value,now())
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
end; $$;
revoke all on function public.complete_pos_sale(uuid,text,text,text,integer,jsonb,text,integer,text,text,date) from public;
grant execute on function public.complete_pos_sale(uuid,text,text,text,integer,jsonb,text,integer,text,text,date) to anon, authenticated;

-- Expose backAmount on products in the dashboard payload
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
    'staff',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.display_order,s.name),'[]'::jsonb) from public.staff s where s.store_id=target_store and s.enabled),
    'history',(select coalesce(jsonb_agg(x.item order by x.paid_at desc),'[]'::jsonb) from (select c.paid_at,jsonb_build_object('id',c.id,'number',c.check_number,'table',coalesce(t.name,''),'customer',c.customer_name,'guests',c.guest_count,'total',c.total_amount,'paidAt',c.paid_at,'method',p.method) item from public.checks c left join public.bar_tables t on t.id=c.table_id left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.status='paid' order by c.paid_at desc limit 50)x),
    'summary',(select jsonb_build_object('sales',coalesce(sum(c.total_amount),0),'checks',count(*),'guests',coalesce(sum(c.guest_count),0),'cash',coalesce(sum(c.total_amount) filter(where p.method='cash'),0),'qr',coalesce(sum(c.total_amount) filter(where p.method='qr'),0),'receivable',coalesce(sum(c.total_amount) filter(where p.method='receivable'),0),'other',coalesce(sum(c.total_amount) filter(where p.method='other'),0)) from public.checks c left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.business_date=target_day and c.status='paid')
  ) into result; return result;
end; $$;
revoke all on function public.get_pos_dashboard(uuid,text) from public;
grant execute on function public.get_pos_dashboard(uuid,text) to anon,authenticated;

-- Report: add per-staff drink count + drink-back total for the period
create or replace function public.get_pos_report(target_store uuid, raw_token text, period text default 'day')
returns jsonb language plpgsql security definer set search_path=public as $$
declare target_day date; start_day date; result jsonb;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  if period not in ('day','week','month') then raise exception 'invalid period'; end if;
  target_day:=public.business_date_for(target_store);
  start_day:=target_day-(case period when 'week' then 6 when 'month' then 29 else 0 end);
  select jsonb_build_object(
    'period',period,'businessDate',target_day,'periodStart',start_day,'periodEnd',target_day,
    'summary',(select jsonb_build_object('sales',coalesce(sum(c.total_amount),0),'checks',count(*),'guests',coalesce(sum(c.guest_count),0),'cash',coalesce(sum(c.total_amount) filter(where p.method='cash'),0),'qr',coalesce(sum(c.total_amount) filter(where p.method='qr'),0),'receivable',coalesce(sum(c.total_amount) filter(where p.method='receivable'),0),'other',coalesce(sum(c.total_amount) filter(where p.method='other'),0)) from public.checks c left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.business_date between start_day and target_day and c.status='paid'),
    'staffDrinks',(select coalesce(jsonb_agg(jsonb_build_object('name',x.staff_name,'count',x.cnt,'back',x.back) order by x.back desc,x.cnt desc),'[]'::jsonb) from (select cl.staff_name,sum(cl.quantity)::integer cnt,sum(cl.back_amount*cl.quantity)::integer back from public.check_lines cl join public.checks c on c.id=cl.check_id where c.store_id=target_store and c.status='paid' and c.business_date between start_day and target_day and cl.kind='staff_drink' group by cl.staff_name) x)
  ) into result;
  return result;
end; $$;
revoke all on function public.get_pos_report(uuid,text,text) from public;
grant execute on function public.get_pos_report(uuid,text,text) to anon,authenticated;
