# TGCG-EMCOP

**The Game Changer Group — Election Monitoring & Collation Programme**

TGCG-EMCOP is a Flutter-based election operations platform for membership and agent accreditation, field monitoring, incident/evidence reporting, polling-unit result capture, hierarchical collation, GIS operations, communications and situation-room workflows.

## Foundation

This repository is being bootstrapped from the reusable architectural ideas in `Bkzazzau1/benuestatepdp` while deliberately removing Benue-, PDP- and candidate-specific assumptions.

Source baseline reviewed for the migration:

- Repository: `Bkzazzau1/benuestatepdp`
- Source commit: `763edba33d378804cc5555730a1d45b7f3b73a17`

The new TGCG codebase uses a national model rather than a Benue-only model.

## Core hierarchy

```text
Nigeria
  -> Geopolitical Zone
    -> State
      -> Senatorial District
        -> LGA
          -> Ward / Registration Area
            -> Polling Unit
```

## Product principles

- Offline-first field operations.
- Server-side authorization; UI visibility is never treated as authorization.
- Every operational record has stable identity, provenance and auditability.
- Election-day campaign/observer submissions remain unofficial until declared by the legally authorized election authority.
- Result evidence is preserved separately from extracted or manually entered figures.
- AI/OCR assists verification; it must not silently alter submitted figures.
- Geographic scope is explicit on users, assignments, incidents, reports and results.
- App, SMS, USSD and manual submissions are source-tagged and reconciled.

## Initial modules

1. Authentication and accreditation
2. Membership and field-agent management
3. National geography and polling-unit catalogue
4. Monitoring and incident management
5. Evidence capture
6. Result submission and verification
7. Hierarchical collation
8. Situation Room
9. Communications
10. GIS and geofencing
11. SMS/USSD fallback
12. Audit, reporting and governance

## Architecture direction

```text
Flutter clients
  -> repository contracts
    -> encrypted local storage + durable sync outbox
      -> backend APIs
        -> PostgreSQL/PostGIS
        -> Redis / queues
        -> object storage
        -> OCR / biometric services
        -> SMS / USSD gateways
```

The Flutter domain layer is kept backend-agnostic so development can begin with local implementations while preserving a clean path to production APIs and offline synchronization.

## Connecting to the backend

