# Backend Tunnel Deployment

This directory documents the repo-owned production-style split deployment:

- `www.kapi-net.com` -> Cloudflare Pages
- `kapi-net.com` -> Cloudflare Redirect Rule -> `https://www.kapi-net.com`
- `api.kapi-net.com` -> Cloudflare Tunnel -> `app_api`
- `panel.kapi-net.com` -> Cloudflare Tunnel -> `xboard-web`
- `panel.kapi-net.com/ws` -> Cloudflare Tunnel -> `xboard-ws-server`

## Root Redirect

For the root domain redirect, keep two Cloudflare-side pieces:

- proxied `A` record: `kapi-net.com -> 192.0.2.1`
- Redirect Rule:

```txt
if: http.host eq "kapi-net.com"
then: concat("https://www.kapi-net.com", http.request.uri.path)
status: 301
preserve query string: on
```

Practical rule:

- the proxied placeholder `A` record is required so the request reaches Cloudflare edge
- do not point the root domain at the backend server IP just to achieve the redirect

## Local Build

Build the web bundle for Pages with the dedicated API domain:

```bash
APP_CONFIG_URLS= \
APP_API_DEFAULT_DOMAIN="https://api.kapi-net.com" \
bash scripts/build_web_release.sh
```

Upload `build/web` to the Pages project, or zip it first and upload the archive.

Build output expectations:

- `build/web/index.html` loads `flutter_bootstrap.js?v=<build_id>`
- `build/web/flutter_bootstrap.js` loads `main.dart.js?v=<build_id>`
- `build/web/_headers` exists and comes from `web/_headers`

## Pages Deploy

Prefer a repo-owned Pages deploy instead of manual dashboard upload:

```bash
CLOUDFLARE_ACCOUNT_ID='<cloudflare-account-id>'
CLOUDFLARE_API_TOKEN='<pages-edit-token>'
API_DOMAIN=api.kapi-net.com
PAGES_PROJECT_NAME=capybara-web-prod
PAGES_BRANCH=main
bash scripts/deploy_pages_frontend.sh
```

Practical rule:

- the script rebuilds `build/web` with `APP_API_DEFAULT_DOMAIN=https://api.kapi-net.com`
- the script also prepares `/tmp/capybara-web-prod-pages.zip` for manual fallback upload
- required token scope is the minimum needed to edit Pages for this account
- set `PAGES_BRANCH=main` so the deploy updates the production environment instead of creating a preview from the current local git branch
- if `/Users/frank/Desktop/flux/.runtime/production/cloudflare-prod.env` exists, the script auto-loads Cloudflare credentials from there

Dashboard fallback:

- if Cloudflare Pages upload in the browser is healthy, upload `build/web` or the prepared zip
- if the dashboard render is unstable, use the script with a scoped API token instead

## Pages Cache Strategy

Repo-owned cache policy for the Pages frontend now lives in:

- `/Users/frank/Desktop/flux/web/_headers`

Current production cache rules:

- `/` and `/index.html` -> `Cache-Control: public, max-age=0, must-revalidate`
- `/flutter_bootstrap.js` -> `Cache-Control: public, max-age=31536000, immutable`
- `/main.dart.js` -> `Cache-Control: public, max-age=31536000, immutable`
- `/assets/*`, `/canvaskit/*`, `/icons/*`, `/manifest.json`, `/favicon.png` -> `Cache-Control: public, max-age=31536000, immutable`

Practical rule:

- keep `index.html` short-cached so the latest deploy can switch bundle versions immediately
- keep the heavy static assets immutable because `scripts/build_web_release.sh` already appends `?v=<build_id>` to the bootstrap and main bundle URLs
- do not rely on manual dashboard header edits as the source of truth

Verification pattern after build or deploy:

- confirm `build/web/_headers` exists
- confirm `index.html` references `flutter_bootstrap.js?v=<build_id>`
- confirm `flutter_bootstrap.js` references `main.dart.js?v=<build_id>`

## Web First Render Rule

For mainland access, phase one is now explicitly "static-first":

- `www.kapi-net.com` must render its shell before waiting on `api.kapi-net.com`
- web auth bootstrap must not block first paint on `RemoteConfigService`
- if a local session token exists, the web app may enter the shell first and validate the session in the background
- the home page should render a static loading frame immediately, then hydrate notices and subscription data asynchronously

Practical rule:

- keep `api.kapi-net.com` and the Tunnel topology unchanged in phase one
- do not add new first-paint dependencies outside the Pages bundle
- treat the web shell and home page skeleton as the acceptance path for "page visible before API"

## App API Edge Cache Rule

Stage-one API caching is intentionally narrow:

