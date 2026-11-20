// Supabase Edge Function: notify-nearby-drivers
// Sends FCM HTTP v1 pushes to online nearby drivers for a new order offer.
//
// Deploy:
//   supabase functions deploy notify-nearby-drivers --no-verify-jwt
//
// Secrets (Dashboard → Edge Functions → Secrets, or CLI):
//   FIREBASE_PROJECT_ID=sheetal-1430e
//   FIREBASE_CLIENT_EMAIL=...@....iam.gserviceaccount.com
//   FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.
//
// Payload (either):
//   { "order_id": "<uuid>" }
//   or Database Webhook shape: { "type":"INSERT", "record": { "order_id": "...", "driver_id": "..." } }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

type AlertRow = {
  driver_id: string;
  order_id: string;
  distance_km: number | null;
  drivers: {
    fcm_token: string | null;
    full_name: string | null;
    is_online: boolean | null;
    latitude: number | null;
    longitude: number | null;
  } | null;
};

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return json({ error: "POST only" }, 405);
    }

    const body = await req.json().catch(() => ({}));
    const orderId = extractOrderId(body);
    const singleDriverId = extractDriverId(body);

    if (!orderId) {
      return json({ error: "order_id required" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
    const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
    const privateKey = (Deno.env.get("FIREBASE_PRIVATE_KEY") ?? "").replace(
      /\\n/g,
      "\n",
    );

    if (!projectId || !clientEmail || !privateKey) {
      return json(
        {
          error:
            "Missing FIREBASE_PROJECT_ID / FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY secrets",
        },
        500,
      );
    }

    const admin = createClient(supabaseUrl, serviceKey);

    const { data: order, error: orderErr } = await admin
      .from("orders")
      .select(
        "id, order_number, status, driver_id, total, customer_name, customer_phone, delivery_address, delivery_lat, delivery_lng, payment_method",
      )
      .eq("id", orderId)
      .maybeSingle();

    if (orderErr) return json({ error: orderErr.message }, 500);
    if (!order) return json({ error: "order not found" }, 404);

    // Already accepted — do not spam remaining partners.
    if (order.driver_id || order.status !== "placed") {
      return json({ skipped: true, reason: "order already assigned" });
    }

    const { data: store } = await admin
      .from("delivery_stores")
      .select("name, phone, address, latitude, longitude")
      .eq("id", 1)
      .maybeSingle();

    let query = admin
      .from("driver_order_alerts")
      .select(
        "driver_id, order_id, distance_km, drivers!inner(fcm_token, full_name, is_online, latitude, longitude)",
      )
      .eq("order_id", orderId)
      .eq("status", "pending")
      .eq("drivers.is_online", true)
      .not("drivers.fcm_token", "is", null);

    if (singleDriverId) {
      query = query.eq("driver_id", singleDriverId);
    }

    const { data: alerts, error: alertErr } = await query;
    if (alertErr) return json({ error: alertErr.message }, 500);

    const rows = (alerts ?? []) as unknown as AlertRow[];
    if (rows.length === 0) {
      return json({ sent: 0, reason: "no nearby online drivers with fcm_token" });
    }

    const accessToken = await getGoogleAccessToken({
      clientEmail,
      privateKey,
    });

    const storeName = store?.name ?? "Sheetal Ice Cream";
    const title = "New Sheetal delivery";
    const bodyText = `${storeName} → ${order.customer_name ?? "Customer"} · ₹${
      Math.round(Number(order.total ?? 0))
    }`.trim();

    const results: Array<{ driver_id: string; ok: boolean; detail?: string }> =
      [];

    for (const row of rows) {
      const token = row.drivers?.fcm_token;
      if (!token) {
        results.push({ driver_id: row.driver_id, ok: false, detail: "no token" });
        continue;
      }

      // distance_km on driver_order_alerts = driver → store (pickup).
      const toStoreKm = row.distance_km;
      const toCustomerKm = haversineKm(
        row.drivers?.latitude,
        row.drivers?.longitude,
        Number(order.delivery_lat),
        Number(order.delivery_lng),
      );
      const storeToCustomerKm = haversineKm(
        store?.latitude != null ? Number(store.latitude) : null,
        store?.longitude != null ? Number(store.longitude) : null,
        Number(order.delivery_lat),
        Number(order.delivery_lng),
      );
      const tripKm =
        toStoreKm != null || storeToCustomerKm != null
          ? (toStoreKm ?? 0) + (storeToCustomerKm ?? 0)
          : toCustomerKm;

      // Data-only high-priority so the app shows Accept/Reject local notif
      // (FCM "notification" payloads skip action buttons on Android).
      const message = {
        message: {
          token,
          data: {
            type: "delivery_offer",
            title,
            body: bodyText,
            order_id: orderId,
            order_number: String(order.order_number ?? ""),
            total: String(order.total ?? ""),
            payment_method: String(order.payment_method ?? "cod"),
            customer_name: String(order.customer_name ?? ""),
            customer_phone: String(order.customer_phone ?? ""),
            delivery_address: String(order.delivery_address ?? ""),
            delivery_lat: String(order.delivery_lat ?? ""),
            delivery_lng: String(order.delivery_lng ?? ""),
            distance_to_store_km: formatKm(toStoreKm),
            distance_to_customer_km: formatKm(toCustomerKm),
            trip_distance_km: formatKm(tripKm),
            store_name: storeName,
            store_phone: String(store?.phone ?? ""),
            store_address: String(store?.address ?? ""),
            store_lat: String(store?.latitude ?? ""),
            store_lng: String(store?.longitude ?? ""),
          },
          android: {
            priority: "HIGH",
          },
          apns: {
            headers: {
              "apns-priority": "10",
              "apns-push-type": "alert",
            },
            payload: {
              aps: {
                alert: { title, body: bodyText },
                sound: "default",
                contentAvailable: true,
                interruptionLevel: "time-sensitive",
              },
            },
          },
        },
      };

      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(message),
        },
      );

      if (!res.ok) {
        const detail = await res.text();
        results.push({ driver_id: row.driver_id, ok: false, detail });
        // Drop invalid tokens so we stop retrying them.
        if (detail.includes("UNREGISTERED") || detail.includes("INVALID_ARGUMENT")) {
          await admin
            .from("drivers")
            .update({ fcm_token: null })
            .eq("id", row.driver_id)
            .eq("fcm_token", token);
        }
      } else {
        results.push({ driver_id: row.driver_id, ok: true });
      }
    }

    return json({
      sent: results.filter((r) => r.ok).length,
      failed: results.filter((r) => !r.ok).length,
      results,
    });
  } catch (error) {
    return json({ error: String(error) }, 500);
  }
});

