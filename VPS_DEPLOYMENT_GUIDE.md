# FreshPrice VPS Deployment Guide

This guide deploys FreshPrice to the VPS with Docker Swarm and runs Sequelize
migrations without deleting the existing PostgreSQL data volume.

Production uses `docker stack deploy` with `docker-compose.prod.yml`. Do not use
`task restart`, `task up`, or plain `docker compose up` for production unless the
Compose file is changed away from Swarm-only settings. The production file uses
an `overlay` network and `deploy` settings, which are intended for Swarm.

The current backend repository and image are named `platform-backend`. In Docker
Swarm commands, the backend service is still `freshprice_backend` because Swarm
combines the stack name `freshprice` with the service name `backend`.

The current database volume uses PostgreSQL 14. Keep `postgres:14` unless you
perform a planned PostgreSQL major-version upgrade.

## 1. Connect to the VPS

```bash
ssh YOUR_USER@YOUR_SERVER_IP
cd /var/projects/freshprice/fpdocker
```

Confirm you are on the deployment host and in the Docker repository:

```bash
pwd
docker info --format '{{.Swarm.LocalNodeState}}'
```

Expected Swarm state:

```text
active
```

If Swarm is inactive on a single-node VPS, initialize it before deploying:

```bash
docker swarm init
```

## 2. Back Up PostgreSQL

Load the deployment environment variables:

```bash
set -a
source .env
set +a
```

Find the PostgreSQL container:

```bash
POSTGRES_CONTAINER="$(docker ps -q -f name=freshprice_postgres | head -n 1)"
echo "$POSTGRES_CONTAINER"
```

Do not continue if that command prints nothing.

Create a compressed backup:

```bash
mkdir -p /var/backups/freshprice

docker exec "$POSTGRES_CONTAINER" \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc \
  > "/var/backups/freshprice/freshprice-$(date +%Y%m%d-%H%M%S).dump"
```

Confirm the backup is present and not empty:

```bash
ls -lh /var/backups/freshprice
```

Do not continue if the backup file is `0B` or the command failed.

## 3. Update Repositories

Check for local changes first:

```bash
git status --short
```

Pull the latest Docker configuration:

```bash
git pull --ff-only
```

If the frontend and backend are checked out as separate repositories on the VPS,
update them too. The backend repository is `platform-backend`; `fresh-price-backend`
is an old path and should not be used for the current backend.

```bash
cd /var/projects/freshprice/platform-backend
git status --short
git pull --ff-only

cd /var/projects/freshprice/fresh-price-front
git status --short
git pull --ff-only

cd /var/projects/freshprice/fpdocker
```

If production uses prebuilt GHCR images only, pulling source repositories is
optional, but keeping `fpdocker` current is still required.

## 4. Check `.env`

Open `/var/projects/freshprice/fpdocker/.env` and confirm these values:

```env
POSTGRES_USER=your_database_user
POSTGRES_PASSWORD=your_strong_database_password
POSTGRES_DB=freshprice
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/${POSTGRES_DB}

JWT_SECRET=replace_with_a_long_random_secret
ALLOWED_ORIGINS=https://freshprice.philwatch.com

BACKEND_IMAGE_TAG=latest
FRONTEND_IMAGE_TAG=latest
SUGILANON_IMAGE_TAG=latest

SUGILANON_API_BASE_URL=https://sugilanon.philwatch.com/api
SUGILANON_SITE_URL=https://sugilanon.philwatch.com

NGINX_PORT=80
NGINX_SSL_PORT=443

DB_POOL_MAX=20
DB_POOL_MIN=2
DB_SSL=false
```

Generate a strong JWT secret when needed:

```bash
openssl rand -hex 64
```

Do not commit `.env`. Avoid a trailing slash in `ALLOWED_ORIGINS`.

If Sugilanon needs authenticated browser calls to the shared backend, include
its exact origin in `ALLOWED_ORIGINS` as a comma-separated value:

```env
ALLOWED_ORIGINS=https://freshprice.philwatch.com,https://sugilanon.philwatch.com
```

Confirm the backend log directory matches the production Compose file:

```bash
mkdir -p /var/projects/freshprice/logs/backend
```

## 5. Confirm PostgreSQL Version

Both development and production Compose files should use PostgreSQL 14:

```bash
grep -n "image: postgres" docker-compose*.yml
```

Expected result:

```text
image: postgres:14
```

Hard stop: if `docker-compose.prod.yml` renders `postgres:15`, `postgres:16`,
`postgres:17`, or `postgres:latest`, do not deploy it to the current VPS data
volume. The PostgreSQL service will fail with an incompatible data directory
because the existing volume was initialized by PostgreSQL 14.

Use this pre-deploy check:

```bash
POSTGRES_IMAGE="$(
  docker compose -f docker-compose.prod.yml --env-file .env config |
    awk '/image: postgres:/ { print $2; exit }'
)"

echo "$POSTGRES_IMAGE"
test "$POSTGRES_IMAGE" = "postgres:14"
```

