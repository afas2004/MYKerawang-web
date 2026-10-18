-- #lostfound is the reserved Lost & Found tag. Older posts saved it as
-- 'lost&found' (from the "Lost&Found" suggestion); rewrite them so tag
-- feeds and search only need the one spelling. Safe to re-run.
update public.posts
set tags = array_replace(tags, 'lost&found', 'lostfound')
where 'lost&found' = any(tags);

-- array_replace can leave a duplicate if both spellings were present;
-- drop repeats, keeping first-seen order (the first tag leads on cards).
update public.posts
set tags = array(
  select t from unnest(tags) with ordinality u(t, n)
  group by t order by min(n))
where array_length(tags, 1) <> (select count(distinct t) from unnest(tags) t);
