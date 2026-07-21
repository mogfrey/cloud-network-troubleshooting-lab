# Runbook: TLS certificate, trust or SNI failure

## Symptoms

- hostname verification failure;
- certificate signed by an unknown authority;
- expired or not-yet-valid certificate;
- handshake timeout or reset;
- browser works but CLI/application fails;
- direct IP test returns a different certificate;
- one load-balanced endpoint works while another fails.

## Preserve the exact error

Record the client, runtime, hostname, port, timestamp and full verification error. Different clients may use different trust stores, TLS versions, proxy settings and SNI behaviour.

## Inspect the handshake with SNI

```bash
HOST=service.example.com
PORT=443

openssl s_client \
  -connect "$HOST:$PORT" \
  -servername "$HOST" \
  -showcerts \
  -verify_return_error </dev/null
```

Extract the leaf certificate:

```bash
openssl s_client -connect "$HOST:$PORT" -servername "$HOST" </dev/null 2>/dev/null |
openssl x509 -noout -subject -issuer -serial -dates -fingerprint -sha256 -ext subjectAltName
```

The `-servername` value matters. A reverse proxy or load balancer commonly selects the certificate and virtual host using SNI.

## Test a specific resolved address without losing SNI

```bash
curl -vkI --resolve service.example.com:443:192.0.2.25 https://service.example.com/
```

This sends traffic to `192.0.2.25` while retaining `service.example.com` for HTTP Host and TLS SNI. It is more useful than curling the IP directly.

## Diagnostic categories

### Hostname mismatch

The requested hostname must appear in the certificate Subject Alternative Name. The Common Name alone should not be treated as sufficient by modern clients.

Check:

- wrong DNS alias;
- certificate issued for an internal/backend name rather than the client-facing name;
- missing wildcard coverage;
- direct IP access;
- load balancer listener using the wrong certificate;
- one backend bypassing the intended TLS termination layer.

### Unknown authority or incomplete chain

Compare the served chain with the issuing CA hierarchy. Servers should normally present the leaf and required intermediate certificates, not the private root.

Check the application trust store separately from the operating-system store. Java, Python virtual environments, containers and appliances may use different CA bundles.

### Expiry or validity window

```bash
openssl s_client -connect "$HOST:$PORT" -servername "$HOST" </dev/null 2>/dev/null |
openssl x509 -noout -startdate -enddate
```

Also verify client and server time. A correct certificate can appear invalid on a host with substantial clock drift.

### Protocol or cipher mismatch

```bash
openssl s_client -connect "$HOST:$PORT" -servername "$HOST" -tls1_2 </dev/null
openssl s_client -connect "$HOST:$PORT" -servername "$HOST" -tls1_3 </dev/null
```

A legacy client may not support the server policy; a legacy server may not support the organization’s required minimum. Fix the incompatible endpoint or client instead of permanently weakening TLS policy.

### Proxy or TLS inspection

Check `HTTPS_PROXY` and `NO_PROXY`. Compare certificate issuer and fingerprint from the affected environment with a known direct path. Enterprise TLS inspection may present an organizational certificate that only works where the inspection CA is trusted.

Do not disable verification globally. Correct proxy routing or trust distribution through the approved security process.

### Mutual TLS

For mTLS, confirm the client presents the correct certificate and private key and that the server trusts the issuing CA:

```bash
curl -v \
  --cert client.crt \
  --key client.key \
  --cacert server-ca.crt \
  https://service.example.com/
```

Protect private-key file permissions and never paste keys into tickets or repositories.

## Kubernetes and ingress checks

```bash
kubectl -n ingress-system get secret <tls-secret> -o jsonpath='{.data.tls\.crt}' |
base64 -d |
openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

Verify the Ingress/Route hostname, referenced Secret, certificate-controller status and load-balancer listener. A renewed Secret may not take effect if the controller did not reload it.

## Verification

Test with the real application client after correcting the issue. Confirm:

1. DNS resolves to the intended endpoint;
2. SNI selects the intended certificate;
3. hostname and chain validation succeed without `-k` or equivalent bypass;
4. the application protocol succeeds;
5. certificate-expiry monitoring covers the renewed endpoint.
