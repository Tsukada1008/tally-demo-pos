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
    'summary',(select jsonb_build_object('sales',coalesce(sum(c.total_amount),0),'checks',count(*),'guests',coalesce(sum(c.guest_count),0),'cash',coalesce(sum(c.total_amount) filter(where p.method='cash'),0),'qr',coalesce(sum(c.total_amount) filter(where p.method='qr'),0),'receivable',coalesce(sum(c.total_amount) filter(where p.method='receivable'),0),'other',coalesce(sum(c.total_amount) filter(where p.method='other'),0)) from public.checks c left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.business_date between start_day and target_day and c.status='paid')
  ) into result;
  return result;
end; $$;
revoke all on function public.get_pos_report(uuid,text,text) from public;
grant execute on function public.get_pos_report(uuid,text,text) to anon,authenticated;
