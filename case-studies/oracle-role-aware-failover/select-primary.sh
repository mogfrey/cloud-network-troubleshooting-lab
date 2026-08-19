#!/usr/bin/env bash
set -euo pipefail

SOCKET="${SOCKET:-/run/oracle-router/admin.sock}"
BACKEND="${BACKEND:-oracle_rw}"
ROLE_CHECK="${ROLE_CHECK:-$(dirname "$0")/check-oracle-roles.sh}"
SITE_A="${SITE_A:-172.20.10.10}"
SITE_B="${SITE_B:-172.20.20.10}"

haproxy_cmd() {
    printf '%s\n' "$1" | socat - UNIX-CONNECT:"$SOCKET" >/dev/null
}

fail_closed() {
    local reason="$1"

    echo "FAIL CLOSED: $reason"

    if [[ -S "$SOCKET" ]]; then
        printf 'set server %s/site_a state maint\n' "$BACKEND" |
            socat - UNIX-CONNECT:"$SOCKET" >/dev/null || true

        printf 'set server %s/site_b state maint\n' "$BACKEND" |
            socat - UNIX-CONNECT:"$SOCKET" >/dev/null || true
    fi

    echo "No Oracle backend is eligible for new connections."
    exit 2
}

[[ -x "$ROLE_CHECK" ]] || fail_closed "Role checker is unavailable."
[[ -S "$SOCKET" ]] || fail_closed "HAProxy runtime socket is unavailable."

if ! OUTPUT="$($ROLE_CHECK 2>&1)"; then
    printf '%s\n' "$OUTPUT"
    fail_closed "Oracle role discovery failed."
fi

printf '%s\n' "$OUTPUT"

A_PRIMARY=0
A_STANDBY=0
B_PRIMARY=0
B_STANDBY=0

if printf '%s\n' "$OUTPUT" |
   grep -Eq "^${SITE_A//./\\.}[[:space:]]+->[[:space:]]+PRIMARY([[:space:]]|$)"
then
    A_PRIMARY=1
fi

if printf '%s\n' "$OUTPUT" |
   grep -Eq "^${SITE_A//./\\.}[[:space:]]+->[[:space:]]+(PHYSICAL STANDBY|LOGICAL STANDBY|SNAPSHOT STANDBY|FAR SYNC)([[:space:]]|$)"
then
    A_STANDBY=1
fi

if printf '%s\n' "$OUTPUT" |
   grep -Eq "^${SITE_B//./\\.}[[:space:]]+->[[:space:]]+PRIMARY([[:space:]]|$)"
then
    B_PRIMARY=1
fi

if printf '%s\n' "$OUTPUT" |
   grep -Eq "^${SITE_B//./\\.}[[:space:]]+->[[:space:]]+(PHYSICAL STANDBY|LOGICAL STANDBY|SNAPSHOT STANDBY|FAR SYNC)([[:space:]]|$)"
then
    B_STANDBY=1
fi

if [[ "$A_PRIMARY" -eq 1 && "$B_STANDBY" -eq 1 ]]; then
    haproxy_cmd "set server ${BACKEND}/site_b state maint"
    haproxy_cmd "set server ${BACKEND}/site_a state ready"
    echo "ACTIVE ROUTE: $SITE_A"

elif [[ "$B_PRIMARY" -eq 1 && "$A_STANDBY" -eq 1 ]]; then
    haproxy_cmd "set server ${BACKEND}/site_a state maint"
    haproxy_cmd "set server ${BACKEND}/site_b state ready"
    echo "ACTIVE ROUTE: $SITE_B"

else
    fail_closed "Could not prove exactly one PRIMARY and one STANDBY."
fi