Only continue when the final command exits successfully.

Do not change an existing PostgreSQL 14 volume directly to `postgres:15` or
newer. PostgreSQL major-version upgrades require a separate `pg_dump`/`pg_restore`
or `pg_upgrade` maintenance plan.

## 6. Confirm TLS Certificates

The SSL nginx config expects both domains to have LetEncrypt files mounted from
`/etc/letsencrypt`:

```text
/etc/letsencrypt/live/freshprice.philwatch.com/fullchain.pem
/etc/letsencrypt/live/sugilanon.philwatch.com/fullchain.pem
```

If the Sugilanon certificate is missing, issue it before switching nginx to
`nginx.prod.ssl.conf`:

```bash
sudo certbot certonly --standalone -d sugilanon.philwatch.com
```

Port 80 must point to the VPS and be free while standalone certbot runs. If nginx
is already using port 80, stop the frontend/nginx service briefly, issue the
certificate, then redeploy the stack.

## 7. Validate the Production Compose File

Render the production configuration with `.env`:

```bash
docker compose -f docker-compose.prod.yml --env-file .env config --quiet
```

No output means the file is valid.

Check the rendered network driver:

```bash
docker compose -f docker-compose.prod.yml --env-file .env config | grep -A2 "node-network:"
```

Expected production network:

```text
node-network:
  driver: overlay
```

Because this is an overlay network, deploy with `docker stack deploy`, not
`docker compose up`.

## 8. Pull Images

Log in if the registry is private:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

Pull the backend, frontend, and Sugilanon images:

```bash
docker pull "ghcr.io/jamesabilong/platform-backend:${BACKEND_IMAGE_TAG:-latest}"
docker pull "ghcr.io/jamesabilong/fresh-price-frontend:${FRONTEND_IMAGE_TAG:-latest}"
docker pull "ghcr.io/jamesabilong/sugilanon:${SUGILANON_IMAGE_TAG:-latest}"
```

For production, prefer commit-specific tags over `latest` so rollback targets are
clear.

## 9. Deploy the Stack

Load `.env`, then deploy:

```bash
set -a
source .env
set +a

docker stack deploy --with-registry-auth \
  -c docker-compose.prod.yml freshprice
```

The deploy workflow runs database migrations as a one-off container before
forcing the backend service to use the newly pulled image:

```text
docker run --rm --env-file .env --network freshprice_node-network ghcr.io/jamesabilong/platform-backend:latest npx sequelize-cli db:migrate
```

Already-applied migrations are skipped. If a migration fails, stop the backend
release and fix the migration issue before updating the backend service.

## 10. Monitor Services

List services:

```bash
docker stack services freshprice
```

Check detailed task status:

```bash
docker service ps freshprice_backend --no-trunc
docker service ps freshprice_postgres --no-trunc
docker service ps freshprice_frontend --no-trunc
docker service ps freshprice_sugilanon --no-trunc
```

Watch backend logs:

```bash
docker service logs -f --tail 150 freshprice_backend
```

Expected backend log shape:

```text
Sequelize CLI
Using environment "production"
... migrated
Database connection established.
Server is running on port 4000
```

Check PostgreSQL logs:

```bash
docker service logs --tail 100 freshprice_postgres
```

Expected PostgreSQL signal:

```text
database system is ready to accept connections
```

Check Sugilanon logs:

```bash
docker service logs --tail 100 freshprice_sugilanon
```

Expected Sugilanon signal:

```text
Ready
```

## 11. Verify Migrations

Find an active backend container:

```bash
BACKEND_CONTAINER="$(docker ps -q -f name=freshprice_backend | head -n 1)"
echo "$BACKEND_CONTAINER"
```

Check migration status:

```bash
docker exec "$BACKEND_CONTAINER" npx sequelize-cli db:migrate:status
```

The latest backend release should show the current migrations as `up`, including:

```text
20260609000001-separate-budget-expenses-and-add-budget-title
20260609000002-create-scheduled-sub-budgets
20260615000001-scale-budgets-and-community-prices
```

## 12. Verify Application Health

From the VPS:

```bash
curl --fail --silent \
  https://freshprice.philwatch.com/api/platform/db/health
```

Expected response:

```json
{"status":"ok","database":"ready"}
```

Verify the public site:

```bash
curl -I https://freshprice.philwatch.com
```

Verify Sugilanon:

```bash
curl -I https://sugilanon.philwatch.com
curl --fail --silent \
  https://sugilanon.philwatch.com/api/platform/db/health
```

Smoke test the main workflows in a browser:

1. Log in as a normal user.
2. Submit a market price.
3. Log in as an administrator.
4. Review the submitted price.
5. Publish the daily price.
6. Confirm the public price and statistics.
7. Confirm unauthorized users cannot modify products, markets, or users.

## 13. Troubleshooting

### `task restart` fails on the VPS

Production is Swarm-based. Use:

```bash
docker stack deploy --with-registry-auth -c docker-compose.prod.yml freshprice
```

Do not use:

