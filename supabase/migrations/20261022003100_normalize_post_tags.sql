-- Hashtag feeds showed nothing for older posts: the first editors saved
-- tags as typed ("Rant", "Lost&Found", "#rant") while the app now looks
-- them up in their stored form (lowercase, no '#', Lost & Found spelt
-- "lostfound" — lib/utils/tags.dart normalizeTag).
--
-- 1. normalize_tags(): the SQL twin of normalizeTag/parseTags.
-- 2. A trigger keeps every future write normalised, whoever writes it.
-- 3. A backfill rewrites existing rows.
-- 4. A GIN index makes `tags && '{rant}'` (PostgREST `ov`) cheap.
-- Safe to re-run.

create or replace function public.normalize_tags(p_tags text[])
returns text[]
language sql immutable
set search_path = public
as $$
  select coalesce(array(
    select t
    from (
      select
        case when regexp_replace(x, '[&_\s-]', '', 'g') = 'lostfound'
             then 'lostfound' else x end as t,
        n
      from (
        select lower(btrim(regexp_replace(btrim(raw), '^#+', ''))) as x, n
        from unnest(p_tags) with ordinality as u(raw, n)
        where raw is not null
      ) cleaned
      where x <> ''
    ) mapped
    group by t
    order by min(n)          -- first spelling wins, order kept
  ), '{}'::text[]);
$$;

create or replace function public.posts_normalize_tags()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.tags := public.normalize_tags(new.tags);
  return new;
end;
$$;

drop trigger if exists trg_posts_normalize_tags on public.posts;
create trigger trg_posts_normalize_tags
before insert or update of tags on public.posts
for each row execute function public.posts_normalize_tags();

-- Backfill. Runs without auth.uid(), so the moderation write guard lets
-- it through (system write).
update public.posts
set tags = public.normalize_tags(tags)
where tags is not null
  and tags is distinct from public.normalize_tags(tags);

create index if not exists posts_tags_gin on public.posts using gin (tags);
