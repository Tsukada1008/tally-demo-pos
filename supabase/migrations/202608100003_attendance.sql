-- Hourly wage per staff member
alter table public.staff add column if not exists hourly_wage integer not null default 0 check (hourly_wage>=0);

-- Shared-terminal time clock: one open (clock_out is null) shift per staff at a time
create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  staff_id uuid references public.staff(id) on delete set null,
  staff_name text not null,
  business_date date not null,
  clock_in timestamptz not null default now(),
  clock_out timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists attendance_store_date_idx on public.attendance_records(store_id,business_date);
create unique index if not exists one_open_shift_per_staff on public.attendance_records(store_id,staff_name) where clock_out is null;
alter table public.attendance_records enable row level security;
revoke all on public.attendance_records from anon,authenticated;
drop policy if exists owner_attendance on public.attendance_records;
create policy owner_attendance on public.attendance_records for all using (public.is_store_owner(store_id)) with check (public.is_store_owner(store_id));

-- Tap a staff name to clock in; tap again to clock out
create or replace function public.toggle_attendance(target_store uuid, raw_token text, staff_name text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare selected_staff_id uuid; open_id uuid; clean_name text; result jsonb;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  clean_name:=left(trim(staff_name),80);
  if clean_name='' then raise exception 'staff name required'; end if;
  insert into public.staff(store_id,name) values(target_store,clean_name) on conflict(store_id,name) do update set updated_at=now() returning id into selected_staff_id;
  select ar.id into open_id from public.attendance_records ar where ar.store_id=target_store and ar.staff_name=clean_name and ar.clock_out is null for update;
  if open_id is not null then
    update public.attendance_records set clock_out=now(),updated_at=now() where id=open_id;
    result:=jsonb_build_object('action','out','staffName',clean_name,'at',now());
  else
    insert into public.attendance_records(store_id,staff_id,staff_name,business_date,clock_in) values(target_store,selected_staff_id,clean_name,public.business_date_for(target_store),now());
    result:=jsonb_build_object('action','in','staffName',clean_name,'at',now());
  end if;
  return result;
end; $$;
revoke all on function public.toggle_attendance(uuid,text,text) from public;
grant execute on function public.toggle_attendance(uuid,text,text) to anon,authenticated;

-- Expose current shift status + hourly wage on the dashboard payload
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
    'onShift',(select coalesce(jsonb_agg(jsonb_build_object('staffName',a.staff_name,'clockIn',a.clock_in) order by a.clock_in),'[]'::jsonb) from public.attendance_records a where a.store_id=target_store and a.clock_out is null),
    'history',(select coalesce(jsonb_agg(x.item order by x.paid_at desc),'[]'::jsonb) from (select c.paid_at,jsonb_build_object('id',c.id,'number',c.check_number,'table',coalesce(t.name,''),'customer',c.customer_name,'guests',c.guest_count,'total',c.total_amount,'paidAt',c.paid_at,'method',p.method) item from public.checks c left join public.bar_tables t on t.id=c.table_id left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.status='paid' order by c.paid_at desc limit 50)x),
    'summary',(select jsonb_build_object('sales',coalesce(sum(c.total_amount),0),'checks',count(*),'guests',coalesce(sum(c.guest_count),0),'cash',coalesce(sum(c.total_amount) filter(where p.method='cash'),0),'qr',coalesce(sum(c.total_amount) filter(where p.method='qr'),0),'receivable',coalesce(sum(c.total_amount) filter(where p.method='receivable'),0),'other',coalesce(sum(c.total_amount) filter(where p.method='other'),0)) from public.checks c left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.business_date=target_day and c.status='paid')
  ) into result; return result;
end; $$;
revoke all on function public.get_pos_dashboard(uuid,text) from public;
grant execute on function public.get_pos_dashboard(uuid,text) to anon,authenticated;

