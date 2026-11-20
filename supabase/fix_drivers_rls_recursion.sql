-- Fix: PostgrestException 42P17
-- "infinite recursion detected in policy for relation \"drivers\""
--
-- Cause: an RLS policy on public.drivers that SELECTs from public.drivers
-- (common with "is admin" checks). Run this in Supabase → SQL Editor.

-- Helper used by OTHER tables (orders, etc). SECURITY DEFINER so it does
-- not re-enter drivers RLS and cannot recurse.
create or replace function public.is_sheetal_driver()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.drivers d where d.id = auth.uid()
  );
$$;

revoke all on function public.is_sheetal_driver() from public;
grant execute on function public.is_sheetal_driver() to authenticated;

-- Drop EVERY policy currently on drivers (names may vary in production).
do $$
declare
  pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'drivers'
  loop
    execute format('drop policy if exists %I on public.drivers', pol.policyname);
  end loop;
end $$;

-- Safe non-recursive policy: partners only touch their own row.
create policy "Drivers manage own profile"
  on public.drivers
  for all
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Optional: service role / dashboard still bypasses RLS.
-- If you need an admin UI later, use a SECURITY DEFINER RPC
-- (like admin_review_partner) — never "exists (select from drivers)" inside
-- a drivers policy.

-- Point order policies at the helper so they also cannot recurse.
drop policy if exists "Drivers read delivery orders" on public.orders;
create policy "Drivers read delivery orders"
  on public.orders
  for select
  to authenticated
  using (public.is_sheetal_driver());

drop policy if exists "Drivers update delivery orders" on public.orders;
create policy "Drivers update delivery orders"
  on public.orders
  for update
  to authenticated
  using (public.is_sheetal_driver())
  with check (public.is_sheetal_driver());

do $$
begin
  if to_regclass('public.order_items') is not null then
    execute 'drop policy if exists "Drivers read order items" on public.order_items';
    execute 'create policy "Drivers read order items" on public.order_items for select to authenticated using (public.is_sheetal_driver())';
  end if;
end $$;
