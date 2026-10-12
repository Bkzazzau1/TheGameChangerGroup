# TGCG VPS deployment

Configured and verified on 12 October 2026 (Africa/Lagos).

## Public URLs

| Service | URL |
| --- | --- |
| Flutter web app | https://app.tgcg.online |
| Django administration | https://admin.tgcg.online |
| API health | https://api.tgcg.online/api/v1/health/ |

`tgcg.online` and `www.tgcg.online` redirect to the web app. HTTP redirects to HTTPS. All five names are covered by the Let's Encrypt certificate; automatic renewal and its Nginx reload hook passed a simulated renewal.

## Current state

- VPS: `159.198.75.103`, AlmaLinux 9.8.
- Source: `Bkzazzau1/tgcg_backend`, deployed commit `ee7c2661ec721eac65312057a49f6aaff8c33e13`.
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

- Published release: `/var/www/tgcg/releases/web-20261012-163806-9a87bb5d70ea`.
- Frontend source: committed `main` from `Bkzazzau1/TheGameChangerGroup`, including the OCR timeout changes and their tests. The exact commit is recorded in the release metadata.
- Previous web release retained: `/var/www/tgcg/releases/web-20261012-135705-cb2320b76d59`.
- Active release link: `/var/www/tgcg/app-current`.
- Main JavaScript SHA256: `9a87bb5d70ea94b628c3c5c1036fae268282c21aa9ee95e75c5b3d9177a33107`.
- Build: 855 files, 53,968,804 uncompressed bytes. The served main bundle matches the compiled release.
- Release metadata: `/opt/tgcg/deployment/web-release.json`.

The app was published with the user's approved demo labels. Local and mixed operational views show a page-specific notice before their statistics. Mixed result and report views distinguish live submissions from sample totals. Role Management, Member Review, Unit Mapping, Agent Tracking and API-backed member tabs keep their live data views. The polling-agent assignment selector and sample Digital Agent ID also carry explicit notices.

The browser version keeps its offline queue in memory, so pending work does not survive a reload. Browser PVC photos go through `POST /api/v1/register/read-pvc/`: the VPS sends the first reading request to Google Cloud Vision and uses Tesseract locally if Google fails or returns no text. Mobile OCR runs on the device. The browser registration form and polling-unit change dialog use the returned text. Cardholders must check every extracted field, especially VIN and polling-unit digits. Audio-file recording remains unavailable on web, and unintegrated dashboards remain demonstrations. Compilation and public HTTP checks passed; browser UI automation was unavailable in this session.

The release was built with:

```powershell
flutter build web --release --dart-define=TGCG_API_URL=https://api.tgcg.online --base-href=/ --pwa-strategy=none
```

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

- `tgcg-maintenance.timer`: removes expired location history daily at 03:00 Africa/Lagos.
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

The user can now test `*384*027031#` in Africa's Talking's simulator with their own `+234` number; completing Join creates their real TGCG membership. Callback address restrictions remain pending the provider's trusted IP/CIDR list from support. The backend's `docs/ussd-registration.md` describes the menu and callback contract. To disable USSD, remove the two environment lines and restart the API; callback POSTs then return 404.

The operational dashboards marked as demonstrations still need server integration before their totals can be used as live reports.

Moving from sandbox to live later requires the exact live service code, an API restart, the same callback checks and user tests on MTN, Airtel, Glo and 9mobile.
