# fpdocker Agent Notes

- The canonical backend repository folder is `platform-backend`.
- Do not change tracked Docker files back to `fresh-price-backend` for a local machine.
- For a machine-specific backend folder name, set `BACKEND_DIR_NAME` in `fpdocker/.env`.
- Production deploys use `docker stack deploy` with `docker-compose.prod.yml`; do not use `task restart` for the VPS production stack while the prod network driver is `overlay`.
- Keep production PostgreSQL pinned to `postgres:14` unless there is a planned major-version database upgrade.
