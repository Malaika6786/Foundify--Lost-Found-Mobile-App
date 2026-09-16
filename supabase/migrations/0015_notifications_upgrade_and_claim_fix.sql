-- Two fixes bundled together:
--
-- 1. BUG: "resolved" count stayed low even after confirming several claim
--    pickups. Root cause: ClaimItemScreen's "Confirm Pickup" is tapped by
--    the CLAIMANT, but `items` UPDATE RLS only lets the item's OWNER (the
--    finder) change it. The client-side `items.update({returned:true})`
--    call therefore silently matched zero rows — no error thrown, since it
--    wasn't a `.single()` call — so the item never actually got marked
--    resolved even though the app showed "Pickup confirmed". Fixed with a
--    SECURITY DEFINER RPC that validates the caller really is the claim's
--    claimant (a legitimate reason to flip `returned`, just not "you own
--    this item"), then updates both rows together server-side.
--
-- 2. Notifications were unusable for their main purpose: a "message"
--    notification had no sender id or chat id stored at all, so tapping one
--    could never open the right conversation. Also, there were no
--    notifications at all for new posts, likes, or comments. This adds the
--    missing columns, backfills the message trigger to populate them, and
--    adds three new triggers (like/comment/new post).

-- ---------------- claim pickup fix ----------------
create or replace function public.confirm_claim_pickup(p_claim_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
  v_claimant_id uuid;
begin
  select item_id, claimant_id into v_item_id, v_claimant_id
  from public.claims where id = p_claim_id;

  if v_item_id is null then
    raise exception 'Claim not found';
  end if;
  if v_claimant_id is distinct from auth.uid() then
    raise exception 'Only the claimant can confirm this pickup';
  end if;

  update public.claims set status = 'picked_up' where id = p_claim_id;
  update public.items set returned = true where id = v_item_id;
end;
$$;

revoke all on function public.confirm_claim_pickup(uuid) from public, anon;
grant execute on function public.confirm_claim_pickup(uuid) to authenticated;

-- ---------------- notifications: richer message data ----------------
alter table public.notifications add column if not exists related_user_id uuid references public.profiles(id) on delete set null;
alter table public.notifications add column if not exists related_chat_id uuid references public.chats(id) on delete set null;

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('message','match','resolved','system','flag','like','comment','new_post'));

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

  insert into public.notifications
    (user_id, type, title, body, related_user_id, related_chat_id)
  values (
    recipient, 'message', coalesce(sender_name, 'Someone') || ' sent you a message',
    left(new.content, 140), new.sender_id, new.chat_id
  );

  return new;
end;
$$;

-- ---------------- notifications: likes ----------------
create or replace function public.findit_notify_new_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
  liker_name text;
  post_title text;
begin
  select user_id, title into owner_id, post_title from public.items where id = new.post_id;
  if owner_id is null or owner_id = new.user_id then
    return new;
  end if;

  select coalesce(username, full_name, 'Someone') into liker_name
  from public.profiles where id = new.user_id;

  insert into public.notifications
    (user_id, type, title, body, related_item_id, related_user_id)
  values (
    owner_id, 'like', coalesce(liker_name, 'Someone') || ' liked your post',
    coalesce(post_title, 'Your post'), new.post_id, new.user_id
  );
  return new;
end;
$$;

drop trigger if exists findit_notify_new_like_trigger on public.likes;
create trigger findit_notify_new_like_trigger
  after insert on public.likes
  for each row execute function public.findit_notify_new_like();

-- ---------------- notifications: comments ----------------
create or replace function public.findit_notify_new_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
  commenter_name text;
begin
  select user_id into owner_id from public.items where id = new.post_id;
  if owner_id is null or owner_id = new.user_id then
    return new;
  end if;

  select coalesce(username, full_name, 'Someone') into commenter_name
  from public.profiles where id = new.user_id;

  insert into public.notifications
    (user_id, type, title, body, related_item_id, related_user_id)
  values (
    owner_id, 'comment', coalesce(commenter_name, 'Someone') || ' commented on your post',
    left(new.content, 140), new.post_id, new.user_id
  );
  return new;
end;
$$;

drop trigger if exists findit_notify_new_comment_trigger on public.comments;
create trigger findit_notify_new_comment_trigger
  after insert on public.comments
  for each row execute function public.findit_notify_new_comment();

-- ---------------- notifications: new posts (broadcast) ----------------
-- NOTE: this writes one notifications row per OTHER user (with
-- notifications enabled) per new item posted — fine at this app's current
-- user count, but is an O(users) fan-out per post and will need rethinking
-- (batched digests, or scoping to matching alert_prefs instead of
-- everyone) if the user base grows much larger.
create or replace function public.findit_notify_new_post()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  poster_name text;
begin
  select coalesce(username, full_name, 'Someone') into poster_name
  from public.profiles where id = new.user_id;

  insert into public.notifications (user_id, type, title, body, related_item_id)
  select p.id, 'new_post',
         coalesce(poster_name, 'Someone') || ' posted a new ' || new.status || ' item',
         new.title,
         new.id
  from public.profiles p
  where p.id <> new.user_id
    and coalesce(p.notifications_enabled, true) = true;

  return new;
end;
$$;

drop trigger if exists findit_notify_new_post_trigger on public.items;
create trigger findit_notify_new_post_trigger
  after insert on public.items
  for each row execute function public.findit_notify_new_post();
