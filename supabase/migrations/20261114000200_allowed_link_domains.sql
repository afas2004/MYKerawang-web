-- Safe links: the websites whose links become tappable in posts, comments
-- and event descriptions. Every other link stays plain text, so a scam or
-- phishing link (a fake login page made to steal passwords) can't be
-- opened with one tap.
--
-- A domain also covers its subdomains: 'uitm.edu.my' lets
-- 'student.uitm.edu.my' through. It is never a substring match:
-- 'evil-forms.gle.com' does NOT match 'forms.gle'. The matching itself is in
-- the app (lib/utils/safe_links.dart); this table is only the list.
--
-- Who can do what (RLS = row-level security, the database's own per-row
-- permission check, applied whatever the app does):
--   read            everyone, signed out too (guests read posts)
--   add / remove    admins and the owner (public.is_admin())
-- There is no edit: remove and add again.

create table if not exists public.allowed_link_domains (
  domain     text primary key,
  note       text,
  added_by   uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  -- Lower-case host name only: no scheme, path, port or spaces.
  constraint allowed_link_domains_domain_valid check (
    length(domain) <= 253
    and domain ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$'),
  constraint allowed_link_domains_note_len check (note is null or length(note) <= 200)
);

comment on table public.allowed_link_domains is
  'Sites whose links are tappable in user-written text (with their subdomains). Read by everyone; admins add/remove.';

alter table public.allowed_link_domains enable row level security;

drop policy if exists "allowed_link_domains_read" on public.allowed_link_domains;
create policy "allowed_link_domains_read" on public.allowed_link_domains
  for select to anon, authenticated
  using (true);

drop policy if exists "allowed_link_domains_insert" on public.allowed_link_domains;
create policy "allowed_link_domains_insert" on public.allowed_link_domains
  for insert to authenticated
  with check (public.is_admin());

drop policy if exists "allowed_link_domains_delete" on public.allowed_link_domains;
create policy "allowed_link_domains_delete" on public.allowed_link_domains
  for delete to authenticated
  using (public.is_admin());

revoke all on public.allowed_link_domains from anon, authenticated;
grant select on public.allowed_link_domains to anon, authenticated;
grant insert, delete on public.allowed_link_domains to authenticated;

-- Starter list. The app has the same list built in as a fallback for when
-- the table can't be read (lib/utils/safe_links.dart, kSeedAllowedDomains).
-- Trim it in Admin → Allowed links; running this file again only re-adds
-- missing rows, it never removes any.
insert into public.allowed_link_domains (domain, note, added_by) values
  ('kerawang.my',       'This app',                null),
  ('forms.gle',         'Google Forms short links',  null),
  ('docs.google.com',   'Google Forms / Docs',       null),
  ('drive.google.com',  'Google Drive',              null),
  ('maps.google.com',   'Google Maps',               null),
  ('maps.app.goo.gl',   'Google Maps short links',   null),
  ('goo.gl',            'Google short links',        null),
  ('chat.whatsapp.com', 'WhatsApp group invites',    null),
  ('wa.me',             'WhatsApp chat links',       null),
  ('whatsapp.com',      'WhatsApp',                  null),
  ('t.me',              'Telegram',                  null),
  ('instagram.com',     'Instagram',                 null),
  ('tiktok.com',        'TikTok',                    null),
  ('youtube.com',       'YouTube',                   null),
  ('youtu.be',          'YouTube short links',       null),
  ('facebook.com',      'Facebook',                  null),
  ('fb.me',             'Facebook short links',      null),
  ('uitm.edu.my',       'UiTM',                      null)
on conflict (domain) do nothing;