function extractOrderId(body: Record<string, unknown>): string | null {
  if (typeof body.order_id === "string") return body.order_id;
  const record = body.record as Record<string, unknown> | undefined;
  if (record && typeof record.order_id === "string") return record.order_id;
  return null;
}

function extractDriverId(body: Record<string, unknown>): string | null {
  if (typeof body.driver_id === "string") return body.driver_id;
  const record = body.record as Record<string, unknown> | undefined;
  if (record && typeof record.driver_id === "string") return record.driver_id;
  return null;
}

async function getGoogleAccessToken(opts: {
  clientEmail: string;
  privateKey: string;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: opts.clientEmail,
    scope: FCM_SCOPE,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encoded = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claim))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(opts.privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(encoded),
  );
  const jwt = `${encoded}.${b64url(signature)}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!tokenRes.ok) {
    throw new Error(`Google token error: ${await tokenRes.text()}`);
  }
  const jsonBody = await tokenRes.json();
  return jsonBody.access_token as string;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function b64url(input: string | ArrayBuffer): string {
  const bytes =
    typeof input === "string"
      ? new TextEncoder().encode(input)
      : new Uint8Array(input);
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function haversineKm(
  lat1: number | null | undefined,
  lng1: number | null | undefined,
  lat2: number | null | undefined,
  lng2: number | null | undefined,
): number | null {
  if (
    lat1 == null ||
    lng1 == null ||
    lat2 == null ||
    lng2 == null ||
    Number.isNaN(lat1) ||
    Number.isNaN(lng1) ||
    Number.isNaN(lat2) ||
    Number.isNaN(lng2)
  ) {
    return null;
  }
  const toRad = (d: number) => (d * Math.PI) / 180;
  const r = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function formatKm(km: number | null | undefined): string {
  if (km == null || Number.isNaN(km)) return "";
  if (km < 1) return `${Math.round(km * 1000)} m`;
  return `${km < 10 ? km.toFixed(1) : Math.round(km)} km`;
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
