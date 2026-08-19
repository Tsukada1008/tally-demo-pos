-- Configurable payroll rounding: unit (5/10/15/30 min) and direction (floor/ceil)
alter table public.store_settings add column if not exists payroll_round_unit_minutes integer not null default 15 check (payroll_round_unit_minutes in (5,10,15,30));
alter table public.store_settings add column if not exists payroll_round_mode text not null default 'ceil' check (payroll_round_mode in ('floor','ceil'));

create or replace function public.update_payroll_rounding(target_store uuid, unit_minutes integer, round_mode text, admin_token text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_store_owner(target_store) and not public.validate_admin_session(target_store,admin_token) then raise exception 'admin authentication required'; end if;
  if unit_minutes not in (5,10,15,30) or round_mode not in ('floor','ceil') then raise exception 'invalid rounding settings'; end if;
  update public.store_settings set payroll_round_unit_minutes=unit_minutes,payroll_round_mode=round_mode,updated_at=now() where store_id=target_store;
  insert into public.audit_logs(store_id,actor_type,actor_id,action,entity_type,after_data) values(target_store,'owner',coalesce(auth.uid()::text,'admin-session'),'payroll_rounding_updated','store_settings',jsonb_build_object('unitMinutes',unit_minutes,'mode',round_mode));
end; $$;
revoke all on function public.update_payroll_rounding(uuid,integer,text,text) from public;
grant execute on function public.update_payroll_rounding(uuid,integer,text,text) to anon,authenticated;

-- Expose the current rounding setting on the dashboard payload
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
    'history',(select coalesce(jsonb_agg(x.item order by x.paid_at desc),'[]'::jsonb) from (select c.paid_at,jsonb_build_object('id',c.id,'number',c.check_number,'table',coalesce(t.name,''),'customer',c.customer_name,'guests',c.guest_count,'total',c.total_amount,'paidAt',c.paid_at,'method',p.method) item from public.checks c left join public.bar_tables t on t.id=c.table_id left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.status='paid' order by c.paid_at desc limit 50)x),
    'summary',(select jsonb_build_object('sales',coalesce(sum(c.total_amount),0),'checks',count(*),'guests',coalesce(sum(c.guest_count),0),'cash',coalesce(sum(c.total_amount) filter(where p.method='cash'),0),'qr',coalesce(sum(c.total_amount) filter(where p.method='qr'),0),'receivable',coalesce(sum(c.total_amount) filter(where p.method='receivable'),0),'other',coalesce(sum(c.total_amount) filter(where p.method='other'),0)) from public.checks c left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.business_date=target_day and c.status='paid')
  ) into result; return result;
end; $$;
revoke all on function public.get_pos_dashboard(uuid,text) from public;
grant execute on function public.get_pos_dashboard(uuid,text) to anon,authenticated;

-- Payroll: apply the store's configured rounding unit + direction instead of a fixed nearest-15-minute rule
create or replace function public.get_pos_report(target_store uuid, raw_token text, period text default 'day')
returns jsonb language plpgsql security definer set search_path=public as $$
declare target_day date; start_day date; result jsonb; round_unit integer; round_mode text;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  if period not in ('day','week','month') then raise exception 'invalid period'; end if;
  target_day:=public.business_date_for(target_store);
  start_day:=target_day-(case period when 'week' then 6 when 'month' then 29 else 0 end);
  select payroll_round_unit_minutes,payroll_round_mode into round_unit,round_mode from public.store_settings where store_id=target_store;
  round_unit:=coalesce(round_unit,15); round_mode:=coalesce(round_mode,'ceil');
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
          sum(
            (case when round_mode='floor'
              then floor(greatest(0,extract(epoch from (coalesce(a.clock_out,now())-a.clock_in))/60.0 - coalesce(br.break_minutes,0))/round_unit)
              else ceil(greatest(0,extract(epoch from (coalesce(a.clock_out,now())-a.clock_in))/60.0 - coalesce(br.break_minutes,0))/round_unit)
            end) * round_unit / 60.0
          ) as hours,
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
