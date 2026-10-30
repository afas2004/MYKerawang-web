-- Repairs three template strings that 20261029002100 wrote with a broken
-- character: its seed was generated in the Windows code page, so "…" and "—"
-- reached the database as U+FFFD ("�"). The 002100 file itself is fixed, so a
-- fresh database never sees this; this corrects the rows already applied.
--
-- Only template text changes. Forms already made from these templates keep
-- their own copy of the questions and are fixed below as well, but only where
-- the broken character is still there (an owner who retyped the label wins).
--
-- Re-runnable: replace() of a character that is no longer there is a no-op.

update public.form_templates
set description    = replace(description,    chr(65533), '—'),
    description_ms = replace(description_ms, chr(65533), '—')
where slug = 'facility_report'
  and (description like '%' || chr(65533) || '%' or description_ms like '%' || chr(65533) || '%');

update public.form_template_fields f
set label    = replace(f.label,    chr(65533), '…'),
    label_ms = replace(f.label_ms, chr(65533), '…')
from public.form_templates t
where t.id = f.template_id
  and t.slug in ('food_preorder', 'lost_found')
  and (f.label like '%' || chr(65533) || '%' or f.label_ms like '%' || chr(65533) || '%');

-- Forms already made from those two templates.
update public.form_fields x
set label = replace(x.label, chr(65533), '…')
from public.event_forms ef
join public.form_templates t on t.id = ef.template_id
where x.form_id = ef.id
  and t.slug in ('food_preorder', 'lost_found')
  and x.label like '%' || chr(65533) || '%';
