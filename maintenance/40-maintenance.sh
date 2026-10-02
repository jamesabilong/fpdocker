#!/bin/sh
set -eu
if [ "${FRESHPRICE_MAINTENANCE:-false}" = "true" ]; then
    touch /etc/nginx/maintenance.enabled
    cp /opt/freshprice-maintenance/planned.html /opt/freshprice-maintenance/index.html
else
    rm -f /etc/nginx/maintenance.enabled
fi
