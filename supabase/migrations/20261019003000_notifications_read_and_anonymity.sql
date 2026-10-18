-- Notifications: unread badge, "Mark all as read", and no actor on
-- mentions made from anonymous posts/comments.

-- ---------------------------------------------------------- unread count
-- The badge runs count(*) where user_id = me and is_read = false on every
-- change; keep that an index-only lookup.
update public.notifications set is_read = false where is_read is null;
alter table public.notifications alter column is_read set default false;

create index if not exists notifications_unread_idx
  on public.notifications (user_id)
  where is_read = false;

-- ---------------------------------------------------------- mark as read
-- The recipient may update their own rows (is_read). Before this, the
-- per-row tap update was never actually sent by the client, so a missing
-- policy would have gone unnoticed.
alter table public.notifications enable row level security;

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own" on public.notifications
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- ---------------------------------------------------------- anonymity
-- Mention notifications store the author as actor_id. When the mention
-- comes from an anonymous post or comment that deanonymises the author
-- to the person mentioned, so drop the actor in that case.
alter table public.notifications alter column actor_id drop not null;

create or replace function public.notification_hides_actor(n public.notifications)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select n.type = 'mention' and (
    case
      when n.data ->> 'comment_id' is not null then exists (
        select 1 from public.comments c
        where c.id::text = n.data ->> 'comment_id'
          and coalesce(c.is_anonymous, false))
      when n.data ->> 'post_id' is not null then exists (
        select 1 from public.posts p
        where p.id::text = n.data ->> 'post_id'
          and coalesce(p.is_anonymous, false))
      else false
    end);
$$;

revoke execute on function public.notification_hides_actor(public.notifications) from anon, authenticated;

create or replace function public.strip_anonymous_actor()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if public.notification_hides_actor(new) then
    new.actor_id := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_strip_anonymous_actor on public.notifications;
create trigger trg_strip_anonymous_actor
before insert on public.notifications
for each row execute function public.strip_anonymous_actor();

-- Existing rows.
update public.notifications n
set actor_id = null
where n.actor_id is not null and public.notification_hides_actor(n);
