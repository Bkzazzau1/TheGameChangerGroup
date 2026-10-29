# TGCG VPS deployment

Initial setup on 12 October 2026; latest code release deployed on 26 October 2026 (Africa/Lagos).

## Public URLs

| Service | URL |
| --- | --- |
| Flutter web app | https://app.tgcg.online |
| Django administration | https://admin.tgcg.online |
| API health | https://api.tgcg.online/api/v1/health/ |

`tgcg.online` and `www.tgcg.online` redirect to the web app. HTTP redirects to HTTPS. All five names are covered by the Let's Encrypt certificate; automatic renewal and its Nginx reload hook passed a simulated renewal.

## Current state

- **Maintenance mode is ON** again since 29 October 2026, 21:01 Africa/Lagos, at the owner's request. The page now has a countdown to the presidential election. It first ran the same day from 09:38 to 16:56. See Operations.
- VPS: `159.198.75.103`, AlmaLinux 9.8.
- Source: `Bkzazzau1/tgcg_backend`, deployed commit `82a304be9f293023f6f45fa327d2bf21e239dd5e`.
- Application: `/opt/tgcg/backend`, running as the `tgcg` system account.
- Python 3.12.15, Django 5.2.18, Gunicorn 26.2.0, PostgreSQL 16.
- Tesseract 4.1.1 with English language data; `TESSERACT_CMD=/usr/bin/tesseract`.
- PVC reader: Google Cloud Vision first; installed Tesseract handles Google errors, timeouts, malformed replies and blank text.
- Service: `tgcg-api.service`, enabled at boot, listening on `127.0.0.1:8000`.
- Database: `tgcg`, accessed through `/var/run/postgresql` with local peer authentication.
- Production environment: `/opt/tgcg/backend/.env`, mode 600. The generated secret remains on the VPS.
- Nginx configuration: `/etc/nginx/nginx.conf`, `/etc/nginx/conf.d/tgcg.conf` and `/etc/nginx/tgcg-*.inc`.
- TLS certificate: `/etc/letsencrypt/live/tgcg.online/`; renewal uses `certbot-renew.timer`.
- Geography: 8,809 wards, 176,846 polling units; 160,873 polling units with INEC locations across all 36 states and the FCT.
- Administrator: access ID and display name `TGCG`, national administrator with country scope.

Nginx publishes the API and administration over HTTPS while Gunicorn remains on loopback. Flutter uses `https://api.tgcg.online`; browser access is limited to the app origin. Termii SMS credentials and the Paystack secret key remain to be configured. Phone-code registration remains disabled; registration credits use the default `signIn` policy.

## Web release and demo labels

- Published release: `/var/www/tgcg/releases/web-20261026-135340-9b5f6c72d92e` (release directory timestamps use UTC).
- Frontend build source: `d27eef9` from `Bkzazzau1/TheGameChangerGroup`, built on the owner's PC from a clean checkout. Android version 5 is from the earlier `cb5c7ac`: it still says "credits" and has neither the upload back-off nor the slower refreshes. The owner chose no new APK for now.
- Previous web release retained: `/var/www/tgcg/releases/web-20261026-125219-48b90459a43a` (TGC tokens); earlier releases are also retained.
- Active release link: `/var/www/tgcg/app-current`.
- Main JavaScript SHA256: `9b5f6c72d92ed9e5249382fd847b4d62fd3dfd8688c02b45ef193fe992166a6b`.
- Build: 856 files, 59,315,630 uncompressed bytes. The public JavaScript checksum matched after publication.
- Release metadata: `/opt/tgcg/deployment/web-release.json`; earlier records are kept as `web-release-20261026-tgc-tokens.json`, `web-release-20261026-video-pictures.json`, `web-release-20261026-askme-referrals.json`, `web-release-20261024-registrars.json` and `web-release-20261024-social-forum.json`.

Production builds require `TGCG_API_URL=https://api.tgcg.online`. The app opens on the TGCG poster, logo and welcome note, with the sign-in form beside the poster on wide screens and opened by Sign in on phones. Menus offer server-backed screens, and dashboard/agent-home totals come from existing API counts and tracking coverage. The app now defaults to the production API, and production builds also set its address explicitly. Demo and presentation sign-in routes were removed.

The browser version keeps its offline queue in memory, so pending work does not survive a reload. Incident and result photos use authenticated multipart evidence uploads and can be opened for review. Browser PVC photos go through `POST /api/v1/register/read-pvc/`: the VPS sends the first reading request to Google Cloud Vision and uses Tesseract locally if Google fails or returns no text. Mobile OCR runs on the device. The browser registration form and polling-unit change dialog use the returned text. Cardholders must check every extracted field, especially VIN and polling-unit digits. Audio-file recording remains unavailable on web; unsupported screens are hidden. The desktop welcome/poster/sign-in screen was verified in the browser for an earlier release.

The release was built with:

```powershell
flutter build web --release --dart-define=TGCG_API_URL=https://api.tgcg.online --base-href=/ --pwa-strategy=none
```

Every production APK build must also include `--dart-define=TGCG_API_URL=https://api.tgcg.online`, as documented in README. The Android installer below was built separately from the web release.

Web entrypoints and JavaScript use `no-store`; missing assets return 404 rather than HTML. Nginx serves renderer `.wasm` files as `application/wasm`.

Both readers are enabled at the user's request. `GOOGLE_VISION_API_KEY` is stored only in the private VPS environment, never in Flutter source or compiled artifacts. Google receives browser PVC photos for the first attempt, including requests that later fall back to Tesseract. One reader's text is returned; conflicting readings are never combined. A non-empty reading is not proof that all fields were recognized. The added browser Google Vision notice remains removed as requested.

Each reader has a 25-second timeout; sequential attempts may take about 50 seconds plus processing and transfer. Only the app's card-reading multipart request has a 90-second deadline, covering both sending and the response body. Ordinary uploads retain the 30-second default.

Both repositories are committed and pushed to their GitHub `main` branches. The VPS source checkouts are `/opt/tgcg/backend` and `/opt/tgcg/frontend`; their commits match the local repositories and GitHub. Backend source no longer relies on an applied working-tree patch. `/opt/tgcg/deployment/web-release.json` records the exact frontend and backend commits and the served web bundle checksum. Private runtime configuration, media and database contents remain managed on the VPS.

## Administrator password

In the existing VPS root terminal, retrieve the generated initial credentials:

```bash
cat /root/tgcg-admin-initial.txt
```

The credentials file is root-owned with mode 600. No password or signing secret is included in these notes.

## Operations

### Maintenance mode

The switch is the file `/etc/nginx/tgcg-maintenance.on`. Nginx checks for it on every request, so turning it on or off needs no reload or restart.

**What it does when on:**
- **Web app:** every page of app.tgcg.online, including referral links and APK downloads, shows the maintenance page with HTTP 503. The page is `/var/www/tgcg/maintenance/maintenance.html`, with its logo beside it.
- **Countdown:** since 29 October 2026 the page counts down, in days, hours, minutes and seconds, to the start of the presidential election day: Saturday 16 January 2027, 00:00 WAT. That is the date in INEC's revised timetable under the Electoral Act 2026; the earlier date was 20 February 2027. On the day it reads "Today is the presidential election", and after it, "The presidential election was held on 16 January 2027".
  - The clock runs in the visitor's browser; the date is in the page's script (`Date.UTC(2027, 0, 15, 23, 0, 0)`).
  - **If INEC moves the election, change that date.**
  - Copies are in `/opt/tgcg/deployment/maintenance-20261029/`: `maintenance-countdown.html` (current) and `maintenance-plain.html` (without the countdown).
- **API:** every api.tgcg.online request gets HTTP 503 with `{"detail": "Maintenance is ongoing. Please come back later."}` and `Retry-After: 3600`. It carries the CORS headers for the web app, and CORS preflights still reach Django, so an open browser tab can show the message. The apps show the `detail`.
- **Phones:** they keep unsent records queued and send them after maintenance.

**What it leaves alone:** the admin site (admin.tgcg.online), the API service itself, timers, backups and certificate renewal on port 80.

**How it is wired:** the rules are `/etc/nginx/tgcg-maintenance-app.inc` and `/etc/nginx/tgcg-maintenance-api.inc`, included in the app and API server blocks of `conf.d/tgcg.conf`. The configuration before them is kept in `/opt/tgcg/deployment/maintenance-20261029/`. With the switch off, the app, API health, the temporary SMS notices, admin and downloads behaved exactly as before.

```bash
rm /etc/nginx/tgcg-maintenance.on      # end maintenance: everything is live again
touch /etc/nginx/tgcg-maintenance.on   # start maintenance
```

### Service

```bash
systemctl status tgcg-api.service --no-pager
journalctl -u tgcg-api.service -n 50 --no-pager
systemctl restart tgcg-api.service
curl -fsS -H 'X-Forwarded-Proto: https' http://127.0.0.1:8000/api/v1/health/
```

Expected health response: `{"status":"ok","database":"ok"}`. Plain HTTP without the trusted proxy header redirects to HTTPS.

After selecting and checking out a backend release, run the deployment helper as root:

```bash
/usr/local/sbin/tgcg-deploy
```

The helper stops the API, synchronizes the application's locked dependencies, reinstalls the pinned Gunicorn dependency from `/opt/tgcg/deployment/requirements-runtime.txt`, checks production settings, applies migrations, imports geography, collects static files and starts the service. It does not choose or fetch a Git release. It also attempts to start the service if a deployment command fails.

It also publishes Django static files to `/var/www/tgcg/static`, checks Nginx configuration and reloads Nginx. This helper updates the backend; a Flutter web release requires a separate build, upload and active-release link change.

Private uploads remain under `/opt/tgcg/backend/media`; they require the application's authenticated download endpoints. Nginx blocks public `/media/` and hidden configuration paths. Collected static files are copied from `/opt/tgcg/backend/staticfiles` to `/var/www/tgcg/static` for the HTTPS reverse proxy.

## Scheduled work and backups

