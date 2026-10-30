-- preflight.sql — READ ONLY. Run this in the Supabase SQL Editor and paste the
-- output back before applying 20261026015100_security_review_fixes.sql.
--
-- It answers the only questions that decide whether that migration can break
-- something that already exists. Nothing here writes anything.

-- 1. Forms the new title/intro caps would block on the next save or publish.
--    (The constraints are NOT VALID, so existing rows are not scanned — but a
--    later edit of one of these rows would now fail. If this returns rows,
--    shorten them first, or ask for the caps to be raised.)
select id, length(title) as title_len, length(coalesce(intro, '')) as intro_len
from public.event_forms
where length(title) > 120 or length(coalesce(intro, '')) > 500;

-- 2. Fields the new help/choice caps would block when the form is saved or
--    published. publish_form() re-validates every field, so a legacy long
--    choice makes an existing draft unpublishable.
select f.id, f.form_id, f.kind, length(coalesce(f.help, '')) as help_len,
       (select max(length(c))
          from jsonb_array_elements_text(f.options -> 'choices') c) as max_choice_len
from public.form_fields f
where length(coalesce(f.help, '')) > 300
   or (jsonb_typeof(f.options -> 'choices') = 'array'
       and exists (select 1
                     from jsonb_array_elements_text(f.options -> 'choices') c
                    where length(c) > 60));

-- 3. Verified rows whose address is not the student domain. Reads and existing
--    status are untouched; this only matters if someone later edits the row.
select user_id, email::text, status
from public.student_verifications
where status = 'verified'
  and lower(split_part(email::text, '@', 2))
      is distinct from lower(ltrim((select student_domain from public.access_settings where id), '@'));

-- 4. Images uploaded without an owner. Under the new policy their uploader
--    cannot replace or delete them (they stay readable; this is cleanup only).
select count(*) filter (where owner is null) as no_owner,
       count(*)                              as total
from storage.objects
where bucket_id = 'images';

-- 5. The policies that exist on storage.objects right now — this is the
--    "before" picture for the images bucket. If more than one permissive row
--    mentions 'images', the migration's drop loop removes all of them.
select polname, polcmd,
       pg_get_expr(polqual, polrelid)       as using_expr,
       pg_get_expr(polwithcheck, polrelid)  as check_expr
from pg_policy
where polrelid = 'storage.objects'::regclass
order by polname;

-- 6. Who can read profiles / followers / event_participants today (the H2
--    sign-off item). Compare with what the repo says anon should have.
select table_name, grantee, string_agg(privilege_type, ', ' order by privilege_type) as privs
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('profiles', 'followers', 'event_participants')
  and grantee in ('anon', 'authenticated')
group by table_name, grantee
order by table_name, grantee;

-- 7. How many objects are in each bucket (context for the storage change).
select bucket_id, count(*) from storage.objects group by bucket_id order by bucket_id;

-- 8. THE IMPORTANT ONE FOR THE REVIEW GAP. The base tables were created in the
--    dashboard, so their policies are not in the repo and are the only part of
--    the RLS picture that could not be read. This prints them.
select tablename, policyname, cmd, roles::text,
       coalesce(qual, '(none)')       as using_expr,
       coalesce(with_check, '(none)') as check_expr
from pg_policies
where schemaname = 'public'
  and tablename in ('profiles', 'posts', 'comments', 'events', 'listings', 'reports')
order by tablename, cmd, policyname;

-- 9. The dangerous subset: a policy that lets a normal signed-in user write or
--    DELETE with no ownership predicate. Any row here is a real hole — an
--    UPDATE with `using (true)` lets one student edit another's content, and a
--    DELETE with `using (true)` lets them destroy it. Send me this output and
--    I will say which lines matter.
select tablename, policyname, cmd, roles::text,
       coalesce(qual, '(none)')       as using_expr,
       coalesce(with_check, '(none)') as check_expr
from pg_policies
where schemaname = 'public'
  and permissive = 'PERMISSIVE'
  and tablename in ('profiles', 'posts', 'comments', 'events', 'listings', 'reports',
                    'event_participants', 'club_members', 'form_responses')
  and (
        (cmd = 'INSERT' and (with_check is null or with_check = 'true'))
     or (cmd in ('ALL', 'UPDATE', 'DELETE') and (qual is null or qual = 'true'))
      )
order by tablename, cmd, policyname;

-- ====================================================== THE SUMMARY (last)
-- The SQL editor shows the result of the LAST statement, so this is the one
-- you will see after running the whole file. Six rows. Every number should be
-- 0. Anything above 0: send me this table and I will read it for you.
select '1. forms the new caps would block' as check_name,
       (select count(*) from public.event_forms
         where length(title) > 120 or length(coalesce(intro, '')) > 500) as rows_found,
       '0 = safe to apply the caps' as meaning
union all
select '2. form fields the caps would block',
       (select count(*) from public.form_fields f
         where length(coalesce(f.help, '')) > 300
            or (jsonb_typeof(f.options -> 'choices') = 'array'
                and exists (select 1 from jsonb_array_elements_text(f.options -> 'choices') c
                             where length(c) > 60))),
       '0 = safe to apply the caps'
union all
select '3. verified addresses off the student domain',
       (select count(*) from public.student_verifications
         where status = 'verified'
           and lower(split_part(email::text, '@', 2))
               is distinct from lower(ltrim((select student_domain from public.access_settings where id), '@'))),
       '0 = safe; otherwise only future edits are blocked'
union all
select '4. write/delete policies with no ownership check',
       (select count(*) from pg_policies
         where schemaname = 'public' and permissive = 'PERMISSIVE'
           and tablename in ('profiles', 'posts', 'comments', 'events', 'listings',
                             'reports', 'event_participants', 'club_members', 'form_responses')
           and ((cmd = 'INSERT' and (with_check is null or with_check = 'true'))
             or (cmd in ('ALL', 'UPDATE', 'DELETE') and (qual is null or qual = 'true')))),
       '0 = the review gap is closed; above 0 = send me section 9'
union all
select '5. images objects with no owner',
       (select count(*) from storage.objects
         where bucket_id = 'images' and owner is null),
       'informational: these can no longer be deleted by users'
union all
select '6. old permissive images policies left behind',
       (select count(*) from pg_policy
         where polrelid = 'storage.objects'::regclass
           and polname not like 'images\_%'
           and coalesce(pg_get_expr(polqual, polrelid), '') || ' ' ||
               coalesce(pg_get_expr(polwithcheck, polrelid), '') ilike '%images%'),
       '0 = the storage fix is complete';
