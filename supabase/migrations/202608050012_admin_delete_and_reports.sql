create or replace function public.delete_pos_check(
  target_store uuid, target_check uuid, admin_token text
) returns boolean language plpgsql security definer set search_path=public as $$
declare deleted_number bigint;
begin
  if not public.is_store_owner(target_store) and not public.validate_admin_session(target_store,admin_token) then
    raise exception 'admin authentication required';
  end if;
  select check_number into deleted_number from public.checks where id=target_check and store_id=target_store;
  if deleted_number is null then return false; end if;
  insert into public.audit_logs(store_id,actor_type,actor_id,action,entity_type,entity_id,before_data)
  values(target_store,'owner',coalesce(auth.uid()::text,'admin-session'),'check_deleted','checks',target_check::text,jsonb_build_object('checkNumber',deleted_number));
  delete from public.receivables where check_id=target_check and store_id=target_store;
  delete from public.payments where check_id=target_check;
  delete from public.checks where id=target_check and store_id=target_store;
  return found;
end; $$;
revoke all on function public.delete_pos_check(uuid,uuid,text) from public;
grant execute on function public.delete_pos_check(uuid,uuid,text) to anon,authenticated;
