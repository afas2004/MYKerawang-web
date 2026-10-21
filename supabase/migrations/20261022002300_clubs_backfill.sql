-- Clubs, part 3: move the old role-based clubs onto real club pages.
--
--   role = 'club'          → an ACTIVE, verified club, that user president
--   role = 'club_pending'  → a PENDING club request, that user president
--
-- Onboarding used to store the club proof in profiles.bio as
-- "Club Verification: …". That text moves to club_private.proof_note and
-- is removed from the bio. Roles are left as they are, so code that
-- checks role = 'club' keeps working. Re-runnable: accounts that already
-- preside over a club are skipped.

create or replace function public._club_handle_for(p_base text)
returns text
language plpgsql
set search_path = public
as $$
declare
  v_base text := left(regexp_replace(coalesce(p_base, ''), '[^A-Za-z0-9_]', '', 'g'), 26);
  v_try  text;
  n      int := 1;
begin
  if length(v_base) < 3 then
    v_base := 'club' || v_base;
  end if;
  v_try := v_base;
  while exists (select 1 from public.clubs where handle = v_try::extensions.citext) loop
    n := n + 1;
    v_try := v_base || n;
  end loop;
  return v_try;
end;
$$;

do $$
declare
  p       record;
  v_id    uuid;
  v_proof text;
  v_bio   text;
begin
  for p in
    select pr.* from public.profiles pr
    where pr.role in ('club','club_pending')
      and not exists (select 1 from public.club_members m
                      where m.user_id = pr.id and m.role = 'president')
  loop
    v_proof := null;
    v_bio := p.bio;
    if v_bio is not null and v_bio ilike 'Club Verification:%' then
      v_proof := btrim(substr(v_bio, length('Club Verification:') + 1));
      v_bio := null;
    end if;

    insert into public.clubs (handle, name, description, logo_url, status, is_verified, created_by)
    values (public._club_handle_for(coalesce(p.username, p.display_name)),
            left(coalesce(nullif(btrim(p.display_name), ''), p.username, 'Club'), 80),
            v_bio,
            p.avatar_url,
            case when p.role = 'club' then 'active' else 'pending' end,
            p.role = 'club',
            p.id)
    returning id into v_id;

    insert into public.club_members (club_id, user_id, role) values (v_id, p.id, 'president');
    insert into public.club_private (club_id, proof_note)
    values (v_id, coalesce(v_proof, case when p.role = 'club_pending'
                                         then '(migrated request — no proof given)' end));

    if v_proof is not null then
      update public.profiles set bio = null where id = p.id;
    end if;

    -- Their earlier posts / events / listings now appear as the club.
    if p.role = 'club' then
      update public.posts    set club_id = v_id where user_id = p.id and club_id is null and not coalesce(is_anonymous, false);
      update public.events   set club_id = v_id where organizer_id = p.id and club_id is null;
      update public.listings set club_id = v_id where seller_id = p.id and club_id is null;
    end if;
  end loop;
end $$;

drop function if exists public._club_handle_for(text);
