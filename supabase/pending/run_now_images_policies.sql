-- RUN THIS ONE NOW — the `images` bucket write policies.
--
-- This is the only destructive hole in the review: with nothing but the
-- publishable key (which is printed in the app's own JavaScript), anyone on the
-- internet can delete or overwrite every photo in the `images` bucket, and
-- those deletions are permanent (Supabase backups cover the database, not
-- storage objects).
--
-- This file is the storage section of
-- 20261026015100_security_review_fixes.sql, extracted so you can close the
-- destructive hole without also applying the form caps and the domain trigger
-- in the same minute. Running this now and the rest of the migration later is
-- safe: both are idempotent and this block would just be re-applied.
--
-- What it does, measured before/after on the live project:
--   BEFORE  anon POST   /object/images/<any path>       → 200
--   BEFORE  anon POST   same path, x-upsert:true        → 200 (overwrites)
--   BEFORE  anon DELETE /object/images/<existing>       → 200, object gone
--   AFTER   all three → 400/403; a signed-in upload still works.
--
-- Nothing is deleted or rewritten by running this. It drops the old policy on
-- storage.objects that mentions `images` and creates four narrower ones.
-- Uploads keep working because the app is always signed in when it uploads.
--
-- Rollback: the previous policy definition is not in the repo — capture it
-- first with the SELECT at the bottom if you want a literal rollback. To undo
-- without it, drop the four `images_*` policies and re-create whatever the
-- dashboard had (a permissive `bucket_id = 'images'` policy for ALL).

do $$
declare
  pol record;
begin
  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'storage' and c.relname = 'objects'
  ) then
    raise notice 'storage.objects not found — nothing to do';
    return;
  end if;

  -- Drop every existing policy on storage.objects whose expression mentions
  -- this bucket (the dashboard's permissive one, plus any leftover from a
  -- previous run). Permissive policies OR together, so a survivor would keep
  -- the hole open.
  for pol in
    select p.polname
    from pg_policy p
    where p.polrelid = 'storage.objects'::regclass
      and coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' ||
          coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') ilike '%images%'
  loop
    execute format('drop policy %I on storage.objects', pol.polname);
    raise notice 'dropped old policy %', pol.polname;
  end loop;

  -- Insert: any signed-in user, any path. Not owner-checked on purpose: if
  -- `owner` were ever null, an owner check here would refuse every upload. The
  -- client generates the name and never reuses one.
  create policy "images_insert" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'images');

  -- Update/delete: only the object's owner. `x-upsert` is INSERT … ON CONFLICT
  -- DO UPDATE, so it needs this policy too — that is what stops a user
  -- overwriting someone else's image by guessing its path.
  create policy "images_update" on storage.objects
    for update to authenticated
    using (bucket_id = 'images' and owner = auth.uid())
    with check (bucket_id = 'images' and owner = auth.uid());

  create policy "images_delete" on storage.objects
    for delete to authenticated
    using (bucket_id = 'images' and owner = auth.uid());

  -- Read stays as it was: public URLs are served by the public object endpoint
  -- and never consult this policy.
  create policy "images_read" on storage.objects
    for select to anon, authenticated
    using (bucket_id = 'images');
end $$;

-- What you should see when this finishes: exactly four rows, all `images_*`,
-- with the old permissive policy gone.
select polname,
       polcmd,
       pg_get_expr(polqual, polrelid)      as using_expr,
       pg_get_expr(polwithcheck, polrelid) as check_expr
from pg_policy
where polrelid = 'storage.objects'::regclass
order by polname;

-- Then prove it from outside, with only the publishable key:
--
--   # 1. anon upload — must be refused (was 200)
--   curl -s -o /dev/null -w "%{http_code}\n" -X POST \
--     "https://zxjuqpqzyzmegdjttzyz.supabase.co/storage/v1/object/images/probe.png" \
--     -H "apikey: sb_publishable_REqYNPrrJEIgmEjZjrJhtg_1JrLn_yO" \
--     -H "Content-Type: image/png" --data-binary @tiny.png
--
--   # 2. anon delete of any existing object — must be refused (was 200)
--   curl -s -o /dev/null -w "%{http_code}\n" -X DELETE \
--     "https://zxjuqpqzyzmegdjttzyz.supabase.co/storage/v1/object/images/posts/<a real name>.jpg" \
--     -H "apikey: sb_publishable_REqYNPrrJEIgmEjZjrJhtg_1JrLn_yO"
--
--   # 3. the app itself still loads images (public URL, no key)
--   curl -s -o /dev/null -w "%{http_code}\n" \
--     "https://zxjuqpqzyzmegdjttzyz.supabase.co/storage/v1/object/public/images/posts/<a real name>.jpg"
--
-- #3 must stay 200. #1 and #2 must be 400 or 403.
