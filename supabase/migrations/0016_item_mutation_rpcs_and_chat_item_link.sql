-- BUG: "Mark as Resolved" and "Delete Post" both looked like they worked
-- (no error shown) but never actually stuck — refreshing showed the item
-- still open/still there. Same root cause as the claim-pickup bug fixed in
-- 0015: these were plain client-side `items.update(...)` calls, and
-- Postgrest does NOT raise an error when an UPDATE's RLS policy silently
-- matches zero rows (it only errors on a `.single()` call). Whatever the
-- exact state of the `items` UPDATE policy turns out to be, routing these
-- through SECURITY DEFINER RPCs that explicitly check ownership removes
-- the dependency on it entirely — the same fix pattern as
-- confirm_claim_pickup.

create or replace function public.mark_item_resolved(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select user_id into v_owner from public.items where id = p_item_id;
  if v_owner is null then
    raise exception 'Item not found';
  end if;
  if v_owner is distinct from auth.uid() then
    raise exception 'Only the reporter can mark this item resolved';
  end if;
  update public.items set returned = true where id = p_item_id;
end;
$$;

revoke all on function public.mark_item_resolved(uuid) from public, anon;
grant execute on function public.mark_item_resolved(uuid) to authenticated;

create or replace function public.soft_delete_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select user_id into v_owner from public.items where id = p_item_id;
  if v_owner is null then
    raise exception 'Item not found';
  end if;
  if v_owner is distinct from auth.uid() then
    raise exception 'Only the reporter can delete this item';
  end if;
  update public.items set deleted_at = now() where id = p_item_id;
end;
$$;

revoke all on function public.soft_delete_item(uuid) from public, anon;
grant execute on function public.soft_delete_item(uuid) to authenticated;

create or replace function public.restore_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select user_id into v_owner from public.items where id = p_item_id;
  if v_owner is null then
    raise exception 'Item not found';
  end if;
  if v_owner is distinct from auth.uid() then
    raise exception 'Only the reporter can restore this item';
  end if;
  update public.items set deleted_at = null where id = p_item_id;
end;
$$;

revoke all on function public.restore_item(uuid) from public, anon;
grant execute on function public.restore_item(uuid) to authenticated;

-- ---------------- notify reporter of a proposed meetup spot ----------------
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('message','match','resolved','system','flag','like','comment','new_post','meetup_proposal'));

create or replace function public.findit_notify_meetup_proposal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
  proposer_name text;
  item_title text;
  spot_name text;
begin
  select user_id, title into owner_id, item_title from public.items where id = new.item_id;
  if owner_id is null or owner_id = new.proposed_by then
    return new;
  end if;

  select coalesce(username, full_name, 'Someone') into proposer_name
  from public.profiles where id = new.proposed_by;
  select name into spot_name from public.safe_spots where id = new.safe_spot_id;

  insert into public.notifications (user_id, type, title, body, related_item_id, related_user_id)
  values (
    owner_id, 'meetup_proposal',
    coalesce(proposer_name, 'Someone') || ' proposed a meetup spot',
    'For "' || coalesce(item_title, 'your report') || '": ' || coalesce(spot_name, 'a spot'),
    new.item_id, new.proposed_by
  );
  return new;
end;
$$;

drop trigger if exists findit_notify_meetup_proposal_trigger on public.meetup_proposals;
create trigger findit_notify_meetup_proposal_trigger
  after insert on public.meetup_proposals
  for each row execute function public.findit_notify_meetup_proposal();

-- ---------------- chats remember which item started them ----------------
-- So the item being discussed stays visible/consistent every time the chat
-- is reopened (previously it only showed up if you happened to navigate in
-- from that item's contact sheet in the same session — opening the same
-- chat later from the Messages list showed no item context at all).
alter table public.chats add column if not exists related_item_id uuid references public.items(id) on delete set null;
