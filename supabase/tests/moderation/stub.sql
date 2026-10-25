create schema if not exists auth;
create role anon nologin;
create role authenticated nologin;
grant usage on schema public, auth to anon, authenticated;
create table auth.users (id uuid primary key, created_at timestamptz not null default now(), email text default 'x@student.uitm.edu.my', raw_app_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant execute on function auth.uid() to anon, authenticated;
alter default privileges in schema public grant select, insert, update, delete on tables to anon, authenticated;

create table public.profiles (id uuid primary key references auth.users(id) on delete cascade,
  username text, display_name text, full_name text, avatar_url text, bio text,
  role text not null default 'student', is_verified boolean default false,
  is_banned boolean default false, ban_reason text, phone_number text, payment_qr_url text, created_at timestamptz default now());
create table public.events (id uuid primary key default gen_random_uuid(), organizer_id uuid references public.profiles(id),
  title text, description text, location text, start_datetime timestamptz, end_datetime timestamptz,
  image_url text, gallery_urls text[], tags text[], is_public boolean default true, registration_link text,
  created_at timestamptz default now());
create table public.listings (id uuid primary key default gen_random_uuid(), seller_id uuid references public.profiles(id),
  title text, description text, price numeric, category text, image_url text, gallery_urls text[],
  is_sold boolean default false, fulfillment_type text, created_at timestamptz default now());
create table public.posts (id uuid primary key default gen_random_uuid(), user_id uuid references public.profiles(id),
  title text, body text, image_url text, gallery_urls text[], tags text[], upvotes int default 0,
  comment_count int default 0, is_anonymous boolean, is_hidden boolean,
  shared_event_id uuid references public.events(id), shared_listing_id uuid references public.listings(id),
  created_at timestamptz default now());
create table public.comments (id uuid primary key default gen_random_uuid(), post_id uuid references public.posts(id),
  event_id uuid references public.events(id), user_id uuid references public.profiles(id), body text,
  is_anonymous boolean, created_at timestamptz default now());
-- The real table has a primary key on (event_id, user_id): check-in and the
-- join button both rely on ON CONFLICT to dedupe. Without it here, a test can
-- insert the same person twice and pass.
create table public.event_participants (event_id uuid references public.events(id), user_id uuid references public.profiles(id),
  primary key (event_id, user_id));
create table public.followers (follower_id uuid, following_id uuid);
create table public.reports (id uuid primary key default gen_random_uuid(), reporter_id uuid, target_id uuid,
  target_type text, reason text);
create table public.notifications (id uuid primary key default gen_random_uuid(), user_id uuid, actor_id uuid not null,
  type text, title text, body text, data jsonb, is_read boolean default false, created_at timestamptz default now());

alter table public.posts enable row level security;
create policy p_ins on public.posts for insert with check (user_id = auth.uid());
create policy p_upd on public.posts for update using (true);
alter table public.comments enable row level security;
create policy c_ins on public.comments for insert with check (user_id = auth.uid());
alter table public.events enable row level security;
create policy e_all on public.events for all using (true) with check (organizer_id = auth.uid());
alter table public.listings enable row level security;
create policy l_all on public.listings for all using (true) with check (seller_id = auth.uid());
alter table public.profiles enable row level security;
create policy pr_sel on public.profiles for select using (true);
create policy pr_upd on public.profiles for update using (id = auth.uid());
alter table public.notifications enable row level security;
create policy n_sel on public.notifications for select using (user_id = auth.uid());
