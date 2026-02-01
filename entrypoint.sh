#!/bin/sh
set -eu

SERVER__PORT="${UNBOUND__SERVER__PORT:-5353}"
SERVER__USERNAME="${UNBOUND__SERVER__USERNAME:-}"
SERVER__NUM_THREADS="${UNBOUND__SERVER__NUM_THREADS:-2}"
SERVER__SO_RCVBUF="${UNBOUND__SERVER__SO_RCVBUF:-0}"
SERVER__SO_SNDBUF="${UNBOUND__SERVER__SO_SNDBUF:-0}"
SERVER__DO_NOT_QUERY_LOCALHOST="${UNBOUND__SERVER__DO_NOT_QUERY_LOCALHOST:-yes}"
SERVER__VERBOSITY="${UNBOUND__SERVER__VERBOSITY:-1}"
SERVER__LOG_QUERIES="${UNBOUND__SERVER__LOG_QUERIES:-yes}"
SERVER__USE_SYSLOG="${UNBOUND__SERVER__USE_SYSLOG:-no}"
SERVER__LOGFILE="${UNBOUND__SERVER__LOGFILE:-\"\"}"
SERVER__AUTO_TRUST_ANCHOR_FILE="${UNBOUND__SERVER__AUTO_TRUST_ANCHOR_FILE:-/var/unbound/root.key}"
FORWARD_ZONE__FORWARD_ADDR="${UNBOUND__FORWARD_ZONE__FORWARD_ADDR:-}"
FORWARD_ZONE__NAME="${UNBOUND__FORWARD_ZONE__NAME:-.}"
FORWARD_ZONE__FORWARD_TLS_UPSTREAM="${UNBOUND__FORWARD_ZONE__FORWARD_TLS_UPSTREAM:-no}"
CONF="/etc/unbound/unbound.conf"
TEMPLATE="/etc/unbound/unbound.conf.template"

if [ -f "$TEMPLATE" ]; then
    esc() {
        printf '%s' "$1" | sed -e 's/[&|]/\\&/g'
    }

    sed \
        -e "s|__SERVER__USERNAME__|$(esc "$SERVER__USERNAME")|g" \
        -e "s|__SERVER__PORT__|$(esc "$SERVER__PORT")|g" \
        -e "s|__SERVER__NUM_THREADS__|$(esc "$SERVER__NUM_THREADS")|g" \
        -e "s|__SERVER__SO_RCVBUF__|$(esc "$SERVER__SO_RCVBUF")|g" \
        -e "s|__SERVER__SO_SNDBUF__|$(esc "$SERVER__SO_SNDBUF")|g" \
        -e "s|__SERVER__DO_NOT_QUERY_LOCALHOST__|$(esc "$SERVER__DO_NOT_QUERY_LOCALHOST")|g" \
        -e "s|__SERVER__VERBOSITY__|$(esc "$SERVER__VERBOSITY")|g" \
        -e "s|__SERVER__LOG_QUERIES__|$(esc "$SERVER__LOG_QUERIES")|g" \
        -e "s|__SERVER__USE_SYSLOG__|$(esc "$SERVER__USE_SYSLOG")|g" \
        -e "s|__SERVER__LOGFILE__|$(esc "$SERVER__LOGFILE")|g" \
        -e "s|__SERVER__AUTO_TRUST_ANCHOR_FILE__|$(esc "$SERVER__AUTO_TRUST_ANCHOR_FILE")|g" \
        "$TEMPLATE" > "$CONF"
fi

if [ -n "$SERVER__AUTO_TRUST_ANCHOR_FILE" ] && [ ! -f "$SERVER__AUTO_TRUST_ANCHOR_FILE" ]; then
    unbound-anchor -a "$SERVER__AUTO_TRUST_ANCHOR_FILE"
fi

if [ -n "$FORWARD_ZONE__FORWARD_ADDR" ]; then
    FORWARD_ADDR_HOST="$FORWARD_ZONE__FORWARD_ADDR"
    FORWARD_ADDR_PORT=""
    if printf '%s' "$FORWARD_ZONE__FORWARD_ADDR" | grep -q '@'; then
        FORWARD_ADDR_HOST="${FORWARD_ZONE__FORWARD_ADDR%@*}"
        FORWARD_ADDR_PORT="${FORWARD_ZONE__FORWARD_ADDR#*@}"
    fi

    if printf '%s' "$FORWARD_ADDR_HOST" | grep -Eq '^[0-9.]+$|^[0-9a-fA-F:]+$'; then
        FORWARD_ADDR_RESOLVED_HOST="$FORWARD_ADDR_HOST"
    else
        FORWARD_ADDR_RESOLVED_HOST="$(getent hosts "$FORWARD_ADDR_HOST" | awk 'NR==1{print $1}')"
        if [ -z "$FORWARD_ADDR_RESOLVED_HOST" ]; then
            echo "unable to resolve forward-addr host: $FORWARD_ADDR_HOST" >&2
            exit 1
        fi
    fi

    if [ -n "$FORWARD_ADDR_PORT" ]; then
        FORWARD_ADDR_RESOLVED="${FORWARD_ADDR_RESOLVED_HOST}@${FORWARD_ADDR_PORT}"
    else
        FORWARD_ADDR_RESOLVED="${FORWARD_ADDR_RESOLVED_HOST}"
    fi

    cat >> "$CONF" <<EOF

forward-zone:
    name: "${FORWARD_ZONE__NAME}"
    forward-addr: ${FORWARD_ADDR_RESOLVED}
    forward-tls-upstream: ${FORWARD_ZONE__FORWARD_TLS_UPSTREAM}
EOF
fi

exec /usr/sbin/unbound -d -c "$CONF"
