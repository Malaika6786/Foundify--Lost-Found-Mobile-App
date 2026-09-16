-- Soft-delete for items, so "Delete Post" can offer a real Undo instead of
-- being instantly irreversible. Existing owner-scoped RLS on `items` already
-- allows the poster to update their own row (used today by "Mark as
-- Resolved"), so this reuses that same permission rather than needing a new
-- policy.
alter table public.items add column if not exists deleted_at timestamptz;
create index if not exists items_deleted_at_idx on public.items(deleted_at);
