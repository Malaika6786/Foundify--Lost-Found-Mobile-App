-- ROOT CAUSE FIX for a cluster of bugs: posting an item failing with
-- "insert or update on table items violates foreign key constraint
-- items_user_id_fkey ... Key is not present in table profiles", profile
-- edits silently not saving, and every other user showing as "Unknown"
-- in chat.
--
-- All of these trace back to one thing: the ONLY place a `profiles` row
-- ever got created was a client-side upsert run immediately after
-- SupabaseService.signUp() / in auth_screen.dart's submit(). When the
-- Supabase project requires email confirmation, signUp() returns a user
-- with NO session yet (confirmation email not clicked) — so that upsert
-- runs as an unauthenticated request and profiles_owner_insert (auth.uid()
-- = id) rejects it: "new row violates row-level security policy for table
-- profiles". The auth account still gets created, but its profiles row
-- never does — so every feature that needs one (posting an item, editing
-- your profile, showing your name/avatar to others) breaks for that user
-- from then on, with no obvious way to retry it from the app.
--
-- Fix: create the profiles row server-side via a trigger on auth.users,
-- using SECURITY DEFINER so it always succeeds regardless of session state
-- or email-confirmation status — this is the standard Supabase pattern for
-- exactly this problem. The client now passes name/username/phone as
-- signup metadata (see SupabaseService.signUp), which the trigger reads
-- from `raw_user_meta_data`.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, username, phone)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'username',
    new.raw_user_meta_data ->> 'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill: give every existing auth user who was bitten by this bug
-- (created an account, but ended up with no profiles row) one now.
insert into public.profiles (id, email)
select u.id, u.email
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;
