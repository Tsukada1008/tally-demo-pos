-- "中抜け"（休憩）区間を打刻中の勤務に記録する
create table if not exists public.attendance_breaks (
  id uuid primary key default gen_random_uuid(),
  attendance_id uuid not null references public.attendance_records(id) on delete cascade,
  break_start timestamptz not null default now(),
  break_end timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists one_open_break_per_shift on public.attendance_breaks(attendance_id) where break_end is null;
alter table public.attendance_breaks enable row level security;
revoke all on public.attendance_breaks from anon,authenticated;
drop policy if exists owner_attendance_breaks on public.attendance_breaks;
create policy owner_attendance_breaks on public.attendance_breaks for all using (exists(select 1 from public.attendance_records a where a.id=attendance_id and public.is_store_owner(a.store_id))) with check (exists(select 1 from public.attendance_records a where a.id=attendance_id and public.is_store_owner(a.store_id)));

-- Tap to start/end a break on the current open shift
create or replace function public.toggle_break(target_store uuid, raw_token text, staff_name text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare clean_name text; shift_id uuid; open_break_id uuid; result jsonb;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  clean_name:=left(trim(staff_name),80);
  select ar.id into shift_id from public.attendance_records ar where ar.store_id=target_store and ar.staff_name=clean_name and ar.clock_out is null order by ar.clock_in desc limit 1;
  if shift_id is null then raise exception 'not clocked in'; end if;
  select b.id into open_break_id from public.attendance_breaks b where b.attendance_id=shift_id and b.break_end is null for update;
  if open_break_id is not null then
    update public.attendance_breaks set break_end=now() where id=open_break_id;
    result:=jsonb_build_object('action','break_end','staffName',clean_name,'at',now());
  else
    insert into public.attendance_breaks(attendance_id,break_start) values(shift_id,now());
    result:=jsonb_build_object('action','break_start','staffName',clean_name,'at',now());
  end if;
  return result;
end; $$;
revoke all on function public.toggle_break(uuid,text,text) from public;
grant execute on function public.toggle_break(uuid,text,text) to anon,authenticated;

-- Clocking out also closes any still-open break for that shift
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
    update public.attendance_breaks set break_end=now() where attendance_id=open_id and break_end is null;
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

-- Dashboard: expose whether each on-shift staff member is currently on a break
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
    'history',(select coalesce(jsonb_agg(x.item order by x.paid_at desc),'[]'::jsonb) from (select c.paid_at,jsonb_build_object('id',c.id,'number',c.check_number,'table',coalesce(t.name,''),'customer',c.customer_name,'guests',c.guest_count,'total',c.total_amount,'paidAt',c.paid_at,'method',p.method) item from public.checks c left join public.bar_tables t on t.id=c.table_id left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.status='paid' order by c.paid_at desc limit 50)x),
    'summary',(select jsonb_build_object('sales',coalesce(sum(c.total_amount),0),'checks',count(*),'guests',coalesce(sum(c.guest_count),0),'cash',coalesce(sum(c.total_amount) filter(where p.method='cash'),0),'qr',coalesce(sum(c.total_amount) filter(where p.method='qr'),0),'receivable',coalesce(sum(c.total_amount) filter(where p.method='receivable'),0),'other',coalesce(sum(c.total_amount) filter(where p.method='other'),0)) from public.checks c left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.business_date=target_day and c.status='paid')
  ) into result; return result;
end; $$;
revoke all on function public.get_pos_dashboard(uuid,text) from public;
grant execute on function public.get_pos_dashboard(uuid,text) to anon,authenticated;

-- Payroll: subtract break time and round each shift's paid duration to the nearest 15 minutes
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
      from (
        select a.staff_name,coalesce(st.hourly_wage,0)::integer as wage,
          sum(round((extract(epoch from (coalesce(a.clock_out,now())-a.clock_in))/60.0 - coalesce(br.break_minutes,0))/15.0)*0.25) as hours,
          count(*)::integer as shifts
        from public.attendance_records a
        left join public.staff st on st.store_id=target_store and st.name=a.staff_name
        left join lateral (select sum(extract(epoch from (coalesce(b.break_end,now())-b.break_start))/60.0) as break_minutes from public.attendance_breaks b where b.attendance_id=a.id) br on true
        where a.store_id=target_store and a.business_date between start_day and target_day
        group by a.staff_name,st.hourly_wage
      ) pr)
  ) into result;
  return result;
end; $$;
revoke all on function public.get_pos_report(uuid,text,text) from public;
grant execute on function public.get_pos_report(uuid,text,text) to anon,authenticated;
