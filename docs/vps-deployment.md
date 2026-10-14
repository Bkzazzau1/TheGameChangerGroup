# TGCG VPS deployment

Initial setup on 12 October 2026; latest web release verified on 14 October 2026 (Africa/Lagos).

## Public URLs

| Service | URL |
| --- | --- |
| Flutter web app | https://app.tgcg.online |
| Django administration | https://admin.tgcg.online |
| API health | https://api.tgcg.online/api/v1/health/ |

`tgcg.online` and `www.tgcg.online` redirect to the web app. HTTP redirects to HTTPS. All five names are covered by the Let's Encrypt certificate; automatic renewal and its Nginx reload hook passed a simulated renewal.

## Current state

- VPS: `159.198.75.103`, AlmaLinux 9.8.
- Source: `Bkzazzau1/tgcg_backend`, deployed commit `194ea18e60d68bea6ffe0ad6da04320eecb35558`.
- Application: `/opt/tgcg/backend`, running as the `tgcg` system account.
- Python 3.12.15, Django 5.2.18, Gunicorn 26.2.0, PostgreSQL 16.
- Tesseract 4.1.1 with English language data; `TESSERACT_CMD=/usr/bin/tesseract`.
- PVC reader: Google Cloud Vision first; installed Tesseract handles Google errors, timeouts, malformed replies and blank text.
- Service: `tgcg-api.service`, enabled at boot, listening on `127.0.0.1:8000`.
- Database: `tgcg`, accessed through `/var/run/postgresql` with local peer authentication.
- Production environment: `/opt/tgcg/backend/.env`, mode 600. The generated secret remains on the VPS.
- Nginx configuration: `/etc/nginx/nginx.conf`, `/etc/nginx/conf.d/tgcg.conf` and `/etc/nginx/tgcg-*.inc`.
- TLS certificate: `/etc/letsencrypt/live/tgcg.online/`; renewal uses `certbot-renew.timer`.
- Geography: 8,809 wards, 176,846 polling units, 11,382 imported INEC locations.
- Administrator: access ID and display name `TGCG`, national administrator with country scope.

Nginx publishes the API and administration over HTTPS while Gunicorn remains on loopback. Flutter uses `https://api.tgcg.online`; browser access is limited to the app origin. Termii SMS credentials remain to be configured.

## Web release and demo labels

- Published release: `/var/www/tgcg/releases/web-20261014-080116-fcfd68e3228e` (release directory timestamps use UTC).
- Frontend build source: `4ae479d8f3b8e4a93978753581b39c211b646973` from `Bkzazzau1/TheGameChangerGroup`. Later documentation commits do not change this bundle.
- Previous web release retained: `/var/www/tgcg/releases/web-20261013-234832-aeb1b7f8c708`.
- Active release link: `/var/www/tgcg/app-current`.
- Main JavaScript SHA256: `fcfd68e3228ed1a4213d88e941537bd884d54bf7669683551db43e52cdafd7d1`.
- Build: 854 files, 54,504,608 uncompressed bytes. All files matched the upload manifest; the public bundle checksum was checked after publication.
- Release metadata: `/opt/tgcg/deployment/web-release.json`.

Production builds require `TGCG_API_URL=https://api.tgcg.online`. The app opens on the TGCG poster, logo and welcome note, with the sign-in form beside the poster on wide screens and opened by Sign in on phones. Menus offer server-backed screens, and dashboard/agent-home totals come from existing API counts and tracking coverage. The app now defaults to the production API, and production builds also set its address explicitly. Demo and presentation sign-in routes were removed.

