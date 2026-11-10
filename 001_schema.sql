-- DigiVault core schema + RLS. Run in Supabase SQL editor.
create extension if not exists pgcrypto;

create type payment_status as enum ('awaiting_payment','under_review','approved','rejected','refunded');
create type delivery_status as enum ('pending','delivered','completed');
create type delivery_type as enum ('automatic','manual','external');

-- Profiles: everyone is 'customer' on signup. Admin is set ONLY manually via SQL.
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  email text, role text not null default 'customer' check (role in ('customer','admin')),
  created_at timestamptz default now()
);
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin insert into profiles(id,email,role) values (new.id,new.email,'customer'); return new; end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

create or replace function is_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin') $$;

-- Block privilege escalation: nobody can change their own role via the API
create or replace function protect_role() returns trigger language plpgsql as $$
begin
  if new.role is distinct from old.role and current_user not in ('postgres','service_role') then
    raise exception 'role change not allowed'; end if;
  return new; end $$;
create trigger profiles_protect_role before update on profiles
  for each row execute function protect_role();

create table categories (
  id uuid primary key default gen_random_uuid(),
  name text not null, slug text unique not null, sort int default 0
);

create table products (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null, name text not null, description text,
  price numeric(12,2) not null check (price >= 0),
  sale_price numeric(12,2) check (sale_price >= 0),
  currency text not null default 'USD',
  category_id uuid references categories on delete set null,
  image_url text, delivery delivery_type not null default 'automatic',
  instructions text,
  featured boolean default false, best_seller boolean default false,
  active boolean default true, created_at timestamptz default now()
);

-- PRIVATE inventory (codes/files). No policies for anon/authenticated => server-only.
create table product_inventory (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products on delete cascade,
  payload text not null,                 -- code or storage path (encrypt at app layer)
  order_id uuid, delivered_at timestamptz,
  created_at timestamptz default now()
);

create table coupons (
  id uuid primary key default gen_random_uuid(),
  code text unique not null, percent_off int check (percent_off between 1 and 100),
  amount_off numeric(12,2), max_uses int, used int default 0,
  expires_at timestamptz, active boolean default true
);

create table orders (
  id uuid primary key default gen_random_uuid(),
  ref text unique not null,              -- public order reference, e.g. DV-8F3K2A
  token_hash text not null,              -- sha256(token + pepper); raw token only emailed/shown once
  customer_email text not null, customer_name text,
  total numeric(12,2) not null, currency text not null,
  payment_method text not null check (payment_method in ('binance','baridimob')),
  payment_reference text, receipt_path text,
  payment_status payment_status not null default 'awaiting_payment',
  delivery_status delivery_status not null default 'pending',
  coupon_id uuid references coupons, admin_notes text,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders on delete cascade,
  product_id uuid references products on delete set null,
  name text not null, unit_price numeric(12,2) not null, qty int not null check (qty > 0)
);
create table order_events (  -- audit/history
  id bigserial primary key, order_id uuid references orders on delete cascade,
  actor uuid, event text not null, created_at timestamptz default now()
);
create table reviews (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references products on delete cascade,
  author text not null, rating int check (rating between 1 and 5), body text,
  approved boolean default false, created_at timestamptz default now()
);
create table settings (key text primary key, value jsonb not null);  -- maintenance mode, payment details, links

-- RLS
alter table profiles enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table product_inventory enable row level security;
alter table coupons enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table order_events enable row level security;
alter table reviews enable row level security;
alter table settings enable row level security;

create policy "own profile read" on profiles for select using (id = auth.uid() or is_admin());
create policy "cat public read" on categories for select using (true);
create policy "cat admin write" on categories for all using (is_admin()) with check (is_admin());
create policy "products public read" on products for select using (active or is_admin());
create policy "products admin write" on products for all using (is_admin()) with check (is_admin());
create policy "reviews public read" on reviews for select using (approved or is_admin());
create policy "reviews admin write" on reviews for all using (is_admin()) with check (is_admin());
create policy "orders admin all" on orders for all using (is_admin()) with check (is_admin());
create policy "items admin all" on order_items for all using (is_admin()) with check (is_admin());
create policy "events admin all" on order_events for all using (is_admin()) with check (is_admin());
create policy "coupons admin all" on coupons for all using (is_admin()) with check (is_admin());
create policy "settings admin all" on settings for all using (is_admin()) with check (is_admin());
-- product_inventory: intentionally NO policies. Only the service role (server) can touch it.
-- Customers never query orders directly: the server validates ref+token, then uses the service role.

-- Storage (create in dashboard or here)
insert into storage.buckets (id,name,public) values ('product-images','product-images',true) on conflict do nothing;
insert into storage.buckets (id,name,public) values ('receipts','receipts',false) on conflict do nothing;
create policy "img admin write" on storage.objects for all
  using (bucket_id='product-images' and is_admin()) with check (bucket_id='product-images' and is_admin());
create policy "receipts admin read" on storage.objects for select
  using (bucket_id='receipts' and is_admin());
-- Receipt uploads go through a server route that validates type/size, then uploads with the service role.

-- ONE-TIME: after you sign up with your own email, promote yourself:
--   update profiles set role='admin' where email='YOU@example.com';
