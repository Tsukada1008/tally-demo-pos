-- Calendar-month history for the demo POS. Additive functions keep existing clients unchanged.
create or replace function public.get_pos_report_month(target_store uuid, raw_token text, target_month date)
returns jsonb language plpgsql security definer set search_path=public as $$
declare start_day date; end_day date; result jsonb; round_unit integer; round_mode text;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  if target_month is null then raise exception 'target month required'; end if;
  start_day:=date_trunc('month',target_month)::date;
  end_day:=(start_day+interval '1 month'-interval '1 day')::date;
  select payroll_round_unit_minutes,payroll_round_mode into round_unit,round_mode from public.store_settings where store_id=target_store;
  round_unit:=coalesce(round_unit,15); round_mode:=coalesce(round_mode,'ceil');
  select jsonb_build_object(
    'period','month','businessDate',end_day,'periodStart',start_day,'periodEnd',end_day,
    'summary',(select jsonb_build_object('sales',coalesce(sum(c.total_amount),0),'checks',count(*),'guests',coalesce(sum(c.guest_count),0),'cash',coalesce(sum(c.total_amount) filter(where p.method='cash'),0),'qr',coalesce(sum(c.total_amount) filter(where p.method='qr'),0),'receivable',coalesce(sum(c.total_amount) filter(where p.method='receivable'),0),'other',coalesce(sum(c.total_amount) filter(where p.method='other'),0)) from public.checks c left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.business_date between start_day and end_day and c.status='paid'),
    'staffDrinks',(select coalesce(jsonb_agg(jsonb_build_object('name',s.staff_name,'count',s.cnt,'back',s.back,'products',(select coalesce(jsonb_agg(jsonb_build_object('name',p.product_name,'count',p.cnt) order by p.cnt desc,p.product_name),'[]'::jsonb) from (select cl2.product_name,sum(cl2.quantity)::integer cnt from public.check_lines cl2 join public.checks c2 on c2.id=cl2.check_id where c2.store_id=target_store and c2.status='paid' and c2.business_date between start_day and end_day and cl2.kind='staff_drink' and cl2.staff_name=s.staff_name group by cl2.product_name) p)) order by s.back desc,s.cnt desc),'[]'::jsonb)
      from (select cl.staff_name,sum(cl.quantity)::integer cnt,sum(cl.back_amount*cl.quantity)::integer back from public.check_lines cl join public.checks c on c.id=cl.check_id where c.store_id=target_store and c.status='paid' and c.business_date between start_day and end_day and cl.kind='staff_drink' group by cl.staff_name) s),
    'daily',(select coalesce(jsonb_agg(jsonb_build_object('date',gs.d::date,'sales',coalesce(x.sales,0),'checks',coalesce(x.checks,0)) order by gs.d),'[]'::jsonb)
      from generate_series(start_day,end_day,interval '1 day') gs(d)
      left join (select business_date,sum(total_amount)::integer sales,count(*)::integer checks from public.checks where store_id=target_store and status='paid' and business_date between start_day and end_day group by business_date) x on x.business_date=gs.d::date),
    'payroll',(select coalesce(jsonb_agg(jsonb_build_object('name',pr.staff_name,'hours',round(pr.hours::numeric,2),'hourlyWage',pr.wage,'wageTotal',round(pr.hours*pr.wage)::integer,'shifts',pr.shifts) order by pr.staff_name),'[]'::jsonb)
      from (
        select a.staff_name,coalesce(st.hourly_wage,0)::integer as wage,
          sum((case when round_mode='floor'
              then floor(greatest(0,extract(epoch from (coalesce(a.clock_out,now())-a.clock_in))/60.0-coalesce(br.break_minutes,0))/round_unit)
              else ceil(greatest(0,extract(epoch from (coalesce(a.clock_out,now())-a.clock_in))/60.0-coalesce(br.break_minutes,0))/round_unit)
            end)*round_unit/60.0) as hours,
          count(*)::integer as shifts
        from public.attendance_records a
        left join public.staff st on st.store_id=target_store and st.name=a.staff_name
        left join lateral (select sum(extract(epoch from (coalesce(b.break_end,now())-b.break_start))/60.0) break_minutes from public.attendance_breaks b where b.attendance_id=a.id) br on true
        where a.store_id=target_store and a.business_date between start_day and end_day
        group by a.staff_name,st.hourly_wage
      ) pr)
  ) into result;
  return result;
end; $$;
revoke all on function public.get_pos_report_month(uuid,text,date) from public;
grant execute on function public.get_pos_report_month(uuid,text,date) to anon,authenticated;

create or replace function public.get_pos_attendance_detail_month(target_store uuid, raw_token text, target_month date)
returns jsonb language plpgsql security definer set search_path=public as $$
declare start_day date; end_day date;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  if target_month is null then raise exception 'target month required'; end if;
  start_day:=date_trunc('month',target_month)::date;
  end_day:=(start_day+interval '1 month'-interval '1 day')::date;
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'staffName',a.staff_name,'businessDate',a.business_date,'clockIn',a.clock_in,'clockOut',a.clock_out
  ) order by a.clock_in),'[]'::jsonb)
  from public.attendance_records a
  where a.store_id=target_store and a.business_date between start_day and end_day);
end; $$;
revoke all on function public.get_pos_attendance_detail_month(uuid,text,date) from public;
grant execute on function public.get_pos_attendance_detail_month(uuid,text,date) to anon,authenticated;
