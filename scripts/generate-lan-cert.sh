#!/bin/sh

set -eu

if ! command -v mkcert >/dev/null 2>&1; then
    echo "mkcert is required. On macOS, install it with: brew install mkcert" >&2
    exit 1
fi

freshprice_lan_ip="${LAN_IP:-}"
if [ -z "$freshprice_lan_ip" ] && command -v ipconfig >/dev/null 2>&1; then
    freshprice_lan_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
fi
if [ -z "$freshprice_lan_ip" ] && command -v hostname >/dev/null 2>&1; then
    freshprice_lan_ip="$(hostname -I 2>/dev/null | awk '{ print $1 }' || true)"
fi
if [ -z "$freshprice_lan_ip" ]; then
    echo "Unable to detect a LAN IP. Run with LAN_IP=192.168.x.x task share" >&2
    exit 1
fi

freshprice_hostname="$(hostname -s 2>/dev/null || hostname)"
freshprice_cert_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/.certs"
mkdir -p "$freshprice_cert_dir"

mkcert \
    -cert-file "$freshprice_cert_dir/freshprice-lan.pem" \
    -key-file "$freshprice_cert_dir/freshprice-lan-key.pem" \
    localhost 127.0.0.1 ::1 "$freshprice_lan_ip" "$freshprice_hostname.local"

cp "$(mkcert -CAROOT)/rootCA.pem" "$freshprice_cert_dir/rootCA.pem"
cp "$freshprice_cert_dir/rootCA.pem" "$freshprice_cert_dir/freshprice-rootCA.crt"
cp "$freshprice_cert_dir/freshprice-lan.pem" "$freshprice_cert_dir/freshprice-lan.crt"
chmod 600 "$freshprice_cert_dir/freshprice-lan-key.pem"

echo "LAN HTTPS certificate generated for $freshprice_lan_ip."
echo "FreshPrice URL: https://$freshprice_lan_ip:${SHARE_HTTPS_PORT:-8443}"
echo "Tester CA certificate: $freshprice_cert_dir/freshprice-rootCA.crt"
echo "If this CA is not trusted on the host yet, run: mkcert -install"
echo "Share only freshprice-rootCA.crt with testers."
echo "Never share freshprice-lan-key.pem or the mkcert rootCA-key.pem file."
