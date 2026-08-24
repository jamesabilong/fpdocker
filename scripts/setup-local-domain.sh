#!/bin/sh

set -eu

freshprice_hostname="${1:-freshprice-local.com}"
hosts_file="/etc/hosts"

case "$freshprice_hostname" in
    *[!A-Za-z0-9.-]*|'')
        echo "Hostname contains unsupported characters: $freshprice_hostname" >&2
        exit 1
        ;;
esac

if [ "$(uname -s)" != "Darwin" ]; then
    echo "This setup script is intended for macOS." >&2
    exit 1
fi

if awk -v hostname="$freshprice_hostname" '
    $1 == "127.0.0.1" {
        for (field = 2; field <= NF; field++) {
            if ($field == hostname) found = 1
        }
    }
    END { exit(found ? 0 : 1) }
' "$hosts_file"; then
    echo "$freshprice_hostname is already present in $hosts_file."
else
    printf '\n127.0.0.1 %s\n' "$freshprice_hostname" | sudo tee -a "$hosts_file" >/dev/null
    echo "Added $freshprice_hostname to $hosts_file."
fi

sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true
echo "Local URL: http://${freshprice_hostname}:5173"
