"""MYKerawang phone notifications (push) sender.

Runs from .github/workflows/push.yml: on a schedule, and at once when the
database starts it (see push_kick() in
supabase/migrations/20261114000100_notifications_v2.sql). Each run:

  1. creates "starting soon" reminders (make_event_reminders()),
  2. takes what is due from the queue (push_take(): quiet hours, the daily
     cap and the reader's settings are already applied there),
  3. sends each one to the reader's devices through Firebase Cloud Messaging,
     written in the reader's language, opening the exact post/event/form,
  4. removes devices FCM says are gone,

and keeps checking for a short while so a burst is sent by one run.

Works the same from a laptop:

    export SUPABASE_URL=https://<project>.supabase.co
    export SUPABASE_SERVICE_ROLE_KEY=...
    export FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
    python worker/push.py --once            # one pass
    python worker/push.py --dry-run --once  # don't send, don't take
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import time

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
SERVICE_ACCOUNT = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "")
APP_URL = os.environ.get("APP_URL", "https://kerawang.my").rstrip("/")
# Malaysia has no daylight saving: a fixed UTC+8 needs no tz database.
APP_TZ = dt.timezone(dt.timedelta(hours=8))
FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
FCM_ERROR_TYPE = "type.googleapis.com/google.firebase.fcm.v1.FcmError"

# ----------------------------------------------------------------- text
# Same wording as the bell (lib/screens/notification_screen.dart).
# {who} actor name, {n} count, {others} count - 1, {title} post/event/form.

T = {
    "comment_post": {
        "en": ("{who} commented on your post", "{who} and {others} others commented on your post"),
        "ms": ("{who} mengulas siaran anda", "{who} dan {others} lagi mengulas siaran anda"),
        "ja": ("{who}さんがあなたの投稿にコメントしました", "{who}さん他{others}人があなたの投稿にコメントしました"),
    },
    "comment_event": {
        "en": ("{who} commented on your event", "{who} and {others} others commented on your event"),
        "ms": ("{who} mengulas acara anda", "{who} dan {others} lagi mengulas acara anda"),
        "ja": ("{who}さんがあなたのイベントにコメントしました", "{who}さん他{others}人があなたのイベントにコメントしました"),
    },
    "also_commented": {
        "en": ("{who} also commented on a post you commented on", "{who} and {others} others also commented"),
        "ms": ("{who} turut mengulas siaran yang anda ulas", "{who} dan {others} lagi turut mengulas"),
        "ja": ("{who}さんもあなたがコメントした投稿にコメントしました", "{who}さん他{others}人もコメントしました"),
    },
    "form_answer": {
        "en": ("New answer to your form", "{n} new answers to your form"),
        "ms": ("Jawapan baharu untuk borang anda", "{n} jawapan baharu untuk borang anda"),
        "ja": ("フォームに新しい回答があります", "フォームに{n}件の新しい回答があります"),
    },
    "event_join": {
        "en": ("{who} joined your event", "{who} and {others} others joined your event"),
        "ms": ("{who} menyertai acara anda", "{who} dan {others} lagi menyertai acara anda"),
        "ja": ("{who}さんがあなたのイベントに参加しました", "{who}さん他{others}人があなたのイベントに参加しました"),
    },
    "event_changed": {
        "en": ("Event changed", "Event changed"),
        "ms": ("Acara dikemas kini", "Acara dikemas kini"),
        "ja": ("イベントが変更されました", "イベントが変更されました"),
    },
    "event_cancelled": {
        "en": ("Event cancelled", "Event cancelled"),
        "ms": ("Acara dibatalkan", "Acara dibatalkan"),
        "ja": ("イベントが中止されました", "イベントが中止されました"),
    },
    "event_reminder": {
        "en": ("Starting soon", "Starting soon"),
        "ms": ("Akan bermula", "Akan bermula"),
        "ja": ("まもなく開始", "まもなく開始"),
    },
    "new_event": {
        "en": ("New event", "New event"),
        "ms": ("Acara baharu", "Acara baharu"),
        "ja": ("新しいイベント", "新しいイベント"),
    },
    "mention": {
        "en": ("{who} mentioned you", "{who} mentioned you"),
        "ms": ("{who} menyebut anda", "{who} menyebut anda"),
        "ja": ("{who}さんがあなたをメンションしました", "{who}さんがあなたをメンションしました"),
    },
    "follow": {
        "en": ("{who} followed you", "{who} followed you"),
        "ms": ("{who} mengikuti anda", "{who} mengikuti anda"),
        "ja": ("{who}さんがあなたをフォローしました", "{who}さんがあなたをフォローしました"),
    },
}

SOMEONE = {"en": "Someone", "ms": "Seseorang", "ja": "誰か"}
STARTS_AT = {"en": "{title} · starts {time}", "ms": "{title} · mula {time}", "ja": "{title} · {time}開始"}
NOW_AT = {"en": "Now {time}", "ms": "Kini {time}", "ja": "{time}に変更"}
NOW_PLACE = {"en": "Now at {place}", "ms": "Kini di {place}", "ja": "場所: {place}"}


def fmt_time(iso: str | None, lang: str) -> str:
    if not iso:
        return ""
    try:
        t = dt.datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(APP_TZ)
    except ValueError:
        return ""
    today = dt.datetime.now(APP_TZ).date()
    hm = t.strftime("%H:%M") if lang == "ja" else t.strftime("%I:%M %p").lstrip("0").lower()
    if lang == "ms":
        hm = hm.replace("am", "pg").replace("pm", "ptg")
    if t.date() == today:
        return hm
    day = t.strftime("%m/%d") if lang == "ja" else t.strftime("%d %b").lstrip("0")
    return f"{day} {hm}"


def render(row: dict) -> tuple[str, str]:
    """(title, body) for a push, in the reader's language."""
    lang = row.get("language") if row.get("language") in ("en", "ms", "ja") else "en"
    data = row.get("data") or {}
    kind = row.get("type") or ""
    if kind == "comment":
        kind = "comment_event" if data.get("event_id") and not data.get("post_id") else "comment_post"
    n = int(row.get("count") or 1)
    who = row.get("actor_name") or (data.get("who") if kind == "form_answer" else None) or SOMEONE[lang]

    tpl = T.get(kind, {}).get(lang)
    if not tpl:  # moderation, clubs, old rows: the stored English text
        return (row.get("title") or "MYKerawang", row.get("body") or "")
    title = (tpl[1] if n > 1 else tpl[0]).format(who=who, n=n, others=n - 1)

    ev_title = data.get("event_title") or ""
    if kind in ("comment_post", "comment_event", "also_commented", "mention"):
        body = data.get("snippet") or row.get("body") or ""
    elif kind == "form_answer":
        body = data.get("form_title") or row.get("body") or ""
    elif kind in ("event_reminder", "new_event"):
        body = STARTS_AT[lang].format(title=ev_title, time=fmt_time(data.get("start"), lang)).rstrip(" ·")
        if data.get("location"):
            body += f" · {data['location']}"
    elif kind == "event_changed":
        parts = [ev_title]
        if data.get("start") != data.get("old_start"):
            parts.append(NOW_AT[lang].format(time=fmt_time(data.get("start"), lang)))
        if data.get("location") != data.get("old_location") and data.get("location"):
            parts.append(NOW_PLACE[lang].format(place=data["location"]))
        body = " · ".join(p for p in parts if p)
    elif kind in ("event_join", "event_cancelled"):
        body = ev_title or row.get("body") or ""
    else:
        body = row.get("body") or ""
    return title, body[:180]


