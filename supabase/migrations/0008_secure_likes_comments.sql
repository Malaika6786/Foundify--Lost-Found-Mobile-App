-- CRITICAL SECURITY FIX: the `likes`, `comments`, and `profiles` tables
-- (pre-dating this app's RLS hardening work) currently have no working
-- row-level security on writes — verified live: an anonymous caller with
-- only the public API key can insert/delete likes and comments as ANY
-- user, and can UPDATE ANY USER'S PROFILE (name, phone, etc.) with zero
-- authentication. This closes those gaps the same way every other table
-- in this app already works.
-- Run this once in Supabase Dashboard -> SQL Editor -> New query -> Run.
-- Safe to re-run.

-- ---- profiles: anyone can currently overwrite anyone's profile ----
alter table public.profiles enable row level security;

drop policy if exists "profiles_public_read" on public.profiles;
create policy "profiles_public_read" on public.profiles for select using (true);

drop policy if exists "profiles_owner_update" on public.profiles;
create policy "profiles_owner_update" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "profiles_owner_insert" on public.profiles;
create policy "profiles_owner_insert" on public.profiles
  for insert with check (auth.uid() = id);

alter table public.likes enable row level security;
alter table public.comments enable row level security;

-- Anyone can read likes/comments (needed to show counts on the public feed).
drop policy if exists "likes_public_read" on public.likes;
create policy "likes_public_read" on public.likes for select using (true);

drop policy if exists "comments_public_read" on public.comments;
create policy "comments_public_read" on public.comments for select using (true);

-- Only a signed-in user can like/comment as themselves — not as anyone else.
drop policy if exists "likes_owner_write" on public.likes;
create policy "likes_owner_write" on public.likes
  for insert with check (auth.uid() = user_id);

drop policy if exists "likes_owner_delete" on public.likes;
create policy "likes_owner_delete" on public.likes
  for delete using (auth.uid() = user_id);

drop policy if exists "comments_owner_write" on public.comments;
create policy "comments_owner_write" on public.comments
  for insert with check (auth.uid() = user_id);

drop policy if exists "comments_owner_delete" on public.comments;
create policy "comments_owner_delete" on public.comments
  for delete using (auth.uid() = user_id);
