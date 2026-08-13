# fpdocker Agent Notes

- The canonical backend repository folder is `platform-backend`.
- Do not change tracked Docker files back to `fresh-price-backend` for a local machine.
- For a machine-specific backend folder name, set `BACKEND_DIR_NAME` in `fpdocker/.env`.
- Production deploys use `docker stack deploy` with `docker-compose.prod.yml`; do not use `task restart` for the VPS production stack while the prod network driver is `overlay`.
- Keep production PostgreSQL pinned to `postgres:14` unless there is a planned major-version database upgrade.
- Production deploy automation is driven by `repository_dispatch` events, not by direct `fpdocker` pushes.
- App dispatch event names are `frontend-updated`, `backend-updated`, and `sugilanon-updated`.
- Push `fpdocker` `master` before triggering an app dispatch when Docker, Compose, nginx, or deploy workflow files changed; the VPS deploy step runs `git pull --ff-only origin master`.
- Backend-only dispatches should run migrations and update `freshprice_backend` directly once the backend service exists; do not redeploy the full stack because that can fail on unrelated missing images such as Sugilanon.
- Production nginx proxy targets and server-side app API defaults must use the Swarm service name `http://freshprice_backend:4000`, not `http://backend:4000`. The `backend` alias is acceptable only for local Compose/dev-network settings.
- Manual dispatches target `https://api.github.com/repos/jamesabilong/fpdocker/dispatches` and require a token with permission to dispatch workflows in `jamesabilong/fpdocker`.
- The production frontend healthcheck should probe `http://127.0.0.1/`, not `http://localhost/`, because the VPS Swarm task previously served traffic but failed the `localhost` probe and was stopped.
- The production backend healthcheck should probe `http://127.0.0.1:4000/api/platform/db/health`, not `http://localhost:4000/api/platform/db/health`, for the same Swarm healthcheck behavior.
- The production Sugilanon healthcheck should probe `http://127.0.0.1:3000/`, not `http://localhost:3000/`, for the same Swarm healthcheck behavior.