-- Let the staff editor manage hourly_wage
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
    else insert into public.staff(store_id,name,display_order,enabled,hourly_wage) values(target_store,left(item_name,80),array_length(keep_names,1)*10,true,greatest(0,coalesce((item->>'hourlyWage')::integer,0))) on conflict(store_id,name) do update set display_order=excluded.display_order,enabled=true,hourly_wage=excluded.hourly_wage,updated_at=now();end if;
  end loop;
  if catalog_kind='categories' then update public.categories c set enabled=false,updated_at=now() where c.store_id=target_store and not(c.name=any(keep_names)) and not exists(select 1 from public.products p where p.category_id=c.id and p.enabled);
  elsif catalog_kind='products' then update public.products set enabled=false,updated_at=now() where store_id=target_store and not(name=any(keep_names));
  elsif catalog_kind='tables' then update public.bar_tables t set enabled=false,updated_at=now() where t.store_id=target_store and not(t.name=any(keep_names)) and not exists(select 1 from public.checks c where c.table_id=t.id and c.status='open');
  else update public.staff set enabled=false,updated_at=now() where store_id=target_store and not(name=any(keep_names));end if;
  insert into public.audit_logs(store_id,actor_type,actor_id,action,entity_type,after_data) values(target_store,'owner',coalesce(auth.uid()::text,'admin-session'),'catalog_updated',catalog_kind,jsonb_build_object('count',coalesce(array_length(keep_names,1),0)));
end; $$;
revoke all on function public.update_pos_catalog(uuid,text,jsonb,text) from public;
grant execute on function public.update_pos_catalog(uuid,text,jsonb,text) to anon,authenticated;

-- Report: payroll (hours x hourly wage) per staff for the selected period
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
    'staffDrinks',(select coalesce(jsonb_agg(jsonb_build_object('name',s.staff_name,'count',s.cnt,'back',s.back,'products',(select coalesce(jsonb_agg(jsonb_build_object('name',p.product_name,'count',p.cnt) order by p.cnt desc,p.product_name),'[]'::jsonb) from (select cl2.product_name,sum(cl2.quantity)::integer cnt from public.check_lines cl2 join public.checks c2 on c2.id=cl2.check_id where c2.store_id=target_store and c2.status='paid' and c2.business_date between start_day and target_day and cl2.kind='staff_drink' and cl2.staff_name=s.staff_name group by cl2.product_name) p)) order by s.back desc,s.cnt desc),'[]'::jsonb)
      from (select cl.staff_name,sum(cl.quantity)::integer cnt,sum(cl.back_amount*cl.quantity)::integer back from public.check_lines cl join public.checks c on c.id=cl.check_id where c.store_id=target_store and c.status='paid' and c.business_date between start_day and target_day and cl.kind='staff_drink' group by cl.staff_name) s),
    'daily',(select coalesce(jsonb_agg(jsonb_build_object('date',gs.d::date,'sales',coalesce(x.sales,0),'checks',coalesce(x.checks,0)) order by gs.d),'[]'::jsonb)
      from generate_series(start_day,target_day,interval '1 day') gs(d)
      left join (select business_date,sum(total_amount)::integer sales,count(*)::integer checks from public.checks where store_id=target_store and status='paid' and business_date between start_day and target_day group by business_date) x on x.business_date=gs.d::date),
    'payroll',(select coalesce(jsonb_agg(jsonb_build_object('name',pr.staff_name,'hours',round(pr.hours::numeric,2),'hourlyWage',pr.wage,'wageTotal',round(pr.hours*pr.wage)::integer,'shifts',pr.shifts) order by pr.staff_name),'[]'::jsonb)
      from (select a.staff_name,coalesce(st.hourly_wage,0)::integer as wage,sum(extract(epoch from (coalesce(a.clock_out,now())-a.clock_in))/3600.0) as hours,count(*)::integer as shifts
            from public.attendance_records a left join public.staff st on st.store_id=target_store and st.name=a.staff_name
            where a.store_id=target_store and a.business_date between start_day and target_day group by a.staff_name,st.hourly_wage) pr)
  ) into result;
  return result;
end; $$;
revoke all on function public.get_pos_report(uuid,text,text) from public;
grant execute on function public.get_pos_report(uuid,text,text) to anon,authenticated;