- `tgcg-maintenance.timer`: removes expired location history and USSD progress daily at 03:00 Africa/Lagos.
- `tgcg-recordings.service` and `tgcg-recordings.timer`: enabled for recording maintenance every minute, including ending streams older than 120 minutes. The initial run succeeded; provider error output is discarded to keep credentials out of logs.
- `tgcg-messages.service` and `tgcg-messages.timer`: enabled and active for message delivery every minute, using `deliver_messages --seconds 55 --batch 10`. The initial run succeeded with `Handled 0 message(s).`; only aggregate counts reach stdout and stderr is discarded.
- `tgcg-withdrawals.service` and `tgcg-withdrawals.timer`: installed and verified, with the timer enabled and active, waiting to check withdrawal outcomes every 15 minutes as `tgcg` with production settings. Its first run succeeded with `Paystack is not set up: nothing to check.`; stderr is discarded.
- `tgcg-backup.timer`: backs up PostgreSQL, private media, `.env`, Nginx configuration, TLS configuration and deployment metadata daily at 03:15 Africa/Lagos.
- Backup directories: `/var/backups/tgcg/<UTC timestamp>-<unique suffix>`, accessible to root.
- Database archives are checked with `pg_restore --list`; a full restore has not been exercised.
- **Since 26 October 2026 (owner's decision; Claude Code):**
  - **Layout.** `/usr/local/sbin/tgcg-backup` writes:
    - `database.dump`;
    - `settings.tar.gz` (`.env`);
    - `media/`, the private files as a plain folder;
    - `web-server-config.tar.gz`;
    - a `COMPLETE` marker, written last.
  - **Shared files.** `media/` shares every file unchanged since the previous backup through hard links (`/usr/local/sbin/tgcg-media-snapshot`), so a backup adds only new files. The first such backup copied all 2,652 files and matched the live files exactly. The second copied none and added about 0.2 GB instead of 3.4 GB.
  - **Older backups** hold a full `private-files.tar.gz` instead.
  - **Undo.** The previous script is kept as `/usr/local/sbin/tgcg-backup.before-20261026`.
- **Retention.** `/usr/local/sbin/tgcg-backup-prune --delete` runs after every backup. It keeps every backup from the last 7 days, the newest of each day for 30 days and the newest of each week after that. It always keeps the newest complete backup. It removes backups that failed part way once they are an hour old. A shared file goes only with the last backup holding it. Run it without `--delete` for a dry run.
- **First thinning.** The schedule's first run on 26 October deleted 54 of 88 backups (9.2 GB). Free space grows over the following week as the full-copy backups of 19–26 October thin out.
- **Restore private files** from the new layout: `cp -a <backup>/media/. /opt/tgcg/backend/media/`. Ownership (`tgcg:tgcg`), permissions and times are kept. From an older backup, extract `private-files.tar.gz` into `/opt/tgcg/backend`.
- **Off-site copy.** All backups are still on this VPS only. An encrypted copy to Backblaze B2 is planned and waits for the owner's account and key.

```bash
systemctl list-timers --all 'tgcg-*' --no-pager
systemctl start tgcg-backup.service
journalctl -u tgcg-backup.service -n 10 --no-pager
```

## SSH access

- Root signs in with a key or a password. Keys in `/root/.ssh/authorized_keys`, by comment: `codex-tgcg-vps-2026-10-12` (listed twice) and `claude-code-tgcg-2026-10-24` (Claude Code, added by the owner on 24 October 2026). To revoke a key, delete its line.
- Password guessing against root reached 388 failed attempts before 24 October 2026. Password sign-in stays on until the owner has a key of their own. Turning it off then is the planned next step.
- `fail2ban` (`fail2ban-server` 1.1.0 from EPEL) is enabled since 24 October 2026. An address with 5 failed SSH sign-ins within 10 minutes is blocked for 1 hour. Key sign-ins are not affected.
  - The settings are in `/etc/fail2ban/jail.d/tgcg-sshd.local`.
  - Bans go straight to nftables (table `inet f2b-table`), because `firewalld` is not running.
  - Two addresses were blocked at once from the attempts still under way.

```bash
fail2ban-client status sshd
fail2ban-client set sshd unbanip <address>
```

## Verification completed

Production settings passed `manage.py check --deploy`. Database migrations and geography imports completed. The managed service returned healthy database status. Administrator login, profile access, protected geography access, token rotation, logout and rejection of the revoked refresh token passed. Unauthenticated member access returned 401. The Gunicorn control socket runs in the service-owned `/run/tgcg` runtime directory.

Public HTTPS health, API sign-in/logout, the app's CORS preflight, Django admin form sign-in/logout and secure host-specific cookies passed. Admin static CSS and Flutter bootstrap/JavaScript/renderer files were served successfully. Root/www redirects, deep-link HTML handling, private-path 404 responses and missing JavaScript 404 responses were checked. Certificate renewal and the reload hook passed a dry run.

An earlier deployment on 12 October 2026 rebuilt frontend `f6e362f`, updated the matching backend to `c793d8e` and applied the polling-unit location-note and USSD registration-channel migrations. Its targeted member-app/server-login suite passed 18 tests; backend authentication, access policy, USSD, location import and mapping checks passed 105 tests against an isolated database.

An earlier deployment on 12 October 2026 published frontend `3f5405c` with backend `c2dd3cd` and installed Tesseract with English language data. Its targeted Flutter suite passed 41 tests and backend registration-related suites passed 66 tests. Public card reading, missing-image validation, administrator HTTPS login/logout, API health and the served web bundle checksum passed.

The latest deployment on 12 October 2026 enabled Google-first/Tesseract-fallback reading and published the longer-timeout web build. The targeted Flutter API-client, member-app, server-login and PVC suites passed 53 tests, including deadline and streamed-response checks. Backend PVC-reading, registration, membership and USSD suites passed 85 tests using isolated SQLite without opening dotenv files. One native-Tesseract test was skipped locally; production verification used a real Google read, then a simulated Google failure with the real installed Tesseract, and both recognized the synthetic name and polling-unit code. The public HTTPS endpoint returned HTTP 200 with app CORS allowed, production settings passed, and API health and the served web checksum passed. No dependency or migration changes were needed. Backups ran before the update and after publication.

## Remaining configuration

### Election-day load: shared area summaries and lighter refreshes (26 October 2026)

This is the first part of election-day readiness. The owner expects about a million users on election day: at least five per polling unit, plus ward, LGA and state teams. The owner asked for the website and server only, with no APK. Backend `82a304be9f293023f6f45fa327d2bf21e239dd5e` went live over `567d18d`, and the web build followed from frontend `d27eef9`.

**Server.** Collation, check-in coverage and member analysis for an area are now computed at most once per `SUMMARY_CACHE_SECONDS` (30) and shared by everyone allowed to see that area. Permissions are still checked on each request first, and each answer carries `computed_at`. The cache is each worker's memory (`LocMemCache`); `CACHE_URL` can point at Redis once there are several app servers. There were no migrations or setting changes.

**Web.**
- The dashboard refreshes every 3 minutes instead of every minute.
- The dashboard, collation, agents on the ground, meetings, project and security screens skip their refresh while the tab is hidden. A visible window without focus still refreshes.
- The project list is fetched about every 10 minutes instead of every 2.
- The upload back-off (45 s up to 15 min, randomly spread, honouring `Retry-After`) only reaches phones with the next APK.

**Validation.** **666 backend tests passed on isolated PostgreSQL**, with zero failures and zero skips; the throwaway databases were removed. Locally, 639 tests passed and 27 were skipped. **351 Flutter tests** passed and analysis was clean.

**Deployment** (`/opt/tgcg/deployment/release-20261026d/`, a systemd job: backup, then `deploy.sh`):
- The guards required a clean checkout at `567d18d` and no dependency, static or migration changes. The API was stopped for the fast-forward and `check --deploy`, the script confirmed nothing was pending, and the API restarted. Health passed, and no server errors followed.
- The backup before deployment took 22 seconds: it copied 9 new private files and shared the other 2,652. Production reports the shared cache as `LocMemCache` with 30 seconds. Anonymous collation returned **401**.

The web release went live at `/var/www/tgcg/releases/web-20261026-135340-9b5f6c72d92e`, and the public `main.dart.js` checksum matched `9b5f6c72…`. The frontend checkout was fast-forwarded to `d27eef9`. Backups succeeded before and after. No data was changed.

### Credits renamed TGC tokens (26 October 2026)

The owner renamed registration credits "TGC tokens" and asked for the website and backend only, with no APK. Backend `567d18d34105524f38d23096806a63dff4a80116` went live over `fbdc2b4`, and the web build followed from frontend `2608195`.

- Members and staff now read "TGC tokens" in the wallet, its history ("Converted 2 TGC tokens"), errors, the registrars list and referral card ("Rewarded" instead of "Credited"), the rates screen ("Token rates") and the rates permission. Naira payments from TGCG keep their names.
- API fields, URLs, the database and audit actions still say `credits`, so phones on versions 3 and 5 keep working; they show the old word until a new APK.
- The tokens are not on a blockchain: they remain entries in TGCG's wallet ledger, worth naira at the rate of the day.

**Validation.** **663 backend tests passed on isolated PostgreSQL**, with zero failures and zero skips; the throwaway databases were removed. Locally, 636 tests passed and 27 were skipped. **346 Flutter tests** passed and analysis was clean.

**Deployment** (`/opt/tgcg/deployment/release-20261026c/`, a systemd job: backup, then `deploy.sh`):
- The guards required a clean checkout at `fbdc2b4`, no dependency or static changes, and only `wallets.0003_tgc_token_labels`. That migration records the new entry-kind labels and changes nothing in the database.
- With the API stopped, `migrate.py` (passed to `tgcg` on standard input) applied exactly that migration, with the role-sync receiver disconnected. **Zero migrations are pending.** Fingerprints matched: **92 roles, 2,381 appointments, 113 delegation grants**.
- Health passed, and no server errors followed. The 47 existing reward entries are unchanged and show the new label. Anonymous `/me/wallet/` returned **401**.

The web release went live at `/var/www/tgcg/releases/web-20261026-125219-48b90459a43a`, and the public `main.dart.js` checksum matched `48b90459…`. The frontend checkout was fast-forwarded to `2608195`. Backups succeeded before and after. No wallet balance, member, role or appointment was changed, no money moved, and no message was sent.

### Forum video pictures, web and Android version 5 (26 October 2026)

The owner approved publishing all three. Backend `fbdc2b4b64a5d8646b2ea70084c2b3db6ba18704` went live over `09e9270`. The web build and Android version 5 both come from frontend `cb5c7ac`, so the web and phone apps match. Each forum video now shows a picture taken from it, in its own shape (upright phone videos stand upright), at most 420 pixels tall, with a play button and its length. The posting app takes the picture: Android uses `MediaMetadataRetriever` and the browser uses a canvas. The server re-saves it as a small JPEG and serves it at `/forum/attachments/{id}/poster/`.

**Validation.**
- **663 backend tests passed on isolated PostgreSQL**, with zero failures and zero skips; the throwaway databases and the staging folder were removed.
- Locally, 636 tests passed and 27 were skipped, and Ruff passed.
- **346 Flutter tests** passed and analysis was clean.
- The browser picture grab was checked in headless Chrome on a video Chrome recorded itself. The result was a 240×320 JPEG whose centre pixel was the recorded colour, so it is not a black frame. Flutter's own browser tests do not start on this PC, so `test/video_poster_web_test.dart` repeats that check where they can run.
- The Android picture grab compiled into the release build. It has not been tried on a phone yet.

**Deployment** (`/opt/tgcg/deployment/release-20261026b/`, run as a systemd job, `run.sh`):
- The first run stopped at the backup, which failed with "file changed as we read it": the backup also archives the deployment folder, and the APK was still uploading into it. Nothing else had run. The second run's backup succeeded.
- `deploy.sh` checked the checkout was clean at `09e9270`, that no dependency or static file changed, and that the only new migration was `forum.0003_video_posters`. With the API stopped, it applied exactly that migration, with the role-sync receiver disconnected and `migrate.py` passed to `tgcg` on standard input.
- **Zero migrations are pending.** Fingerprints matched: **92 roles, 2,381 appointments, 113 delegation grants**. Health passed, and no server errors followed.
- Before the deployment, a careless file-access check briefly ran `migrate.py` itself on the old code. It stopped at its guard, because the pending migrations did not match, and applied nothing.

**Read-only checks.** The forum has 6 earlier videos, none with a picture. The app makes pictures itself for the 4 that are at most 5 MB; the 2 larger ones show the new layout without one. Anonymous requests for a poster return **401**.

**Web release.** It went live at `/var/www/tgcg/releases/web-20261026-110521-f178e86a8daa`. The public `main.dart.js` checksum matched `f178e86a…`.

**Android version 5.**
- Download: <https://app.tgcg.online/downloads/tgcg-emcop-0.1.0-5.apk>. Version `0.1.0+5`, package `ng.tgcg.tgcg_emcop`, minimum Android API 24, with ARM, ARM64 and x86_64 support.
- Size: 195,680,191 bytes. SHA256: `7961d960142bda7af159054c55b4ad4681cdefde5e5301c20b0feae0b7b0abf8`.
- It was built with `flutter build apk --release --build-number=5 --dart-define=TGCG_API_URL=https://api.tgcg.online`.
- **Signing.** The signer matches versions 2–4 (`e58a513e…`, this PC's existing debug identity), so it installs as an update and keeps sign-in and unsent records. The build is non-debuggable, and signature and 16 KB alignment checks passed.
- **Contents.** Every ABI has the production API address. The four ML Kit registrars keep their public no-argument constructors after R8.
- **Download checks.** The public file has the Android package type, the right length and ranged downloads. The full download, fetched by the server over HTTPS, matched the checksum.
- One more exact route was added to `/etc/nginx/tgcg-downloads.inc`, and nginx passed its test. Versions 2 and 3 stay available; other download paths return 404. The metadata is in `/opt/tgcg/deployment/android-release.json`, and the version 3 record is kept as `android-release-v3.json`.
- Version 5 adds everything since version 3: Social Forum, wallets and registrars, Ask Me (typing; voice once the Spitch key is set), referral codes, projects, security response and video pictures.

The frontend checkout was fast-forwarded to `cb5c7ac`. The backup after release succeeded. No member, role or appointment was changed, no money moved, and no message was sent.

### Ask Me voice, backend only, with an outage (26 October 2026)

The owner asked to publish all changes. Claude Code deployed backend `09e9270052af76a7040361fc9841cd3968caebcd` over `268fd07`: Ask Me's voice (`0db2c94`) and the reviewers' "what was really said" (`09e9270`). The web build was not changed; it is still from `e1c4c33`.

**Validation.** The pinned source passed all **657 backend tests on isolated PostgreSQL**, with zero failures and zero skips. The throwaway databases and the staging folder were removed. Locally, 630 tests passed and 27 were skipped; **343 Flutter tests** passed.

**What went wrong.**
- The backup finished at 09:26 UTC. `deploy.sh` (`/opt/tgcg/deployment/release-20261026/`) then passed its guards, stopped the API, fast-forwarded to `09e9270` and passed `check --deploy`.
- It could not run `migrate.py`. The release folder is root-only (mode 700), and the helper runs as `tgcg`, so it failed with "Permission denied". The script stopped, and its exit hook restarted the API on the new code **without migration `askme.0002_voice`**.
- From 09:26 to about 10:47 UTC, `GET /askme/me/` failed with HTTP 500, because the column `voice_enabled` did not exist yet. **9 requests failed.** Health, sign-in, the forum and the rest of the API were not affected.
- At the same time the owner had interrupted the deploy command on their PC. The command had already reached the server, so it ran there anyway.

**Repair.**
- At about 10:47 UTC, `migrate.py` was run as `tgcg` from standard input, with the API stopped. It applied exactly `askme.0002_voice`, with the role-sync `post_migrate` receiver disconnected.
- **Zero migrations are pending.** The fingerprints matched before and after: **92 roles, 2,381 appointments, 113 delegation grants**. Health passed.
- Read-only checks found the Ask Me settings readable (`enabled=false`, `voice_enabled=true`), 1 preference, 0 questions and 0 spoken answers. No server errors followed. Anonymous `/askme/me/` returned **401**.
- Later release scripts pass helpers to `tgcg` on standard input (`python - < migrate.py`).

Voice stays off until `SPITCH_API_KEY` is set in the private environment and the API restarted. The backup before deployment is `tgcg-backup.service` from 09:23–09:26 UTC. No member, role or appointment was changed, no money moved, and no message was sent.

### Ask Me and referral codes (26 October 2026)

Deployed by Claude Code with the owner's approval. Backend `268fd07894ce20e416c4dcf7eee821f7029e5e8f` went live over `ee34d84`. It includes Ask Me (`6c5843e`) and referral codes (`268fd07`). The web build followed, from frontend `e1c4c33`. No APK was built; APK v5 stays on hold.

**Validation.** The pinned source passed all **651 backend tests on isolated PostgreSQL**, with zero failures and zero skips. The throwaway databases and the staging folder were removed. Locally, 624 tests passed and 27 were skipped, and Ruff passed. **338 Flutter tests** passed and analysis was clean. A scan of the web build for keys and local paths found nothing.

**Deployment** (`/opt/tgcg/deployment/release-20261025/deploy.sh`):
- It refused to run unless the checkout was clean at `ee34d84`, no dependency or static file changed, and the only new migrations were `askme.0001_initial` and `membership.0016_referral_codes`.
- The API was stopped while `migrate.py` applied exactly those two migrations, with the access app's role-sync `post_migrate` receiver disconnected.
- **Zero migrations are pending.** The fingerprints of every role, appointment and delegation row matched before and after: **92 roles, 2,381 appointments, 113 delegation grants**.
- `check --deploy` showed only the known OpenAPI enum warning, and health passed.
- The scripts had first been copied with Windows line endings and refused to start. Nothing ran until they were converted.

**Read-only checks.** These ran in process as the National Administrator, without a login call; the administrator's `last_login` was unchanged.
- Ask Me settings returned **200**, `enabled=false`. Items, sites, pages and the review queue all returned **200** with **0**.
- `ai_ready=false`: no Gemini key is set. The default settings row was created at first read.
- The registrars summary returned **200**: 80 registrars, 439 registered, 45 signed in, **45 credited**, 394 waiting.
- No member has a referral code yet; codes are made when first asked for.
- Anonymous requests to `/me/referral/`, `/askme/ask/`, `/askme/me/` and `/wallets/registrars/` returned **401**.

**Web release.** It went live at `/var/www/tgcg/releases/web-20261026-083201-133155abd36b`: 856 files, main JavaScript SHA256 `133155ab…`. The server's own fetch of app.tgcg.online matched that checksum.

The first upload attempt failed before connecting. SSH from the owner's network timed out for about an hour while HTTPS kept working. fail2ban's log shows **2 bans of addresses in the owner's provider ranges**, which explains it. Once the owner's own key is in place and password sign-in is off, repeated wrong passwords from that network can no longer cause it.

The frontend checkout was fast-forwarded to `e1c4c33`. Backups succeeded before and after: `20261026T074016Z-PMsxOq` and `20261026T083346Z-GgViuU`.

**Not done.** A weekly timer for `manage.py check_askme_sources` waits for the owner's approval; it is not needed until source pages are imported. No member, role or appointment was changed, no money moved, and no message was sent.

### Registrars list and past sign-in credits (24 October 2026)

Deployed by Claude Code over SSH with its own key. Backend `ee34d84df9d21fda6dc155212e27d4a0c6c5b1a3` went live over `4b9f177`, followed by the web build from frontend `00d19ee`. No APK was built; APK v5 stays on hold.

The owner reported that registrars' credits were not increasing. Production counts showed why:
- **409** members had been registered by **74** registrars.
- **374** of those members had never signed in. Credits come only at a registered member's first sign-in.
- **34** had signed in before credits started on 23 October, so they earned nothing.
- **1** had signed in since then and was credited correctly.

The owner kept the first-sign-in rule, chose to credit the 34 past sign-ins once, and asked for a registrars list for the National Administrator and finance staff by area.

The release adds:
- `GET /api/v1/wallets/registrars/`, with `summary/` and `{access_id}/registered/`;
- the member's own `registrations` counts in `GET /api/v1/me/wallet/`;
- `manage.py credit_past_registrations` (a dry run unless `--commit`).

The app adds a Registrars section on the Wallets page, and the counts on My wallet.

Validation:
- The pinned source passed all **629 backend tests on isolated PostgreSQL**, with zero failures and zero skips (5 min 31 s). It ran under `config.settings.test`, with no dotenv file and empty provider keys, using the existing validation virtualenv. Both throwaway databases and the staging folder were removed afterwards.
- Locally: 602 passed and 27 skipped on SQLite; Ruff passed.
- **329 Flutter tests** passed and analysis was clean.
- The web build used `TGCG_API_URL=https://api.tgcg.online` and base href `/`. A scan for keys and local paths found nothing; the only hits were Flutter's own graphics symbols.

Deployment (`/opt/tgcg/deployment/registrars-release-20261024/deploy.sh`):
- It refused to run unless the checkout was clean at `4b9f177`, and unless no dependency, migration or static file changed.
- It fast-forwarded the checkout, ran `check --deploy` (only the known OpenAPI enum warning), and confirmed no unapplied migrations with `showmigrations`.
- `migrate` was never run, so the role-sync `post_migrate` receiver never fired.
- It restarted `tgcg-api.service`, and health passed.
- The frontend checkout was fast-forwarded to `00d19ee`.

The catch-up dry run reported **34 to credit (34 credits) to 14 registrars, 0 skipped**. `--commit` credited **34 registrations**, each audited as `wallet.creditsEarned` with `backfill: true`. A second dry run found **0** left.

Read-only National Administrator checks ran in process, with no login; the administrator's `last_login` was unchanged:
- registrars **200** (74 listed);
- summary **200**: 74 registrars, 409 registered, 35 signed in, 35 credited, 374 waiting;
- ordering by waiting **200**;
- the top registrar's people **200**, with no phone numbers.

An anonymous request returned **401**. Reward entries now number **35**.

The web release `/var/www/tgcg/releases/web-20261024-133831-eb94bdb1509f` holds 856 files and 59,201,447 bytes. The public main JavaScript checksum matched (`eb94bdb1…`), the app returned 200 and API health was ok.

Backups succeeded before and after: `20261024T133508Z-LR2zKP` and `20261024T134207Z-b8leLb`. No member, role or appointment was changed, and no money moved. No message or SMS was sent.

### Social Forum (24 October 2026)

Backend `4b9f177bf358120be394b23bd447d6132884d322` was deployed, followed by the Social Forum web release. The user then approved the additional edit-dialog fix, committed and pushed as frontend `50890962df05c43b93242f9b1321df04bdc8b452` on top of `5cd3539`; the corrected build is now published. No APK is included; APK v5 stays on hold. This release adds no settings, dependencies or timers.

The Social Forum is open to active members and accounts holding a role. Posts appear immediately, with comments, one-level answers, likes and reports. Authors can edit or delete their own posts and comments. Editors, meaning accounts holding a role or position, can hide or restore anywhere; hiding closes the item's open reports. Forum actions no longer depend on discussion permissions, and no role definition was changed. Older clients' approve/refuse requests returning 404 and settings PATCH returning 405 are expected; compatibility settings GET always reports approval disabled.

All **621 backend tests passed on isolated PostgreSQL**, with zero failures and zero skips (**327.37 seconds**); the full Ruff check passed. All **329 tracked backend files** matched the tested source exactly, and both isolated databases were removed. An initial test attempt was interrupted near a VPS boot; the clean durable second attempt passed the full suite. The final corrected web snapshot passed **327 Flutter tests in 38 seconds**, and analysis reported no issues (**58.8 seconds**). Its production build succeeded in **62.2 seconds**, after the backend was live, using the required production API define, base href `/` and PWA strategy `none`. All **817 source assets** were exact, and artifact and decoded-manifest privacy scans had **zero findings**. All **1,134 non-generated committed inputs** were verified against the tested source; two reviewed text files used canonical CRLF/LF comparison, with their raw tested hashes retained.

The approved fix prevents a successful save response from closing the underlying post page when a post or comment edit dialog is dismissed during its save. Three regression cases cover the added dialog behavior; the fix is included in the final pinned web release.

Exactly **`forum.0002_social_forum`** was applied, with **zero migrations pending** afterward. It adds post/comment edit timestamps and comment parents, creates Like and Report tables, deletes the old ForumSettings table, and publishes waiting posts using `published_at=created_at`. Reversing the migration does not unpublish those posts. The private transactional wrapper saved the old counts and approval values before the drop, locked the affected forum/access tables while the API was stopped, and verified the exact intended field changes. Existing attachment files were not opened or modified.

Only the access application's system-role `post_migrate` receiver was suppressed for the migration process, then restored. The original deployment helper is unchanged. All five protected fingerprints matched both their independent baseline and the before/after snapshots: **92 roles, 2,381 appointments covering 2,393 areas, and 113 delegation grants covering 125 areas**. Every other old post field, all comment fields and attachment metadata were preserved; added edit timestamps and comment parents were null.

The old approval switch held **one saved `true` value**; it was not using the unsaved default. Its table was removed. There were no waiting posts to publish, so **`published_from_pending=0`**. The exact aggregate counts were:

| Forum records | Before | After |
| --- | ---: | ---: |
| Posts: pending | 0 | 0 |
| Posts: published | 0 | 0 |
| Posts: rejected | 0 | 0 |
| Posts: hidden | 0 | 0 |
| Posts: deleted | 0 | 0 |
| Comments: visible | 0 | 0 |
| Comments: hidden | 0 | 0 |
| Comments: deleted | 0 | 0 |
| Attachments | 0 | 0 |
| Likes | Table not yet created | 0 |
| Reports | Table not yet created | 0 |

All five authenticated National Administrator checks returned **200**, using a short-lived access token held only in memory and no login call. The administrator's `last_login` was unchanged. No response bodies or forum content were retained:

| Read-only GET | Result |
| --- | --- |
| `/api/v1/forum/me/` | `takes_part=true`, `editor=true` |
| `/api/v1/forum/settings/` | `approval_required=false`, `can_change=false` |
| `/api/v1/forum/posts/?show=review` | Count 0 |
| `/api/v1/forum/reports/` | Count 0 |
| `/api/v1/forum/posts/` | Published count 0 |

API health returned **200**. The private environment remains `600:tgcg:tgcg`, registration retains `phone_code_required=false`, message channels remain empty, and all five existing TGCG timers are active. The release made no production forum posts, comments, likes, reports or moderation actions, changed no members, roles or appointments, sent no messages or SMS, and created or decided no payments, withdrawals or credit rates. No card photos were read and no bulk comparison ran.

| Final release evidence | Result |
| --- | --- |
| Backend validation and schema | 621 PostgreSQL tests passed, zero failures/skips, 327.37 seconds; Ruff passed; both test databases removed; only forum migration 0002 applied; none pending |
| Existing records and read-only checks | All five protected fingerprints unchanged; posts, comments and attachments stayed at zero; Like and Report counts zero; one saved approval value `true` removed with its table; five NA GETs returned 200 without login |
| Corrected web validation | 327 Flutter tests passed in 38 seconds; analysis clean in 58.8 seconds; production build succeeded in 62.2 seconds; approved `5089096` source and assets verified with zero privacy findings |
| Final web release | Published `/var/www/tgcg/releases/web-20261024-122253-235366b8caed`; immediate previous `/var/www/tgcg/releases/web-20261024-121230-be22735f1813` retained; 856 files, 59,186,932 bytes; main JavaScript SHA256 `235366b8caed7d35412f2d8731560fa5481d326272e6300a5993ae14f3cb77f8` |
| Public release checks | All 23 final corrected-release checks passed, including the public checksum, health, app-origin CORS/preflights, anonymous forum me/reports 401s, private-path 404s and unchanged SMS-code 503 blocks. One JavaScript download timed out; only that failed checksum check was retried and matched |
| Backups | All succeeded with exit status zero on 24 October 2026: pre-deployment at **11:43:16 UTC**, first Social Forum publication at **12:17:22 UTC**, and final corrected-release backup at **12:35:30 UTC** |

The final uploaded web archive is **22,246,426 bytes**, SHA256 `7c5a0001be109581a8c82fc454ac60ae4c48eccd027b8de16f5e4d9ed774382e`. The first publication used original frontend `5cd3539` and remains retained as the immediate previous release; the backend did not change during the approved web correction.

### Registration credits and Paystack withdrawals (23 October 2026)

Approved backend `8ed24e7d8f50d433b620aea293b9ac0121aa336c` was deployed, and the production web build from approved frontend `909f685a1205c9d258ef8cb55427a17279f0253f` was published. Both commits were pushed on `main`. No APK was built or published; APK v5 remains on hold.

The release adds credits earned once when a member registered by another member first signs in, conversion at the current credit rate, and reviewed withdrawals to a bank account whose name matches the member. The initial defaults are **one credit per registration, ₦100.00 per credit and a ₦1,000.00 minimum withdrawal**, returned without inserting a credit-rate record. Credits can accrue before the registrar's identity is verified; conversion and withdrawals require verification. The web wallet screens show credits, conversions, withdrawal status and the payment/withdrawal/rate views allowed by the account's permissions.

The approved corrections make a first sign-in atomic with its reward, login timestamp and refresh-token record. A failed reward returns 503 without consuming the first sign-in, so a retry can earn once. Password failure counters remain outside this transaction. Existing sign-ins and a first sign-in made while rewards are paused do not receive later backpay. Bank-name matching requires distinct matching words instead of reusing one word. Web dialogs reject repeated submissions and ignore responses after dismissal.

All **619 backend tests passed on isolated PostgreSQL**, with zero failures and zero skips (**331.84 seconds**); Ruff passed. All 328 approved backend files matched the tested source exactly, and both isolated test databases were removed. All **322 Flutter tests passed**, analysis was clean, and the production web build used the required API define. The archive SHA256 is `bf173ef2bc7367ae0c4bf0098f08da77a35a1f50e698591c7bfe25ca8dc7821b`.

Exactly **`wallets.0002_credits_and_withdrawals`** was applied, with **zero migrations pending** afterward. The deployment used a private copy of the normal helper whose migration step invoked a transactional wrapper. It suppressed only the access application's system-role `post_migrate` receiver for that process, then restored the receiver; the original deployment helper was unchanged. This preserved stored role permissions and existing appointments rather than allowing the normal role-sync hook to rewrite them.

The migration's before/after fingerprints matched for all protected role, appointment, appointment-area, delegation and delegation-area records. Original wallet balance, payment and ledger columns also matched across the additive schema change. Counts stayed at **92 roles, 2,381 appointments covering 2,393 areas, and 113 grants covering 125 areas**. Wallet, payment and ledger row counts were **zero before and after**. Lists, projects, broadcasts, deliveries and security dispatches remained zero.

Read-only National Administrator checks used a short-lived access token held only in memory, without calling login; the administrator's `last_login` was unchanged. `GET /api/v1/wallets/credit-rates/` returned **200** with the initial **1 / "100.00" / "1000.00"** defaults, `set_by=null` and no history. `GET /api/v1/withdrawals/` returned **200** with `count=0`. Credit-rate, withdrawal, reward-entry and noncredit-entry row counts were all **zero**, and the protected counts and baseline fingerprints remained unchanged.

`PAYSTACK_SECRET_KEY` remains **absent**. `CREDITS_EARNED_ON` remains **unset**, selecting the user's `signIn` default. Registration still reports `phone_code_required=false`, available message channels remain empty, and the Nginx SMS-code blocks are unchanged. The private environment remains `600:tgcg:tgcg`, the backend checkout is clean at the approved commit, and the original deployment helper is unchanged. No member was signed in by deployment checks. The release created or decided no payment, withdrawal or credit rate, sent no money or message, and changed no member, role or appointment. No card photos were read and no bulk identity comparison ran.

The new **`tgcg-withdrawals.timer`** is installed, verified, enabled and active, waiting on its 15-minute schedule. Its first service invocation succeeded with exactly:

```text
Paystack is not set up: nothing to check.
```

The command checks processing withdrawals older than ten minutes; it never initiates a transfer. With no key configured it contacts no provider. For future processing withdrawals it can verify status and settle or refund existing records. A single webhook POST with `{}` and an invalid signature reached Django and returned **401**, recording no financial change. Nginx configuration validation passed.

The new web release is `/var/www/tgcg/releases/web-20261023-195046-ff592b2dd840`; the previous `/var/www/tgcg/releases/web-20261019-143256-956119733647` remains retained. The bundle contains **856 files and 59,169,385 uncompressed bytes**, with main JavaScript SHA256 `ff592b2dd8405d594c8557614c3fee72f0669b5f5e898691d7a4726c8d3981d4`. All **21 public checks passed**, including the matching public checksum, health 200, app-origin CORS/preflights, anonymous staff/member withdrawal requests returning 401/401, SMS blocks returning 503/503 and private paths returning 404. A second authenticated read-only check after publication and the invalid webhook request again confirmed all financial row counts zero and protected fingerprints unchanged.

| Final release evidence | Result |
| --- | --- |
| Backend and web validation | 619 PostgreSQL tests passed, zero failures/skips, 331.84 seconds; Ruff passed; both isolated databases removed; 322 Flutter tests passed and analysis clean |
| Schema and existing records | Only wallets migration 0002 applied; none pending; protected and original money fingerprints unchanged; 92 roles, 2,381 appointments and 113 grants |
| Authenticated read-only API | Credit rates 200 with defaults/no history; withdrawals 200 with count zero; no login and unchanged administrator login timestamp |
| New financial tables and entries | CreditRate, Withdrawal, reward and noncredit counts all zero; no deployment money operations |
| Configuration and withdrawal worker | Paystack absent; default `signIn`; phone code false; channels empty; 15-minute timer enabled/active and initial run succeeded without a provider call |
| Webhook and Nginx | One invalid-signature POST returned 401 without mutation; Nginx configuration passed |
| Public release checks | All 21 passed; public main JavaScript checksum matched; health/CORS/preflights, anonymous withdrawal 401s, SMS 503s and private-path 404s passed |
| Backups | Both succeeded with exit status zero: the fresh pre-deployment backup finished **19:46:36 UTC on 23 October 2026**, and the post-release backup finished **19:53:46 UTC on 23 October 2026** |

These Paystack dashboard steps remain for the user:

- Set the webhook URL to `https://api.tgcg.online/api/v1/paystack/webhook/`.
- Turn off OTP for transfers.
- Fund TGCG's Paystack balance.

### Printable member lists and Adamawa chapter import (19 October 2026)

Backend `2c35f0dbd7a6685c302ad1402fe55451554418b3` was deployed, followed by the pinned production web build from frontend `1f155cc63648eef3b26e2170e87b51280e6a06b1`. No migrations were applied and none remain pending. Dependencies, runtime settings and timers were unchanged. No APK was built or published.

Members & Exco can download an area's members and exco together as one printable PDF, grouped by place with exco first. Phone numbers are omitted, and FCC access supports multiple authorized areas. All **310 Flutter tests passed**, analysis reported no issues (50.1 seconds), and the production web build succeeded (47.5 seconds) with the required API define. Artifact and decoded-manifest privacy checks passed; all 817 source assets and every archive file matched their recorded sizes and hashes.

All **600 backend tests passed on isolated PostgreSQL**, with zero failures and zero skips (320.66 seconds); Ruff passed. A collection-counter bug in the private test wrapper was reconciled using an independent collection of 600 tests and matching source hashes. The successful full suite was not rerun. Both isolated test databases were removed.

The new web release is `/var/www/tgcg/releases/web-20261019-143256-956119733647`; the previous `b193272` build at `/var/www/tgcg/releases/web-20261018-133943-1e2fc9caad53` remains retained. The new bundle contains **856 files and 59,136,554 uncompressed bytes**, with main JavaScript SHA256 `95611973364781fc41edc0cfe9c39e649a8e9a7dedfdd2943f36f409891eee5a`. All **19 public checks passed**, including the served checksum, app-origin CORS/preflights and the new anonymous PDF request returning 401.

One authorized National Administrator PDF check used a one-member ward and returned **HTTP 200**, **`application/pdf`**, **181,752 bytes**. The response was streamed to `/dev/null`; no PDF file was retained. Exactly **one** expected `members.list_downloaded` audit event was recorded.

The private Adamawa VPS CSV matched its checksum and **42-row** contract, owned by `tgcg` with mode 600. The dry run passed the full approved baseline gate, with **20 already-registered holds and zero unexpected reasons**:

```text
22 to import, 20 held back. Placed at 17 polling units, 3 wards and 1 LGAs; 0 with a VIN.
1 placed at state level.
13 roles, 6 of them new.
Dry run: nothing was saved. Add --commit to import.
```

The requested read-only review of all 20 already-registered rows completed before the commit was released. Individual row labels, roles and diagnostic lines are excluded from these notes. The existing 20 members, their roles and their appointments were left unchanged.

The single-transaction commit succeeded:

```text
Imported 22 members with their roles (13 roles); 9 coordinators may appoint in their areas.
```

Independent and exact-brief postchecks confirmed **22 source members, all 22 verified, with 22 linked active accounts and 22 chapter consent/import audit events**. Member registration placements are **17 polling-unit, three ward, one LGA and one state**. There are **22 active appointments covering 34 areas**: 19 LGA, 13 state and two senatorial-district areas. The two deputy areas are one each in `SD/004/AD` and `SD/005/AD`. Seven FCCs cover **19 distinct LGAs, each exactly once**.

All **nine delegation grants are active**, permit appointments at LGA, ward and polling-unit levels, and cover **21 areas** (19 LGA and two senatorial district); none permits redelegation. The import recorded **176 ordinary chapter identity-check records**, eight per member, without image reads (`read=False`). It supplied zero VINs, card photos or selfies. No production OCR or card-photo reads were performed.

Global totals are **92 roles, 2,381 assignments and 113 grants**; broadcasts, deliveries, lists, projects and security dispatches remain zero. API/database health passed. Registration retains `phone_code_required=false`, the Nginx SMS-code blocks still return 503, and the environment remains `600:tgcg:tgcg`.

The job returned `Result=success`, `ExecMainStatus=0` and stopped cleanly. The private CSV was shredded, and its absence was independently confirmed. Backups succeeded before deployment, again immediately before the import and after the completed release/import. The final backup returned `Result=success`, `ExecMainStatus=0`, finishing at **14:39:44 UTC on 19 October 2026**.

| Release and import evidence | Result |
| --- | --- |
| Backend validation | 600 PostgreSQL tests passed, zero failures/skips; wrapper count reconciled independently; Ruff passed; both isolated databases removed |
| Deployment and web validation | Backend `2c35f0d`, no migrations applied/pending; 310 Flutter tests passed, analysis clean; all 19 public checks passed |
| Authorized PDF check | 200, `application/pdf`, 181,752 bytes, one expected download audit; streamed to `/dev/null`, no file retained |
| Adamawa dry run | 22 importable, 20 already registered, zero unexpected holds; 13 roles, six new; full 42-row baseline matched |
| Commit and independent postchecks | 22 verified members and linked active accounts, 22 chapter audits, 22 active appointments/34 areas, nine active grants/21 areas; all brief checks matched |
| Existing records and private input | Existing 20 members, roles and appointments unchanged; private CSV shredded and absence independently confirmed; job succeeded |
| Backups | Pre-deployment, fresh pre-import and final post-import backups succeeded; final `Result=success`, `ExecMainStatus=0`, finished 14:39:44 UTC |

### Members-only importer and Jigawa agents import (19 October 2026)

Backend `312277a4e1db07463a80ccb7b27c2a8da15a9608`, including `02a80ee`, was deployed with the existing helper. All **593 backend tests passed on an isolated PostgreSQL database**, with zero failures and zero skips (312.52 seconds); Ruff passed. The isolated test database was removed and its absence confirmed. Three private harness checks also passed (17.45 seconds), and their separate test database was removed. Migration checks passed before and after the helper, which reported `No migrations to apply`; no migration ran and none remain pending. API/database health passed, the VPS backend checkout remains clean at that commit, and the private environment remains `600:tgcg:tgcg`.

The new `import_members` command imports listed people as members only, calling `register_imported` with `verified=False`. Their identities remain unverified, with no identity-check records or review-queue entries created by the import. It creates no roles, appointments or agent accreditations, stores no NINs and sends no SMS. The chapter's statement of consent is recorded; the phone number as written is the initial password. Existing members are held back and left unchanged.

This was a backend-only release. No web or APK was built or published for it. At that point the live web build remained pinned frontend `b19327258a8191bc45abea569dc5919e129d79b8`, with main JavaScript SHA256 `1e2fc9caad5321c15ffbf115be6dc6d9950e1efb6704a2a95f0f81288ebcb689`; the web bundle was unchanged by that release.

The private VPS file passed its checksum, schema and **8,134-row** checks, owned by `tgcg` with mode 600. The dry run passed the exact approved gate, with zero already-registered holds and zero unexpected reasons:

```text
6562 to import, 1572 held back. Placed at 4905 polling units, 1599 wards and 58 LGAs.
Dry run: nothing was saved. Add --commit to import.
```

| Held reason | Rows |
| --- | ---: |
| held by the list: no phone number on the list | 748 |
| phone number shared with another row | 240 |
| not a valid Nigerian mobile number | 193 |
| the same person listed again (imported once) | 98 |
| held by the list: several names share one phone number on the list | 97 |
| the same person has another place on another row | 79 |
| held by the list: the same name listed at several units with different phone numbers | 44 |
| held by the list: no valid phone number on the list | 36 |
| held by the list: names and phone numbers on the list cannot be paired | 34 |
| no name | 3 |
| **Total** | **1,572** |

Production-cost password hashes were prepared in memory before database writes (3,024 seconds), preserving the existing password policy and source importer. The **single-transaction commit completed in 166 seconds**:

```text
Imported 6562 members, with no post; their identity is not checked yet.
```

Independent read-only checks confirmed **6,562 source members, 6,562 linked accounts, all 6,562 accounts active, and 6,562 consent audit events**. Every imported identity is unverified; verified-by and verified-at counts are zero. Appointments, delegation grants, accreditations, identity checks and review rows are all zero. Member placements are 4,905 at polling-unit level, 1,599 at ward level and 58 at LGA level; these count members, and all 19 LGA counts matched the approved brief. Already-registered review was unnecessary because its hold count was zero. No individual row diagnostics are included here.

Global roles (86), assignments (2,359), grants (104), broadcasts (0) and deliveries (0) were unchanged. API health returned `status=ok`, `database=ok`; registration retains `phone_code_required=false`, and the Nginx SMS-code blocks, active web path and JavaScript checksum were unchanged. No existing member was changed, no production card photos were read, no bulk identity recheck was run and no messages were sent.

The private CSV was successfully shredded and its absence independently confirmed. The job returned `Result=success`, `ExecMainStatus=0` and stopped cleanly. Aggregate evidence is retained privately in `/opt/tgcg/deployment/jigawa-members-import-20261019/summary.json`. Backups succeeded before deployment, again immediately before import and after the import. The final backup returned `Result=success`, `ExecMainStatus=0`, finishing at 06:09:39 UTC on 19 October 2026.

| Import evidence | Result |
| --- | --- |
| Private file validation | Checksum, schema and 8,134 rows matched; VPS copy owned by `tgcg`, mode 600 |
| Dry run | Exact approved gate passed: 6,562 importable, 1,572 held; zero registered holds and unexpected reasons |
| Commit | One transaction succeeded: 6,562 members, with no appointments or identity verification |
| Read-only postchecks | 6,562 members and linked active accounts, all unverified; consent audits and placements matched; zero appointments, grants, accreditations, identity checks and review rows |
| Private CSV cleanup | Shredding succeeded; absence independently confirmed; job succeeded and stopped cleanly |
| Backups | Pre-deployment, fresh pre-import and post-import backups succeeded; final `Result=success`, `ExecMainStatus=0` |

### Zamfara chapter import, second attempt (18 October 2026)

The user supplied a corrected brief for the same unchanged CSV. It supplied the full expected hold text and allowed the role total to fall when already-registered people were held back. This remained a data-only job using the existing importer: no deployment, migration or web build. Backups succeeded before and after the attempt.

The actual dry run passed the corrected gate: **222 to import, 18 held back**, placed at **129 polling units, 89 wards and four LGAs**, with **zero VINs**. The plan used **29 roles, two of them new**, with **15 coordinator delegation grants**, all confirmed after commit. All 12 baseline holds matched, there were zero unexpected holds, and six additional rows were held because they were already registered. Importable and held counts totalled 240.

The six already-registered rows were reviewed read-only before the commit was released. Their requested row-level details belong in the user's reply only and are excluded from these notes. No already-registered person's membership, identity, role or appointment was changed by this import.

The single-transaction commit succeeded. Independent read-only checks verified **222 imported members, all 222 verified, with 222 linked active accounts**, placed at 129 polling units, 89 wards and four LGAs. There are **222 appointments**: 209 at LGA level, ten at state level and three at senatorial-district level, including three deputy appointments across two districts (two and one). There are **15 delegation grants** and **222 import-source audit events**.

Global totals are now 86 roles, 2,359 assignments and 104 grants; broadcasts and deliveries remain zero. Registration retains `phone_code_required=false`, the environment remains `600:tgcg:tgcg`, the Nginx SMS-code blocks remain present, and API health passed. The active web path and JavaScript checksum were unchanged. The private VPS CSV was successfully shredded and its removal independently confirmed; the job returned `Result=success`, `ExecMainStatus=0` and stopped cleanly. The final post-attempt backup also succeeded with `Result=success`, `ExecMainStatus=0`.

| Import evidence | Result |
| --- | --- |
| Dry run | Passed: 222 importable, 18 held; 29 roles, two new; 12/12 baseline holds matched, zero unexpected, six already registered. |
| Commit | `Imported 222 members with their roles (29 roles); 15 coordinators may appoint in their areas.` |
| Read-only postchecks | 222 members, 222 verified, 222 accounts, all active; 129 polling-unit/89 ward/4 LGA placements; 222 appointments (209 LGA/10 state/3 district), three deputy appointments across two districts (two and one), 15 grants and 222 source audit events. |
| Private CSV cleanup | Shredding succeeded; removal independently confirmed; job succeeded and stopped cleanly. |
| Backups | Pre-attempt and post-attempt backups succeeded; final backup returned `Result=success`, `ExecMainStatus=0`. |

### Zamfara chapter import stopped at the dry-run gate (18 October 2026)

This was a data-only import attempt using the existing command: no deployment, migration or web build. The pre-import baseline contained zero imported Zamfara members. Backups succeeded before and after the attempt. The strict gate failed and no import was committed; no retry was performed. The private VPS CSV copy was shredded and its removal confirmed. No source rows, row labels, personal details or held-reason text are retained in these notes.

The dry-run plan contained 222 importable rows and 18 held rows, totalling 240. Six extra holds for already-registered numbers were allowed by the brief, but only 11 of the 12 required baseline holds matched and one hold reason was unexpected. The accepted rows used 29 roles, including two prospective new roles; the brief requires 32 roles. These mismatches stopped the run before commit.

Prospective registration placement was 129 polling units, 89 wards and four LGAs, with zero VINs. The plan contained 209 LGA, ten state and three senatorial-district appointments, with 15 prospective coordinator delegation grants. These are dry-run figures only: no memberships, accounts, roles, appointments or grants were created by this attempt.

Post-attempt read-only checks found zero imported Zamfara members, zero verified members, zero accounts, no member-level counts (`{}`), zero appointments with no appointment-level counts (`{}`), no deputy districts (`[]`) and zero grants. The import source has zero audit events. Global roles (84), assignments (2,137) and grants (89) were unchanged; broadcasts and deliveries remain zero. Registration still reports `phone_code_required=false`, API health passed, and the active web path and JavaScript checksum were unchanged.

| Import evidence | Result |
| --- | --- |
| Dry run | 222 importable, 18 held; 29 roles, two new; strict gate failed. |
| Commit | Not run; zero import changes committed. |
| Private CSV cleanup | VPS copy shredded; removal confirmed. |
| Post-attempt read-only checks | All Zamfara import/member/account/appointment/grant counts and source audit events were zero; global role/assignment/grant totals and the active web release were unchanged. API healthy; phone codes remain disabled. |
| Backups | Pre-attempt and post-attempt backups succeeded; final backup returned `Result=success`, `ExecMainStatus=0`. |

### Enhanced member analysis, search and VIN comparison (18 October 2026)

Backend `5f93c030608e86a8a4df0e285ce6ae951ac91b51` was deployed with the existing helper, and the pinned production build of frontend `b19327258a8191bc45abea569dc5919e129d79b8` was published at `/var/www/tgcg/releases/web-20261018-133943-1e2fc9caad53`. Both source commits are pushed. The preceding morning web release remains retained. All 18 final public checks passed, and backups succeeded before deployment and after publication.

National member analysis adds adjacent previous 7-day and 30-day registration windows, verification sources (automatic, chapter and person), app-account presence and recorded sign-in recency, and missing profile and registration fields. Sign-in counts describe recorded logins, not app activity. Scoped drill-down filters share the summary predicates and use the current time for each request, fixing the earlier cached appointment-expiry cutoff. Geographic coverage includes members lacking the selected child level, including a matching `missingZone` drill-down when Nigeria is broken down by zone; zone-only members are placed for that breakdown even when they have no state.

Member search accepts names, membership numbers, positions and places, with phone lookup limited to areas where the caller may see personal details. Opening a member profile fetches fresh details and retains the existing private-data permission checks for the photo, WhatsApp number, birth date and disability details. WhatsApp, verification date and polling-unit list-selection status are read-only staff fields. Existing identity-completeness requirements remain; a legacy empty VIN counts as missing consistently in the profile, filters and analysis.

Card comparison allows up to two character substitutions, insertions or deletions in the VIN while still requiring the member's name on the card. Three to six differences remain pending for review with a count-only diagnostic. This is TGCG's card-comparison policy, not authoritative INEC validation. Stored comparisons remain cached against their existing basis; this deployment does not run `--recompare`, bulk verification or any production card-photo reads. Release checks use read-only aggregate queries and create no production test data. No APK is included.

No new migrations, dependencies, environment settings, provider credentials or timers were required. The helper reported `No migrations to apply`, with zero pending migrations. API/database health passed, the private environment remains `600:tgcg:tgcg`, and all four existing TGCG timers remain active.

The pre-deployment aggregate baseline was 2,350 members and 2,353 users; postchecks counted 2,351 and 2,354. Totals increased during deployment; the checks created none. Roles (84), assignments (2,137) and delegation grants (89) were unchanged; projects, broadcasts, deliveries, message lists and security dispatches remain zero. The helper ran its routine geography synchronization; deployment checks were read-only and created no production test data. Available messaging channels remain `[]`, registration reports `phone_code_required=false`, and Termii/Firebase/LiveKit credentials remain absent. Read-only configuration flags matched the baseline.

Read-only national analysis counted 2,123 exco people holding 2,137 appointments, matching an independent appointment query. All 20 drill-down counts matched their summaries. Nigeria's state breakdown contained 37 areas, 28 with members, three with exco and zero unplaced members; its zone breakdown contained six areas, all six with members, one with exco and zero unplaced members. Account counts were zero without an account, 2,276 with no recorded sign-in, 75 last signed in within seven days, the same 75 within 30 days, and zero older sign-ins. Verified identities totalled 2,206: 61 automatic, 2,123 chapter and 22 person; 75 profiles were fully verified.

Profile and registration quality counts were: missing name 0, VIN 2,077, card photo 2,186, selfie 2,156, gender 2,129, birth date 2,151, state 0, LGA 22, ward 262 and polling unit 834; 31 polling units were chosen from a list. These are aggregate counts only.

The initial public checks found web-access failures because the release root inherited mode 700 under umask 077. Its mode was corrected to 755 and the publisher helper was corrected to set that mode. All 18 checks passed on the final rerun. Main JavaScript returned 200 with `no-store` and the exact build checksum; index, bootstrap and poster returned 200. Anonymous registered-member, security, analysis, exco and `missingZone` filter requests returned 401 with app-origin CORS and successful preflights. Hidden configuration and media paths returned 404; the exact blocked SMS-code endpoints returned 503. Registration options retained `phone_code_required=false`.

| Release evidence | Result |
| --- | --- |
| Local backend validation | 563 passed, 27 skipped on isolated SQLite; 26 PostgreSQL-specific skips and one unavailable-Tesseract skip. All 16 focused analysis/exco cases passed; Ruff, Django system check, migration check and diff check passed. Dotenv loading was disabled and the Google key cleared for these synthetic tests. |
| Isolated PostgreSQL suite | All 590 passed on pinned backend `5f93c030608e86a8a4df0e285ce6ae951ac91b51`, zero failures and skips (302.63 seconds); Ruff passed. The isolated database was dropped and its absence confirmed. |
| Flutter validation and production web build | All 308 Flutter tests passed; analysis clean (66.4 seconds). The pinned production build succeeded (79.4 seconds) with `TGCG_API_URL=https://api.tgcg.online`. |
| Web artifact and privacy checks | Published 856 files, 59,134,358 bytes; all manifest files verified and zero privacy findings. Main JavaScript SHA256 `1e2fc9caad5321c15ffbf115be6dc6d9950e1efb6704a2a95f0f81288ebcb689`; archive SHA256 `85b2ec9108855f59cf7191c622909c26ee193a8627ef86b7cd32ac1bb4c7193c`. |
| Production deployment and services | Backend `5f93c030608e86a8a4df0e285ce6ae951ac91b51` deployed through the helper; no migrations to apply and zero pending. API/database healthy, environment `600:tgcg:tgcg`, all four existing TGCG timers active. Nginx configuration tests passed at deployment and publication. |
| Public and National Administrator checks | All 18 final public checks passed, including the exact served JavaScript checksum. All 20 read-only aggregate drill-down counts matched. No member/executive test login, test registrations, messages or card reads. |
| Aggregate preservation | Member/User totals increased by one each during deployment; checks created none. Roles, assignments and grants were unchanged; projects, broadcasts, deliveries, lists and dispatches remain zero, as detailed above. |
| Backups | Backups succeeded before deployment and after publication; final backup returned `Result=success`, `ExecMainStatus=0`. |

### Security response and Members & Exco (18 October 2026)

Backend `f17f613cb8b6e5af3a02a8ed405efa541ea51604`, including `c878cd7` and `006620e`, was deployed with the existing helper. The production web build from pinned frontend source `5c2c4ce33623f0bdbc81722e63d75a3eafdd2dbc` was published at `/var/www/tgcg/releases/web-20261018-081722-f6aa7cc4ea6d`; the preceding 17 October release remains retained. Later frontend commits, including the phone-icon changes, are outside this pinned web build. No APK was built or published for this release.

A security officer remains an ordinary member using the same sign-in account, appointed to a role holding `respondToSecurity`. The Situation Room can pick the nearest eligible officer using a recent project location or the officer's assigned area, then send an incident to one officer at a time. The officer accepts or declines, reports being on the way and arriving, and records the resolution. The incident trail records these steps; cancellation or closure stands the officer down. A National Administrator is not offered as an officer merely because they hold every permission.

Members & Exco now separates ordinary members from members holding appointments and lists each area's own appointments at its level, with Nigeria opening into zones or states. Member analysis reports verification and profile gaps separately, so verification on a chapter's word does not imply a complete card profile.

All three production migrations succeeded, with none pending:

```text
Applying field.0007_security_officer_event... OK
Applying messaging.0002_notices... OK
Applying security.0001_security_dispatches... OK
```

Dependencies, environment settings, keys and timers were unchanged; the private environment remains `600:tgcg:tgcg`. Roles (84), assignments (2,137), grants (89), projects (0), broadcasts (0), deliveries (0) and message lists (0) were unchanged. Member/User totals rose from 2,304/2,307 to 2,306/2,309 during live activity; the deployment created none. No roles were created or officers appointed, and the global security-dispatch count is zero. Verification uses read-only checks and aggregate counts; no incident or notification test was sent.

Analysis returned 2,306 members and 2,123 people holding 2,137 appointments. The appointment counts were LGA 348, polling unit 1,189, senatorial district 4, state 68 and ward 528. Nigeria's breakdown contained 37 areas, 26 with members and 3 with exco. A direct RoleAssignment query independently counted 2,137 active or suspended, non-protected appointments whose end date is absent or in the future. Available messaging channels remain empty, and registration options retain `phone_code_required=false`.

Known limitation from read-only review: the member list's `withRole` and `withoutRole` filters cache the appointment-expiry cutoff when a worker imports the module, so expired appointments can remain in those filters until the worker restarts. Analysis summaries use the current time, and permission checks are unaffected. No code change for this limitation is included in the release.

| Release evidence | Result |
| --- | --- |
| Backend tests and lint | 577 passed on isolated PostgreSQL, zero failures and skips (314.19 seconds); Ruff passed; test database removed and absence confirmed |
| Flutter tests, analysis and production web build | 292 tests passed; analysis clean; production build succeeded (141.9 seconds) with `TGCG_API_URL=https://api.tgcg.online` |
| Web artifact | Published 856 files, 59,097,883 bytes; main JavaScript SHA256 `f6aa7cc4ea6d9f34631619b0b84de33b24e4e9c293cf905dc7bfe3a1cf2fdebc`; public checksum matched |
| Artifact privacy checks | 829 text artifacts, decoded asset manifest and private filenames checked; zero findings; production API URL present |
| Production migrations and services | All three applied; no pending migrations; API/database healthy; Nginx configuration test passed with no configuration changes |
| Read-only public and permission checks | All 17 passed; counts-only check record: `/opt/tgcg/deployment/security-public-checks-20261018.json` |
| Runtime preservation | Existing dependencies, settings and keys unchanged; environment `600:tgcg:tgcg`; all four existing TGCG timers enabled and active; no release-created roles, appointments or dispatches |
| Backups | Pre-deployment and post-verification backups succeeded; final backup returned `Result=success`, `ExecMainStatus=0` |

The three new protected routes returned 401 anonymously with app-origin CORS and preflight responses of 200; the existing registered-members route also returned 401. API/database health returned 200, registration options retained `phone_code_required=false`, and both SMS-code routes returned 503. Index, bootstrap and main JavaScript returned 200 with `no-store`; the poster returned 200. Private paths and media, and missing JavaScript, returned 404. These checks created no production records and sent no messages.

### Registration by another member and permission safeguards (17 October 2026 follow-up)

Deployed backend `e8ea828c41d661f31802b6d1f88e86a19900497f` from `main` with the existing helper, including requested registration change `ac98348` and the approved permission/concurrency fix. A signed-in person can register another member with their name, phone number and agreement, then complete that registration until the identity is checked. The phone number is the initial password; the member can change it after signing in. Adding a card supplies the name and place from that card.

The fix reloads and locks the Member before checking the registrar's permission, so a concurrent identity decision or membership suspension cannot leave stale permission in use. Corrections also lock and reload the User before checking whether first sign-in has occurred, protecting the phone number and initial password. PVC decisions and completion take locks in the same Member-then-PVC order. The 37 new regression tests include 14 real PostgreSQL checks. All **567 backend tests passed on an isolated PostgreSQL database**, with zero failures and zero skips (281.11 seconds); Ruff passed and the test database was removed.

All **284 Flutter tests passed**, analysis found no issues, and the production web build from `d2fb6a7ff259dcb5c256ba6d55876de0d5c1a745` succeeded with the required API define. The published artifact has 856 files and 59,064,055 uncompressed bytes; main JavaScript SHA256 is `c71f74e0a6dcd971e193b34693e3603a798d67336f537ed895ca6371d810ca0c`. Filename, decoded asset-manifest and credential-pattern checks found no private artifacts or matching credentials. The preceding morning web release remains retained.

The production migration succeeded, with no migrations pending:

```text
Applying membership.0015_registered_by_another_person... OK
```

API/database health and Nginx configuration checks passed; Nginx was unchanged. Geography remains at 160,873 INEC-located polling units, and the private environment retains `600:tgcg:tgcg`. Roles (84), assignments (2,137), grants (89), projects (0), messages (0) and lists (0) were unchanged. The aggregate baseline grew by one Member and one User; queries confirmed one of each was created during concurrent live activity. Deployment scripts registered no one and did not edit existing member data. Runtime settings, dependencies and timers were unchanged. No APK was built, and this documentation update adds no app UI text.

All **14 public release checks passed**. Index, bootstrap, poster and JavaScript returned 200; index, bootstrap and JavaScript use `no-store`. The served JavaScript checksum matched. API/database health returned 200; anonymous `GET /api/v1/me/registered/` returned 401 with app-origin CORS and a successful preflight. Registration options still report `phone_code_required=false`; both SMS-code routes remain 503. Missing JavaScript, private configuration paths and forum/evidence media returned 404. Secret-free results are private at `/opt/tgcg/deployment/followup-public-checks-20261017.json`. No one signed in and no production records were created by these checks. Backups succeeded before deployment and after public verification (`Result=success`, `ExecMainStatus=0`); all four existing TGCG timers remain enabled and active.

Termii setup does not authorize registration SMS codes: retain `REGISTRATION_PHONE_CODE_REQUIRED=False` and the temporary Nginx SMS-code blocks until the user separately approves enabling phone verification. This 17 October policy supersedes the older Termii enablement instructions below.

### Projects, messaging, card verification and locations (17 October 2026)

Deployed backend `979009f5dd2de9c9dbb97acd53131a8cc73e2a7b` with the existing deployment helper, then published web source `4854dba88b31959d69d94c25ac251e6b37c82d38`. All **521 backend tests passed on an isolated PostgreSQL database**, with zero failures and zero skips (246.21 seconds), and Ruff passed. All **281 Flutter tests passed**, analysis found no issues, and the production web build succeeded with the required API define. Artifact filename, asset-manifest and credential-pattern checks passed. No UI guidance was added.

Locked dependencies include `cryptography==50.0.2`; pinned Gunicorn 26.2.0 was reinstalled after synchronization. All nine production migrations succeeded:

```text
Applying membership.0013_verification_card_match... OK
Applying projects.0001_initial... OK
Applying field.0006_project_links... OK
Applying membership.0014_member_whatsapp_number... OK
Applying messaging.0001_initial... OK
Applying results.0004_project_links... OK
Applying tracking.0004_project_links... OK
Applying tracking.0005_end_sharing_from_before_projects... OK
Applying wallets.0001_initial... OK
```

The location-sharing migration ends sessions started before projects were introduced. Production had zero active legacy duty sessions before and after deployment; no projects were created. All 12 system roles already existed. Member, User, Role, Appointment and Grant counts were unchanged before the separately authorized card-verification run.

The loader returned:

```text
INEC locations applied to 86,826 polling units (86,826 new, 0 updated, 74,047 unchanged).
```

It rejected 13,414 `no_location`, 2,202 `outside_lga`, 2 `outside_nigeria` and 4 `shared_spot` candidates. Coverage is now 160,873 of 176,846 polling units across all 36 states and the FCT.

The card-verification dry run selected 98 awaiting-review members, including 69 with card photos; 57 could be verified automatically if their cards matched. It read no cards and changed no records. After the user explicitly approved Google-first photo transfer using the existing key, the completed run processed 98 members and 69 cards, reported zero unread cards and automatically verified 30 members. Previously verified and rejected statuses were unchanged (zero changes). Aggregate-only results are private at `/opt/tgcg/deployment/verification-20261017/summary.json`; no personal details, card text or row identifiers are included here. No new provider keys were created.

Messaging provider channels remain `[]`; the National Administrator's role-choice request returned 84 choices. Termii and Firebase credentials are absent, and production WhatsApp/Push transport defaults remain `termii`/`fcm`, without demo or console credentials. Registration still reports `phone_code_required=false`; Nginx still returns 503 for the temporary SMS-code routes. When adding Termii credentials later, also set `REGISTRATION_PHONE_CODE_REQUIRED=False` and retain those blocks; enabling registration SMS codes is a separate user decision. Queue, campaign and list counts are zero. No messages, projects, roles, lists or appointments were created manually.

The enabled, active message service/timer runs every minute with `deliver_messages --seconds 55 --batch 10` and a 15-minute service timeout. It starts one batch, then checks its soft deadline between batches. The first run succeeded with `Handled 0 message(s).`; stdout contains counts only and stderr is discarded. Actual provider delivery remains pending credentials and configuration.

All **19 public checks passed**: index, bootstrap, poster and matching JavaScript returned 200; entrypoints use `no-store`; missing JavaScript, private paths and media returned 404. API/database health, app-origin CORS, registration options and place lookups passed. Anonymous card, broadcast, roles and projects requests returned 401; SMS routes remained 503. Results are private at `/opt/tgcg/deployment/release-checks-20261017.json`.

Backups succeeded before deployment and after verification. The isolated PostgreSQL test database was removed. No migrations remain pending, and the private environment retains mode `600:tgcg:tgcg`. No APK, phone testing or new secret-provider setup was performed, following the user's final override. No nonexistent version-5 APK link was added to README. The latest public Android installer remains version 3, with version 4 private staging unchanged.

### State chapter imports completed (16 October 2026)

Deployed backend `ec8311a4b1991fe61c5da959b8ce74ac8db7f558` from `3ff6e3b`; API/database health passed. All **493 backend tests passed on an isolated PostgreSQL database**, with zero failures and zero skips (243.49 seconds), and Ruff passed. The isolated test database was removed. No dependencies or migrations changed. The web build remains `066944ceae2613024bcf286021528d6f2644bb9a`; no web, APK or UI changes were made for this backend-only deployment.

A successful backup preceded the imports. Four private chapter CSVs were placed outside all web roots under `/run/tgcg-state-import-20261016`, owned by `tgcg` with mode 600; transfer checksums matched. The `tgcg-state-import-20261016` systemd job discarded console output and captured importer output only in memory. Each file passed its expected dry-run gate, single-transaction commit and postchecks. No names, phone numbers, VINs, source rows or individual references are recorded here.

| Chapter file | Status | Members | Appointments | Roles | New roles | Delegation grants | Held |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Kebbi | Committed and independently verified | 25 | 25 | 22 | 21 | 1 | 4 |
| Jigawa | Committed and independently verified | 26 | 26 | 22 | 15 | 4 | 0 |
| Kaduna 1 | Committed and independently verified | 833 | 844 | 54 | 28 | 74 | 140 |
| Kaduna 2 | Committed and independently verified | 1,053 | 1,056 | 16 | 2 | 10 | 199 |

Totals: **1,937 new members and sign-in accounts, 1,951 appointments, 89 delegation grants and 66 new role definitions**. Independent PostgreSQL checks against each exact import source verified these counts, active accounts, verified membership, active appointments and the intended grants. No SMS was sent; the import command does not call SMS.

The 343 held entries comprise 341 entries designated by the dry-run plan plus two already-registered members in Kaduna 1. Kebbi held two invalid entries and two held-list entries. Kaduna 1 held 98 held-list entries, 39 invalid entries, one missing-name entry and the two already-registered entries. Kaduna 2 held 147 held-list entries, 51 invalid entries and one missing-name entry, with no additional already-registered entries. The two existing members were held back: this run created no memberships, appointments or delegation grants for them. Both Kaduna files were processed; no earlier import of these Kaduna state chapter files is recorded.

All four source CSVs were shredded and their removal independently verified; the private import plan was also removed. The job completed with `Result=success` and `ExecMainStatus=0`, then stopped cleanly after verification with a successful `ExecStopPost`. Aggregate-only job results remain private at `/opt/tgcg/deployment/state-imports-20261016/summary.json`, containing counts, phase and error codes only. Public API health returned HTTP 200 with `status=ok`, `database=ok`; the active web path and public JavaScript checksum were unchanged. Backups succeeded before import and after verification; the post-import backup returned `Result=success` and `ExecMainStatus=0`.

### Field duty, live incident video, member cards and locations (16 October 2026)

Deployed backend `3ff6e3b4d0e6fca25368a245908cfa3668f9db5d` and web build source `066944ceae2613024bcf286021528d6f2644bb9a`. The backend includes `c17586f` (membership-card PDF downloads and disabilities), `57a8508` (INEC locations for ten more states), `6d42f4c` (live incident video), `daaf5f7` (GPS required for polling-unit incident reports) and `5ea0e64` (polling-unit executive check-ins/location sharing). Review found that field-worker coverage counted appointments even when their permission restrictions excluded `fieldDuty`; `3ff6e3b` fixes that per-appointment check, with 18 new regression tests. An empty restriction list grants nothing; null restrictions retain the role's permissions.

All **488 backend tests passed on an isolated PostgreSQL database**, with zero failures and zero skips (244.69 seconds); Ruff passed. All **260 Flutter tests passed** and analysis found no issues. The production web build passed with the required API define. Bundle filename and asset-manifest checks found no private paths; compiled JavaScript passed the credential-pattern checks. No app UI guidance was added.

Both production migrations succeeded:

```text
Applying field.0005_live_stream... OK
Applying membership.0012_member_disabilities... OK
```

The loader returned:

```text
INEC locations applied to 62,665 polling units (62,665 new, 0 updated, 11,382 unchanged).
```

It rejected 7,876 `no_location`, 1,440 `outside_lga` and 4 `shared_spot` candidates; 74,047 polling units now have INEC locations. A dry run reported `gains it` for all six custom polling-unit executive roles before the committed command returned `Added fieldDuty to 6 role(s).` Six `role.updated` audit events identify National Administrator `TGCG` as the actor. The removed Situation Room permission remains removed. Member, User, Incident, Evidence and Post counts were unchanged.

Locked dependencies were synchronized and pinned Gunicorn 26.2.0 was reinstalled afterward; API/database health passed. No migrations remain pending, and all 186 custom-role appointments remain present. The private environment remains unchanged at `600:tgcg:tgcg`. Nginx was unchanged: forum uploads retain `160m` and 300-second timeouts, private `/media/` remains blocked with 404, SMS-code routes remain 503, and USSD callback protection remains in place. The recording maintenance service completed successfully and its timer is enabled and active, running every minute. Free VPS disk space was approximately 106 GB.

LiveKit URL, API key and API secret are all absent from the VPS. The local configuration has a URL but blank key/secret values; no credentials were copied. The user selected live viewing only: no paid recording storage was created. After credentials are configured, create a webhook in LiveKit Cloud under **Settings > Webhooks > Create**, using `https://api.tgcg.online/api/v1/livekit/webhook/` and the matching `LIVEKIT_API_KEY` for its signature. The webhook is not configured yet, and real live-video verification remains pending.

All 16 public checks passed: index, bootstrap, poster and matching JavaScript checksum returned 200; entrypoints use `no-store`; missing JavaScript and private forum/evidence media returned 404. API health returned 200 with healthy database status. Anonymous member-card access returned 401 with app-origin CORS and a successful preflight. Registration options still report `phone_code_required=false`; public place lookups returned 37 states, 23 Kaduna LGAs, 13 Zaria wards and 51 units for ward `18-23-01`, with CORS and preflights passing. Both temporary SMS-code routes still return 503. No production test members, incidents or posts were created. Results are stored privately in `/opt/tgcg/deployment/release-checks-20261016.json`.

Backups succeeded before deployment and after verification; database archive listings were checked by the backup service. Private media is included in the backup archives. The isolated PostgreSQL test database was removed. The previous web release remains retained. No APK was built or published for this request: automatic approval review rejected that build as outside the web/VPS scope before any APK process ran. The latest public installer remains version 3; the earlier version 4 remains private staging only.

### Forum, national Situation Room and map member counts (15 October 2026)

Deployed backend `fb36a48`, including `ed1df60`, before publishing web source `afbbf0c`. This includes the server forum, map navigation from wards to polling units and members, phone layout fixes and the `video_player` dependency. Current source version is `0.1.0+5`. No APK was built or published for this deployment; the user installs on their phone with `flutter run`.

Validation: all **446 backend tests passed on an isolated PostgreSQL database**, with no failures or skips. All **228 Flutter tests passed**, analysis reported no issues, and the production web build succeeded with `--dart-define=TGCG_API_URL=https://api.tgcg.online`. The isolated test database was removed. Locked production dependencies and pinned Gunicorn were installed. Migration output:

```text
Applying forum.0001_initial... OK
```

The migration created forum settings, posts, attachments and replies. Its post-migrate hook synchronized system-role definitions: ward coordinators now have `moderateDiscussion`; agents and observers have `createDiscussionThread`; zonal, state, LGA and ward coordinators no longer have `viewSituationRoom`. The existing non-blocking OpenAPI status-enum warning remains. No environment changes were required; forum limits retain defaults of 15 MB/photo, 50 MB/video, 10 attachments and 100 MB total files/post. The private environment remains `600:tgcg:tgcg`.

Existing custom polling-unit executive roles were changed using `remove_role_permission viewSituationRoom`, as the National Administrator. The dry run reported:

```text
PU Coordinator: loses it
Assistant PU Coordinator: loses it
PU Youth Leader: loses it
Assistant PU Youth Leader: loses it
PU Women Coordinator: loses it
PU Organising Officer: loses it
Dry run: nothing was saved. Add --commit to change them.
```

The commit returned `Removed viewSituationRoom from 6 role(s).` Each role has one new `role.updated` audit event attributed to the administrator; all other permissions and existing appointments were preserved.

Nginx `/etc/nginx/tgcg-backend.inc` now has a dedicated `/api/v1/forum/` proxy location, covering post uploads and attachment downloads. It sets `client_max_body_size 160m`, `client_body_timeout 300s`, `proxy_read_timeout 300s` and `proxy_send_timeout 300s`, preserving the usual proxy headers. The existing `/media/` block still returns 404; forum and evidence files have no public alias. Forum files use only the authenticated `/api/v1/forum/attachments/` endpoint. Nginx configuration passed and was reloaded; the API was restarted and health returned `status=ok`, `database=ok`.

Production feature checks used only the National Administrator. `GET /api/v1/forum/settings/` returned `approval_required=true` and `can_change=true`; its first read initializes the default settings row. `GET /api/v1/members/counts/?level=lga&code=KD-ZARIA&by=ward` returned ward counts including `18-23-05`. Both allowed the app origin. System-role and custom-role permissions were verified directly. No members or executives were signed in, no posts or replies were created, and no post content was fetched. Browser private media uses authenticated byte downloads, with images in memory and Blob URLs for videos; playback/upload with real production content was not exercised.

All 854 uploaded web files matched their manifest; public JavaScript checksum, bootstrap and poster checks passed. The previous web release is retained. Secret-free results are in `/opt/tgcg/deployment/forum-release-checks.json`; build source and checksums are in `/opt/tgcg/deployment/web-release.json`. Deployment notes include the previously uncommitted import/Change PIN record below, with no personal details or post content. A successful backup preceded the deployment.

### Earlier Kaura chapter import and Change PIN (15 October 2026)

Deployed backend `3236ee4` and frontend feature commit `cab29e3`, including Change PIN, in web build `4cfa70e`. The final frontend build also guards duplicate PIN submissions and prevents a pending response from closing the account page after the dialog is dismissed. Both regressions were reproduced and fixed without changing UI text. All 216 Flutter tests passed and analysis found no issues.

Before production deployment, all **428 backend tests passed on a separate PostgreSQL database**, including chapter import, working scoped executive roles, repeated imports and password changes. The isolated test database was removed. Locked production dependencies and the pinned Gunicorn runtime were installed. Migration `membership.0011_registration_channel_import` was applied; `0010_pvc_update` was already present. The API was restarted and returned healthy database status. No runtime settings changed; the private environment remains `600:tgcg:tgcg`. The deployment check retained its non-blocking OpenAPI status-enum naming warning.

The National Administrator imported the Zaria LGA chapter's Kaura ward polling-unit executive list for ward `18-23-05`, using source `TGCG Zaria LGA chapter: polling unit executives list`. The private dry run matched the required 186 accepted rows, 10 held rows and the exact expected held-row set. It saved nothing. The subsequent commit created **186 members with 186 polling-unit role appointments** in one transaction; postchecks verified active accounts, verified membership and each appointment's exact polling-unit scope. No SMS was sent.

The CSV was transferred outside all web roots into a private runtime directory, owned by `tgcg` with mode 600. It was not committed or included in deployment artifacts. Command output was captured in memory; only safe summary counts were retained. The job ran independently of the SSH connection with console output disabled, and `shred -u` removed the VPS CSV immediately afterward. No names, phone numbers or individual rows appear in these notes. Summary-only status is retained privately in `/opt/tgcg/deployment/kaura-import-status.json`.

The rebuilt web release contains 854 files; every file matched the upload manifest. Public JavaScript SHA256, bootstrap and poster checks passed. The prior web release is retained.

An APK version 4 was built and verified during the earlier work, but its publication was cancelled when the user chose `flutter run`. It remains a private staging artifact with no published download route. The latest published installer remains version 3. No further APK build or publication was performed for the forum deployment.

### Earlier member profile and PVC-scan web release (14 October 2026)

Published the member profile, optional selfie, occupation, gender and date-of-birth changes, plus the member's single PVC scan and coordinator review. Frontend feature commit `f5ed2e6` is included in build `44fbfc3`; backend feature commit `67ec44d` is included in deployed `aa3788c`. Migration `membership.0010_pvc_update` created the PVC-update record and its one-pending-update-per-member constraint. It was the only pending migration. No dependencies or runtime settings changed; the private environment remains `600:tgcg:tgcg`.

Review fixed four PostgreSQL row-lock queries in the new profile, selfie, scan and approval operations. They now lock the member row without attempting to lock the nullable account join. The frontend also handles incorrectly scanned future or overly old birth years when opening the date picker; it retains the scanned value until the member confirms a correction. No UI text or notes were added.

Members without a verified identity apply their checked scan details immediately. Verified members submit a pending update for an authorized coordinator's second check; approval preserves verified status and enforces the member's existing and proposed scopes. The card image is private evidence available to reviewers with identity-verification access in the member's area, following the existing polling-unit-change evidence pattern. General lists still mask VIN and restrict date-of-birth visibility.

Validation: **213 Flutter tests passed** and analysis reported no issues, including four reproduced date-picker regressions. The backend's 416 existing tests passed on an isolated PostgreSQL database; six new PostgreSQL regressions passed separately after correcting their fixture. They cover profile/selfie completion, immediate scan application and verified scan approval, both with and without a linked account. The isolated databases were removed after testing. Production migration checks passed; the Django deployment check completed with one OpenAPI status-enum naming warning and no errors.

Read-only public verification passed:

| Check | Result |
| --- | --- |
| API health | 200; `status=ok`, `database=ok` |
| Registration options and all four place lookups | 200, app-origin CORS; SMS-code requirement remains false |
| Anonymous profile, selfie, scan-status, review-list and card requests | 401, with app-origin CORS; preflights passed |
| Existing member profile and PVC-scan status | Authenticated 200 |
| Coordinator PVC-update list | Authenticated 200 |
| Missing private card | Authenticated 404 |
| Temporary SMS-code and PIN-code endpoints | Existing 503 blocks retained |
| Member, User and PVC-update counts | Unchanged; no production test records created |
| Web upload and public assets | All 854 files matched; public JavaScript SHA256, bootstrap and poster passed |

`tgcg-api.service` was restarted after migration. Nginx configuration passed; no Nginx changes were required. Secret-free results are in `/opt/tgcg/deployment/member-profile-release-checks.json`; web metadata is in `/opt/tgcg/deployment/web-release.json`. Sources and deployment notes are synchronized across local, GitHub and VPS checkouts. A backup succeeded before deployment.

The user will build the APK separately. No APK was built or published for this release; the previous version 3 download remains available. The current source version is `0.1.0+4`. Use `flutter build apk --release --dart-define=TGCG_API_URL=https://api.tgcg.online`, preserving the existing package and signing identity. Physical-phone testing of these new flows remains with the user.

### Earlier member-registration release and Android version 3 (14 October 2026)

Deployed backend `194ea18`, including `50fdf1d`, and built web and Android from frontend `4ae479d`. Migration `membership.0009_member_polling_unit_from_list` added the boolean field with default `false`; it was the only pending migration. Production Django checks and migration checks passed, and `tgcg-api.service` was restarted successfully. No runtime settings were changed. The private environment remains `600:tgcg:tgcg`.

Termii has no API key configured and `REGISTRATION_PHONE_CODE_REQUIRED` remains unset. The effective value is `false`, so app registration does not require an SMS code. The registration-place throttle retains its `600/hour` default. Polling units can now be selected by name while joining; these selections await PVC review.

The existing `/etc/nginx/tgcg-sms-pending.inc` uses exact locations only for `/api/v1/register/code/` and `/api/v1/register/pin-code/`. Both still return 503. Registration options and place lookups pass through to Django without sign-in. Read-only checks passed on loopback and public HTTPS, with `Origin: https://app.tgcg.online`; both GET CORS headers and OPTIONS preflights passed for every endpoint:

| Endpoint | Result |
| --- | --- |
| `/api/v1/register/options/` | 200; `{"phone_code_required": false}` |
| `/api/v1/register/places/states/` | 200; 37 entries, `code` and `name` |
| `/api/v1/register/places/lgas/?state=KD` | 200; 23 entries, `code` and `name` |
| `/api/v1/register/places/wards/?lga=KD-ZARIA` | 200; 13 entries, `code` and `name` |
| `/api/v1/register/places/polling-units/?ward=18-23-01` | 200; 51 entries, only `code`, `name` and `location` |

No members or sign-in accounts were created in production; their counts were unchanged. API health returned `{"status":"ok","database":"ok"}`. Secret-free results are recorded in `/opt/tgcg/deployment/registration-release-checks.json`.

Validation: 203 Flutter tests passed and static analysis found no issues. The backend passed 396 tests locally with seven environment-dependent skips; all 403 tests passed against a separate PostgreSQL database on the VPS, including real concurrency and native Tesseract checks. The isolated database was removed after testing. All 854 web files matched their upload manifest, and public JavaScript, bootstrap and poster checks passed.

Download: <https://app.tgcg.online/downloads/tgcg-emcop-0.1.0-3.apk>. Version `0.1.0+3`, package `ng.tgcg.tgcg_emcop`, minimum Android API 24, with ARM, ARM64 and x86_64 support. Size: 170,924,198 bytes. SHA256: `32067e0a961db9c4bdf12f2a8e455b5388491d62f2e821f961db80af2b733913`.

```powershell
flutter build apk --release --build-number=3 --dart-define=TGCG_API_URL=https://api.tgcg.online
```

The package and signer match version 2. The existing signing identity was retained (`e58a513eead318719b1ab854181cbcdee5130e2d3305c49442019434e6808a41`); the APK is non-debuggable. Signature and 16 KB alignment checks passed. Every ABI includes the production API address and native SQLite library. The PVC release fix from `1b2ef7f` is included: all four ML Kit registrar classes and their public no-argument constructors were confirmed in the packaged manifest and DEX. Public MIME type, length, ranged download and full checksum checks passed. Version 2 and the previous web release are retained.

The user chose to handle phone testing with `flutter run`; release-APK Scan PVC on a real phone remains unverified. To test the actual release fix, install the version 3 APK above or run `flutter run --release --dart-define=TGCG_API_URL=https://api.tgcg.online`. No UI notes were added for this deployment.

The new APK route was added to `/etc/nginx/tgcg-downloads.inc`; Nginx configuration passed and was reloaded. Release metadata is in `/opt/tgcg/deployment/web-release.json` and `/opt/tgcg/deployment/android-release.json`. Local and GitHub sources were pulled before building and the VPS source checkouts were fast-forwarded to those same releases. Backup verification succeeded before deployment.

Superseded by the 17 October separate-approval policy above: adding Termii credentials must retain `REGISTRATION_PHONE_CODE_REQUIRED=False` and both temporary SMS locations. Enabling registration SMS codes requires a separate user decision.

### Previous Android installer: version 2 (14 October 2026)

Download: <https://app.tgcg.online/downloads/tgcg-emcop-0.1.0-2.apk>. Version `0.1.0`, version code `2`, package `ng.tgcg.tgcg_emcop`, minimum Android API 24 (Android 7). This universal APK includes ARM, ARM64 and x86_64 support. Its size is 170,833,912 bytes; SHA256 is `388e19745820f90abe3195fa206a43a4c946d8f06bba011e1c5e90555136ec61`.

Built from source `3c3a103` with:

```powershell
flutter build apk --release --build-number=2 --dart-define=TGCG_API_URL=https://api.tgcg.online
```

The installed debug APK lacked the production API URL. The new release embeds it in every ABI and is non-debuggable. Android signature and 16 KB alignment checks passed. It uses the existing workspace debug signing identity so it can replace the previous APK from this workspace; the signer fingerprint matches (`e58a513eead318719b1ab854181cbcdee5130e2d3305c49442019434e6808a41`). Keep this signing identity for updates. A physical phone was not connected, so device installation, camera/GPS and runtime OCR remain for phone verification.

The release shrinker initially reported eight absent classes for optional OCR scripts. TGCG explicitly uses Latin OCR. Narrow generated `-dontwarn` rules were added in `android/app/proguard-rules.pro` and wired into the release build, following [Android's compile-only dependency guidance](https://developer.android.com/build/releases/agp-7-0-0-release-notes#missing-class-warnings-in-r8-shrinker). The release rebuilt successfully without disabling the shrinker. The existing 195 Flutter tests cover the unchanged Dart source. No app UI notes were added; `AGENTS.md` records the user's preference and required production build flag.

The APK is stored separately from Flutter web assets under `/var/www/tgcg/downloads`. The app host includes `/etc/nginx/tgcg-downloads.inc`, which serves this exact versioned URL with the Android package MIME type, attachment filename, HTTPS security headers and no-store caching; other download paths return 404. Signature/manifest/API URL/SQLite library checks passed locally. Public MIME type, file length, ranged download and full served checksum passed. API health stayed healthy and the backend was not changed or restarted. APK metadata is in `/opt/tgcg/deployment/android-release.json`; private signing keys and APK binaries are not committed to Git. VPS configuration backups ran before and after publication. The previous web release remains unchanged.

### Frontend-only release (14 October 2026)

Pulled `main` at `1c0f039`, rebuilt with the documented production command and published the welcome/poster, server-backed dashboard/agent home and photo-evidence updates. All 195 Flutter tests passed, analysis reported no issues, and the build contained the production API URL and welcome poster. All 855 uploaded files matched their manifest. Public JavaScript checksum, bootstrap and poster requests passed, as did API/database health. The desktop welcome and sign-in layout was visually verified. Backups ran before publication and after verification; the previous web release is retained.

This release changed frontend source and static web assets only. Backend commit `e5f5d72` was preserved, with no migrations, runtime-setting changes or API restart; the API service start timestamp was checked before and after publication. Local/GitHub/VPS frontend source is synchronized, including the deployment notes. Existing SMS, LiveKit and election-configuration requirements remain as recorded below.

### Latest feature release (13 October 2026)

Published the committed frontend updates for server-backed incidents, field reports, results, collation, meetings and the agreed role menus, with matching backend permission and scoped identity-review changes. The meetings schema migration `meetings.0001_initial` was applied; migration hooks refreshed system-role definitions. Source from both GitHub `main` branches was checked out on the VPS. Existing private runtime settings and USSD callback configuration were preserved.

Review found and fixed meeting navigation races: disconnects, end responses, Back navigation and a disconnect during confirmation now close the call route once. The backend now rejects invalid/blank meeting date filters with HTTP 400 and locks/reloads a meeting before admission, so a concurrent closure cannot issue a stale pass. Full PostgreSQL testing also exposed nullable outer joins in member administration and administrator recovery; row locks now cover the affected records without locking nullable joins. Polling-unit decisions retain their member lock. An oversized incident test reference was corrected without changing the schema.

Validation: the original full Flutter suite passed 179 tests and static analysis passed. After the navigation fix, all 10 meeting tests passed, including four reproduced regressions. The updated backend's full suite passed **394 tests on an isolated PostgreSQL database**, including real meeting and USSD concurrency checks and native Tesseract. Production Django checks, migration, Nginx configuration and API/database health passed. The previous release was retained, and backups ran before deployment and after verification.

Read-only public checks passed: authentication/profile and access payloads; authenticated meeting, incident, field-report, result and election lists; unauthenticated rejection (401); invalid meeting date rejection (400); USSD menu, membership lookup and wrong-service responses plus wrong-token 404. No Member, User, Meeting, Admission or USSD progress records were created. Collation content could not be checked because no election is configured. Results are recorded in `/opt/tgcg/deployment/latest-release-checks.json`.

Meeting planning is live. Audio/video is awaiting the project's `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET`; they are not configured on the VPS yet. The browser host has no restrictive camera/microphone Permissions-Policy or CSP. API tests use mocked LiveKit; real audio/video still needs verification after credentials are configured. See backend `docs/meetings.md`. The restricted local `build/livekit-private.env` is Git ignored; participant tokens cannot replace the API secret used to issue per-user passes. Media uploads, recordings and remaining demonstration dashboards retain their documented limits.

The Termii enablement instructions from this release are superseded by the 17 October separate-approval policy above. Nginx returns a clear 503 JSON response for SMS-code and PIN-code requests through `/etc/nginx/tgcg-sms-pending.inc`; retain those blocks and `REGISTRATION_PHONE_CODE_REQUIRED=False` when adding provider credentials unless the user separately approves phone verification. No administrator phone or email was supplied.

### Africa's Talking USSD sandbox enabled

Enabled on 12 October 2026 for Africa's Talking sandbox code `*384*027031#`, preserving the leading zero and trailing `#`. Both `USSD_CALLBACK_TOKEN` and `USSD_SERVICE_CODE` are configured in the private environment, owned by `tgcg` with mode 600. The API was restarted and production checks passed. No application code or migrations were changed, and no Africa's Talking API key is used or stored.

A random callback token of at least 32 characters is active privately on the VPS. The callback URL was provided to the user through a restricted local file under the Git-ignored `build` directory for the dashboard's USSD channel setup. The callback URL is unchanged from sandbox preparation. Neither the URL nor the token is included in these notes.

Nginx now has a dedicated `/api/v1/ussd/` location in `/etc/nginx/tgcg-backend.inc`, with access logging off and callback error output discarded; the HTTP redirect location has the same logging protection. Proxy headers and timeouts match the existing API proxy. Africa's Talking callback IP addresses/CIDR ranges have not yet been supplied; provider allow rules followed by `deny all` will be added when that list is available.

The API service loads `/opt/tgcg/deployment/gunicorn-ussd.conf.py`. This operational logging configuration records only IP, method, status and duration in Gunicorn access entries, and suppresses USSD URL records from process logging after Django starts. Other API diagnostics remain available. Application Git source remains unchanged.

Backups ran successfully before activation and after the verified configuration was recorded. Nginx configuration and Django production checks passed; API health returned `status=ok`, `database=ok` after restart. The environment file remains `600:tgcg:tgcg`.

The requested safe callback tests all passed on loopback and through public HTTPS:

| Check | Local | Public HTTPS |
| --- | --- | --- |
| Initial menu | 200, `CON Welcome to TGCG` with both menu choices | Same |
| Non-member lookup (`text=2`) | 200, `END This number is not a TGCG member yet...` | Same |
| Wrong service code | 200, `END This service is not available.` | Same |
| Wrong callback token | 404 | 404 |

Successful screens used `text/plain`. The callback token was absent from newly written Nginx access/error logs and the API service journal. The test number's membership and sign-in-account counts were unchanged, and no Join sequence was submitted. Secret-free results are recorded in `/opt/tgcg/deployment/ussd-status.json`.

Reverified on 13 October 2026 after a successful backup, reusing the existing callback token and service code `*384*027031#`. Initial menu, non-member lookup (`text=2`) and wrong-service checks returned 200 with `text/plain`; a wrong token returned 404, on both loopback and public HTTPS. Member/User counts were unchanged, API/database health passed, and the API and Nginx remained active. No environment, code, migration, Nginx or restart changes were needed.

In the dashboard, replace any literal `<TOKEN>` placeholder by pasting the complete callback URL from the restricted, Git-ignored `build/ussd-callback-private.txt`. Leave Events URL blank. The private VPS copy is `/root/tgcg-ussd-callback-private.txt`. The user's 13 October 2026 screenshot confirmed the callback in the [Africa's Talking simulator](https://developers.africastalking.com/simulator), reaching the TGCG Join prompt: `Enter your full name as written on your PVC:`. Provider IP/CIDR restrictions remain pending; completed registration and creation of a new membership have not yet been confirmed.

The user can now test `*384*027031#` in Africa's Talking's simulator with their own `+234` number; completing Join creates their real TGCG membership. Callback address restrictions remain pending the provider's trusted IP/CIDR list from support. The backend's `docs/ussd-registration.md` describes the menu and callback contract. To disable USSD, remove the two environment lines and restart the API; callback POSTs then return 404.

### Quick USSD membership and resumable progress deployed (13 October 2026)

Deployed backend implementation `f9ded2a` and Flutter build `c06b1ad`. Menu 1 joins or continues: enter the required 19-letter/digit VIN, then the polling unit code as `18-23-01-001`, `18*23*01*001` or separate parts. The unit confirmation includes the data-use notice: `1` joins, `2` changes the unit and `0` cancels. Successful confirmation returns a membership number and creates active membership awaiting identity review (`verification_status=pendingReview`), with an empty name and no sign-in account. Full name and a repeated 6-digit app PIN can be added later through menu 1; quick membership alone does not enable app sign-in. Coordinator review displays a clear label and membership number until a name is added.

Migration `membership.0008_ussd_resumable_registration` was applied after a successful backup. PostgreSQL now keeps progress by normalized phone number across workers, API restarts and provider session IDs for 30 days of inactivity. The opening notice explains this retention. `/etc/systemd/system/tgcg-maintenance.service.d/ussd.conf` adds `purge_ussd_progress` to the existing daily maintenance service; its manual run succeeded. Cancelling clears progress, leaving existing membership intact. Duplicate and callback-prefix tracking uses keyed HMAC digests rather than raw callback text or PINs. Each new question, including consent and PIN confirmation, must be displayed before its answer can be accepted. Native session timeouts remain controlled by the provider; an in-flight old-format session asks the caller to redial.

The existing callback token, sandbox code `*384*027031#`, protected Nginx locations and Gunicorn logging remain unchanged. No Africa's Talking API key is required. The environment file remains `600:tgcg:tgcg`. Provider IP/CIDR restrictions and the user's completion of a real registration remain pending.

Validation used isolated databases without reading dotenv files: the full local backend suite passed 354 tests, with one native Tesseract test skipped; 57 focused USSD integration tests passed. On the VPS, 91 USSD, registration-service and concurrency tests passed against a separate PostgreSQL database. These included simultaneous final joins, redial/completion races, simultaneous profile completion and cleanup lock ordering. The isolated database was removed afterward. Fifteen existing coordinator/phone Flutter tests and targeted static analysis passed, and the production web build succeeded.

Production checks passed without creating a test membership or sign-in account:

| Check | Result |
| --- | --- |
| Saved VIN survives API restart | Passed; public redial resumed at polling unit |
| Partial polling-unit code survives redial | Passed across local and public callbacks |
| Cancel progress | Passed; temporary draft and callback records removed |
| Initial menu, non-member lookup, wrong service code | Passed on loopback and public HTTPS; 200, expected `CON`/`END`, `text/plain` |
| Wrong callback token | 404 on loopback and public HTTPS |
| Member, User, draft and session counts after temporary checks | Unchanged |
| Production Django checks and API/database health | Passed |
| Nginx configuration and daily maintenance | Passed |
| Callback credential logging and existing private URL | No credential in Nginx logs or the new API journal; private URL still matches |
| Built web assets | All 855 files matched the uploaded manifest; public JavaScript checksum matched |

That deployment used `/var/www/tgcg/releases/web-20261013-122745-a3cbb36d5073`; its previous release was retained. Secret-free operational results are in `/opt/tgcg/deployment/ussd-quick-validation.json`. Backups cover the release and operational configuration. Source checkouts are synchronized with GitHub; later documentation commits do not require rebuilding this web bundle.

The operational dashboards marked as demonstrations still need server integration before their totals can be used as live reports.

Moving from sandbox to live later requires the exact live service code, an API restart, the same callback checks and user tests on MTN, Airtel, Glo and 9mobile.