The browser version keeps its offline queue in memory, so pending work does not survive a reload. Incident and result photos use authenticated multipart evidence uploads and can be opened for review. Browser PVC photos go through `POST /api/v1/register/read-pvc/`: the VPS sends the first reading request to Google Cloud Vision and uses Tesseract locally if Google fails or returns no text. Mobile OCR runs on the device. The browser registration form and polling-unit change dialog use the returned text. Cardholders must check every extracted field, especially VIN and polling-unit digits. Audio-file recording remains unavailable on web; unsupported screens are hidden. The published desktop welcome/poster/sign-in screen was verified in the browser.

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
- `tgcg-backup.timer`: backs up PostgreSQL, private media, `.env`, Nginx configuration, TLS configuration and deployment metadata daily at 03:15 Africa/Lagos.
- Backup directories: `/var/backups/tgcg/<UTC timestamp>-<unique suffix>`, accessible to root.
- Initial backup: `/var/backups/tgcg/20261012T072156Z-gTgoU1`.
- Database archives are checked with `pg_restore --list`; a full restore has not been exercised.
- Backups currently remain on this VPS and have no automatic retention limit.

```bash
systemctl list-timers --all 'tgcg-*' --no-pager
systemctl start tgcg-backup.service
journalctl -u tgcg-backup.service -n 10 --no-pager
```

## Verification completed

Production settings passed `manage.py check --deploy`. Database migrations and geography imports completed. The managed service returned healthy database status. Administrator login, profile access, protected geography access, token rotation, logout and rejection of the revoked refresh token passed. Unauthenticated member access returned 401. The Gunicorn control socket runs in the service-owned `/run/tgcg` runtime directory.

Public HTTPS health, API sign-in/logout, the app's CORS preflight, Django admin form sign-in/logout and secure host-specific cookies passed. Admin static CSS and Flutter bootstrap/JavaScript/renderer files were served successfully. Root/www redirects, deep-link HTML handling, private-path 404 responses and missing JavaScript 404 responses were checked. Certificate renewal and the reload hook passed a dry run.

An earlier deployment on 12 October 2026 rebuilt frontend `f6e362f`, updated the matching backend to `c793d8e` and applied the polling-unit location-note and USSD registration-channel migrations. Its targeted member-app/server-login suite passed 18 tests; backend authentication, access policy, USSD, location import and mapping checks passed 105 tests against an isolated database.

An earlier deployment on 12 October 2026 published frontend `3f5405c` with backend `c2dd3cd` and installed Tesseract with English language data. Its targeted Flutter suite passed 41 tests and backend registration-related suites passed 66 tests. Public card reading, missing-image validation, administrator HTTPS login/logout, API health and the served web bundle checksum passed.

The latest deployment on 12 October 2026 enabled Google-first/Tesseract-fallback reading and published the longer-timeout web build. The targeted Flutter API-client, member-app, server-login and PVC suites passed 53 tests, including deadline and streamed-response checks. Backend PVC-reading, registration, membership and USSD suites passed 85 tests using isolated SQLite without opening dotenv files. One native-Tesseract test was skipped locally; production verification used a real Google read, then a simulated Google failure with the real installed Tesseract, and both recognized the synthetic name and polling-unit code. The public HTTPS endpoint returned HTTP 200 with app CORS allowed, production settings passed, and API health and the served web checksum passed. No dependency or migration changes were needed. Backups ran before the update and after publication.

## Remaining configuration

### Member-registration release and Android version 3 (14 October 2026)

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

When Termii SMS is configured, adding its key enables registration phone codes by default. At the same time, remove the two temporary SMS locations, restart the API, test and reload Nginx, and verify SMS delivery with the approved sender.

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

Configure `TERMII_API_KEY` and an approved `TERMII_SENDER_ID` in the server environment before enabling phone verification. Nginx currently returns a clear 503 JSON response for SMS-code and PIN-code requests through `/etc/nginx/tgcg-sms-pending.inc`. After the real provider is configured and verified, remove those temporary locations, restart the API, test Nginx configuration and reload Nginx. No administrator phone or email was supplied.

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

The current web release is `/var/www/tgcg/releases/web-20261013-122745-a3cbb36d5073`; the previous release is retained. Secret-free operational results are in `/opt/tgcg/deployment/ussd-quick-validation.json`. Backups cover the release and operational configuration. Source checkouts are synchronized with GitHub; later documentation commits do not require rebuilding this web bundle.

The operational dashboards marked as demonstrations still need server integration before their totals can be used as live reports.

Moving from sandbox to live later requires the exact live service code, an API restart, the same callback checks and user tests on MTN, Airtel, Glo and 9mobile.
