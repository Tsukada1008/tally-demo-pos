-- Demo POS additions. Existing dashboard/report RPCs remain unchanged.

create or replace function public.get_pos_receivables(target_store uuid, raw_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'checkId',r.check_id,'number',c.check_number,'table',coalesce(t.name,''),
    'debtorName',r.debtor_name,'amount',r.amount,'memo',r.memo,'dueDate',r.due_date,
    'createdAt',r.created_at
  ) order by r.created_at desc),'[]'::jsonb)
  from public.receivables r
  join public.checks c on c.id=r.check_id
  left join public.bar_tables t on t.id=c.table_id
  where r.store_id=target_store and r.status='unpaid');
end; $$;
revoke all on function public.get_pos_receivables(uuid,text) from public;
grant execute on function public.get_pos_receivables(uuid,text) to anon,authenticated;

create or replace function public.settle_pos_receivable(target_store uuid, raw_token text, target_receivable uuid, paid_method text)
returns boolean language plpgsql security definer set search_path=public as $$
declare selected public.receivables%rowtype; method_value public.payment_method;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  method_value:=case paid_method when 'cash' then 'cash'::public.payment_method when 'qr' then 'qr'::public.payment_method when 'other' then 'other'::public.payment_method else null end;
  if method_value is null then raise exception 'invalid payment method'; end if;
  select * into selected from public.receivables where id=target_receivable and store_id=target_store and status='unpaid' for update;
  if selected.id is null then raise exception 'unpaid receivable not found'; end if;
  update public.receivables set status='paid',paid_at=now(),paid_method=method_value,updated_at=now() where id=selected.id;
  update public.payments set method=method_value,recorded_at=now() where check_id=selected.check_id;
  insert into public.audit_logs(store_id,actor_type,actor_id,action,entity_type,entity_id,before_data,after_data)
  values(target_store,'device',null,'receivable_settled','receivable',selected.id::text,jsonb_build_object('status','unpaid'),jsonb_build_object('status','paid','method',method_value));
  return true;
end; $$;
revoke all on function public.settle_pos_receivable(uuid,text,uuid,text) from public;
grant execute on function public.settle_pos_receivable(uuid,text,uuid,text) to anon,authenticated;

create or replace function public.get_pos_attendance_detail(target_store uuid, raw_token text, period text default 'day')
returns jsonb language plpgsql security definer set search_path=public as $$
declare target_day date; start_day date;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  if period not in ('day','week','month') then raise exception 'invalid period'; end if;
  target_day:=public.business_date_for(target_store);
  start_day:=target_day-(case period when 'week' then 6 when 'month' then 29 else 0 end);
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'staffName',a.staff_name,'businessDate',a.business_date,'clockIn',a.clock_in,'clockOut',a.clock_out
  ) order by a.clock_in),'[]'::jsonb)
  from public.attendance_records a
  where a.store_id=target_store and a.business_date between start_day and target_day);
end; $$;
revoke all on function public.get_pos_attendance_detail(uuid,text,text) from public;
grant execute on function public.get_pos_attendance_detail(uuid,text,text) to anon,authenticated;
