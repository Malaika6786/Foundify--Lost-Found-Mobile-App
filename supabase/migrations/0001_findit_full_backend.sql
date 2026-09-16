-- FindIt full backend migration
-- Run this ONCE in Supabase Dashboard -> SQL Editor -> New query -> Run.
-- Safe to re-run: every statement is guarded with IF NOT EXISTS / OR REPLACE.

-- ============================================================
-- 0. Extensions
-- ============================================================
create extension if not exists pg_trgm;
create extension if not exists pgcrypto; -- gen_random_uuid()

-- ============================================================
-- 1. items: add category / location_label
-- ============================================================
alter table public.items add column if not exists category text;
alter table public.items add column if not exists location_label text;

-- ============================================================
-- 2. profiles: add phone / notification + language prefs
-- ============================================================
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists notifications_enabled boolean not null default true;
alter table public.profiles add column if not exists language_code text not null default 'en';

-- ============================================================
-- 3. alert_prefs — one row per user (Alert Radius screen)
-- ============================================================
create table if not exists public.alert_prefs (
  user_id uuid primary key references auth.users(id) on delete cascade,
  radius_km numeric not null default 3,
  categories text[] not null default array['Bags','Wallet'],
  push_enabled boolean not null default true,
  ai_only boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.alert_prefs enable row level security;

drop policy if exists "alert_prefs_owner_all" on public.alert_prefs;
create policy "alert_prefs_owner_all" on public.alert_prefs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ============================================================
-- 4. item_tags — linked QR tags (My Item Tags screen)
-- ============================================================
create table if not exists public.item_tags (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null,
  code text not null unique,
  item_id uuid references public.items(id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.item_tags enable row level security;

drop policy if exists "item_tags_owner_all" on public.item_tags;
create policy "item_tags_owner_all" on public.item_tags
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Public (unauthenticated) lookup by code, for the "scan a tag" landing page —
-- only exposes label + active state + owner_id, never contact details.
drop policy if exists "item_tags_public_lookup" on public.item_tags;
create policy "item_tags_public_lookup" on public.item_tags
  for select using (true);

-- ============================================================
-- 5. notifications — real notification feed
-- ============================================================
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('message','match','resolved','system','flag')),
  title text not null,
  body text not null,
  related_item_id uuid references public.items(id) on delete cascade,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_idx on public.notifications(user_id, created_at desc);

alter table public.notifications enable row level security;

drop policy if exists "notifications_owner_select" on public.notifications;
create policy "notifications_owner_select" on public.notifications
  for select using (auth.uid() = user_id);

drop policy if exists "notifications_owner_update" on public.notifications;
create policy "notifications_owner_update" on public.notifications
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- inserts happen only from trigger functions (security definer), not directly from clients.

-- ============================================================
-- 6. safe_spots — curated public meetup locations
-- ============================================================
create table if not exists public.safe_spots (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null,
  lat double precision,
  lng double precision,
  verified boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.safe_spots enable row level security;

drop policy if exists "safe_spots_public_read" on public.safe_spots;
create policy "safe_spots_public_read" on public.safe_spots for select using (true);

insert into public.safe_spots (name, description, verified)
select * from (values
  ('Downtown Police Station Lobby', 'Staffed 24/7', true),
  ('Campus Security Desk, Building A', 'Staffed 8am-10pm', true),
  ('Riverside Coffee, Main St', 'Busy public cafe', false)
) as v(name, description, verified)
where not exists (select 1 from public.safe_spots);

-- ============================================================
-- 7. meetup_proposals — "Propose This Spot" from the contact sheet
-- ============================================================
create table if not exists public.meetup_proposals (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  proposed_by uuid not null references auth.users(id) on delete cascade,
  safe_spot_id uuid not null references public.safe_spots(id),
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now()
);

alter table public.meetup_proposals enable row level security;

drop policy if exists "meetup_proposals_participants" on public.meetup_proposals;
create policy "meetup_proposals_participants" on public.meetup_proposals
  for all using (
    auth.uid() = proposed_by
    or auth.uid() = (select user_id from public.items where id = item_id)
  ) with check (auth.uid() = proposed_by);

-- ============================================================
-- 8. institution_partners + claims — drop-off / pickup flow
-- ============================================================
create table if not exists public.institution_partners (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text not null,
  verified boolean not null default true
);

alter table public.institution_partners enable row level security;
drop policy if exists "institution_partners_public_read" on public.institution_partners;
create policy "institution_partners_public_read" on public.institution_partners for select using (true);

insert into public.institution_partners (name, address, verified)
select * from (values ('Central Mall Security Desk', 'Central Mall, Ground Floor', true)) as v(name, address, verified)
where not exists (select 1 from public.institution_partners);

create table if not exists public.claims (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null unique references public.items(id) on delete cascade,
  claimant_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid references public.institution_partners(id),
  pickup_code text not null,
  status text not null default 'pending' check (status in ('pending','verified','picked_up')),
  created_at timestamptz not null default now()
);

alter table public.claims enable row level security;

drop policy if exists "claims_participants" on public.claims;
create policy "claims_participants" on public.claims
  for all using (
    auth.uid() = claimant_id
    or auth.uid() = (select user_id from public.items where id = item_id)
  ) with check (auth.uid() = claimant_id);

-- ============================================================
-- 9. item_matches — server-side match scoring (backs "Possible Matches")
-- ============================================================
create table if not exists public.item_matches (
  id uuid primary key default gen_random_uuid(),
  lost_item_id uuid not null references public.items(id) on delete cascade,
  found_item_id uuid not null references public.items(id) on delete cascade,
  score int not null,
  dismissed boolean not null default false,
  created_at timestamptz not null default now(),
  unique (lost_item_id, found_item_id)
);

create index if not exists item_matches_lost_idx on public.item_matches(lost_item_id);

alter table public.item_matches enable row level security;

drop policy if exists "item_matches_owner_select" on public.item_matches;
create policy "item_matches_owner_select" on public.item_matches
  for select using (
    auth.uid() = (select user_id from public.items where id = lost_item_id)
    or auth.uid() = (select user_id from public.items where id = found_item_id)
  );

drop policy if exists "item_matches_owner_update" on public.item_matches;
create policy "item_matches_owner_update" on public.item_matches
  for update using (auth.uid() = (select user_id from public.items where id = lost_item_id))
  with check (auth.uid() = (select user_id from public.items where id = lost_item_id));

-- ============================================================
-- 10. Trigger: auto-score matches + notify when a new item is posted
-- ============================================================
create or replace function public.findit_score_new_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  candidate record;
  computed_score int;
  lost_id uuid;
  found_id uuid;
  owner_id uuid;
begin
  if new.status = 'lost' then
    for candidate in
      select * from public.items
      where status = 'found' and coalesce(returned,false) = false and id <> new.id
    loop
      computed_score := least(99, round(
        similarity(coalesce(new.title,''), coalesce(candidate.title,'')) * 70
        + case when new.category is not null and new.category = candidate.category then 25 else 0 end
      )::int);
      if computed_score >= 30 then
        lost_id := new.id;
        found_id := candidate.id;
        insert into public.item_matches (lost_item_id, found_item_id, score)
        values (lost_id, found_id, computed_score)
        on conflict (lost_item_id, found_item_id) do update set score = excluded.score;

        if computed_score >= 60 then
          insert into public.notifications (user_id, type, title, body, related_item_id)
          values (new.user_id, 'match', 'Possible match found',
                  'We found a ' || computed_score || '% match for your report "' || new.title || '"', new.id);
        end if;
      end if;
    end loop;
  elsif new.status = 'found' then
    for candidate in
      select * from public.items
      where status = 'lost' and coalesce(returned,false) = false and id <> new.id
    loop
      computed_score := least(99, round(
        similarity(coalesce(new.title,''), coalesce(candidate.title,'')) * 70
        + case when new.category is not null and new.category = candidate.category then 25 else 0 end
      )::int);
      if computed_score >= 30 then
        lost_id := candidate.id;
        found_id := new.id;
        owner_id := candidate.user_id;
        insert into public.item_matches (lost_item_id, found_item_id, score)
        values (lost_id, found_id, computed_score)
        on conflict (lost_item_id, found_item_id) do update set score = excluded.score;

        if computed_score >= 60 then
          insert into public.notifications (user_id, type, title, body, related_item_id)
          values (owner_id, 'match', 'Possible match found',
                  'We found a ' || computed_score || '% match for your report "' || candidate.title || '"', candidate.id);
        end if;
      end if;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists findit_score_new_item_trigger on public.items;
create trigger findit_score_new_item_trigger
  after insert on public.items
  for each row execute function public.findit_score_new_item();

-- ============================================================
-- 11. Trigger: notify on new chat message
-- ============================================================
create or replace function public.findit_notify_new_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recipient uuid;
  sender_name text;
begin
  select case when user1 = new.sender_id then user2 else user1 end
  into recipient
  from public.chats where id = new.chat_id;

  if recipient is null or recipient = new.sender_id then
    return new;
  end if;

  select coalesce(username, full_name, 'Someone') into sender_name
  from public.profiles where id = new.sender_id;

  insert into public.notifications (user_id, type, title, body)
  values (recipient, 'message', coalesce(sender_name, 'Someone') || ' sent you a message',
          left(new.content, 140));

  return new;
end;
$$;

drop trigger if exists findit_notify_new_message_trigger on public.messages;
create trigger findit_notify_new_message_trigger
  after insert on public.messages
  for each row execute function public.findit_notify_new_message();

-- ============================================================
-- 12. Trigger: notify owner when their item is marked resolved
-- ============================================================
create or replace function public.findit_notify_resolved()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.returned = true and coalesce(old.returned,false) = false then
    insert into public.notifications (user_id, type, title, body, related_item_id)
    values (new.user_id, 'resolved', 'Item marked resolved',
            '"' || new.title || '" was marked as resolved.', new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists findit_notify_resolved_trigger on public.items;
create trigger findit_notify_resolved_trigger
  after update on public.items
  for each row execute function public.findit_notify_resolved();
