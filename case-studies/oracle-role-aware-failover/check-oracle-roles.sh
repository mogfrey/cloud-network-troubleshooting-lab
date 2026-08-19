#!/usr/bin/env bash
set -euo pipefail

# Synthetic example configuration. Replace through deployment tooling,
# environment variables or a root-owned configuration file.
VAULT_URL="${VAULT_URL:-https://kv-shared-prod.vault.azure.net}"
SECRET_NAME="${SECRET_NAME:-APP_RW_PASSWORD}"
SQLPLUS="${SQLPLUS:-/opt/oracle/instantclient/sqlplus}"
DBUSER="${DBUSER:-APP_RW_USER}"
SERVICE="${SERVICE:-APPDB}"
PORT="${PORT:-1521}"
SITE_A="${SITE_A:-172.20.10.10}"
SITE_B="${SITE_B:-172.20.20.10}"

for bin in curl jq expect timeout; do
    command -v "$bin" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $bin" >&2
        exit 1
    }
done

[[ -x "$SQLPLUS" ]] || {
    echo "ERROR: SQL*Plus not executable at $SQLPLUS" >&2
    exit 1
}

PASSFILE="$(mktemp /run/oracle-router-password.XXXXXX)"
chmod 600 "$PASSFILE"

cleanup() {
    rm -f "$PASSFILE"
}
trap cleanup EXIT

get_token() {
    curl -fsS \
      --noproxy "*" \
      -H Metadata:true \
      "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net" \
    | jq -r '.access_token'
}

get_password() {
    local token="$1"

    curl -fsS \
      -H "Authorization: Bearer ${token}" \
      "${VAULT_URL}/secrets/${SECRET_NAME}?api-version=7.4" \
    | jq -r '.value'
}

check_db() {
    local host="$1"

    ORACLE_ROLE_HOST="$host" \
    ORACLE_ROLE_PASSFILE="$PASSFILE" \
    ORACLE_ROLE_SQLPLUS="$SQLPLUS" \
    ORACLE_ROLE_USER="$DBUSER" \
    ORACLE_ROLE_SERVICE="$SERVICE" \
    ORACLE_ROLE_PORT="$PORT" \
    /usr/bin/expect <<'EXPECT'
set timeout 20
log_user 0

set host $env(ORACLE_ROLE_HOST)
set passfile $env(ORACLE_ROLE_PASSFILE)
set sqlplus $env(ORACLE_ROLE_SQLPLUS)
set dbuser $env(ORACLE_ROLE_USER)
set service $env(ORACLE_ROLE_SERVICE)
set port $env(ORACLE_ROLE_PORT)

set fh [open $passfile r]
set password [string trimright [read $fh] "\r\n"]
close $fh

spawn $sqlplus -L "$dbuser@//$host:$port/$service"

expect {
    -re {Enter password:} {
        send -- "$password\r"
    }
    -re {(ORA-[0-9]+:[^\r\n]+)} {
        puts "__ROLE_ERROR__|$host|$expect_out(1,string)"
        exit 2
    }
    timeout {
        puts "__ROLE_ERROR__|$host|PASSWORD_PROMPT_TIMEOUT"
        exit 2
    }
    eof {
        puts "__ROLE_ERROR__|$host|EARLY_EOF"
        exit 2
    }
}

unset password

expect {
    -re {SQL>} {
        send -- "SET HEADING OFF\r"
        send -- "SET FEEDBACK OFF\r"
        send -- "SET PAGESIZE 0\r"
        send -- "SET VERIFY OFF\r"
        send -- "SET ECHO OFF\r"
        send -- "SELECT '__ROLE_RESULT__|' || SYS_CONTEXT('USERENV','DATABASE_ROLE') || '|' || SYS_CONTEXT('USERENV','DB_UNIQUE_NAME') || '|' || SYS_CONTEXT('USERENV','SERVER_HOST') || '|' || SYS_CONTEXT('USERENV','SERVICE_NAME') FROM dual;\r"
    }
    -re {(ORA-[0-9]+:[^\r\n]+)} {
        puts "__ROLE_ERROR__|$host|$expect_out(1,string)"
        exit 3
    }
    timeout {
        puts "__ROLE_ERROR__|$host|SQL_PROMPT_TIMEOUT"
        exit 3
    }
    eof {
        puts "__ROLE_ERROR__|$host|LOGIN_FAILED"
        exit 3
    }
}

expect {
    -re {__ROLE_RESULT__\|(PRIMARY|PHYSICAL STANDBY|LOGICAL STANDBY|SNAPSHOT STANDBY|FAR SYNC)\|([^|\r\n]+)\|([^|\r\n]+)\|([^|\r\n]+)} {
        puts "__ROLE_RESULT__|$host|$expect_out(1,string)|$expect_out(2,string)|$expect_out(3,string)|$expect_out(4,string)"
        send -- "EXIT\r"
        expect eof
        exit 0
    }
    -re {(ORA-[0-9]+:[^\r\n]+)} {
        puts "__ROLE_ERROR__|$host|$expect_out(1,string)"
        exit 4
    }
    timeout {
        puts "__ROLE_ERROR__|$host|QUERY_TIMEOUT"
        exit 4
    }
    eof {
        puts "__ROLE_ERROR__|$host|QUERY_FAILED"
        exit 4
    }
}
EXPECT
}

TOKEN="$(get_token)"
get_password "$TOKEN" > "$PASSFILE"
unset TOKEN

echo "Oracle role discovery"

for HOST in "$SITE_A" "$SITE_B"; do
    RESULT="$(check_db "$HOST" || true)"

    if [[ "$RESULT" == __ROLE_RESULT__* ]]; then
        IFS='|' read -r _ IP ROLE DBUNIQUE SERVER SERVICE_NAME <<< "$RESULT"
        printf '%-16s -> %-20s DB=%-12s HOST=%-20s SERVICE=%s\n' \
            "$IP" "$ROLE" "$DBUNIQUE" "$SERVER" "$SERVICE_NAME"
    else
        printf '%-16s -> %s\n' "$HOST" "${RESULT:-UNKNOWN}"
    fi
done
