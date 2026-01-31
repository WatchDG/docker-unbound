#!/bin/sh
set -eu

SERVER__PORT="${UNBOUND__SERVER__PORT:-53}"
SERVER__DO_NOT_QUERY_LOCALHOST="${UNBOUND__SERVER__DO_NOT_QUERY_LOCALHOST:-yes}"
FORWARD_ZONE__FORWARD_ADDR="${UNBOUND__FORWARD_ZONE__FORWARD_ADDR:-}"
FORWARD_ZONE__NAME="${UNBOUND__FORWARD_ZONE__NAME:-.}"
CONF="/etc/unbound/unbound.conf"
TEMPLATE="/etc/unbound/unbound.conf.template"

if [ -f "$TEMPLATE" ]; then
    sed \
        -e "s/__SERVER__PORT__/${SERVER__PORT}/g" \
        -e "s/__SERVER__DO_NOT_QUERY_LOCALHOST__/${SERVER__DO_NOT_QUERY_LOCALHOST}/g" \
        "$TEMPLATE" > "$CONF"
fi

if [ -n "$FORWARD_ZONE__FORWARD_ADDR" ]; then
    cat >> "$CONF" <<EOF

forward-zone:
    name: "${FORWARD_ZONE__NAME}"
    forward-addr: ${FORWARD_ZONE__FORWARD_ADDR}
EOF
fi

exec /usr/sbin/unbound -d -c "$CONF"
