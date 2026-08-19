create or replace function public.move_pos_open_check(
  target_store uuid, raw_token text, check_id uuid, new_table_name text
)
returns void language plpgsql security definer set search_path=public as $$
declare new_table_id uuid;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  select id into new_table_id from public.bar_tables
    where store_id=target_store and name=new_table_name and enabled limit 1;
  if new_table_id is null then raise exception 'table not found'; end if;
  if exists(select 1 from public.checks where store_id=target_store and table_id=new_table_id and status='open' and id<>check_id) then
    raise exception 'destination table is occupied';
  end if;
  update public.checks set table_id=new_table_id,updated_at=now()
    where id=check_id and store_id=target_store and status='open';
  if not found then raise exception 'open check not found'; end if;
end; $$;

revoke all on function public.move_pos_open_check(uuid,text,uuid,text) from public;
grant execute on function public.move_pos_open_check(uuid,text,uuid,text) to anon,authenticated;
