# Access, registration and student verification

Status: **design draft v3** — rollout steps 1 and 2 are built.
Shipped: backup email + reminders, second-account warning, impersonation
reports, and the verification record + owner switch (default **off**) +
the `VERIFY:required` gate on joining/creating events and selling.
Not built: the verify sheet, code-by-email, club-path gates.


v3 changes from v2:
- student verification is **one owner-only switch**, not a preset dial
- the star badge stays **official-only** (admin / MPP / owner / clubs);
  verified students get no public badge
- student-email logins get a **backup-email reminder**
- duplicate-account detection is designed (§7)
- legacy "club" accounts confirmed as `no-op` (§11)
- domain purchase deferred; nothing but code verification depends on it

---

## 0. Plain-language glossary

| Plain term | Meaning |
|---|---|
| **Account** | the thing you log into |
| **Login email** | the address typed at the login screen. Changeable. Not an identity. |
| **Backup email** | a second address on the same account, used so the account survives the student mailbox dying |
| **Student verification** | a permanent record: "this account proved it belonged to a UiTM student, on this date" |
| **Member** | anyone with an account who has not verified |
| **Verified student** | member with a verified record |
| **Staff** | admin and owner. Never required to verify. |
| **Official badge** | the existing blue star + tick. Admin, MPP, owner/dev, and clubs. |

Rule of thumb: **the login email is a door key, not an ID card.**
Verification is the ID card, and it stays valid after the door key stops
working.

---

## 1. The five things that decide access

1. **Account** — guest / registered / confirmed / banned.
2. **Student verification** — none / pending / verified / rejected / revoked.
   Never expires.
3. **Platform role** — member / club (legacy) / admin / owner.
4. **Club role** — president / officer / member, per club.
5. **Moderation** — banned, or restricted for one area until a date.

Permission is granted only when all five allow it. Today one field does
all of it; that is why every new rule becomes a special case.

Collisions to fix: the existing "verified" badge means **official**, not
student; and anything without a role currently displays as "Student"
(`lib/utils/roles.dart`) — it becomes "Member" unless verified.

---

## 2. Registration

Anyone can create an account with any email.

| How they signed up | Immediately after | Student status |
|---|---|---|
| Student email + password | confirm link | verified automatically on confirmation |
| Student email via Google | nothing | verified automatically |
| Personal email, either method | — | none |

Rules:

1. The student-domain restriction on signup is removed. It survives as a
   switch in case of a spam wave.
2. Automatic verification needs a confirmed email. If confirmation is
   ever disabled in Supabase, the automatic path must be off — an
   unconfirmed address proves nothing.
3. Open registration gets a captcha.
4. Staff are never required to verify. The owner account keeps using its
   personal address.
5. The "verify your student status" prompt after signup is shown **only
   when the feature is switched on** (§3).

---

## 3. Student verification is one switch, owned by the owner

Decision: this whole feature is not ready to be a policy system. It is a
single switch, and only the owner can flip it.

```
student_verification_enabled = false   (default)
```

| Switch is OFF | Switch is ON |
|---|---|
| No prompt, no gate, no badge, no admin queue | Student-only actions require verification (table in §8) |
| Everything behaves like today, plus open registration | Owner decides how strict, per capability, later |

Why a switch and not a policy dial: the college has not been talked to
yet. If they say "no verification, ever", the switch stays off and
nothing in the UI remembers it existed. If they ask for it, the switch
goes on. Building the dial first would be designing for a conversation
that has not happened.

The switch is **owner-only**; admin accounts cannot see or flip it. Every
flip writes one audit row with a reason.

### 3.1 When it is ON

| Method | What happens | Who works |
|---|---|---|
| automatic | student email confirmed at signup | nobody |
| code by email | 6-digit code to the student inbox | the user |
| manual | admin approves a submission | exceptions only |

Code-by-email is the primary route (it is the only one that scales);
manual approval exists for expired mailboxes and disputes. It needs a
sending domain — deferred, see §12.

### 3.2 What verification is not

