-- Add each staff member's per-business-day drink breakdown to attendance detail.
create or replace function public.get_pos_attendance_detail(target_store uuid, raw_token text, period text default 'day')
returns jsonb language plpgsql security definer set search_path=public as $$
declare target_day date; start_day date;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  if period not in ('day','week','month') then raise exception 'invalid period'; end if;
  target_day:=public.business_date_for(target_store);
  start_day:=target_day-(case period when 'week' then 6 when 'month' then 29 else 0 end);
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'staffName',a.staff_name,'businessDate',a.business_date,'clockIn',a.clock_in,'clockOut',a.clock_out,
    'drinks',coalesce((select jsonb_agg(jsonb_build_object('name',d.product_name,'count',d.cnt) order by d.product_name) from (
      select cl.product_name,sum(cl.quantity)::integer cnt
      from public.check_lines cl join public.checks c on c.id=cl.check_id
      where c.store_id=target_store and c.status='paid' and c.business_date=a.business_date
        and cl.kind='staff_drink' and cl.staff_name=a.staff_name
      group by cl.product_name
    ) d),'[]'::jsonb)
  ) order by a.clock_in),'[]'::jsonb)
  from public.attendance_records a
  where a.store_id=target_store and a.business_date between start_day and target_day);
end; $$;
revoke all on function public.get_pos_attendance_detail(uuid,text,text) from public;
grant execute on function public.get_pos_attendance_detail(uuid,text,text) to anon,authenticated;

create or replace function public.get_pos_attendance_detail_month(target_store uuid, raw_token text, target_month date)
returns jsonb language plpgsql security definer set search_path=public as $$
declare start_day date; end_day date;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  if target_month is null then raise exception 'target month required'; end if;
  start_day:=date_trunc('month',target_month)::date;
  end_day:=(start_day+interval '1 month'-interval '1 day')::date;
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'staffName',a.staff_name,'businessDate',a.business_date,'clockIn',a.clock_in,'clockOut',a.clock_out,
    'drinks',coalesce((select jsonb_agg(jsonb_build_object('name',d.product_name,'count',d.cnt) order by d.product_name) from (
      select cl.product_name,sum(cl.quantity)::integer cnt
      from public.check_lines cl join public.checks c on c.id=cl.check_id
      where c.store_id=target_store and c.status='paid' and c.business_date=a.business_date
        and cl.kind='staff_drink' and cl.staff_name=a.staff_name
      group by cl.product_name
    ) d),'[]'::jsonb)
  ) order by a.clock_in),'[]'::jsonb)
  from public.attendance_records a
  where a.store_id=target_store and a.business_date between start_day and end_day);
end; $$;
revoke all on function public.get_pos_attendance_detail_month(uuid,text,date) from public;
grant execute on function public.get_pos_attendance_detail_month(uuid,text,date) to anon,authenticated;
