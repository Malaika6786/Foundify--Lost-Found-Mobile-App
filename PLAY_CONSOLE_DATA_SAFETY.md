# Play Console — Data Safety form answers

Derived directly from the codebase (not guessed) so it matches what the app actually does. You fill this into Play Console → App content → Data safety; I can't submit it for you since it's tied to your developer account.

## Does your app collect or share user data?
**Yes.**

## Data types to declare

| Data type | Collected? | Shared with 3rd party? | Optional or required? | Purpose |
|---|---|---|---|---|
| Name | Yes | No | Required (signup) | Account, app functionality |
| Email address | Yes | No | Required (signup) | Account, authentication |
| Phone number | Yes | No | **Optional** | Lets other users call you about a found item |
| User IDs | Yes | No | Required | Account functionality |
| Precise location | Yes | No | Optional (only if you tap "Use my location") | Attach a location to a lost/found report |
| Approximate location | Yes | No | Optional (same as above) | Same |
| Photos | Yes | No | Optional (item photos, avatar) | Show what an item looks like; profile picture |
| In-app messages | Yes | No | Required for chat feature | Let users coordinate returning an item |
| App activity (comments/likes) | Yes | No | Optional | Social feed feature |
| Advertising ID | Yes | **Yes (Google AdMob)** | Required for ad-supported app | Serving/measuring the home screen banner ad |
| App interactions / device or other IDs (ads) | Yes | **Yes (Google AdMob)** | Required for ad-supported app | Ad delivery, frequency capping, fraud prevention |

## "Shared with third party" — how to answer
For Supabase/Firebase: answer **"Data isn't shared"** (they're *service providers/processors* running the app's infrastructure, not independent third parties Play Console's "sharing" definition targets). Separately, most developer accounts still list processors in the privacy policy itself (already done in `PRIVACY_POLICY.md`).

For **AdMob**: this app now shows ads, so in Play Console go to **App content → Ads** and declare **"Yes, my app contains ads"**. The Advertising ID / device ID rows above ARE shared with a third party (Google, for ad serving) — answer accordingly in the Data Safety form's sharing question for those two rows specifically.

## Security practices section
- ✅ Data is encrypted in transit (HTTPS/TLS everywhere — Supabase and Firebase both enforce this)
- ✅ You can request data deletion — **yes**, real in-app account deletion exists (Profile → Delete Account), deletes profile, items, tags, alerts, notifications, and the auth account itself
- Data encrypted at rest: Supabase encrypts data at rest by default — you can confirm this on their side if asked

## Permissions this app requests (for reference, matches AndroidManifest.xml)
- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` — only used when a user taps "Use my location" while reporting an item. Not used in the background.
- `POST_NOTIFICATIONS` — push notifications (matches, messages, resolved items).
- `INTERNET` — required for all backend calls.
- `READ_EXTERNAL_STORAGE` (Android ≤12 only) — legacy photo picker fallback; modern Android uses the system Photo Picker which needs no permission.

## One thing to double check yourself
The app now shows a Google AdMob banner ad on Home, with a UMP consent prompt shown to EU/UK/CCPA-applicable users before any personalized ads load. If you add analytics or crash reporting SDKs later, this form will need another update.
