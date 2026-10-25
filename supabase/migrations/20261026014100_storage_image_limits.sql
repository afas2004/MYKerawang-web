-- 20261026014100_storage_image_limits.sql
--
-- What the two public image buckets will accept.
--
-- The app already uploads safely: the picker re-encodes and downsizes, the
-- object name is fixed (`posts/<stamp>_<i>.jpg`, `avatars/<uid>_<ts>.jpg`) and
-- the content type is sniffed from the bytes (`imageContentType`), so nothing a
-- user types reaches the storage key.
--
-- The bucket itself was the last line of defence. A signed-in client can call
-- the storage API directly, and without a MIME allowlist the `images` bucket
-- would happily store an `image/svg+xml` or a text/html file, which is then
-- served — with that content type — from the project's storage domain. That is
-- stored script execution on *.supabase.co (a different origin from
-- kerawang.my, so no session theft, but a phishing and defacement surface).
--
-- 5 MB is roomy: the picker caps at 1600 px / quality 80, so a photo lands
-- around 200–500 KB.
--
-- Re-runnable: setting the same values twice is a no-op, and existing objects
-- are untouched (this only checks future writes).

update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
       file_size_limit = 5242880
 where id in ('images', 'avatars');
