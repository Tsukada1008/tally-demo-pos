-- Report: per-staff product breakdown + daily breakdown for week/month, and a check-detail lookup for history
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
      left join (select business_date,sum(total_amount)::integer sales,count(*)::integer checks from public.checks where store_id=target_store and status='paid' and business_date between start_day and target_day group by business_date) x on x.business_date=gs.d::date)
  ) into result;
  return result;
end; $$;
revoke all on function public.get_pos_report(uuid,text,text) from public;
grant execute on function public.get_pos_report(uuid,text,text) to anon,authenticated;

-- Full line-item detail for one check, used to open a receipt from Payment History
create or replace function public.get_pos_check_detail(target_store uuid, raw_token text, target_check uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  select jsonb_build_object(
    'id',c.id,'number',c.check_number,'table',coalesce(t.name,''),'customer',c.customer_name,'guests',c.guest_count,
    'subtotal',c.subtotal,'tax',c.tax_amount,'total',c.total_amount,'status',c.status,'openedAt',c.opened_at,'paidAt',c.paid_at,
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
