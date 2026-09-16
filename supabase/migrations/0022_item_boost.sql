-- "Boost this post" — the reward behind the rewarded ad unit. Watching the
-- ad through to completion marks the poster's own item as boosted for 24
-- hours; the client sorts actively-boosted items higher in the feed.
alter table public.items add column if not exists boosted_until timestamptz;

-- SECURITY DEFINER RPC, not a raw client-side .update() — same reasoning
-- as every other item mutation in this project (mark_item_resolved,
-- soft_delete_item, etc.): a direct update is at the mercy of whatever the
-- base UPDATE policy on `items` allows, and this project has repeatedly
-- hit that policy silently blocking legitimate owner actions. Explicit
-- ownership + not-deleted checks here instead.
create or replace function public.boost_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.items
  set boosted_until = now() + interval '24 hours'
  where id = p_item_id
    and user_id = auth.uid()
    and deleted_at is null;
end;
$$;

revoke all on function public.boost_item(uuid) from public;
revoke all on function public.boost_item(uuid) from anon;
grant execute on function public.boost_item(uuid) to authenticated;
