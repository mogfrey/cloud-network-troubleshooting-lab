#!/usr/bin/env bash
set -uo pipefail

HOST="${1:-}"
PORT="${2:-443}"
PATH_VALUE="${3:-/}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"

if [[ -z "$HOST" ]]; then
  echo "Usage: $0 <hostname> [port] [http-path]" >&2
  exit 2
fi

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "ERROR: port must be an integer between 1 and 65535" >&2
  exit 2
fi

section() {
  printf '\n==== %s ====\n' "$1"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

TMP_CERT=$(mktemp)
trap 'rm -f "$TMP_CERT"' EXIT

section "Request"
printf 'Timestamp (UTC): %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
printf 'Target:          %s:%s%s\n' "$HOST" "$PORT" "$PATH_VALUE"
printf 'Hostname:        %s\n' "$(hostname -f 2>/dev/null || hostname)"
printf 'Kernel:          %s\n' "$(uname -srmo)"

section "Proxy environment"
env | grep -Ei '^(http|https|no)_proxy=' || echo "No proxy variables found."

section "Resolver configuration"
if have resolvectl; then
  resolvectl status 2>/dev/null || true
else
  cat /etc/resolv.conf 2>/dev/null || true
fi

section "DNS answers"
DNS_OUTPUT=$(getent ahostsv4 "$HOST" 2>&1 || true)
if [[ -z "$DNS_OUTPUT" ]]; then
  echo "No IPv4 answer returned for $HOST."
  exit 1
fi
printf '%s\n' "$DNS_OUTPUT"

mapfile -t IPS < <(printf '%s\n' "$DNS_OUTPUT" | awk '$2 == "STREAM" {print $1}' | sort -u)
if (( ${#IPS[@]} == 0 )); then
  mapfile -t IPS < <(printf '%s\n' "$DNS_OUTPUT" | awk '{print $1}' | sort -u)
fi

section "Route selection"
if have ip; then
  for ip_address in "${IPS[@]}"; do
    printf '%s -> ' "$ip_address"
    ip route get "$ip_address" 2>&1 || true
  done
else
  echo "The ip command is not installed."
fi

section "TCP reachability"
TCP_SUCCESS=0
for ip_address in "${IPS[@]}"; do
  printf 'Testing %s:%s ... ' "$ip_address" "$PORT"
  if have nc; then
    if nc -vz -w "$CONNECT_TIMEOUT" "$ip_address" "$PORT" >/tmp/cloud-netdiag-nc.$$ 2>&1; then
      echo "connected"
      TCP_SUCCESS=1
    else
      echo "failed"
      sed 's/^/  /' /tmp/cloud-netdiag-nc.$$ 2>/dev/null || true
    fi
    rm -f /tmp/cloud-netdiag-nc.$$
  elif have timeout; then
    if timeout "$CONNECT_TIMEOUT" bash -c "</dev/tcp/$ip_address/$PORT" 2>/dev/null; then
      echo "connected"
      TCP_SUCCESS=1
    else
      echo "failed"
    fi
  else
    echo "skipped: install netcat or timeout"
  fi
done

section "TLS handshake and certificate"
if have openssl; then
  if timeout "$CONNECT_TIMEOUT" openssl s_client \
      -connect "$HOST:$PORT" \
      -servername "$HOST" \
      -showcerts </dev/null >"$TMP_CERT" 2>&1; then
    awk '/BEGIN CERTIFICATE/{capture=1} capture{print} /END CERTIFICATE/{exit}' "$TMP_CERT" |
      openssl x509 -noout -subject -issuer -serial -dates -fingerprint -sha256 -ext subjectAltName 2>&1 || true
  else
    echo "TLS handshake did not complete successfully."
    sed -n '1,40p' "$TMP_CERT"
  fi
else
  echo "OpenSSL is not installed."
fi

section "HTTP response"
SCHEME=https
if [[ "$PORT" == "80" ]]; then
  SCHEME=http
fi
URL="${SCHEME}://${HOST}:${PORT}${PATH_VALUE}"

if have curl; then
  curl -sSvkI \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$((CONNECT_TIMEOUT * 3))" \
    "$URL" 2>&1 | sed -n '1,80p'
else
  echo "curl is not installed."
fi

section "Summary"
printf 'Resolved IPv4 addresses: %s\n' "${IPS[*]}"
printf 'At least one TCP connection succeeded: %s\n' "$([[ "$TCP_SUCCESS" == "1" ]] && echo yes || echo no)"
echo "Interpret each failed layer before changing firewall, DNS or application configuration."
