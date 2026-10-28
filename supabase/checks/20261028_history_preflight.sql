-- History preflight: is a migration actually live, before telling the CLI it is?
--
-- The remote migration history table is incomplete (earlier files were pasted
-- into the dashboard), so `db push` lists work that is already applied. Marking
-- that work with `migration repair` is only safe if it really is live — this
-- query proves it object by object.
--
--   npx supabase db query --file supabase/checks/20261028_history_preflight.sql --db-url "<uri>"
--
-- Every row should say present = true before repairing that version.

with expected(migration_id, kind, name) as (values
  ('20261025001100', 'function', 'mod_category_from_reason'),
  ('20261025002100', 'function', 'admin_read_backup_email'),
  ('20261025003100', 'default',  'moderation_settings.priority_categories'),
  ('20261025004100', 'table',    'student_verifications'),
  ('20261025005100', 'function', 'request_student_verification'),
  ('20261026001100', 'table',    'content_categories'),
  ('20261026003100', 'function', 'event_guard_merit'),
  ('20261026004100', 'policy',   'events_hide_select'),
  ('20261026005100', 'function', 'enforce_student_email_signup'),
  ('20261026006100', 'function', 'apply_to_club'),
  ('20261026007100', 'table',    'form_templates'),
  ('20261026008100', 'function', 'events_guard_links'),
  ('20261026009100', 'function', 'event_checkin_token'),
  ('20261026010100', 'function', 'set_form_after_checkin'),
  ('20261026011100', 'function', 'checkin_with_token'),
  ('20261026014100', 'bucket',   'images')
)
select e.migration_id,
       e.kind,
       e.name,
       case e.kind
         when 'table'    then to_regclass('public.' || e.name) is not null
         when 'function' then to_regproc('public.' || e.name) is not null
         when 'policy'   then p.polname is not null
         when 'default'  then c.column_default like '%harassment%'
         when 'bucket'   then b.file_size_limit is not null and b.allowed_mime_types is not null
       end as present
from expected e
left join pg_policy p
       on e.kind = 'policy' and p.polname = e.name
left join information_schema.columns c
       on e.kind = 'default'
      and c.table_schema = 'public'
      and c.table_name   = split_part(e.name, '.', 1)
      and c.column_name  = split_part(e.name, '.', 2)
left join storage.buckets b
       on e.kind = 'bucket' and b.id::text = e.name
order by e.migration_id;
