// supabase/functions/send-push/index.ts
//
// Delivers one notification to every device registered for a user via
// Firebase Cloud Messaging (HTTP v1 API). Called internally by the
// `findit_dispatch_push` Postgres trigger (see
// supabase/migrations/0005_push_notifications.sql) whenever a row is
// inserted into `notifications` — not meant to be called by the app itself.
//
// Deploy:
//   supabase functions deploy send-push --no-verify-jwt
//
// Requires one secret, set once:
//   supabase secrets set FCM_SERVICE_ACCOUNT_JSON="$(cat service-account.json)"
// (the full JSON key downloaded from Firebase Console -> Project Settings ->
// Service Accounts -> Generate new private key)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const FCM_SERVICE_ACCOUNT_JSON = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const buf = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let str = '';
  for (const b of buf) str += String.fromCharCode(b);
  return btoa(str).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const contents = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const der = Uint8Array.from(atob(contents), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    'pkcs8',
    der.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function getGoogleAccessToken(serviceAccountJson: string): Promise<string> {
  const sa = JSON.parse(serviceAccountJson);
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const encoder = new TextEncoder();
  const toSign = `${base64url(encoder.encode(JSON.stringify(header)))}.${base64url(encoder.encode(JSON.stringify(claim)))}`;
  const key = await importPrivateKey(sa.private_key);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(toSign));
  const jwt = `${toSign}.${base64url(signature)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(`Failed to get Google access token: ${JSON.stringify(json)}`);
  return json.access_token as string;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405 });
  }

  if (!FCM_SERVICE_ACCOUNT_JSON) {
    // Push isn't configured yet — the notification still exists in-app via
    // the `notifications` table either way, so this is a soft no-op.
    return new Response(JSON.stringify({ skipped: 'FCM_SERVICE_ACCOUNT_JSON not set' }), { status: 200 });
  }

  const { user_id, title, body } = await req.json();
  if (!user_id || !title) {
    return new Response(JSON.stringify({ error: 'Missing user_id or title' }), { status: 400 });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const { data: tokens, error } = await admin
    .from('device_tokens')
    .select('token')
    .eq('user_id', user_id);

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
  if (!tokens || tokens.length === 0) {
    return new Response(JSON.stringify({ skipped: 'no registered devices' }), { status: 200 });
  }

  // Badge count (iOS reads this to update the app icon badge; Android
  // ignores it, since badge/dot display there is launcher-controlled and
  // driven by the number of active notifications instead).
  const { count: badgeCount } = await admin
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', user_id)
    .eq('read', false);

  const sa = JSON.parse(FCM_SERVICE_ACCOUNT_JSON);
  const accessToken = await getGoogleAccessToken(FCM_SERVICE_ACCOUNT_JSON);

  const results = [];
  for (const { token } of tokens) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body: body ?? '' },
            // Explicit sound + a stable channel id so Android plays a
            // sound even when the app is backgrounded or fully killed —
            // the channel itself is auto-created by the FCM Android SDK
            // from the `default_notification_channel_id` meta-data in
            // AndroidManifest.xml the first time it's referenced.
            android: {
              notification: {
                channel_id: 'foundify_default',
                sound: 'default',
              },
            },
            apns: {
              payload: {
                aps: { sound: 'default', badge: badgeCount ?? 0 },
              },
            },
          },
        }),
      },
    );
    const json = await res.json();

    // A token FCM rejects as invalid/unregistered is stale (app reinstalled,
    // notifications revoked, etc.) — clean it up so we stop trying it.
    if (res.status === 404 || json?.error?.status === 'UNREGISTERED') {
      await admin.from('device_tokens').delete().eq('token', token);
    }
    results.push({ token, status: res.status });
  }

  return new Response(JSON.stringify({ sent: results }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
