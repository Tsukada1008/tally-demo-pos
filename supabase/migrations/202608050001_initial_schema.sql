create extension if not exists pgcrypto;

create type public.payment_method as enum ('cash','qr','receivable','other');
create type public.check_status as enum ('open','paid','voided');
create type public.receivable_status as enum ('unpaid','paid','voided');
create type public.line_kind as enum ('product','staff_drink');

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text not null default '',
  phone text not null default '',
  business_day_cutoff time not null default '06:00',
  receipt_note text not null default '',
  invoice_registration_number text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.store_members (
  store_id uuid not null references public.stores(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner')),
  created_at timestamptz not null default now(),
  primary key (store_id,user_id)
);

create table public.store_secrets (
  store_id uuid primary key references public.stores(id) on delete cascade,
  staff_pin_hash text not null,
  admin_pin_hash text not null,
  updated_at timestamptz not null default now()
);

create table public.store_settings (
  store_id uuid primary key references public.stores(id) on delete cascade,
  payment_qr_path text,
  next_check_number bigint not null default 1,
  tax_rounding text not null default 'floor' check (tax_rounding in ('floor','round','ceil')),
  updated_at timestamptz not null default now()
);

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  token_hash text not null unique,
  enabled boolean not null default true,
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  color text not null default '#6b7280',
  display_order integer not null default 0,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(store_id,name)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  category_id uuid not null references public.categories(id),
  name text not null,
  price integer not null check (price >= 0),
  tax_rate numeric(5,2) not null default 10 check (tax_rate >= 0 and tax_rate <= 100),
  display_order integer not null default 0,
  enabled boolean not null default true,
  staff_drink_enabled boolean not null default false,
  back_amount integer not null default 0 check (back_amount >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(store_id,name)
);

create table public.staff (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  display_order integer not null default 0,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(store_id,name)
);

create table public.bar_tables (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  table_number text not null default '',
  display_order integer not null default 0,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(store_id,name)
);

create table public.discount_presets (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  kind text not null check (kind in ('amount','percent','service')),
  value numeric(10,2) not null default 0 check (value >= 0),
  display_order integer not null default 0,
  enabled boolean not null default true,
  unique(store_id,name)
);

create table public.checks (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  table_id uuid references public.bar_tables(id),
  check_number bigint not null,
  business_date date not null,
  status public.check_status not null default 'open',
  customer_name text not null default '',
  guest_count integer not null default 1 check (guest_count > 0),
  memo text not null default '',
  subtotal integer not null default 0 check (subtotal >= 0),
  discount_amount integer not null default 0 check (discount_amount >= 0),
  tax_amount integer not null default 0 check (tax_amount >= 0),
  total_amount integer not null default 0 check (total_amount >= 0),
  opened_at timestamptz not null default now(),
  paid_at timestamptz,
  voided_at timestamptz,
  void_reason text,
  created_by_device uuid references public.devices(id),
  updated_at timestamptz not null default now(),
  unique(store_id,check_number)
);

create unique index one_open_check_per_table on public.checks(table_id) where status='open';
create index checks_store_business_date_idx on public.checks(store_id,business_date,status);

create table public.check_lines (
  id uuid primary key default gen_random_uuid(),
  check_id uuid not null references public.checks(id) on delete cascade,
  kind public.line_kind not null default 'product',
  product_id uuid references public.products(id),
  staff_id uuid references public.staff(id),
  product_name text not null,
  category_name text not null,
  staff_name text,
  unit_price integer not null check (unit_price >= 0),
  tax_rate numeric(5,2) not null check (tax_rate >= 0 and tax_rate <= 100),
  quantity integer not null default 1 check (quantity > 0),
  back_amount integer not null default 0 check (back_amount >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((kind='staff_drink' and staff_id is not null and staff_name is not null) or kind='product')
);

create index check_lines_check_idx on public.check_lines(check_id);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  check_id uuid not null references public.checks(id),
  method public.payment_method not null,
  amount integer not null check (amount >= 0),
  received_amount integer check (received_amount is null or received_amount >= amount),
  change_amount integer not null default 0 check (change_amount >= 0),
  recorded_at timestamptz not null default now(),
  voided_at timestamptz,
  unique(check_id)
);

create table public.receivables (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  check_id uuid not null unique references public.checks(id),
  debtor_name text not null,
  amount integer not null check (amount > 0),
  memo text not null default '',
  due_date date,
  status public.receivable_status not null default 'unpaid',
  paid_at timestamptz,
  paid_method public.payment_method,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index receivables_store_status_idx on public.receivables(store_id,status,due_date);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  store_id uuid not null references public.stores(id),
  actor_type text not null check (actor_type in ('owner','device','system')),
  actor_id text,
  action text not null,
  entity_type text not null,
  entity_id text,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create index audit_logs_store_created_idx on public.audit_logs(store_id,created_at desc);

create or replace function public.is_store_owner(target_store uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.store_members m where m.store_id=target_store and m.user_id=auth.uid() and m.role='owner') $$;

create or replace function public.business_date_for(target_store uuid, moment timestamptz default now())
returns date language sql stable security definer set search_path=public
as $$ select (moment at time zone 'Asia/Tokyo' - s.business_day_cutoff)::date from public.stores s where s.id=target_store $$;

alter table public.stores enable row level security;
alter table public.store_members enable row level security;
alter table public.store_secrets enable row level security;
alter table public.store_settings enable row level security;
alter table public.devices enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.staff enable row level security;
alter table public.bar_tables enable row level security;
alter table public.discount_presets enable row level security;
alter table public.checks enable row level security;
alter table public.check_lines enable row level security;
alter table public.payments enable row level security;
alter table public.receivables enable row level security;
alter table public.audit_logs enable row level security;

create policy owner_stores on public.stores for all using (public.is_store_owner(id)) with check (public.is_store_owner(id));
create policy owner_members on public.store_members for select using (user_id=auth.uid() or public.is_store_owner(store_id));
create policy owner_settings on public.store_settings for all using (public.is_store_owner(store_id)) with check (public.is_store_owner(store_id));
create policy owner_devices on public.devices for all using (public.is_store_owner(store_id)) with check (public.is_store_owner(store_id));
create policy owner_categories on public.categories for all using (public.is_store_owner(store_id)) with check (public.is_store_owner(store_id));
create policy owner_products on public.products for all using (public.is_store_owner(store_id)) with check (public.is_store_owner(store_id));
create policy owner_staff on public.staff for all using (public.is_store_owner(store_id)) with check (public.is_store_owner(store_id));
create policy owner_tables on public.bar_tables for all using (public.is_store_owner(store_id)) with check (public.is_store_owner(store_id));
create policy owner_discounts on public.discount_presets for all using (public.is_store_owner(store_id)) with check (public.is_store_owner(store_id));
create policy owner_checks on public.checks for all using (public.is_store_owner(store_id)) with check (public.is_store_owner(store_id));
create policy owner_lines on public.check_lines for all using (exists(select 1 from public.checks c where c.id=check_id and public.is_store_owner(c.store_id))) with check (exists(select 1 from public.checks c where c.id=check_id and public.is_store_owner(c.store_id)));
create policy owner_payments on public.payments for all using (exists(select 1 from public.checks c where c.id=check_id and public.is_store_owner(c.store_id))) with check (exists(select 1 from public.checks c where c.id=check_id and public.is_store_owner(c.store_id)));
create policy owner_receivables on public.receivables for all using (public.is_store_owner(store_id)) with check (public.is_store_owner(store_id));
create policy owner_audit on public.audit_logs for select using (public.is_store_owner(store_id));

-- Secrets are deliberately inaccessible through the public API. Server-side service-role code only.
revoke all on public.store_secrets from anon, authenticated;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('payment-qr','payment-qr',false,2097152,array['image/png','image/jpeg','image/webp'])
on conflict (id) do nothing;

create policy owner_payment_qr_select on storage.objects for select to authenticated
using (bucket_id='payment-qr' and public.is_store_owner((storage.foldername(name))[1]::uuid));
create policy owner_payment_qr_write on storage.objects for all to authenticated
using (bucket_id='payment-qr' and public.is_store_owner((storage.foldername(name))[1]::uuid))
with check (bucket_id='payment-qr' and public.is_store_owner((storage.foldername(name))[1]::uuid));
