#!/usr/bin/env bash
# Operator-authorized, single-VPS firewall installation; no Docker/service restart.
set -Eeuo pipefail
umask 077
[[ $EUID == 0 ]]
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
audit="/var/backups/freshprice/pg-guard-install-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -m 700 -p "$audit"
[[ -x /usr/sbin/nft ]]
ip -4 route show default | grep -Eq 'dev eth0( |$)'
[[ ! -e /etc/freshprice/postgres-public-guard.nft ]]
[[ ! -e /etc/systemd/system/freshprice-postgres-guard.service ]]
if nft list table inet freshprice_pg_guard >/dev/null 2>&1; then
  printf 'Refusing to overwrite an existing guard table.\n' >&2; exit 1
fi
docker service inspect freshprice_postgres freshprice_backend freshprice_frontend freshprice_sugilanon >"$audit/services-before.json"
docker ps -q | xargs -r docker inspect >"$audit/containers-before.json"
nft list ruleset >"$audit/nft-before.txt"
nft --check --file "$source_root/firewall/postgres-public-guard.nft"
systemd-analyze verify "$source_root/firewall/freshprice-postgres-guard.service"
install -d -m 700 /etc/freshprice
install -m 600 "$source_root/firewall/postgres-public-guard.nft" /etc/freshprice/postgres-public-guard.nft
install -m 644 "$source_root/firewall/freshprice-postgres-guard.service" /etc/systemd/system/freshprice-postgres-guard.service
systemctl daemon-reload
systemctl enable --now freshprice-postgres-guard.service
systemctl is-enabled freshprice-postgres-guard.service
systemctl is-active freshprice-postgres-guard.service
# Reapplying only this guard exercises idempotence without restarting Docker.
systemctl reload freshprice-postgres-guard.service
nft list table inet freshprice_pg_guard
docker service inspect freshprice_postgres freshprice_backend freshprice_frontend freshprice_sugilanon >"$audit/services-after.json"
docker ps -q | xargs -r docker inspect >"$audit/containers-after.json"
python3 - "$audit" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1])
before=json.loads((p/'services-before.json').read_text())
after=json.loads((p/'services-after.json').read_text())
assert {s['ID']:s['Spec'] for s in before} == {s['ID']:s['Spec'] for s in after}, 'Service definition changed'
b={c['Id']:c for c in json.loads((p/'containers-before.json').read_text())}
a={c['Id']:c for c in json.loads((p/'containers-after.json').read_text())}
assert b.keys()==a.keys(), 'Running container identities changed'
for cid,c in b.items():
 assert a[cid]['Image']==c['Image'], 'Image changed'
 if c['State'].get('Health',{}).get('Status')=='healthy':
  assert a[cid]['State'].get('Health',{}).get('Status')=='healthy', 'Container unhealthy'
print('PASS: all production service definitions/container images/identities unchanged; health preserved')
PY
printf 'Protected installation evidence: %s\n' "$audit"
