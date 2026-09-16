-- FIX for "why do I have to refresh every time to see a new message" and
-- ticks never progressing past a single grey check: exactly the same root
-- cause as migration 0018 for notifications — `messages` was never added
-- to the `supabase_realtime` publication, so ChatScreen's live stream
-- (lib/screens/chat_screen.dart, SupabaseService.messageStream) is
-- correctly written but has nothing to actually listen to. A new message
-- only ever appeared after fully closing and reopening the chat (a fresh
-- SELECT), not live — and since delivered/read state changes are also
-- just UPDATEs on this same table, the ticks never updated live either.
-- Guarded so it's safe to re-run.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;
