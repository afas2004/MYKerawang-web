-- Saved items (DESIGN_SPEC §8): a private bookmark list of posts,
-- listings and events. Polymorphic item_id, so no FK to the targets;
-- rows whose target is gone are cleaned up below and simply skipped by
-- the app ("No longer available") until then.

create table if not exists public.saved_items (
  user_id    uuid not null default auth.uid()
             references public.profiles(id) on delete cascade,
  item_type  text not null check (item_type in ('post','listing','event')),
  item_id    text not null, -- target id as text (uuid today)
  created_at timestamptz not null default now(),
  primary key (user_id, item_type, item_id)
);

create index if not exists saved_items_user_recent_idx
  on public.saved_items (user_id, created_at desc);

alter table public.saved_items enable row level security;

drop policy if exists "saved_items_select_own" on public.saved_items;
create policy "saved_items_select_own" on public.saved_items
for select to authenticated using (user_id = auth.uid());

drop policy if exists "saved_items_insert_own" on public.saved_items;
create policy "saved_items_insert_own" on public.saved_items
for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "saved_items_delete_own" on public.saved_items;
create policy "saved_items_delete_own" on public.saved_items
for delete to authenticated using (user_id = auth.uid());

revoke all on public.saved_items from anon;
grant select, insert, delete on public.saved_items to authenticated;

-- Drop bookmarks when the thing itself is deleted.
create or replace function public.forget_saved_target()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  delete from public.saved_items
  where item_type = tg_argv[0] and item_id = old.id::text;
  return old;
end;
$$;

drop trigger if exists trg_forget_saved_post on public.posts;
create trigger trg_forget_saved_post
after delete on public.posts
for each row execute function public.forget_saved_target('post');

drop trigger if exists trg_forget_saved_listing on public.listings;
create trigger trg_forget_saved_listing
after delete on public.listings
for each row execute function public.forget_saved_target('listing');

drop trigger if exists trg_forget_saved_event on public.events;
create trigger trg_forget_saved_event
after delete on public.events
for each row execute function public.forget_saved_target('event');