```bash
ENV_MODE=prod task restart
```

The Taskfile uses `docker compose up/down`; the production Compose file uses an
`overlay` network and Swarm `deploy` settings.

### PostgreSQL files are incompatible

Error:

```text
database files are incompatible with server
The data directory was initialized by PostgreSQL version 14
```

Cause: the existing volume is PostgreSQL 14 but Compose is trying to run a newer
PostgreSQL image.

Fix `docker-compose.prod.yml`:

```yaml
image: postgres:14
```

Redeploy:

```bash
docker stack deploy -c docker-compose.prod.yml freshprice
```

Do not delete the PostgreSQL volume.

### Migration failed

Inspect backend logs:

```bash
docker service logs --tail 250 freshprice_backend
docker service ps freshprice_backend --no-trunc
```

Confirm database variables on the backend service:

```bash
docker service inspect freshprice_backend \
  --format '{{json .Spec.TaskTemplate.ContainerSpec.Env}}'
```

Common causes:

- `POSTGRES_HOST` is not `postgres`.
- the backend image does not include the latest migration files.
- a previous migration partially ran and created some database objects before failing.
- the database user lacks permission to create tables, indexes, functions, or triggers.

After correcting the cause, redeploy the stack:

```bash
docker stack deploy --with-registry-auth -c docker-compose.prod.yml freshprice
```

Or retry manually inside the current backend container:

```bash
docker run --rm \
  --env-file .env \
  --network freshprice_node-network \
  -e NODE_ENV=production \
  -e UPLOAD_DIR=/app/uploads \
  ghcr.io/jamesabilong/platform-backend:${BACKEND_IMAGE_TAG:-latest} \
  npx sequelize-cli db:migrate
```

### Backend does not become healthy

Check backend tasks and logs:

```bash
docker service ps freshprice_backend --no-trunc
docker service logs --tail 250 freshprice_backend
```

Verify PostgreSQL first:

```bash
docker service ps freshprice_postgres --no-trunc
docker service logs --tail 100 freshprice_postgres
```

Verify the health endpoint from inside a backend container:

```bash
BACKEND_CONTAINER="$(docker ps -q -f name=freshprice_backend | head -n 1)"
docker exec "$BACKEND_CONTAINER" wget -qO- http://localhost:4000/api/platform/db/health
```

### Backend image is stale

Check the image configured on the service:

```bash
docker service inspect freshprice_backend \
  --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'
```

Pull the intended tag and redeploy:

```bash
docker pull "ghcr.io/jamesabilong/platform-backend:${BACKEND_IMAGE_TAG:-latest}"
docker stack deploy --with-registry-auth -c docker-compose.prod.yml freshprice
```

### CORS errors

Set the exact frontend origin in `.env`:

```env
ALLOWED_ORIGINS=https://freshprice.philwatch.com
```

Do not add a trailing slash. Redeploy after changing `.env`.

For Sugilanon browser requests, include both production origins:

```env
ALLOWED_ORIGINS=https://freshprice.philwatch.com,https://sugilanon.philwatch.com
```

### Sugilanon does not become healthy

Check service tasks and logs:

```bash
docker service ps freshprice_sugilanon --no-trunc
docker service logs --tail 250 freshprice_sugilanon
```

Verify nginx can resolve the internal service from the frontend/nginx container:

```bash
FRONTEND_CONTAINER="$(docker ps -q -f name=freshprice_frontend | head -n 1)"
docker exec "$FRONTEND_CONTAINER" wget -qO- http://sugilanon:3000/
```

If the service is healthy internally but the domain fails, check DNS, the
LetEncrypt certificate path, and that `nginx.prod.ssl.conf` is included in the
frontend image.

## 14. Rollback

Check previous service tasks:

```bash
docker service ps freshprice_backend --no-trunc
docker service ps freshprice_frontend --no-trunc
docker service ps freshprice_sugilanon --no-trunc
```

Roll back services:

```bash
docker service rollback freshprice_backend
docker service rollback freshprice_frontend
docker service rollback freshprice_sugilanon
```

Database migrations are not automatically reversed during application rollback.
Restore the backup only when a migration damaged data or cannot remain compatible
with the previous application.

To restore into an empty replacement database:

```bash
cat /var/backups/freshprice/YOUR_BACKUP.dump | \
  docker exec -i "$(docker ps -q -f name=freshprice_postgres | head -n 1)" \
  pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists
```

Treat restore operations as destructive. Confirm the target database and backup
file before running them.

## 15. Regular Operations

- Back up PostgreSQL daily.
- Keep at least 7 daily and 4 weekly backups.
- Test restoring a backup at least monthly.
- Use commit-specific image tags instead of `latest`.
- Review `docker service logs` after every deployment.
- Run `npx sequelize-cli db:migrate:status` after backend releases.
- Keep production deployment on `docker stack deploy` while `docker-compose.prod.yml`
  uses `overlay` networking.
- Upgrade PostgreSQL major versions using a separate, tested maintenance plan.
