-- Import from Google Form.
--
-- Someone pastes a Google Form link; the app turns it into an ordinary,
-- editable MYKerawang form. A web page cannot read docs.google.com itself (the
-- browser blocks reading another site's pages, "CORS"), so the database fetches
-- the public form page and hands back only the question data Google embeds in
-- it (`FB_PUBLIC_LOAD_DATA_`). The app turns that into questions
-- (lib/utils/google_form_import.dart) and the user reviews them before
-- anything is saved.
--
-- Safety ("SSRF": using our server to fetch addresses it should not):
--   * only https links on forms.gle or docs.google.com/forms/ are fetched,
--     rebuilt from their id, never passed through as typed
--   * every redirect is checked the same way; a redirect to Google's sign-in
--     page means the form needs an account (reported as `sign_in`)
--   * pages over 2 MB are refused, and a fetch gives up after 10 seconds
--   * signed-in users only, 10 imports per 10 minutes and 30 per day each
--
-- The fetch uses the `http` extension (pgsql-http). If it cannot be created
-- here, the migration still applies and the function answers `unavailable`.
--
-- Re-runnable: the test harness applies every migration twice. The harness
-- has no `http` extension; it replaces google_form_http_get() with a stub.

do $$
begin
  create extension if not exists http with schema extensions;
exception when others then
  raise notice 'http extension unavailable (%); Google Form import will answer "unavailable"', sqlerrm;
end
$$;

-- ====================================================== rate limit log

create table if not exists public.google_form_imports (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists google_form_imports_user_idx
  on public.google_form_imports (user_id, created_at desc);

-- Only import_google_form() (security definer) reads or writes it.
alter table public.google_form_imports enable row level security;
revoke all on public.google_form_imports from public, anon, authenticated;

-- ====================================================== link rules

-- The one fetchable form of a pasted link, or null when it is not a Google
-- Form link. Same rules as normaliseGoogleFormUrl() in the app.
create or replace function public.google_form_url(p_url text)
returns text
language plpgsql immutable
as $$
declare
  v text := btrim(coalesce(p_url, ''));
  m text[];
begin
  -- No spaces, backslashes or "user@host" tricks anywhere.
  if length(v) = 0 or length(v) > 500 or v ~ '[[:space:]\\@]' then
    return null;
  end if;

  m := regexp_match(v,
    '^https://forms\.gle/([A-Za-z0-9_-]{4,64})/?([?#][A-Za-z0-9_.~=&%+-]*)?$');
  if m is not null then
    return 'https://forms.gle/' || m[1];
  end if;

  m := regexp_match(v,
    '^https://docs\.google\.com/forms(?:/u/[0-9]{1,2})?/d/(e/)?([A-Za-z0-9_-]{10,128})'
    || '(?:/[A-Za-z]{0,20})?/?([?#][A-Za-z0-9_.~=&%+-]*)?$');
  if m is not null then
    return 'https://docs.google.com/forms/d/' || coalesce(m[1], '') || m[2] || '/viewform';
  end if;

  return null;
end;
$$;

grant execute on function public.google_form_url(text) to authenticated;

-- ====================================================== the fetch

-- One GET, no questions asked: status, Location header and body. Kept apart
-- so the test harness can swap it for a stub. Not callable by app users.
create or replace function public.google_form_http_get(p_url text)
returns jsonb
language plpgsql
set search_path = public, extensions
as $$
declare
  r     record;
  v_loc text;
begin
  if not exists (select 1 from pg_extension where extname = 'http') then
    raise exception 'GFORM:unavailable';
  end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '10');
  select * into r from extensions.http((
    'GET', p_url,
    array[
      extensions.http_header('User-Agent', 'Mozilla/5.0 (compatible; MYKerawang form import)'),
      extensions.http_header('Accept-Language', 'en')
    ],
    null, null)::extensions.http_request);

  select h.value into v_loc
  from unnest(r.headers) h
  where lower(h.field) = 'location'
  limit 1;

  return jsonb_build_object(
    'status', r.status,
    'location', v_loc,
    'size', coalesce(length(r.content), 0),
    -- Never more than the size limit plus one, so an oversized page is
    -- recognised without carrying it around.
    'body', left(coalesce(r.content, ''), 2000001));
end;
$$;

revoke execute on function public.google_form_http_get(text) from public, anon, authenticated;

-- ====================================================== the RPC

-- {ok: true, data: <FB_PUBLIC_LOAD_DATA_ array>} or {ok: false, reason}.
-- Reasons: bad_url · rate_limited · unavailable · sign_in · closed ·
-- not_found · bad_redirect · too_big · no_data · fetch_failed.
create or replace function public.import_google_form(p_url text)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_url    text := public.google_form_url(p_url);
  v_resp   jsonb;
  v_status int;
  v_loc    text;
  v_body   text;
  v_at     int;
  v_end    int;
  v_json   text;
  v_data   jsonb;
  v_hop    int;
begin
  if v_uid is null then
    raise exception 'FORM:login_required' using errcode = '42501';
  end if;
  if v_url is null then
    return jsonb_build_object('ok', false, 'reason', 'bad_url');
  end if;

  if (select count(*) from public.google_form_imports
      where user_id = v_uid and created_at > now() - interval '10 minutes') >= 10
     or (select count(*) from public.google_form_imports
         where user_id = v_uid and created_at > now() - interval '1 day') >= 30 then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;
  insert into public.google_form_imports (user_id) values (v_uid);

  -- forms.gle → docs.google.com/forms/d/e/…/viewform is one hop; allow a few.
  for v_hop in 1..4 loop
    begin
      v_resp := public.google_form_http_get(v_url);
    exception when others then
      return jsonb_build_object('ok', false, 'reason',
        case when sqlerrm like 'GFORM:unavailable%' then 'unavailable' else 'fetch_failed' end);
    end;

    v_status := coalesce((v_resp->>'status')::int, 0);
    v_loc := btrim(coalesce(v_resp->>'location', ''));

    if v_status between 300 and 399 then
      if v_loc like '/%' then
        v_loc := regexp_replace(v_url, '^(https://[^/]+).*$', '\1') || v_loc;
      end if;
      if v_loc ~* '^https://(accounts\.google\.com|www\.google\.com/accounts)/' then
        return jsonb_build_object('ok', false, 'reason', 'sign_in');
      end if;
      if v_loc ~ '^https://docs\.google\.com/forms/.*/closedform' then
        return jsonb_build_object('ok', false, 'reason', 'closed');
      end if;
      v_url := public.google_form_url(v_loc);
      if v_url is null then
        return jsonb_build_object('ok', false, 'reason', 'bad_redirect');
      end if;
      continue;
    end if;

    if v_status in (404, 410) then
      return jsonb_build_object('ok', false, 'reason', 'not_found');
    end if;
    if v_status in (401, 403) then
      return jsonb_build_object('ok', false, 'reason', 'sign_in');
    end if;
    if v_status <> 200 then
      return jsonb_build_object('ok', false, 'reason', 'fetch_failed');
    end if;
    if coalesce((v_resp->>'size')::int, 0) > 2000000 then
      return jsonb_build_object('ok', false, 'reason', 'too_big');
    end if;

    v_body := coalesce(v_resp->>'body', '');
    v_at := strpos(v_body, 'FB_PUBLIC_LOAD_DATA_');
    if v_at = 0 then
      -- No form data: a sign-in page (the fetch followed Google's redirect
      -- itself), a closed form, or not a form at all.
      if v_body ~* '(ServiceLogin|/v3/signin/|accounts\.google\.com/signin)' then
        return jsonb_build_object('ok', false, 'reason', 'sign_in');
      end if;
      if v_body ~* 'closedform' then
        return jsonb_build_object('ok', false, 'reason', 'closed');
      end if;
      return jsonb_build_object('ok', false, 'reason', 'no_data');
    end if;

    -- FB_PUBLIC_LOAD_DATA_ = [ … ];</script>
    v_body := substr(v_body, v_at);
    v_body := substr(v_body, strpos(v_body, '=') + 1);
    v_end := strpos(v_body, '</script>');
    if v_end = 0 then
      return jsonb_build_object('ok', false, 'reason', 'no_data');
    end if;
    v_json := regexp_replace(btrim(substr(v_body, 1, v_end - 1)), ';[[:space:]]*$', '');
    begin
      v_data := v_json::jsonb;
    exception when others then
      return jsonb_build_object('ok', false, 'reason', 'no_data');
    end;
    if jsonb_typeof(v_data) <> 'array' then
      return jsonb_build_object('ok', false, 'reason', 'no_data');
    end if;
    return jsonb_build_object('ok', true, 'data', v_data);
  end loop;

  return jsonb_build_object('ok', false, 'reason', 'fetch_failed');
end;
$$;

revoke execute on function public.import_google_form(text) from public, anon;
grant execute on function public.import_google_form(text) to authenticated;