The app talks to the Django API in
[tgcg_backend](https://github.com/Bkzazzau1/tgcg_backend). Every build uses the
live server, `https://api.tgcg.online`, so Run in VS Code, `flutter run` and
`flutter build apk` all connect to it. To use another server, such as a
development backend, set its address with `TGCG_API_URL`:

```bash
# Windows desktop or web, with the backend on this machine
flutter run --dart-define=TGCG_API_URL=http://127.0.0.1:8000

# Android emulator (10.0.2.2 is the host machine)
flutter run --dart-define=TGCG_API_URL=http://10.0.2.2:8000

# A phone on the same Wi-Fi: use the computer's LAN address and start Django
# with `runserver 0.0.0.0:8000`
flutter run --dart-define=TGCG_API_URL=http://192.168.1.20:8000
```

The app opens on the TGCG poster
(`assets/brand/login_poster.webp`), the logo and a welcome note. On a phone,
**Sign in** opens the form; on a wide screen the form stands beside the poster.
Sign in with an access ID or phone number and a password, or a PIN for members.
The server decides the role and area. Tokens are kept in secure storage, the
session is restored on the next launch, and an expired session signs the user
out.

There is no presentation or demo mode. Release APKs are built with:

```bash
flutter build apk --release --dart-define=TGCG_API_URL=https://api.tgcg.online
```

[Download the connected Android APK](https://app.tgcg.online/downloads/tgcg-emcop-0.1.0-2.apk)
(`0.1.0`, version code `2`, Android 7 or newer). Install it as an update to the
existing app. APK updates must use an increasing `--build-number`; the last
distributed version code is recorded in `docs/vps-deployment.md`. Keep the
build number in `pubspec.yaml` (`version: 0.1.0+N`) at least that high: Run in
VS Code and `flutter run` build with it, and a lower number than the installed
app makes Flutter uninstall the app first, which signs the phone out and
deletes records it has not sent yet.

The web build is in `docs/vps-deployment.md`.

The connection code lives in `lib/tgcg/api/`:

- `api_client.dart` handles HTTP, token refresh and error messages.
- `auth_repository.dart` handles login, session restore and logout.
- `backend.dart` makes the connection available to the app.
- `field_repository.dart` reads incidents and field reports, and changes them.
- `results_repository.dart` reads results, elections and collation, and records
  review decisions.
- `meetings_repository.dart` lists, calls, ends and cancels meetings, and gets
  the pass to join a meeting's call.
- `overview_repository.dart` reads the Overview's counts: members, results,
  verified results and today's agent check-ins.
- `wallet_repository.dart` reads a member's own wallet and sets its payout
  account, and lists, requests and decides payments for finance staff.
- `projects_repository.dart` schedules projects, assigns people to them,
  watches where they are, and answers invitations.
- `messaging_repository.dart` previews and sends messages, lists sent ones
  with their delivery, keeps saved lists, reads the inbox and registers the
  phone for app notifications.
- `security_repository.dart` lists the security officers nearest an incident,
  sends it to one or takes it back, and carries the officer's answers.
- `member_admin_repository.dart` finds members, reviews identities and
  standing, and (with `member_insights.dart`) reads members and exco area by
  area.

Signed in to a server, these screens work on server records: the Overview,
Members & Exco, Projects, Messages, Role Management, Member Review, Wallets, Unit Mapping,
Agents on the Ground, the Situation Room, Security Response, Field
Monitoring, Result Capture, Collation, the Forum and the Meeting Room. A member's wallet opens from their
card (the member app) or the agent's home.

Anyone signed in registers members with **Register members** in the top bar
of every app (`lib/tgcg/member/registered_members_page.dart`).

- **What's needed:** a name, a phone number, and the person's agreement; the
  place is optional. There is no limit.
- **Signing in:** the new member signs in with their phone number (11
  digits, 08031234567) as the password.
- **Their list:** each person sees the members they registered.
- **Completing it:** until a member's identity is checked, the person who
  registered them completes the registration (`RegisteredMemberPage`):
  - the name and place, until the PVC is on record;
  - the phone number, until the member first signs in;
  - the member's details, a photo and the PVC scan, which use the same rows
    and dialogs as the member's own card (`MemberProfile` in
    `member_repository.dart`).

Projects (`lib/tgcg/projects/`) are scheduled periods of field work, such as
an election. Everyone with a role sees a strip at the top of the app while
one runs in their areas. Someone taking part accepts an invitation once;
while the project runs their app shares their location without a switch
and waits for GPS to be on, and the operations app opens on the project.
Outside a project nobody shares location.

Messages (`lib/tgcg/messaging/`) go out by SMS, WhatsApp and app
notification. The National Administrator gives the powers to send them
(send SMS, send WhatsApp, send app notifications) through roles, and a
sender reaches only people in their own areas: the server works out who each
message reaches, and offers only the channels whose service it has set up.
One message can go to several groups at once: people in
chosen areas, narrowed by role, gender or a checked identity; a project's
team; or a saved list. **Who it reaches** counts the people before sending,
and **Sent** shows how far each message got on each channel. Everyone signed
in has an inbox (the envelope in the top bar) with the messages sent to them,
and a member whose WhatsApp is on another number adds it on their card.

App notifications use Firebase Cloud Messaging and reach Android phones
built with the Firebase project's Android app values:

```bash
flutter build apk --release --build-number=N \
  --dart-define=TGCG_API_URL=https://api.tgcg.online \
  --dart-define=TGCG_FIREBASE_API_KEY=... \
  --dart-define=TGCG_FIREBASE_APP_ID=... \
  --dart-define=TGCG_FIREBASE_SENDER_ID=... \
  --dart-define=TGCG_FIREBASE_PROJECT_ID=...
```

Without them the app builds and runs without notifications, and messages
still reach the inbox. The first Windows desktop build downloads the Firebase
C++ SDK that `firebase_core` needs there.

Members & Exco (`lib/tgcg/membership/members_exco_page.dart`) is the
National Administrator's view of the membership, from Nigeria (by state or
by zone) down to a state, its LGAs, wards and polling units. For each area it shows who the
members are (new members week by week, age, gender, how they joined, identity
and what their profiles hold), its exco (people and posts by level and
position, and how many are fully verified or have signed in), and each
smaller area with its members and exco. Exco are everyone holding an
appointment, and each level has its own: its tabs list the area's own exco,
the exco of each level below it (LGA, ward, polling unit...) or everyone, and
its members, including those not fully verified,
never signed in, with or without a post. The dashboard shows the members and
exco of each account's own area.

Security officers (`lib/tgcg/security/`) are members whose role holds the
power to respond to security escalations, which the National Administrator
gives through roles; they sign in on the same page as everyone else. In the
Situation Room, an incident's **Send to security** lists the officers
nearest to it, by where they are while they share their location for a
project or else by the area of their role, and sends it to the one picked;
the officer is told by app notification and SMS. Their **Security Response**
page shows the incident, directions to it and the reporter's phone, and they
accept or decline, then mark on the way, arrived and resolved. The Situation
Room sees each step on the incident, and can take it back.
Incident actions (acknowledge, assign, escalate, resolve, close, reopen),
field report reviews and result decisions (verify, dispute, reject) go to the
server, which checks each one. Collation shows the server's unofficial totals
of verified results for each election, area by area. Meeting calls run on
LiveKit; the server decides who may join and hands out the join pass (see the
server's docs/meetings.md). New incidents, reports and results are saved on
the device first and upload when there is a connection; photos taken with
them (incident photos, the signed result sheet) upload after their record,
and reviewers open them from the record.

A polling-unit agent's phone opens on their own account: their polling unit,
today's check-in and their duty, with tabs to report an incident, submit the
result and join meetings.

Only these screens are offered (`liveModules` in `lib/tgcg/session.dart`).
The others, such as the old communications screens, reports and member
enrolment, ran on sample records, so they stay hidden until each one works on
the server. The
role grid (`allowedModulesFor`) still says who will get them.
