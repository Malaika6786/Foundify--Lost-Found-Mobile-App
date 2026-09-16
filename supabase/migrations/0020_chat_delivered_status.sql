-- Adds a `delivered` state distinct from `read`, so the chat UI can show
-- WhatsApp-style tick progression: sent (1 tick) -> delivered (2 grey
-- ticks) -> read (2 colored ticks). "Delivered" means the recipient's
-- device has synced this message at all (their chat list or chat screen
-- has loaded it) — "read" means they specifically opened that chat thread.
alter table public.messages add column if not exists delivered boolean not null default false;

-- Bulk version: marks every message sent TO the current user (across every
-- chat they're in) as delivered. Called from the chat list screen's load,
-- since simply having the chat list refresh already means their device
-- has synced that data — matching how delivered receipts work in most
-- chat apps (delivered as soon as the recipient's device is online and
-- synced, not only once they open that specific conversation).
create or replace function public.mark_all_messages_delivered()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.messages m
  set delivered = true
  where m.delivered = false
    and m.sender_id <> auth.uid()
    and exists (
      select 1 from public.chats c
      where c.id = m.chat_id
        and (c.user1 = auth.uid() or c.user2 = auth.uid())
    );
end;
$$;

revoke all on function public.mark_all_messages_delivered() from public;
revoke all on function public.mark_all_messages_delivered() from anon;
grant execute on function public.mark_all_messages_delivered() to authenticated;

-- Reading necessarily implies delivered too, so mark_messages_read should
-- set both — otherwise a message could jump straight from "sent" to
-- "read" in the UI without ever showing the delivered state in between.
create or replace function public.mark_messages_read(p_chat_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.chats
    where id = p_chat_id
      and (user1 = auth.uid() or user2 = auth.uid())
  ) then
    return;
  end if;

  update public.messages
  set read = true, delivered = true
  where chat_id = p_chat_id
    and sender_id <> auth.uid()
    and read = false;
end;
$$;
