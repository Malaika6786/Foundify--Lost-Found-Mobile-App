-- 0009 dropped the policy named "profiles_public_read", but the live
-- database's actual wide-open SELECT policy was named "Allow select on
-- profiles" (qual: true) — a different name, left over from an earlier
-- setup, that 0009 never matched. Postgres OR's multiple permissive
-- policies for the same command together, so that policy alone kept
-- granting full public read access (phone/email included) even after
-- profiles_owner_select was added. Confirmed live via anon REST calls
-- still returning every user's email after 0009 ran.
--
-- Also cleans up two harmless-but-redundant legacy duplicates of policies
-- 0008/0009 already added correctly (same effect, different name) so the
-- policy list on `profiles` reflects exactly what's enforced.
drop policy if exists "Allow select on profiles" on public.profiles;
drop policy if exists "Insert own profile" on public.profiles;
drop policy if exists "Update own profile" on public.profiles;
