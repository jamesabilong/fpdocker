# PostgreSQL public access guard

Production PostgreSQL is reachable by apps as `postgres:5432` on the private
Swarm network. Do not add a production `ports` entry: Swarm ignores loopback
addresses in published-port mappings.

The separate nftables guard also blocks TCP destination port 5432 entering the
current VPS public interface, `eth0`, before Docker destination NAT. It leaves
loopback and private overlay access intact and covers IPv4 and IPv6. Update the
rule if the public interface changes. It never flushes Docker's tables.

The existing production VPS already has this guard installed and enabled.
For a new, explicitly authorized installation on the same topology, run from
this checkout as root:

```sh
bash scripts/install-postgres-guard.sh
```

The installer requires running healthy production services for comparison and
refuses existing guard files/table. It validates syntax, installs the unit and
rule, enables startup before Docker, and exercises reload without restarting
Docker or the database. Root-only snapshots go under `/var/backups/freshprice`.
Do not copy these snapshots into Git; they can contain runtime secrets.

Inspect or reload an existing installation:

```sh
sudo systemctl is-enabled freshprice-postgres-guard.service
sudo systemctl is-active freshprice-postgres-guard.service
sudo nft list table inet freshprice_pg_guard
sudo nft --check --file /etc/freshprice/postgres-public-guard.nft
sudo systemctl reload freshprice-postgres-guard.service
```

After changes, verify external 5432 denial, a **new** internal database
connection, SSH/HTTPS reachability, and application health. Reload validation
does not establish reboot recovery; the production VPS was not rebooted during
the October 21 check.

Stopping the unit leaves the rule installed. Emergency removal requires a
deliberate operator decision: disable the unit, then delete only the
`inet freshprice_pg_guard` table. That reopens any still-published database
port; prefer correcting the narrow rule while preserving protection.

Keep the guard enabled when deploying the Compose port removal. The first full
stack reconciliation will remove the live Swarm publication; monitor PostgreSQL
tasks and application database health during that deployment. This repository's
push alone does not reconcile the production stack.
