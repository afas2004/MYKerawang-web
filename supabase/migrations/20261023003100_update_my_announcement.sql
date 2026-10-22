-- Editing an announcement. posts has no author UPDATE policy (on purpose:
-- authors mustn't touch moderation/counter columns), and update_my_post
-- only covers title/body/tags/photos. This updates the announcement
-- fields the composer edits, for the author, an officer of the posting
-- club, or an admin. post_create_rules (20261023001100) still validates
-- category and action_links on the way through. Safe to re-run.

create or replace function public.update_my_announcement(p_post_id uuid, p_fields jsonb)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_post public.posts;
begin
  select * into v_post from public.posts where id = p_post_id;
  if not found or not coalesce(v_post.is_announcement, false) then
    raise exception 'POST:not_found' using errcode = 'P0001';
  end if;

  if v_uid is null or not (
       v_post.user_id = v_uid
       or public.is_admin()
       or (v_post.club_id is not null and public.can_act_as_club(v_post.club_id))) then
    raise exception 'POST:forbidden' using errcode = 'P0001';
  end if;

  update public.posts set
    title                 = coalesce(p_fields->>'title', title),
    body                  = coalesce(p_fields->>'body', body),
    announcement_category = coalesce(p_fields->>'announcement_category', announcement_category),
    cover_url             = case when p_fields ? 'cover_url' then p_fields->>'cover_url' else cover_url end,
    image_url             = case when p_fields ? 'image_url' then p_fields->>'image_url' else image_url end,
    gallery_urls          = case when p_fields ? 'gallery_urls'
                                 then coalesce(array(select jsonb_array_elements_text(p_fields->'gallery_urls')), '{}')
                                 else gallery_urls end,
    action_links          = coalesce(p_fields->'action_links', action_links),
    linked_event_id       = case when p_fields ? 'linked_event_id'
                                 then (p_fields->>'linked_event_id')::uuid else linked_event_id end,
    publish_at            = coalesce((p_fields->>'publish_at')::timestamptz, publish_at),
    feature_until         = case when p_fields ? 'feature_until'
                                 then (p_fields->>'feature_until')::timestamptz else feature_until end,
    comments_enabled      = coalesce((p_fields->>'comments_enabled')::boolean, comments_enabled),
    show_in_feed          = coalesce((p_fields->>'show_in_feed')::boolean, show_in_feed)
  where id = p_post_id;
end;
$$;

revoke execute on function public.update_my_announcement(uuid, jsonb) from public, anon;
grant  execute on function public.update_my_announcement(uuid, jsonb) to authenticated;
