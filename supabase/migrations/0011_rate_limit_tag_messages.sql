-- Basic abuse protection for `tag_messages`: this is the app's only
-- fully-anonymous, unauthenticated write endpoint (a finder submitting a
-- message with no login at all — see TagLandingScreen /
-- SupabaseService.submitTagMessage). Nothing currently stops a script from
-- hammering it. This adds two independent, cheap guards via a trigger
-- (works regardless of which API path is used to insert, unlike a
-- client-side check):
--   1. Per-tag cap: at most 20 messages per tag per rolling hour — a real
--      finder never needs more than one or two attempts.
--   2. Global cap: at most 60 tag_messages inserts per rolling minute across
--      the whole table — blunts a scripted flood before it fills the table.
-- Safe to re-run.

create or replace function public.findit_rate_limit_tag_messages()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  per_tag_count integer;
  global_count integer;
begin
  select count(*) into per_tag_count
  from public.tag_messages
  where tag_id = new.tag_id
    and created_at > now() - interval '1 hour';

  if per_tag_count >= 20 then
    raise exception 'Too many messages for this tag recently. Please try again later.'
      using errcode = 'P0001';
  end if;

  select count(*) into global_count
  from public.tag_messages
  where created_at > now() - interval '1 minute';

  if global_count >= 60 then
    raise exception 'Too many messages submitted right now. Please try again in a moment.'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists findit_rate_limit_tag_messages_trigger on public.tag_messages;
create trigger findit_rate_limit_tag_messages_trigger
  before insert on public.tag_messages
  for each row execute function public.findit_rate_limit_tag_messages();
