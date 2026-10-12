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
- Source: `Bkzazzau1/tgcg_backend`, deployed commit `bd423b8`.
- Application: `/opt/tgcg/backend`, running as the `tgcg` system account.
- Python 3.12.15, Django 5.2.18, Gunicorn 26.2.0, PostgreSQL 16.
- Service: `tgcg-api.service`, enabled at boot, listening on `127.0.0.1:8000`.
- Database: `tgcg`, accessed through `/var/run/postgresql` with local peer authentication.
- Production environment: `/opt/tgcg/backend/.env`, mode 600. The generated secret remains on the VPS.
- Nginx configuration: `/etc/nginx/nginx.conf`, `/etc/nginx/conf.d/tgcg.conf` and `/etc/nginx/tgcg-*.inc`.
- TLS certificate: `/etc/letsencrypt/live/tgcg.online/`; renewal uses `certbot-renew.timer`.
- Geography: 8,809 wards, 176,846 polling units, 9,858 imported INEC locations.
- Administrator: access ID and display name `TGCG`, national administrator with country scope.

Nginx publishes the API and administration over HTTPS while Gunicorn remains on loopback. Flutter uses `https://api.tgcg.online`; browser access is limited to the app origin. Termii SMS credentials remain to be configured.

## Web release and demo labels

- Published release: `/var/www/tgcg/releases/web-20261012-BDB3291C45FB`.
- Active release link: `/var/www/tgcg/app-current`.
- Main JavaScript SHA256: `bdb3291c45fbdf36a11cd984aedf98231468c1bbb9c9d2b3e9744c058b7c3064`.
- Build: 855 files, 53,951,645 uncompressed bytes. The served main bundle matches the compiled release.
- Release metadata: `/opt/tgcg/deployment/web-release.json`.

The app was published with the user's approved demo labels. Local and mixed operational views show a page-specific notice before their statistics. Mixed result and report views distinguish live submissions from sample totals. Role Management, Member Review, Unit Mapping, Agent Tracking and API-backed member tabs keep their live data views. The polling-agent assignment selector and sample Digital Agent ID also carry explicit notices.

The browser version keeps its offline queue in memory, so pending work does not survive a reload. PVC OCR runs on mobile, and audio-file recording is unavailable on web. Unintegrated dashboards remain demonstrations. Compilation and public HTTP checks passed; browser UI automation was unavailable in this session.

The release was built with:

```powershell
flutter build web --release --dart-define=TGCG_API_URL=https://api.tgcg.online --base-href=/ --pwa-strategy=none
```

Web entrypoints and JavaScript use `no-store`; missing assets return 404 rather than HTML. Nginx serves renderer `.wasm` files as `application/wasm`.

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

## Remaining configuration

Configure `TERMII_API_KEY` and an approved `TERMII_SENDER_ID` in the server environment before enabling phone verification. Nginx currently returns a clear 503 JSON response for SMS-code and PIN-code requests through `/etc/nginx/tgcg-sms-pending.inc`. After the real provider is configured and verified, remove those temporary locations, restart the API, test Nginx configuration and reload Nginx. No administrator phone or email was supplied.

The operational dashboards marked as demonstrations still need server integration before their totals can be used as live reports.
