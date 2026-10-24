-- Queue rules: shaming and explicit content are the ones that cannot
-- wait; everything else — scam and minor safety included — sits until the
-- configured number of distinct reporters agrees.
--
--   priority_categories      hidden on the first report   → shaming, explicit
--   review_first_categories  queued first, not hidden     → impersonation
--   auto_hide_report_count   distinct reporters for the rest (currently 3)
--
-- The counter is the existing setting (owner can raise it to 3–5 from
-- Admin → Settings); only the priority list changes here.
--
-- Re-runnable: the update is idempotent.

alter table public.moderation_settings
  alter column priority_categories set default '{harassment,inappropriate}';

update public.moderation_settings
set priority_categories = '{harassment,inappropriate}',
    updated_at = now()
where id;

comment on column public.moderation_settings.priority_categories is
  'Hidden on the first report: shaming/harassment and explicit content. Every other category waits for auto_hide_report_count distinct reporters.';
