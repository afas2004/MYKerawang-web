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

-- ---------------------------------------------------------- policies
-- Self-sufficient: enabling RLS here must not lock out reads or the
-- client-side follow/mention inserts if RLS was off before. Idempotent.
alter table public.notifications enable row level security;

-- Recipient reads their own (list, realtime stream, unread badge).
drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own" on public.notifications
for select to authenticated
using (user_id = auth.uid());

-- Clients may only send notifications as themselves, so nobody can forge
-- one that appears to come from someone else. Anonymous mentions go
-- through the security-definer notify_mentions() RPC and system
-- notifications through security-definer triggers; both bypass RLS.
-- (A direct insert whose actor_id the trigger below strips to null is
-- therefore rejected — anonymous mentions must use the RPC.)
drop policy if exists "notifications_insert_as_self" on public.notifications;
create policy "notifications_insert_as_self" on public.notifications
for insert to authenticated
with check (actor_id = auth.uid());

-- Recipient marks their own rows read...
drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own" on public.notifications
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- ...and can only change is_read, never rewrite title/body/data.
revoke update on public.notifications from authenticated;
grant update (is_read) on public.notifications to authenticated;

-- Recipient may clear their own.
drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own" on public.notifications
for delete to authenticated
using (user_id = auth.uid());

grant select, insert, delete on public.notifications to authenticated;
revoke all on public.notifications from anon;

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