It does not prove a name. A code in an inbox proves the inbox. So the
record is just: account, address, date, how. Impersonation is handled by
reporting (§10).

### 3.3 History

- One student address → one account, ever.
- A pending claim expires after 24 hours so a typo cannot block the owner.
- Revoking keeps the row (address hashed) so it cannot be laundered by
  deleting and re-registering.
- Account deletion keeps a hashed marker for the same reason; state the
  retention period in the privacy policy (PDPA 2010).

---

## 4. Two kinds of badge, and they never share a look

| Badge | Who | Where |
|---|---|---|
| **Official** — blue star + tick | admin, MPP, owner/dev, clubs | everywhere, existing behaviour |
| **Student** — no star | verified students | **nowhere public**; a small "Verified student · since <date>" row on their own profile and in Settings only |

The star keeps meaning "this is an official voice", which is the only
thing it can reliably mean. If students could wear it, it would stop
being a signal — and the entire point of the star is that a post from
MPP looks different from a post by a random account.

MPP and dev are not new roles: they are ordinary accounts that the owner
marks as official (`profiles.is_verified`, already owner-controlled by
`guard_profile_privileges`). Whether MPP should also get moderation
powers is an open question (§13).

---

## 5. Login email lifecycle — the graduation time bomb

The student mailbox stops working about a year after graduation. If that
is the only key to the account, the account is lost — posts, club
presidency, event history. That is every user, every year.

### 5.1 Backup email (the cheap fix, ships independently)

Any account may add a **backup email**. It is confirmed by a link sent to
that address, stored on the profile, and used to prove ownership when the
login address dies.

- Visible on **Settings** and on the user's **own profile page**.
- The reminder appears only when: the login email is a student address
  **and** there is no confirmed backup email.
- Copy: "You sign in with your student email. UiTM closes it about a year
  after you graduate, and you would lose this account. Add a backup
  email."

This is not verification and does not depend on the switch. It is
available from day one.

### 5.2 Changing the login email

Settings action. Supabase sends a confirmation to the new address (and
the old one, if secure email change is on). Same account, new key — no
new account, no second login.

### 5.3 Recovery when it is already too late

An owner-only operation: set a new login address for an account, with an
audit row. This will happen; better to have one button than an
improvised favour.

Verification is **never** re-checked against the mailbox later, because
that mailbox will be gone.

---

## 6. Nothing about verification blocks reading

Guests keep browsing exactly as today. Verification only ever gates
writes, and only when the switch is on.

---

## 7. Two accounts on one person

People will end up with two accounts: student Google once, personal
Gmail later. It is the single most likely support problem after launch.

### 7.1 Detecting it

Four signals, in order of reliability:

1. **Same student email** — they try to verify with an address that
   already belongs to another account. Server-side, certain.
2. **Same device** — the browser remembers the accounts it has signed
   into (local storage; the `profiles.device_id` column exists but is
   currently never written).
3. **Same phone** — the contact already used by another profile.
4. **Same name + avatar** — weak, only used to prioritise a warning.

### 7.2 What they see

- On login: "This device has another account — @someone (Google).
  Continue as @someone instead?" One tap to switch; signing in a second
  time is the friction we are removing.
- On verification: "That student email is already connected to @someone.
  Sign in with that account."
- Both are informational. Nothing is deleted or merged automatically.

### 7.3 Merging

Not automatic. Two accounts hold separate posts, memberships and saved
items; merging is a reassignment of ownership rows, not a login trick.
v1 detects and warns; an owner-only merge tool can come later, and only
if the warnings prove insufficient.

---

## 8. Who can do what

Only relevant when the switch in §3 is on. With it off, every row reads
"signed in".

| Action | Switch ON (default) |
|---|---|
| Browse, search, view profiles | everyone incl. guests |
| Follow a user or club | signed in |
| Post / comment / anonymous post | signed in |
| Sell in the marketplace | verified |
| Create an event | verified |
| RSVP to an event | verified |
| Request to join a club | verified |
| Hold a roster seat | verified |
| Be appointed officer | president appoints, verified |
| Post as a club / club announcement | club officer |
| Create a club | verified + admin approval |
| Admin console | admin + PIN |
| Flip the switch | owner |

