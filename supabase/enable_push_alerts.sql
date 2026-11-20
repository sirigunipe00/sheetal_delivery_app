-- =============================================================================
-- Push alerts for nearby online drivers (FCM via Edge Function)
-- Run AFTER create_delivery_schema.sql and upgrade_delivery_offers.sql
-- =============================================================================
-- Flow:
-- 1) Customer places order → this function inserts nearby/online alerts
-- 2) Customer app also calls Edge Function notify-nearby-drivers
-- 3) Optional: pg_net / Database Webhook also calls that function
-- =============================================================================

begin;

alter table public.drivers add column if not exists fcm_token text;

create index if not exists drivers_fcm_token_idx
  on public.drivers (fcm_token)
  where fcm_token is not null;

create or replace function public.request_nearby_driver_push(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public, net
as $$
declare
  edge_url text := coalesce(
    nullif(current_setting('app.settings.notify_drivers_url', true), ''),
    'https://kmiuxdaaznmzdbhmrmmh.supabase.co/functions/v1/notify-nearby-drivers'
  );
  edge_key text := nullif(current_setting('app.settings.notify_drivers_key', true), '');
begin
  if edge_key is null then
    raise notice 'Push skipped: set app.settings.notify_drivers_key (service role)';
    return;
  end if;

  perform net.http_post(
    url := edge_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || edge_key
    ),
    body := jsonb_build_object('order_id', p_order_id)
  );
exception
  when undefined_function then
    raise notice 'pg_net missing — customer app still invokes the Edge Function';
  when others then
    raise notice 'Push request failed: %', sqlerrm;
end;
$$;

-- Nearby when coords exist; otherwise all online drivers.
create or replace function public.notify_online_drivers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  radius_km constant double precision := 8;
  center_lat double precision;
  center_lng double precision;
  inserted int := 0;
begin
  if new.status is distinct from 'placed' then
    return new;
  end if;

  center_lat := new.delivery_lat;
  center_lng := new.delivery_lng;

  if center_lat is null or center_lng is null then
    select s.latitude, s.longitude
      into center_lat, center_lng
    from public.delivery_stores s
    where s.id = 1;
  end if;

  if center_lat is not null and center_lng is not null then
    insert into public.driver_order_alerts (driver_id, order_id, status, distance_km)
    select
      d.id,
      new.id,
      'pending',
      round(public.haversine_km(center_lat, center_lng, d.latitude, d.longitude)::numeric, 2)
    from public.drivers d
    where d.is_online = true
      and d.latitude is not null
      and d.longitude is not null
      and public.haversine_km(center_lat, center_lng, d.latitude, d.longitude) <= radius_km
    on conflict (driver_id, order_id) do nothing;
    get diagnostics inserted = row_count;
  end if;

  -- Fallback: no coords or nobody nearby → alert every online partner
  if inserted = 0 then
    insert into public.driver_order_alerts (driver_id, order_id, status, distance_km)
    select d.id, new.id, 'pending', null
    from public.drivers d
    where d.is_online = true
    on conflict (driver_id, order_id) do nothing;
  end if;

  perform public.request_nearby_driver_push(new.id);
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
  center_lat double precision;
  center_lng double precision;
  inserted int := 0;
begin
  if not (
    new.status = 'placed'
    and new.driver_id is null
    and (old.status is distinct from 'placed' or old.driver_id is not null)
  ) then
    return new;
  end if;

  center_lat := new.delivery_lat;
  center_lng := new.delivery_lng;
  if center_lat is null or center_lng is null then
    select s.latitude, s.longitude
      into center_lat, center_lng
    from public.delivery_stores s
    where s.id = 1;
  end if;

  if center_lat is not null and center_lng is not null then
    insert into public.driver_order_alerts (driver_id, order_id, status, distance_km)
    select
      d.id,
      new.id,
      'pending',
      round(public.haversine_km(center_lat, center_lng, d.latitude, d.longitude)::numeric, 2)
    from public.drivers d
    where d.is_online = true
      and d.latitude is not null
      and d.longitude is not null
      and public.haversine_km(center_lat, center_lng, d.latitude, d.longitude) <= radius_km
    on conflict (driver_id, order_id) do update
      set status = 'pending',
          responded_at = null,
          created_at = now(),
          distance_km = excluded.distance_km;
    get diagnostics inserted = row_count;
  end if;

  if inserted = 0 then
    insert into public.driver_order_alerts (driver_id, order_id, status, distance_km)
    select d.id, new.id, 'pending', null
    from public.drivers d
    where d.is_online = true
    on conflict (driver_id, order_id) do update
      set status = 'pending',
          responded_at = null,
          created_at = now(),
          distance_km = null;
  end if;

  perform public.request_nearby_driver_push(new.id);
  return new;
end;
$$;

drop trigger if exists orders_notify_drivers_on_reopen on public.orders;
create trigger orders_notify_drivers_on_reopen
  after update of status, driver_id on public.orders
  for each row execute function public.notify_drivers_on_reopen();

commit;

-- -----------------------------------------------------------------------------
-- REQUIRED one-time setup:
--
-- 1) Deploy Edge Function (from sheetal_driver_app):
--      supabase functions deploy notify-nearby-drivers --no-verify-jwt
--
-- 2) Set Firebase secrets:
--      supabase secrets set FIREBASE_PROJECT_ID=sheetal-1430e \
--        FIREBASE_CLIENT_EMAIL=... \
--        FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
--
-- 3) Optional DB push (pg_net) — customer app also invokes the function:
--      create extension if not exists pg_net with schema extensions;
--      alter database postgres set app.settings.notify_drivers_key = '<SERVICE_ROLE_KEY>';
--
-- 4) Partner app: login → allow notifications → Go Online
--    Check drivers.fcm_token is NOT null in Table Editor.
-- -----------------------------------------------------------------------------
