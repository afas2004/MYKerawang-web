-- Moderation, part 6: data for the admin case detail pane and the
-- report sheet's optional note. Additive and re-runnable.
--
--   reports.note            optional free text from the reporter (≤ 500)
--   admin_case_detail(id)   every report on the case, the author's other
--                           cases and active restrictions. Author history
--                           is omitted for anonymous targets, so the
--                           detail pane can't de-anonymise either.
-- Reporter identities are never returned: admins judge the content.

alter table public.reports add column if not exists note text;

alter table public.reports drop constraint if exists reports_note_length;
alter table public.reports add constraint reports_note_length
  check (note is null or length(note) <= 500);

create or replace function public.admin_case_detail(p_case_id uuid)
returns jsonb
language plpgsql security definer stable
set search_path = public
as $$
declare
  c public.moderation_cases;
  v jsonb;
begin
  perform public.mod_require_admin();

  select * into c from public.moderation_cases where id = p_case_id;
  if not found then
    raise exception 'MOD:not_found' using errcode = 'P0001';
  end if;

  select jsonb_build_object(
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
               'category', r.category, 'reason', r.reason,
               'note', nullif(btrim(coalesce(r.note, '')), ''),
               'created_at', r.created_at, 'status', r.status,
               'counted', r.counts_toward_auto_hide)
             order by r.created_at)
      from public.reports r where r.case_id = c.id), '[]'::jsonb),
    'history', case when c.target_anonymous or c.target_owner_id is null then '[]'::jsonb
      else coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', h.id, 'target_type', h.target_type, 'status', h.status,
                 'decision', h.decision, 'decision_reason', h.decision_reason,
                 'strike', h.strike, 'first_reported_at', h.first_reported_at,
                 'decided_at', h.decided_at)
               order by h.first_reported_at desc)
        from (select * from public.moderation_cases h
              where h.target_owner_id = c.target_owner_id and h.id <> c.id
                and not h.target_anonymous
              order by h.first_reported_at desc limit 20) h), '[]'::jsonb) end,
    'restrictions', case when c.target_anonymous or c.target_owner_id is null then '[]'::jsonb
      else coalesce((
        select jsonb_agg(jsonb_build_object(
                 'scope', x.scope, 'until', x.until, 'reason', x.reason,
                 'automatic', x.created_by is null)
               order by x.created_at desc)
        from public.user_restrictions x
        where x.user_id = c.target_owner_id and x.lifted_at is null
          and (x.until is null or x.until > now())), '[]'::jsonb) end
  ) into v;
  return v;
end;
$$;

revoke execute on function public.admin_case_detail(uuid) from public, anon;
grant  execute on function public.admin_case_detail(uuid) to authenticated;