- Staff bypass verification everywhere.
- A ban, or an area-specific restriction, always overrides the table.
- Verification is never required to read.

---

## 9. Making the switch robust

"Robust" here means: what happens when the human side goes wrong. One
switch that can lock out hundreds of people is worse than no switch.

| What goes wrong | Naive boolean | What we build |
|---|---|---|
| Flip it mid-semester | 400 people cut off instantly | Grace window (default 14 days), and the console shows "24 accounts would lose RSVP" before confirming |
| Flip it by accident | Needs a migration to undo | One RPC, instant, no deploy — plus an audit row so you can see what changed and when |
| Settings row unreadable at 3am | Whole app errors | Reads never consult it; writes that need it fail **closed**. Browsing never breaks |
| Two people flip it | Last write wins, silently | Owner-only, and every flip is one audit row with before/after and a required reason |
| Stale client shows the wrong button | User taps, gets a raw error | Server returns a reason code (`VERIFY:required:event_join`); a sheet explains, never a red toast |
| Someone adds a new write path and forgets the check | Silent hole | One guard already runs before every write (bans + rate limits); verification is its third question. A matrix test asserts every action × every state |
| "Why can't I RSVP?" | Guesswork | The refusal reason is logged, and the user sees which rule blocked them and what would unblock it |
| Policy changes while people are mid-session | Half the app suddenly changes | New rules apply to the next action, with the grace window covering accounts that were already allowed |

---

## 10. Identity theft goes to reports

Verification proves an inbox, not a person. So impersonation is handled
where impersonation is already handled.

Add one report category: **"Pretending to be someone else"**. It is
queued first but, unlike the two urgent categories, it is not hidden on
the first report — an unproven accusation must not be able to take down
someone's post.

Queue policy (owner-editable in Settings):

| Category | First report | Reviewed |
|---|---|---|
| Harassment, sexual or inappropriate content | **hidden** | immediately |
| Impersonation | visible | first |
| Scam, minor safety, spam, misinformation, other | visible | after 3 distinct reporters |

The sheet states this in one line above the category list ("Reviewed
first: …"), read from the live setting so the copy cannot drift.


---

## 11. Legacy club accounts — confirmed no-op

Before clubs were pages, "club" was an account type: one login that
posted as the club. That is what the old account still carries.

Checked: `is_admin()` accepts only `admin` / `owner`; no SQL grants
anything to `club`. Its only visible effect is cosmetic — the profile
shows the "Club" label and the official badge, and it appears in the
official-posters query. Since the club now exists as a page with its own
president, leaving it changed nothing and breaks nothing.

---

## 12. Domain — deferred, and only the code flow needs it

Everything above ships without a domain except code-by-email
verification. Buy it after the hard part, as planned.

Price reality: the advertised first year ($2.99) is a teaser; the renewal
($35.99/yr ≈ RM 160) is the real cost. Budget for the renewal, not the
promo.

Nothing about the app's address changes: email needs DNS records
(SPF/DKIM) on the domain, not a move of the site.

---

## 13. Open questions

1. **MPP** — official badge only, or actual moderation powers (admin)?
   Recommendation: badge only, until there is a reason otherwise.
2. **Recovery** — owner-only login-address changes (recommended) or any
   admin?
3. **Grace window** — 14 days, or "apply immediately" as the default for
   this one switch?

---

## 14. Rollout

| Step | Ships | Depends on |
|---|---|---|
| 1 | Backup email + reminder, duplicate-account warning, "pretending to be someone else" report category | nothing |
| 2 | Verification record + owner switch (default **off**) + guard, no UI | nothing |
| 3 | Verify sheet, Settings row, admin approval fallback | step 2 |
| 4 | Code-by-email verification | sending domain |
| 5 | Owner flip to ON, with grace window | the college conversation |
