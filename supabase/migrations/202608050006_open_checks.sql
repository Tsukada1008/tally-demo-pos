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
    insert into public.check_lines(check_id,kind,staff_id,product_name,category_name,staff_name,unit_price,tax_rate,quantity)
    values(open_id,case when selected_staff_id is null then 'product'::public.line_kind else 'staff_drink'::public.line_kind end,selected_staff_id,left(line->>'name',120),left(coalesce(line->>'category','その他'),80),case when selected_staff_id is null then null else left(trim(line->>'staff'),80) end,greatest(0,(line->>'price')::integer),10,greatest(1,(line->>'qty')::integer));
  end loop;
  return jsonb_build_object('checkId',open_id,'total',subtotal_value);
end; $$;
revoke all on function public.save_pos_open_check(uuid,text,text,text,integer,jsonb,text) from public;
grant execute on function public.save_pos_open_check(uuid,text,text,text,integer,jsonb,text) to anon,authenticated;

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
    'products',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'category',c.name,'price',p.price,'color',c.color,'staffDrink',p.staff_drink_enabled) order by c.display_order,p.display_order),'[]'::jsonb) from public.products p join public.categories c on c.id=p.category_id where p.store_id=target_store and p.enabled),
    'staff',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.display_order,s.name),'[]'::jsonb) from public.staff s where s.store_id=target_store and s.enabled),
    'history',(select coalesce(jsonb_agg(x.item order by x.paid_at desc),'[]'::jsonb) from (select c.paid_at,jsonb_build_object('id',c.id,'number',c.check_number,'table',coalesce(t.name,''),'customer',c.customer_name,'guests',c.guest_count,'total',c.total_amount,'paidAt',c.paid_at,'method',p.method) item from public.checks c left join public.bar_tables t on t.id=c.table_id left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.status='paid' order by c.paid_at desc limit 50)x),
    'summary',(select jsonb_build_object('sales',coalesce(sum(c.total_amount),0),'checks',count(*),'guests',coalesce(sum(c.guest_count),0),'cash',coalesce(sum(c.total_amount) filter(where p.method='cash'),0),'qr',coalesce(sum(c.total_amount) filter(where p.method='qr'),0),'receivable',coalesce(sum(c.total_amount) filter(where p.method='receivable'),0),'other',coalesce(sum(c.total_amount) filter(where p.method='other'),0)) from public.checks c left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.business_date=target_day and c.status='paid')
  ) into result; return result;
end; $$;

create or replace function public.complete_saved_pos_sale(
  target_store uuid, raw_token text, table_name text, customer_name text, guest_count integer,
  lines jsonb, payment_method text, received_amount integer default null, debtor_name text default null,
  receivable_memo text default '', due_date date default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare selected_table_id uuid;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  select id into selected_table_id from public.bar_tables where store_id=target_store and name=table_name and enabled limit 1;
  delete from public.checks where store_id=target_store and table_id=selected_table_id and status='open';
  return public.complete_pos_sale(target_store,raw_token,table_name,customer_name,guest_count,lines,payment_method,received_amount,debtor_name,receivable_memo,due_date);
end; $$;
revoke all on function public.complete_saved_pos_sale(uuid,text,text,text,integer,jsonb,text,integer,text,text,date) from public;
grant execute on function public.complete_saved_pos_sale(uuid,text,text,text,integer,jsonb,text,integer,text,text,date) to anon,authenticated;
