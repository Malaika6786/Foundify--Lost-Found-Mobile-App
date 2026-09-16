-- FindIt: let a tag's owner delete messages left on it (swipe-to-dismiss).
-- Run this once in Supabase Dashboard -> SQL Editor -> New query -> Run.
-- Safe to re-run.

drop policy if exists "tag_messages_owner_delete" on public.tag_messages;
create policy "tag_messages_owner_delete" on public.tag_messages
  for delete using (
    auth.uid() = (select user_id from public.item_tags where id = tag_id)
  );
