# FreshPrice Docker Constitution

> **Authority**: This document is the non-negotiable source of truth for all Docker-related
> decisions in this repository. Any spec, plan, or task that conflicts with a **MUST** rule
> below is invalid and must be corrected before implementation proceeds.

---

## 1. Project Identity

| Property | Value |
|---|---|
| Project | FreshPrice (`fpdocker`) |
| Stack | Node 20 / Vite frontend · Node 20 / Express backend · PostgreSQL 14 · Nginx |
| Environments | `development` (docker-compose.yml) · `production` (docker-compose.prod.yml) |
| Domain (prod) | `freshprice.philwatch.com` |
| Internal network | `node-network` (bridge) |

---

## 2. Core Principles

### I. Environment Parity

- **MUST** maintain a strict separation between development and production configurations.
  Dev compose files MUST NOT be used to deploy to production and vice-versa.
- **MUST** set `NODE_ENV` explicitly on every service that runs Node.js:
  `development` in dev compose, `production` in prod compose. No other values are valid.

### II. Secret & Configuration Management

- **MUST** supply all secrets (passwords, JWT keys, database URLs, allowed origins) via
  environment variables. Secrets MUST NOT be hardcoded in any Dockerfile, compose file, or
  nginx config.
- **MUST** source secrets from `.env` files (via `env_file:` or shell substitution) and
  MUST NOT commit `.env` files to version control.
- **MUST** expose only the environment variables a service actually needs. No service
  receives another service's secrets.
  - `JWT_SECRET` and `ALLOWED_ORIGINS` belong exclusively to the backend service.

### III. Image Hygiene

- **MUST** pin all base images to a specific version tag. `latest` is forbidden.
  - Node images: `node:20-alpine`
  - PostgreSQL: `postgres:14`
  - Nginx: `nginx:alpine`
- **MUST** use `alpine`-based variants. Switching to a Debian/full image requires a
  documented comment explaining the necessity.
- **MUST** use multi-stage builds in `Dockerfile.prod` so no dev tooling, source maps, or
  build-time dependencies are included in production images.

### IV. Dependency Installation

- **MUST** use `npm ci` (not `npm install`) in every production `RUN` layer to guarantee
  reproducible installs from a locked `package-lock.json`.
- **MUST** copy `package*.json` before the `npm ci` layer so Docker layer caching is
  preserved across source-only changes.
- **SHOULD** use `npm install` only in development `command:` overrides (volume-mounted
  source), never in `RUN` layers of production Dockerfiles.

### V. Networking

- **MUST** place all services on the `node-network` bridge network.
- **MUST NOT** use `network_mode: host` in any service.
- External port exposure (`ports:`) MUST follow environment rules:
  - **Development**: frontend (5173) and backend (4000) ports may be exposed.
  - **Production**: only the Nginx port is exposed publicly. Backend (4000) and postgres
    ports MUST NOT be publicly accessible in production.

### VI. Persistence & Volumes

- **MUST** use named volumes (`postgres-data`, `postgres-logs`) for all PostgreSQL data.
  Bind-mounts for database data are forbidden.
- **MUST NOT** mount host `node_modules` into production containers. The
  `/app/node_modules` volume override is only valid in development bind-mount services.
- **MUST** declare all named volumes under the top-level `volumes:` key of the compose
  file.

### VII. Logging

- **MUST** configure the `json-file` logging driver on every service with the following
  caps (or tighter):
  ```yaml
  logging:
    driver: "json-file"
    options:
      max-size: "10m"
      max-file: "3"
  ```
- Alternate log drivers (e.g., `gelf`, `syslog`) may be added in production but MUST
  retain the size caps to prevent disk exhaustion.

### VIII. Health Checks

- **MUST** define a `healthcheck` on the `postgres` service using `pg_isready`.
- **SHOULD** wire `depends_on` with `condition: service_healthy` on the backend so it
  waits for a healthy database before starting.
- **SHOULD** add a `/health` endpoint to the backend and a corresponding `healthcheck`
  once the endpoint exists.

### IX. Restart Policy

- **MUST** set `restart: always` on all services in production (`postgres`, `nginx`,
  `backend` in `docker-compose.prod.yml`).
- **MUST** use `restart: unless-stopped` (or omit `restart`) in development so containers
  do not auto-restart during active debugging sessions.

### X. Nginx Configuration

**Development (`nginx.conf`)**
- **MUST** proxy `location /` to the Vite dev server (`fresh-price-front:5173`) to support
  Hot Module Replacement.
- **MUST** proxy `location /api/` to the backend (`fresh-price-backend:4000`).
- **MUST** forward `Host`, `X-Real-IP`, `X-Forwarded-For`, and `X-Forwarded-Proto` headers
  on every `proxy_pass` block.

**Production (`nginx.prod.conf`)**
- **MUST** include `include /etc/nginx/mime.types` and set `default_type
  application/octet-stream` so static assets are served with correct Content-Type headers.
- **MUST** serve the built SPA from `/usr/share/nginx/html` with `try_files $uri $uri/
  /index.html` under `location /` to support client-side routing.
- **MUST** proxy `location /api/` to the backend upstream.
- **MUST** set `server_name` to `freshprice.philwatch.com`.
- **SHOULD** enable `gzip on` with `gzip_types` for JS, CSS, JSON, and SVG assets.

### XI. Build Context

- **MUST** set the Docker build context to the monorepo root (`context: ..`) so Dockerfiles
  can reference sibling directories (`fresh-price-front/`, `fresh-price-backend/`).
- **MUST NOT** reference files outside the declared build context.

### XII. Security Hardening (SHOULD — escalates to MUST before first public release)

- **SHOULD** run all Node.js processes as a non-root user (`USER node` after `WORKDIR` in
  production stages; `node` user is built into `node:alpine`).
- **SHOULD** set `read_only: true` on the nginx container filesystem with `tmpfs` mounts
  for `/var/cache/nginx` and `/var/run`.
- **SHOULD** drop unnecessary Linux capabilities on backend and nginx containers.

---

## 3. Service Responsibilities

| Service | Development role | Production role |
|---|---|---|
| `frontend` / `nginx` | Vite HMR dev server (port 5173) | Nginx static file server + API proxy (port 80) |
| `backend` | Node dev server with hot-reload (port 4000, exposed) | Compiled Node server (port 4000, internal only) |
| `postgres` | Local DB (port exposed for tooling) | DB (port internal only) |

---

## 4. Quality Gates

Before any change is merged:

1. **Validate**: `docker compose -f docker-compose.yml config` and
   `docker compose -f docker-compose.prod.yml config` MUST exit 0.
2. **Build**: `docker compose build` MUST complete without error in both environments.
3. **Health**: `postgres` container MUST reach `healthy` within 60 s of startup in CI.
4. **Secret scan**: No `.env` values (passwords, keys) may appear in committed files.

---

## Governance

- This constitution supersedes all other practices and documentation in this repository.
- **Constitution amendments** require a standalone, explicitly reasoned commit. Amendments
  MUST NOT be bundled with feature work.
- All pull requests MUST be reviewed for compliance with Section 2 MUST rules before merge.
- Any violation of a MUST rule discovered during review blocks the PR until resolved.

**Version**: 1.0.0 | **Ratified**: 2026-02-24 | **Last Amended**: 2026-02-24
