-- FIX for "notifications not working properly": the bell badge on Home
-- only ever refreshed twice — once when Home first mounted, and once after
-- closing the Notifications screen — because Home stays alive in the
-- background (IndexedStack) the rest of the time. lib/screens/home_screen.dart
-- now subscribes to a live Supabase Realtime stream on `notifications`
-- instead, so a new like/comment/message/match/new-post notification (or
-- marking one read) updates the badge instantly.
--
-- That stream only receives anything if this table is actually enabled for
-- Realtime — `messages` clearly already is (chat updates live), but nothing
-- in this project's migration history ever added `notifications` to the
-- `supabase_realtime` publication, so without this, the client fix above
-- would just sit connected and never receive an event. Guarded with an
-- existence check so it's safe to re-run.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
