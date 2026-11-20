# Nearby order push alerts (Partner app)

## What happens

1. Customer places an order (with `delivery_lat` / `delivery_lng` when available).
2. `notify_online_drivers()` finds **online** drivers within **8 km**.
3. Rows are inserted into `driver_order_alerts`.
4. Edge Function `notify-nearby-drivers` sends **FCM** to those drivers’ `fcm_token`.
5. Partner taps notification → Accept / Cancel overlay.
6. First partner to call `accept_delivery_offer()` wins; other offers become `expired`.

Realtime stays as a backup while the app is open.

## 1. Run SQL (once)

In Supabase SQL editor, run in order:

1. `create_delivery_schema.sql` (if not already)
2. `upgrade_delivery_offers.sql`
3. `enable_push_alerts.sql`

Then enable pg_net + set URL/key:

```sql
create extension if not exists pg_net with schema extensions;

alter database postgres set app.settings.notify_drivers_url =
  'https://kmiuxdaaznmzdbhmrmmh.supabase.co/functions/v1/notify-nearby-drivers';

alter database postgres set app.settings.notify_drivers_key =
  '<SERVICE_ROLE_KEY>';
```

**Or** skip pg_net and create a Database Webhook:

- Table: `driver_order_alerts`
- Event: `INSERT`
- URL: `https://kmiuxdaaznmzdbhmrmmh.supabase.co/functions/v1/notify-nearby-drivers`
- HTTP Headers: `Authorization: Bearer <SERVICE_ROLE_OR_ANON>`

## 2. Firebase for Partner Android app

1. Firebase Console → project `sheetal-1430e`
2. Add a **second** Android app (do not reuse the customer app) with package:
   `in.easycloud.sheetal_partner`
   Customer app stays: `in.easycloud.sheetal_ice_creams`
3. Download that app’s `google-services.json` → replace `android/app/google-services.json`
4. Update `lib/firebase_options.dart` Android `appId` (or run `flutterfire configure`)
5. Project Settings → Service accounts → Generate new private key
6. Supabase Edge Function secrets:

```bash
supabase secrets set \
  FIREBASE_PROJECT_ID=sheetal-1430e \
  FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@sheetal-1430e.iam.gserviceaccount.com \
  FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

## 3. Deploy Edge Function

```bash
cd sheetal_driver_app
supabase functions deploy notify-nearby-drivers --no-verify-jwt
```

## 4. Partner app behaviour

| Event | Action |
|---|---|
| Login / Go Online | Request notification permission, save `drivers.fcm_token` |
| Token refresh | Update `drivers.fcm_token` |
| Logout / Offline | Clear token (logout) / stop listening (offline) |
| Foreground FCM | Show Accept / Cancel overlay |
| Notification tap | Open that order offer |
| Accept | `accept_delivery_offer` — first wins |
| Cancel | `reject_delivery_offer` for this partner only |

## 5. Change alert radius

Edit `radius_km` in `enable_push_alerts.sql` (`notify_online_drivers` / `notify_drivers_on_reopen`), then re-run that function definition.
