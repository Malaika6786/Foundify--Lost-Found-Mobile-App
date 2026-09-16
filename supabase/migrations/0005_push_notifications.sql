-- FindIt: push notifications backend.
-- Run this once in Supabase Dashboard -> SQL Editor -> New query -> Run.
-- Safe to re-run.

create extension if not exists pg_net with schema extensions;

-- ============================================================
-- device_tokens — one row per (user, device). A user can have several
-- devices; each token maps to exactly one user at a time.
-- ============================================================
create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'android',
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_user_idx on public.device_tokens(user_id);

alter table public.device_tokens enable row level security;

drop policy if exists "device_tokens_owner_all" on public.device_tokens;
create policy "device_tokens_owner_all" on public.device_tokens
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ============================================================
-- Trigger: whenever a notification row is inserted, ask the send-push
-- Edge Function to deliver it to that user's registered devices via FCM.
-- Fire-and-forget over pg_net so this never blocks or fails the insert
-- that triggered it.
-- ============================================================
create or replace function public.findit_dispatch_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform net.http_post(
    url := 'https://dkainvkujpjzxngqnsrn.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object(
      'user_id', new.user_id,
      'title', new.title,
      'body', new.body
    )
  );
  return new;
exception when others then
  -- Never let a push-dispatch failure block the notification itself from
  -- being recorded/visible in-app.
  return new;
end;
$$;

drop trigger if exists findit_dispatch_push_trigger on public.notifications;
create trigger findit_dispatch_push_trigger
  after insert on public.notifications
  for each row execute function public.findit_dispatch_push();
