create or replace function public.verify_store_pin(
  target_store uuid,
  entered_pin text,
  pin_kind text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  stored_hash text;
begin
  if entered_pin !~ '^[0-9]{4}$' or pin_kind not in ('staff', 'admin') then
    return false;
  end if;

  select case pin_kind
    when 'staff' then staff_pin_hash
    else admin_pin_hash
  end
  into stored_hash
  from public.store_secrets
  where store_id = target_store;

  return stored_hash is not null and extensions.crypt(entered_pin, stored_hash) = stored_hash;
end;
$$;

create or replace function public.update_store_pin(
  target_store uuid,
  new_pin text,
  pin_kind text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_store_owner(target_store) then
    raise exception 'owner authentication required';
  end if;
  if new_pin !~ '^[0-9]{4}$' or pin_kind not in ('staff', 'admin') then
    raise exception 'PIN must be four digits';
  end if;

  update public.store_secrets
  set staff_pin_hash = case when pin_kind = 'staff'
      then extensions.crypt(new_pin, extensions.gen_salt('bf', 12)) else staff_pin_hash end,
      admin_pin_hash = case when pin_kind = 'admin'
      then extensions.crypt(new_pin, extensions.gen_salt('bf', 12)) else admin_pin_hash end,
      updated_at = now()
  where store_id = target_store;

  insert into public.audit_logs(store_id, actor_user_id, action, entity_type, entity_id)
  values(target_store, auth.uid(), 'pin_updated', 'store_secrets', target_store);
end;
$$;

revoke all on function public.verify_store_pin(uuid,text,text) from public;
grant execute on function public.verify_store_pin(uuid,text,text) to anon, authenticated;
revoke all on function public.update_store_pin(uuid,text,text) from public;
grant execute on function public.update_store_pin(uuid,text,text) to authenticated;
