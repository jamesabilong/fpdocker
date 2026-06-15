# FreshPrice VPS Deployment Guide

This guide deploys the latest FreshPrice changes and runs the PostgreSQL
migrations without deleting the existing database.

The current database volume uses PostgreSQL 14. Keep `postgres:14` unless you
perform a planned PostgreSQL major-version upgrade.

## 1. Connect to the VPS

```bash
ssh YOUR_USER@YOUR_SERVER_IP
```

Move to the Docker repository:

```bash
cd /var/projects/freshprice/fpdocker
```

## 2. Back Up PostgreSQL

Check the stack and locate the PostgreSQL container:

```bash
docker ps --filter name=freshprice_postgres
```

Create a backup directory:

```bash
mkdir -p /var/backups/freshprice
```

Load the deployment environment variables:

```bash
set -a
source .env
set +a
```

Create a compressed database backup:

```bash
docker exec "$(docker ps -q -f name=freshprice_postgres)" \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc \
  > "/var/backups/freshprice/freshprice-$(date +%Y%m%d-%H%M%S).dump"
```

Confirm that the backup is not empty:

```bash
ls -lh /var/backups/freshprice
```

Do not continue if the backup file is empty or the command failed.

## 3. Update the Repository

Check for local changes first:

```bash
git status
```

Pull the latest Docker configuration:

```bash
git pull --ff-only
```

If the backend and frontend are separate repositories, update them as well:

```bash
cd /var/projects/freshprice/fresh-price-backend
git pull --ff-only

cd /var/projects/freshprice/fresh-price-front
git pull --ff-only

cd /var/projects/freshprice/fpdocker
```

## 4. Check the Environment File

Open `.env` and confirm these values:

```env
POSTGRES_USER=your_database_user
POSTGRES_PASSWORD=your_strong_database_password
POSTGRES_DB=freshprice
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

JWT_SECRET=replace_with_a_long_random_secret
ALLOWED_ORIGINS=https://freshprice.philwatch.com

BACKEND_IMAGE_TAG=latest
FRONTEND_IMAGE_TAG=latest

DB_POOL_MAX=20
DB_POOL_MIN=2
DB_SSL=false
```

Generate a strong JWT secret when needed:

```bash
openssl rand -hex 64
```

Do not commit `.env`.

## 5. Confirm the PostgreSQL Version

Both development and production Compose files should use PostgreSQL 14:

```bash
grep -n "image: postgres" docker-compose*.yml
```

Expected result:

```text
image: postgres:14
```

Do not change an existing PostgreSQL 14 volume directly to `postgres:15`.
PostgreSQL major-version upgrades require `pg_dump`/`pg_restore` or
`pg_upgrade`.

## 6. Validate the Compose File

```bash
docker compose -f docker-compose.prod.yml config --quiet
```

No output means the configuration is valid.

For Docker Swarm, also verify that the node is active:

```bash
docker node ls
```

## 7. Pull or Build the Images

When using images from GitHub Container Registry:

```bash
docker pull "ghcr.io/jamesabilong/platform-backend:${BACKEND_IMAGE_TAG:-latest}"
docker pull "ghcr.io/jamesabilong/fresh-price-frontend:${FRONTEND_IMAGE_TAG:-latest}"
```

If the registry is private, log in first:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

## 8. Deploy the Production Stack

Load `.env`, then deploy:

```bash
set -a
source .env
set +a

docker stack deploy --with-registry-auth \
  -c docker-compose.prod.yml freshprice
```

The backend startup command runs:

```text
npx sequelize-cli db:migrate
```

before starting Node.js. Already-applied migrations are skipped.

## 9. Monitor the Migration and Services

List the services:

```bash
docker stack services freshprice
```

Watch the backend:

```bash
docker service logs -f --tail 100 freshprice_backend
```

Look for output similar to:

```text
Sequelize CLI
Using environment "production"
... migrated
Database connection established.
Server is running on port 4000
```

Press `Ctrl+C` to stop following the logs.

Check PostgreSQL:

```bash
docker service logs --tail 100 freshprice_postgres
```

Expected result:

```text
database system is ready to accept connections
```

## 10. Verify the Migration

Find the active backend container:

```bash
BACKEND_CONTAINER="$(docker ps -q -f name=freshprice_backend | head -n 1)"
echo "$BACKEND_CONTAINER"
```

Check migration status:

```bash
docker exec "$BACKEND_CONTAINER" npx sequelize-cli db:migrate:status
```

The required migration should show as `up`:

```text
20260615000001-scale-budgets-and-community-prices
```

## 11. Verify Application Health

From the VPS:

```bash
curl --fail --silent \
  https://freshprice.philwatch.com/api/platform/db/health
```

Expected response:

```json
{"status":"ok","database":"ready"}
```

Also verify the public application:

```bash
curl -I https://freshprice.philwatch.com
```

Test these workflows in the browser:

1. Log in as a normal user.
2. Submit a market price.
3. Log in as an administrator.
4. Review the submitted price.
5. Publish the daily price.
6. Confirm the public price and statistics.
7. Confirm unauthorized users cannot modify products, markets, or users.

## 12. Troubleshooting

### PostgreSQL files are incompatible

Error:

```text
database files are incompatible with server
The data directory was initialized by PostgreSQL version 14
```

Cause: the existing volume is PostgreSQL 14 but Compose uses PostgreSQL 15.

Fix:

```yaml
image: postgres:14
```

Then redeploy:

```bash
docker stack deploy -c docker-compose.prod.yml freshprice
```

Do not delete the PostgreSQL volume.

### Migration failed

Inspect backend logs:

```bash
docker service logs --tail 200 freshprice_backend
```

Confirm database variables:

```bash
docker service inspect freshprice_backend \
  --format '{{json .Spec.TaskTemplate.ContainerSpec.Env}}'
```

Retry the migration after correcting the problem:

```bash
BACKEND_CONTAINER="$(docker ps -q -f name=freshprice_backend | head -n 1)"
docker exec "$BACKEND_CONTAINER" npx sequelize-cli db:migrate
```

### Backend does not become healthy

```bash
docker service ps freshprice_backend --no-trunc
docker service logs --tail 200 freshprice_backend
```

Verify PostgreSQL first:

```bash
docker service ps freshprice_postgres
docker service logs --tail 100 freshprice_postgres
```

### CORS errors

Set the exact frontend origin in `.env`:

```env
ALLOWED_ORIGINS=https://freshprice.philwatch.com
```

Do not add a trailing slash.

Redeploy after changing `.env`.

## 13. Rollback

Check previous service tasks:

```bash
docker service ps freshprice_backend --no-trunc
```

Roll back the backend image:

```bash
docker service rollback freshprice_backend
```

Roll back the frontend image:

```bash
docker service rollback freshprice_frontend
```

Database migrations are not automatically reversed during an application
rollback. Restore the backup only when a migration damaged data or cannot
remain compatible with the previous application.

To restore into an empty replacement database:

```bash
cat /var/backups/freshprice/YOUR_BACKUP.dump | \
  docker exec -i "$(docker ps -q -f name=freshprice_postgres | head -n 1)" \
  pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists
```

Treat restore operations as destructive. Confirm the target database and
backup file before running them.

## 14. Regular Operations

Recommended minimum production schedule:

- Back up PostgreSQL daily.
- Keep at least 7 daily and 4 weekly backups.
- Test restoring a backup at least monthly.
- Use commit-specific image tags instead of `latest`.
- Review `docker service logs` after every deployment.
- Run migration status checks after backend releases.
- Upgrade PostgreSQL major versions using a separate, tested maintenance plan.
