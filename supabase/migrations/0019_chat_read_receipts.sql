-- Chat read receipts: adds a `read` flag to messages and a SECURITY
-- DEFINER RPC to set it, following the same pattern already used for
-- mark_item_resolved / soft_delete_item elsewhere in this project — a raw
-- client-side `.update()` against `messages` would be silently at the
-- mercy of whatever UPDATE policy (if any) already exists on that table,
-- and this project has repeatedly hit exactly that failure mode (an
-- update that "succeeds" with zero rows changed, no error) rather than
-- risk it here too.
alter table public.messages add column if not exists read boolean not null default false;

create or replace function public.mark_messages_read(p_chat_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only the two people in this chat may mark its messages read.
  if not exists (
    select 1 from public.chats
    where id = p_chat_id
      and (user1 = auth.uid() or user2 = auth.uid())
  ) then
    return;
  end if;

  update public.messages
  set read = true
  where chat_id = p_chat_id
    and sender_id <> auth.uid()
    and read = false;
end;
$$;

revoke all on function public.mark_messages_read(uuid) from public;
revoke all on function public.mark_messages_read(uuid) from anon;
grant execute on function public.mark_messages_read(uuid) to authenticated;
