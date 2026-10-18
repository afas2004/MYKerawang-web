-- Post titles are optional: a post needs a title, text or a photo, and
-- the app enforces that. No-op if the column is already nullable.
alter table public.posts alter column title drop not null;
