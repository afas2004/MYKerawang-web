# The security review, in plain words

For reading when your brain is fresh — or for explaining it to the club.

## What happened

Your app is a building with a public front door. The key inside the app is a
visitor badge: it is supposed to be copyable. Security does not come from hiding
the badge; it comes from the guard at each room asking for it.

Two rooms had problems.

**The photo cupboard had no guard.** Anyone on the internet could list what was
inside, take things out, and replace them. Not "someone who hacked in" — just
anyone who knew the address. That is now fixed.

**A few rooms let visitors read names they should not.** Profiles, who follows
whom, and who attended what. Still open, and it is a decision, not a bug —
guests are supposed to see the *public* version of a profile, not the private
one.

Nothing was deleted, changed or lost. The database was never at risk of being
destroyed; only the photos could have been, and now cannot.

## The words, briefly

| Word | What it means here |
|---|---|
| publishable key | the visitor badge. Public on purpose. |
| `anon` | a visitor who has not signed in. |
| RLS / policy | the guard at the room, and the list of who may enter. |
| bucket | the photo cupboard. |
| migration | a saved to-do note that changes the database once. |
| CSP | a rule telling the browser which scripts are allowed to run. |

## What was done

1. A guard was posted on the photo cupboard: you must be signed in, and you can
   only remove your own photos.
2. Some limits that only the app was enforcing are now enforced by the database
   too (form text lengths, who may be verified as a student, who may turn on
   "not hidden" on a moderated event).
3. Three internal switches that anyone could flip are now locked.

## What is left, and it can wait

1. Stop visitors reading the private side of profiles, follow lists and
   attendance. Guests would not notice a change.
2. Deploy the app build that contains the upload and CSV fixes.
3. Housekeeping: the `www` certificate, changing one old password, and the CSP.

None of it is urgent. Ask me when you want any of it, one item at a time.
