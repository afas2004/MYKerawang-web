"""python -m unittest worker/test_push.py  (no network, no keys needed)"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import push  # noqa: E402

POST = "11111111-1111-1111-1111-111111111111"
EVENT = "22222222-2222-2222-2222-222222222222"
FORM = "33333333-3333-3333-3333-333333333333"


class Render(unittest.TestCase):
    def test_grouped_comment_in_malay(self):
        t, b = push.render({"type": "comment", "count": 3, "actor_name": "Aina", "language": "ms",
                            "data": {"post_id": POST, "snippet": "Saya ikut!"}})
        self.assertEqual(t, "Aina dan 2 lagi mengulas siaran anda")
        self.assertEqual(b, "Saya ikut!")

    def test_anonymous_single_comment(self):
        t, _ = push.render({"type": "comment", "count": 1, "language": "en", "data": {"post_id": POST}})
        self.assertEqual(t, "Someone commented on your post")

    def test_event_comment(self):
        t, _ = push.render({"type": "comment", "actor_name": "Ravi", "language": "en",
                            "data": {"event_id": EVENT}})
        self.assertEqual(t, "Ravi commented on your event")

    def test_form_answers_japanese(self):
        t, b = push.render({"type": "form_answer", "count": 5, "language": "ja",
                            "data": {"form_id": FORM, "form_title": "Borang"}})
        self.assertEqual(t, "フォームに5件の新しい回答があります")
        self.assertEqual(b, "Borang")

    def test_event_changed_time(self):
        _, b = push.render({"type": "event_changed", "language": "en",
                            "data": {"event_title": "Ceramah", "start": "2030-01-01T07:00:00+00:00",
                                     "old_start": "2030-01-01T06:30:00+00:00",
                                     "location": "Dewan", "old_location": "Dewan"}})
        self.assertEqual(b, "Ceramah · Now 1 Jan 3:00 pm")

    def test_unknown_kind_keeps_stored_text(self):
        self.assertEqual(push.render({"type": "moderation", "title": "Post hidden", "body": "x"}),
                         ("Post hidden", "x"))

    def test_unknown_language_falls_back(self):
        t, _ = push.render({"type": "follow", "actor_name": "Mei", "language": "fr", "data": {}})
        self.assertEqual(t, "Mei followed you")


class Links(unittest.TestCase):
    def test_comment_opens_exact_comment(self):
        self.assertEqual(push.link_for({"type": "comment", "data": {"post_id": POST, "comment_id": "c1"}}),
                         f"https://kerawang.my/post/{POST}?c=c1")

    def test_event_form_answers(self):
        self.assertEqual(push.link_for({"type": "form_answer", "data": {"form_id": FORM, "event_id": EVENT}}),
                         f"https://kerawang.my/event/{EVENT}/form/responses?f={FORM}")

    def test_standalone_form_answers(self):
        self.assertEqual(push.link_for({"type": "form_answer", "data": {"form_id": FORM, "event_id": None}}),
                         f"https://kerawang.my/f/{FORM}/responses")

    def test_follow_opens_profile(self):
        self.assertEqual(push.link_for({"type": "follow", "actor_id": "u1", "data": {}}),
                         "https://kerawang.my/u/u1")

    def test_moderation_route(self):
        self.assertEqual(push.link_for({"type": "moderation", "data": {"route": "/standing"}}),
                         "https://kerawang.my/standing")


class Tokens(unittest.TestCase):
    def test_dead(self):
        self.assertTrue(push.is_dead_token("NOT_FOUND", None, ""))
        self.assertTrue(push.is_dead_token("INVALID_ARGUMENT", None, "The registration token is not valid"))
        self.assertFalse(push.is_dead_token("INVALID_ARGUMENT", None, "Invalid JSON payload"))
        self.assertFalse(push.is_dead_token("UNAVAILABLE", None, ""))

    def test_message_groups_by_tag(self):
        m = push.fcm_message("tok", {"id": "n1", "group_key": "form:x", "type": "form_answer",
                                     "count": 2, "data": {"form_id": FORM}})
        self.assertEqual(m["message"]["webpush"]["notification"]["tag"], "form:x")


if __name__ == "__main__":
    unittest.main()
