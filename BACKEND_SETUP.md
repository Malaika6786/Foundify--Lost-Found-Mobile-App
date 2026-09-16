# Foundify backend setup (one-time, manual — needs your Supabase login)

I don't have your Supabase dashboard login, database password, or CLI access
token, so these three steps can't be done by me directly. Everything else in
the app is already fully wired to the real backend.

## 1. Run the schema migrations (required — nothing new works without this)

1. Go to https://supabase.com/dashboard → your project → **SQL Editor** → **New query**.
2. Paste the entire contents of [`supabase/migrations/0001_findit_full_backend.sql`](supabase/migrations/0001_findit_full_backend.sql).
3. Click **Run**.
4. New query again → paste [`supabase/migrations/0002_alert_prefs_matching.sql`](supabase/migrations/0002_alert_prefs_matching.sql) → **Run**.
   (This one updates the matching trigger so a user's Alert Radius settings —
   distance, watched categories, push toggle, AI-only — actually govern
   whether they get notified of a match, instead of being saved but ignored.)
5. New query again → paste [`supabase/migrations/0003_tag_scan_landing.sql`](supabase/migrations/0003_tag_scan_landing.sql) → **Run**.
   (Adds the `tag_messages` table + trigger backing the "scan a tag" landing
   page — lets a finder with no account message a tag's owner.)
6. New query again → paste [`supabase/migrations/0004_tag_messages_delete.sql`](supabase/migrations/0004_tag_messages_delete.sql) → **Run**.
   (Lets a tag's owner delete messages left on it — backs swipe-to-dismiss.)
7. New query again → paste [`supabase/migrations/0005_push_notifications.sql`](supabase/migrations/0005_push_notifications.sql) → **Run**.
   (Adds `device_tokens` + a trigger that calls the new `send-push` Edge
   Function — see the Push Notifications section below.)

This adds `items.category`, `items.location_label`, `profiles.phone` /
`notifications_enabled` / `language_code`, and six new tables (`alert_prefs`,
`item_tags`, `notifications`, `safe_spots`, `meetup_proposals`,
`institution_partners`, `claims`, `item_matches`), plus three Postgres
triggers that auto-score item matches and auto-create notifications. It's
idempotent — safe to run again if you ever need to.

## 2. Deploy the account-deletion Edge Function

Deleting an `auth.users` row requires the service-role key, which never ships
to the client — so this one piece of logic has to run on Supabase's servers,
not in the app.

```bash
npm install -g supabase
supabase login
supabase link --project-ref dkainvkujpjzxngqnsrn
supabase functions deploy delete-account
```

No extra secrets to set — `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`SUPABASE_SERVICE_ROLE_KEY` are already injected automatically for every Edge
Function.

## 3. Enable Google sign-in (optional)

The app already calls `signInWithOAuth(OAuthProvider.google)` — it just needs
the provider turned on:

1. Google Cloud Console → create an OAuth 2.0 Client ID (Web application).
2. Supabase Dashboard → **Authentication → Providers → Google** → paste the
   Client ID/Secret → Save.
3. Add the redirect URL Supabase shows you back into the Google Cloud
   Console's "Authorized redirect URIs".

Until this is done, the "Continue with Google" button will show an error
snackbar instead of crashing — everything else in the app works without it.

## 4. Push notifications (Android)

This is the biggest of the four — it touches a Firebase project, a native
Android config file, an Edge Function, and one secret. Every step is guarded
so the app keeps working normally at every point along the way, even before
you finish this section.

### 4a. Create the Firebase project + Android app

1. Go to https://console.firebase.google.com → **Add project** (or reuse one).
2. Inside it, **Add app → Android**.
3. Android package name: **`com.example.lost_and_found_app`** (must match
   exactly — that's the `applicationId` in `android/app/build.gradle.kts`).
4. Download the **`google-services.json`** it gives you and place it at:
   ```
   android/app/google-services.json
   ```
   (Once this file exists, the Gradle build automatically picks it up — I
   wired that conditionally so the build doesn't break before this file
   exists.)

### 4b. Generate a service account key (lets our server call FCM)

1. Firebase Console → ⚙️ **Project settings → Service accounts**.
2. **Generate new private key** → downloads a JSON file. Keep it secret —
   it's a real server credential, equivalent to a password for your Firebase
   project.
3. Set it as a Supabase Function secret (from `D:\lost_and_found_app\lost_and_found_app`):
   ```bash
   supabase secrets set FCM_SERVICE_ACCOUNT_JSON="$(cat path\to\the-downloaded-file.json)"
   ```

### 4c. Deploy the push-sending function

```bash
supabase functions deploy send-push --no-verify-jwt
```

`--no-verify-jwt` is needed because this function is only ever called
internally by the database trigger from migration 0005, never by the app or
a signed-in user directly — it has no meaningful caller identity to check.

### 4d. Rebuild the app

```bash
flutter pub get
flutter run
```

Once google-services.json is in place, the app registers this device's FCM
token in `device_tokens` the moment you're signed in. From then on, every row
inserted into `notifications` (new match, new message, item resolved, tag
scanned) triggers a real push to your phone via `send-push`, not just an
in-app list entry.

---

## What's already fully wired (no action needed)

- Categories, home feed, search, filters — real `items` table.
- **Possible Matches** — a Postgres trigger + `pg_trgm` scores every new
  report against open opposite-status items server-side; results live in
  `item_matches` and are read by the app after step 1.
- **Notifications** — trigger-populated on new match, new chat message, and
  item resolved; read/unread state is real.
- **Alert Radius**, **My Item Tags**, **Language**, **Notifications toggle**
  — real per-user rows in `alert_prefs` / `item_tags` / `profiles`.
- **Choose a Safe Meetup Spot** — reads `safe_spots` (seeded with 3 rows by
  the migration), writes a real `meetup_proposals` row.
- **Claim Your Item** — creates a real `claims` row with a server-stored
  pickup code; confirming pickup marks the item resolved.
- **Contact Reporter → Call / Email** — uses the reporter's real
  `profiles.phone` / `profiles.email` (set your own phone number in Edit
  Profile so others can call you back).
- **Forgot password** — real `resetPasswordForEmail`, no extra setup needed.
- **Delete Account** — wired to the Edge Function from step 2.
- **Scan-a-tag landing page** — tapping a tag in My Item Tags opens its real
  QR code + shareable link (`.../#/tag/<code>`); anyone opening that link
  (no login, no app) can leave a message that's stored in `tag_messages` and
  notifies the owner. Read incoming messages from the same tag details sheet;
  swipe one away to delete it.
- **Google sign-in (Android)** — native deep-link wired in
  `AndroidManifest.xml` to catch the OAuth redirect back into the app.

## One more thing needed for QR tags specifically

The QR code encodes `{current web origin}/#/tag/<code>`. That only resolves
for someone else if this Flutter **web** build is actually hosted somewhere
public (Firebase Hosting, Vercel, Netlify, GitHub Pages — your call, this
needs a hosting decision only you can make). Until then, the QR/link still
generates and the landing page itself works if you open it locally, but a
QR code printed and stuck on your keys won't resolve for someone else's
phone. Build for web with:

```bash
flutter build web
```

then deploy the `build/web` folder to whichever static host you choose.

## Still not built

- **Admin web dashboard** (mockup page 19) — a separate web app for staff, a
  different platform than this Flutter app. Say the word if you want it as
  its own project.
- **iOS push / iOS Google sign-in** — only Android was requested, so the iOS
  side of both (APNs certs, `Info.plist` URL scheme) isn't wired.
- **Tapping a push notification doesn't deep-link into the related item** —
  it just opens the app; you'd then check the Notifications screen. Say the
  word if you want tap-to-navigate wired up too (needs `related_item_id`
  passed through the FCM payload and handled in `PushService`).
