#!/bin/sh
set -eu

SERVER__PORT="${UNBOUND__SERVER__PORT:-53}"
SERVER__NUM_THREADS="${UNBOUND__SERVER__NUM_THREADS:-2}"
SERVER__SO_RCVBUF="${UNBOUND__SERVER__SO_RCVBUF:-0}"
SERVER__SO_SNDBUF="${UNBOUND__SERVER__SO_SNDBUF:-0}"
SERVER__DO_NOT_QUERY_LOCALHOST="${UNBOUND__SERVER__DO_NOT_QUERY_LOCALHOST:-yes}"
FORWARD_ZONE__FORWARD_ADDR="${UNBOUND__FORWARD_ZONE__FORWARD_ADDR:-}"
FORWARD_ZONE__NAME="${UNBOUND__FORWARD_ZONE__NAME:-.}"
CONF="/etc/unbound/unbound.conf"
TEMPLATE="/etc/unbound/unbound.conf.template"

if [ -f "$TEMPLATE" ]; then
    sed \
        -e "s/__SERVER__PORT__/${SERVER__PORT}/g" \
        -e "s/__SERVER__NUM_THREADS__/${SERVER__NUM_THREADS}/g" \
        -e "s/__SERVER__SO_RCVBUF__/${SERVER__SO_RCVBUF}/g" \
        -e "s/__SERVER__SO_SNDBUF__/${SERVER__SO_SNDBUF}/g" \
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