def link_for(row: dict) -> str:
    """The exact page the notification is about (same as the bell's tap)."""
    data = row.get("data") or {}
    kind = row.get("type") or ""
    post, event, form, comment = (data.get(k) for k in ("post_id", "event_id", "form_id", "comment_id"))
    if kind == "form_answer" and form:
        path = f"/event/{event}/form/responses?f={form}" if event else f"/f/{form}/responses"
    elif post:
        path = f"/post/{post}" + (f"?c={comment}" if comment else "")
    elif event:
        path = f"/event/{event}" + (f"?c={comment}" if comment else "")
    elif kind == "follow" and row.get("actor_id"):
        path = f"/u/{row['actor_id']}"
    elif data.get("route"):
        path = str(data["route"])
    else:
        path = "/notifications"
    return APP_URL + path


def is_dead_token(status: str, code: str | None, message: str) -> bool:
    """True only when FCM says the device itself is gone (as in efoc)."""
    if code == "UNREGISTERED" or status == "NOT_FOUND":
        return True
    return status == "INVALID_ARGUMENT" and "registration token" in message.lower()


def fcm_message(token: str, row: dict) -> dict:
    title, body = render(row)
    tag = row.get("group_key") or str(row.get("id"))
    return {
        "message": {
            "token": token,
            "notification": {"title": title, "body": body},
            "data": {"link": link_for(row), "id": str(row.get("id"))},
            "webpush": {
                "notification": {
                    "icon": "/icons/Icon-192.png",
                    # A grouped notification replaces its older copy on screen.
                    "tag": tag,
                    "renotify": True,
                },
                "fcm_options": {"link": link_for(row)},
            },
        }
    }