- cache only `GET https://api.kapi-net.com/api/app/v1/public/config`
- do not cache `GET /api/app/v1/catalog/plans` yet because the same route serves both guest and authenticated flows

Repo behavior:

- `backend/app_api` now returns:
  - `Cache-Control: public, s-maxage=60, stale-while-revalidate=300`
  - only on anonymous `GET /api/app/v1/public/config`

Cloudflare rule to add manually:

```txt
if: http.host eq "api.kapi-net.com"
and http.request.method eq "GET"
and http.request.uri.path eq "/api/app/v1/public/config"
```

Rule action:

- cache eligible: on
- origin cache control: on

Practical rule:

- keep the rule scoped to the exact host, method, and path
- do not broaden the rule to `/api/app/*` in phase one

## CloudflareSpeedTest And BestWorkers Positioning

Current production stance:

- `CloudflareSpeedTest` is a measurement tool only
- do not write CloudflareSpeedTest IP results into production DNS for `www.kapi-net.com` or `api.kapi-net.com`
- `BestWorkers` remains a phase-two fallback for the `www.kapi-net.com` frontend entry only

Phase-two trigger:

- only consider `BestWorkers` after the stage-one cache changes run stably for 48 hours
- only proceed if the remaining bottleneck is still the China-mainland `www` static entry, not `api.kapi-net.com`
- phase two must not change `api.kapi-net.com`, `panel.kapi-net.com`, or the Tunnel topology

Suggested baseline commands:

```bash
./CloudflareST -httping -dd -tl 300 -url https://www.kapi-net.com/ -httping-code 200
./CloudflareST -httping -dd -tl 500 -url https://api.kapi-net.com/api/app/v1/public/config -httping-code 200
```

## Backend Deploy

Required local env when deploying:

```bash
BACKEND_HOST=root@178.104.115.63
API_DOMAIN=api.kapi-net.com
PANEL_DOMAIN=panel.kapi-net.com
ADMIN_ACCOUNT=admin@demo.com
ADMIN_PASSWORD='<set-a-real-password>'
TUNNEL_TOKEN='<cloudflare-tunnel-token>'
```

Run:

```bash
bash scripts/deploy_backend_tunnel.sh
```

Default database mode is MySQL in Docker:

- `mysql:8.4` runs inside `docker/backend-tunnel.compose.yaml`
- persistent volume: `xboard-mysql-data`
- local repeatable secrets file: `.runtime/production/backend-db.env`
- `RESET_DATA=1` destroys the Docker MySQL volume and rebuilds schema from scratch

The deploy script now bootstraps Xboard without editing upstream code:

- creates a pre-deploy MySQL dump and downloads it into `.local/backend-mysql-backups`
- keeps only the newest 3 local MySQL backup directories by default
- prepares `.runtime/backend/xboard.env`
- starts `mysql` and `redis`
- runs `scripts/bootstrap_xboard.php` inside the Xboard container
- migrates schema, ensures the admin account exists, restores protected plugins, installs default plugins
- resets the admin password through `scripts/reset_xboard_admin_password.php`
- reapplies app/mail/ws settings and starts the long-running services

Optional local secret file for repeatable deploys:

```bash
.runtime/production/cloudflare-prod.env
```

Supported keys in that file:

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN`
- `TUNNEL_TOKEN`

Standalone backup command:

```bash
BACKEND_HOST=root@178.104.115.63 bash scripts/backup_backend_mysql.sh
```

Optional backup knobs:

- `LOCAL_BACKUP_ROOT` defaults to `.local/backend-mysql-backups`
- `LOCAL_BACKUP_KEEP` defaults to `3`
- `DEPLOY_PATH` defaults to `/opt/capybara-backend`
- `BACKUP_BEFORE_DEPLOY=0` disables the automatic pre-deploy backup step

## Fresh-Machine Rule

The deploy script assumes the backend host can be reset at any time. The script therefore must:

- install `docker.io` and `docker-compose-v2` if missing
- recreate runtime env under `.runtime/backend`
- start `mysql` and `redis` first
- run the repo-owned bootstrap helper as a one-off container
- reset the admin password
- reapply runtime `APP_URL` and `SERVER_WS_URL`
- only then start long-running `xboard-web`, `xboard-horizon`, `xboard-ws-server`, `app-api`, and `cloudflared`

## Important Pitfall

Do not patch `upstreams/xboard` just to automate MySQL installation.

Practical rule:

- keep automation in repo-owned scripts under `scripts/`
- treat `.runtime/production/backend-db.env` as the source of truth for MySQL credentials
- if you intentionally want a clean backend, set `RESET_DATA=1`
