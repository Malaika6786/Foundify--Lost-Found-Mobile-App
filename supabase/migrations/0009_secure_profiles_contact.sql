-- CRITICAL SECURITY FIX: `profiles_public_read` (added in 0008) used
-- `using (true)`, which let anyone with only the anon API key read every
-- user's phone number and email address straight off the `profiles` table
-- (confirmed: SupabaseService.getProfile() is unfiltered and is called with
-- OTHER users' ids from the item-detail contact sheet). This migration:
--   1. Locks `profiles` SELECT down to the owner's own row.
--   2. Adds a `profiles_public` view exposing only the safe columns
--      (id, username, avatar_url, created_at) that the feed/chat/comments
--      UI actually needs to show about OTHER users.
--   3. Adds a scoped RPC, `get_item_reporter_contact`, that returns just the
--      phone/email of ONE item's reporter — the only legitimate case where
--      another user's contact info must be readable (the "Contact Reporter"
--      sheet) — instead of leaving the whole table publicly queryable.
-- Also fixes the same shape of bug on `item_tags`: the public tag-lookup
-- policy exposed every column (including the owner's user_id) to anonymous
-- scanners; that's narrowed to a public view of only the columns the "scan a
-- tag" landing page needs.
-- Safe to re-run.

-- ---------------- profiles ----------------
drop policy if exists "profiles_public_read" on public.profiles;

drop policy if exists "profiles_owner_select" on public.profiles;
create policy "profiles_owner_select" on public.profiles
  for select using (auth.uid() = id);

create or replace view public.profiles_public
  with (security_invoker = false) as
  select id, username, avatar_url, created_at
  from public.profiles;

grant select on public.profiles_public to anon, authenticated;

create or replace function public.get_item_reporter_contact(p_item_id uuid)
returns table(phone text, email text)
language sql
security definer
set search_path = public
as $$
  select p.phone, p.email
  from public.items i
  join public.profiles p on p.id = i.user_id
  where i.id = p_item_id;
$$;

revoke all on function public.get_item_reporter_contact(uuid) from public;
grant execute on function public.get_item_reporter_contact(uuid) to authenticated;

-- ---------------- item_tags ----------------
drop policy if exists "item_tags_public_lookup" on public.item_tags;

create or replace view public.item_tags_public
  with (security_invoker = false) as
  select id, code, label, active
  from public.item_tags;

grant select on public.item_tags_public to anon, authenticated;