# ----------------------------------------------------------------- I/O

def _headers() -> dict:
    return {"apikey": SERVICE_KEY, "Authorization": f"Bearer {SERVICE_KEY}",
            "Content-Type": "application/json"}


def rpc(name: str, args: dict) -> object:
    import requests
    r = requests.post(f"{SUPABASE_URL}/rest/v1/rpc/{name}", headers=_headers(), json=args, timeout=30)
    r.raise_for_status()
    return r.json()


def forget_token(token: str) -> None:
    import requests
    requests.delete(f"{SUPABASE_URL}/rest/v1/push_tokens", headers=_headers(),
                    params={"token": f"eq.{token}"}, timeout=30).raise_for_status()


def fcm_session():
    import requests
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    info = json.loads(SERVICE_ACCOUNT)
    creds = service_account.Credentials.from_service_account_info(info, scopes=[FCM_SCOPE])
    creds.refresh(Request())
    s = requests.Session()
    s.headers["Authorization"] = f"Bearer {creds.token}"
    return s, info["project_id"]


def send(session, project: str, msg: dict):
    """None on success, else FCM's (status, error code, message)."""
    r = session.post(f"https://fcm.googleapis.com/v1/projects/{project}/messages:send", json=msg, timeout=30)
    if r.ok:
        return None
    try:
        err = r.json()["error"]
        code = next((d.get("errorCode") for d in err.get("details", [])
                     if d.get("@type") == FCM_ERROR_TYPE), None)
        return err.get("status", f"HTTP {r.status_code}"), code, err.get("message", "")
    except Exception:
        return f"HTTP {r.status_code}", None, r.text[:200]


def one_pass(session, project, dry_run: bool) -> int:
    if dry_run:
        print("dry run: not taking from the queue")
        return 0
    rows = rpc("push_take", {"p_limit": 200}) or []
    sent = failed = removed = 0
    for row in rows:
        for token in row.get("tokens") or []:
            err = send(session, project, fcm_message(token, row))
            if err is None:
                sent += 1
                continue
            status, code, message = err
            if is_dead_token(status, code, message):
                forget_token(token)
                removed += 1
            else:
                failed += 1
                print(f"  send failed ({status}/{code}: {message})", file=sys.stderr)
    if rows:
        print(f"{len(rows)} notification(s): sent {sent}, removed {removed} dead device(s), {failed} failed")
    return len(rows)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true", help="one pass, then exit")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--seconds", type=int, default=int(os.environ.get("PUSH_LOOP_SECONDS", "150")),
                    help="keep checking for this long")
    args = ap.parse_args()

    if not SUPABASE_URL or not SERVICE_KEY:
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required", file=sys.stderr)
        return 1
    if not SERVICE_ACCOUNT and not args.dry_run:
        print("FIREBASE_SERVICE_ACCOUNT is required to send", file=sys.stderr)
        return 1

    if not args.dry_run:
        made = rpc("make_event_reminders", {})
        if made:
            print(f"{made} reminder(s) created")

    session, project = (None, None) if args.dry_run else fcm_session()
    deadline = time.monotonic() + (0 if args.once else args.seconds)
    while True:
        took = one_pass(session, project, args.dry_run)
        if time.monotonic() >= deadline:
            break
        if not took:
            time.sleep(15)
    return 0


if __name__ == "__main__":
    sys.exit(main())
