-- Foundify: same fix as 0006, applied to the Claim Your Item flow. Removes
-- the single hardcoded "Central Mall Security Desk" that every claim was
-- silently assigned to (the code always grabbed whichever partner happened
-- to be first in the table), and adds the missing INSERT policy so users
-- can actually add a real drop-off location.
-- Run this once in Supabase Dashboard -> SQL Editor -> New query -> Run.
-- Safe to re-run.

-- Removes any claim still pointing at the fake seeded partner (leftover
-- test data from the old auto-assign bug) so the delete below doesn't hit
-- the foreign key constraint.
delete from public.claims
where partner_id = (
  select id from public.institution_partners
  where name = 'Central Mall Security Desk' and verified = true
);

delete from public.institution_partners
where name = 'Central Mall Security Desk' and verified = true;

drop policy if exists "institution_partners_authenticated_insert" on public.institution_partners;
create policy "institution_partners_authenticated_insert" on public.institution_partners
  for insert
  with check (auth.uid() is not null);
