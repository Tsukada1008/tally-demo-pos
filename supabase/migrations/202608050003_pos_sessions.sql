create table if not exists public.pos_sessions (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  token_hash text not null unique,
  device_name text not null default '店舗端末',
  expires_at timestamptz not null,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.pos_sessions enable row level security;

create or replace function public.open_pos_session(
  target_store uuid,
  entered_pin text,
  requested_device_name text default '店舗端末'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  raw_token text;
begin
  if not public.verify_store_pin(target_store, entered_pin, 'staff')
     and not public.verify_store_pin(target_store, entered_pin, 'admin') then
    return null;
  end if;

  delete from public.pos_sessions where expires_at <= now();
  raw_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.pos_sessions(store_id, token_hash, device_name, expires_at)
  values(
    target_store,
    encode(extensions.digest(raw_token, 'sha256'), 'hex'),
    left(coalesce(nullif(trim(requested_device_name), ''), '店舗端末'), 80),
    now() + interval '30 days'
  );
  return raw_token;
end;
$$;

create or replace function public.validate_pos_session(
  target_store uuid,
  raw_token text
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.pos_sessions
    where store_id = target_store
      and token_hash = encode(extensions.digest(raw_token, 'sha256'), 'hex')
      and expires_at > now()
  );
$$;

revoke all on table public.pos_sessions from anon, authenticated;
revoke all on function public.open_pos_session(uuid,text,text) from public;
grant execute on function public.open_pos_session(uuid,text,text) to anon, authenticated;
revoke all on function public.validate_pos_session(uuid,text) from public;
grant execute on function public.validate_pos_session(uuid,text) to anon, authenticated;
