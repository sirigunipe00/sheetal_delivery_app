-- =============================================================================
-- Delivery offers: nearby drivers + accept/cancel + store (pickup) details
-- Shared by Sheetal customer app + Sheetal partner (driver) app.
-- Run once in Supabase SQL Editor.
-- Same file as sheetal_icecream/supabase/upgrade_delivery_offers.sql
-- =============================================================================

begin;

create table if not exists public.delivery_stores (
  id integer primary key default 1 check (id = 1),
  name text not null default 'Sheetal Ice Cream',
  phone text not null default '+91 73000 51000',
  address text not null default 'Sheetal Food World, Hyderabad',
  latitude double precision,
  longitude double precision,
  updated_at timestamptz not null default now()
);

insert into public.delivery_stores (id, name, phone, address)
values (1, 'Sheetal Ice Cream', '+91 73000 51000', 'Sheetal Food World, Hyderabad')
on conflict (id) do nothing;

alter table public.delivery_stores enable row level security;

drop policy if exists "Anyone can read delivery store" on public.delivery_stores;
create policy "Anyone can read delivery store"
  on public.delivery_stores for select
  to authenticated, anon
  using (true);

grant select on public.delivery_stores to authenticated, anon;

alter table public.drivers add column if not exists fcm_token text;

alter table public.driver_order_alerts
  add column if not exists status text;

alter table public.driver_order_alerts
  add column if not exists responded_at timestamptz;

alter table public.driver_order_alerts
  add column if not exists distance_km numeric(8, 2);

update public.driver_order_alerts
set status = coalesce(status, 'pending')
where status is null;

alter table public.driver_order_alerts
  alter column status set default 'pending';

do $$
begin
  alter table public.driver_order_alerts
    add constraint driver_order_alerts_status_check
    check (status in ('pending', 'accepted', 'rejected', 'expired'));
exception when duplicate_object then null;
end $$;

create unique index if not exists driver_order_alerts_unique_offer
  on public.driver_order_alerts (driver_id, order_id);

create or replace function public.haversine_km(
  lat1 double precision,
  lng1 double precision,
  lat2 double precision,
  lng2 double precision
)
returns double precision
language sql
immutable
as $$
  select case
    when lat1 is null or lng1 is null or lat2 is null or lng2 is null then null
    else (
      6371 * acos(
        least(1.0, greatest(-1.0,
          cos(radians(lat1)) * cos(radians(lat2)) *
          cos(radians(lng2) - radians(lng1)) +
          sin(radians(lat1)) * sin(radians(lat2))
        ))
      )
    )
  end;
$$;

create or replace function public.notify_online_drivers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  radius_km constant double precision := 8;
begin
  if new.status is distinct from 'placed' then
    return new;
  end if;

  insert into public.driver_order_alerts (driver_id, order_id, status, distance_km)
  select
    d.id,
    new.id,
    'pending',
    round(public.haversine_km(new.delivery_lat, new.delivery_lng, d.latitude, d.longitude)::numeric, 2)
  from public.drivers d
  where d.is_online = true
    and (
      new.delivery_lat is null
      or new.delivery_lng is null
      or d.latitude is null
      or d.longitude is null
      or public.haversine_km(new.delivery_lat, new.delivery_lng, d.latitude, d.longitude) <= radius_km
    )
  on conflict (driver_id, order_id) do nothing;

  return new;
end;
$$;

drop trigger if exists orders_notify_online_drivers on public.orders;
create trigger orders_notify_online_drivers
  after insert on public.orders
  for each row execute function public.notify_online_drivers();

create or replace function public.notify_drivers_on_reopen()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  radius_km constant double precision := 8;
begin
  if not (
    new.status = 'placed'
    and new.driver_id is null
    and (old.status is distinct from 'placed' or old.driver_id is not null)
  ) then
    return new;
  end if;

  insert into public.driver_order_alerts (driver_id, order_id, status, distance_km)
  select
    d.id,
    new.id,
    'pending',
    round(public.haversine_km(new.delivery_lat, new.delivery_lng, d.latitude, d.longitude)::numeric, 2)
  from public.drivers d
  where d.is_online = true
    and (
      new.delivery_lat is null
      or new.delivery_lng is null
      or d.latitude is null
      or d.longitude is null
      or public.haversine_km(new.delivery_lat, new.delivery_lng, d.latitude, d.longitude) <= radius_km
    )
  on conflict (driver_id, order_id) do update
    set status = 'pending',
        responded_at = null,
        created_at = now(),
        distance_km = excluded.distance_km;

  return new;
end;
$$;

drop trigger if exists orders_notify_drivers_on_reopen on public.orders;
create trigger orders_notify_drivers_on_reopen
  after update of status, driver_id on public.orders
  for each row execute function public.notify_drivers_on_reopen();

create or replace function public.accept_delivery_offer(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver uuid := auth.uid();
  v_order public.orders%rowtype;
  v_store public.delivery_stores%rowtype;
  v_items jsonb;
begin
  if v_driver is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (select 1 from public.drivers d where d.id = v_driver) then
    raise exception 'Not a delivery partner';
  end if;

  update public.driver_order_alerts
  set status = 'accepted', responded_at = now()
  where order_id = p_order_id
    and driver_id = v_driver
    and status = 'pending';

  update public.orders
  set driver_id = v_driver,
      status = 'preparing',
      updated_at = now()
  where id = p_order_id
    and status = 'placed'
    and driver_id is null
  returning * into v_order;

  if v_order.id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Order already taken by another partner'
    );
  end if;

  update public.driver_order_alerts
  set status = 'expired', responded_at = coalesce(responded_at, now())
  where order_id = p_order_id
    and driver_id <> v_driver
    and status = 'pending';

  select * into v_store from public.delivery_stores where id = 1;

  select coalesce(o.items, '[]'::jsonb) into v_items
  from public.orders o
  where o.id = p_order_id;

  if to_regclass('public.order_items') is not null then
    select coalesce(jsonb_agg(to_jsonb(oi) order by oi.id), v_items)
      into v_items
    from public.order_items oi
    where oi.order_id = p_order_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'order', to_jsonb(v_order) || jsonb_build_object('items', v_items),
    'store', to_jsonb(v_store)
  );
end;
$$;

create or replace function public.reject_delivery_offer(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver uuid := auth.uid();
begin
  if v_driver is null then
    raise exception 'Not authenticated';
  end if;

  update public.driver_order_alerts
  set status = 'rejected', responded_at = now()
  where order_id = p_order_id
    and driver_id = v_driver
    and status = 'pending';

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.accept_delivery_offer(uuid) to authenticated;
grant execute on function public.reject_delivery_offer(uuid) to authenticated;
grant execute on function public.haversine_km(double precision, double precision, double precision, double precision) to authenticated;

drop policy if exists "Drivers update own alerts" on public.driver_order_alerts;
create policy "Drivers update own alerts"
  on public.driver_order_alerts
  for update
  to authenticated
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

grant update on public.driver_order_alerts to authenticated;

do $$
begin
  begin
    alter publication supabase_realtime add table public.driver_order_alerts;
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table public.orders;
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table public.delivery_stores;
  exception when others then null;
  end;
end $$;

commit;
