-- FindIt: "scan a tag" landing page backend — lets a finder with no account
-- leave a message for the tag owner, and notifies the owner.
-- Run this once in Supabase Dashboard -> SQL Editor -> New query -> Run.
-- Safe to re-run.

create table if not exists public.tag_messages (
  id uuid primary key default gen_random_uuid(),
  tag_id uuid not null references public.item_tags(id) on delete cascade,
  finder_name text,
  finder_contact text, -- phone or email the finder leaves so the owner can reach back
  message text not null,
  created_at timestamptz not null default now()
);

alter table public.tag_messages enable row level security;

-- Anyone (including an anonymous finder with no account) can leave a
-- message for a tag that exists and is currently active.
drop policy if exists "tag_messages_public_insert" on public.tag_messages;
create policy "tag_messages_public_insert" on public.tag_messages
  for insert
  with check (
    exists (select 1 from public.item_tags where id = tag_id and active = true)
  );

-- Only the tag's owner can read messages left for it.
drop policy if exists "tag_messages_owner_select" on public.tag_messages;
create policy "tag_messages_owner_select" on public.tag_messages
  for select using (
    auth.uid() = (select user_id from public.item_tags where id = tag_id)
  );

create or replace function public.findit_notify_tag_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
  tag_label text;
begin
  select user_id, label into owner_id, tag_label
  from public.item_tags where id = new.tag_id;

  if owner_id is null then
    return new;
  end if;

  insert into public.notifications (user_id, type, title, body)
  values (
    owner_id,
    'message',
    'Someone scanned your "' || coalesce(tag_label, 'item') || '" tag',
    left(new.message, 140)
  );

  return new;
end;
$$;

drop trigger if exists findit_notify_tag_message_trigger on public.tag_messages;
create trigger findit_notify_tag_message_trigger
  after insert on public.tag_messages
  for each row execute function public.findit_notify_tag_message();
