-- Foundify: let users add their own meetup spots instead of picking from a
-- fixed list of made-up examples. Removes the 3 placeholder rows seeded by
-- migration 0001 and adds the INSERT policy that was missing (only a SELECT
-- policy existed before, so no one could actually add a spot).
-- Run this once in Supabase Dashboard -> SQL Editor -> New query -> Run.
-- Safe to re-run.

delete from public.safe_spots
where name in (
  'Downtown Police Station Lobby',
  'Campus Security Desk, Building A',
  'Riverside Coffee, Main St'
) and verified = true;

drop policy if exists "safe_spots_authenticated_insert" on public.safe_spots;
create policy "safe_spots_authenticated_insert" on public.safe_spots
  for insert
  with check (auth.uid() is not null);
