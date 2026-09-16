-- 0009's `revoke all ... from public` on get_item_reporter_contact did not
-- actually block anonymous callers. Confirmed live: an anon REST call to
-- the RPC with a real item id returned that item's reporter's real email.
-- Root cause: this project's database (like all Supabase projects) has
-- `alter default privileges in schema public grant execute on functions to
-- anon, authenticated` configured at the schema level, so newly created
-- functions get EXECUTE granted directly to `anon` — a grant separate from,
-- and not removed by, revoking from the `public` pseudo-role. This revokes
-- the role-specific grant explicitly.
revoke execute on function public.get_item_reporter_contact(uuid) from public, anon, authenticated;
grant execute on function public.get_item_reporter_contact(uuid) to authenticated;
