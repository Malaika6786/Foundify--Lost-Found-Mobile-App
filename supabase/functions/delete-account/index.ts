// supabase/functions/delete-account/index.ts
//
// Deletes the calling user's auth account and owned data. Must run with the
// service-role key (never shipped to the client) because deleting an
// auth.users row is not possible with the publishable/anon key.
//
// Deploy:
//   supabase functions deploy delete-account
// Invoke from the app with the caller's own session (already wired in
// SupabaseService.deleteAccount()) — the function derives the user id from
// the caller's JWT, so nobody can delete another user's account.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405 });
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const jwt = authHeader.replace('Bearer ', '');
  if (!jwt) {
    return new Response(JSON.stringify({ error: 'Missing authorization' }), { status: 401 });
  }

  // Verify the caller's identity using their own JWT (anon-key client).
  const callerClient = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await callerClient.auth.getUser(jwt);
  if (userErr || !userData?.user) {
    return new Response(JSON.stringify({ error: 'Invalid session' }), { status: 401 });
  }
  const userId = userData.user.id;

  // Service-role client to perform privileged deletes.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Clean up owned rows first (in case FKs aren't set to cascade in older schemas).
  await admin.from('items').delete().eq('user_id', userId);
  await admin.from('comments').delete().eq('user_id', userId);
  await admin.from('likes').delete().eq('user_id', userId);
  await admin.from('item_tags').delete().eq('user_id', userId);
  await admin.from('alert_prefs').delete().eq('user_id', userId);
  await admin.from('notifications').delete().eq('user_id', userId);
  await admin.from('profiles').delete().eq('id', userId);

  const { error: deleteErr } = await admin.auth.admin.deleteUser(userId);
  if (deleteErr) {
    return new Response(JSON.stringify({ error: deleteErr.message }), { status: 500 });
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
