# Layered cloud network troubleshooting method

## 1. Define one exact failing flow

Avoid “the application cannot connect.” Record:

- source process, pod, container or host;
- source address and network;
- destination hostname and resolved address;
- protocol and port;
- timestamp and timeout;
- expected path;
- exact client error;
- whether the failure is constant or intermittent.

A precise flow can be matched across routes, flow logs, firewalls, packet captures and application telemetry.

## 2. Reproduce from the correct context

Test from the same network namespace and identity as the application. Differences may exist between:

- Windows and WSL;
- host and Podman/Docker container;
- Kubernetes node and pod;
- jump server and private workload subnet;
- administrator credentials and workload identity.

A successful test from the wrong context is not proof that the application path works.

## 3. Walk the layers in order

### DNS

Evidence:

```bash
getent ahostsv4 host.example.com
dig host.example.com A
```

Question: did the intended resolver return the intended address?

### Route selection

Evidence:

```bash
ip route get 192.0.2.25
```

Question: which interface, source address and next hop will the kernel use?

### Packet policy and transit

Evidence sources:

- security groups and NSGs;
- NACLs;
- route tables and transit associations;
- firewall session logs;
- flow logs;
- Kubernetes NetworkPolicies;
- host firewall rules.

Question: where is the first hop that does not show the expected packet?

### TCP

Evidence:

```bash
nc -vz -w 5 host.example.com 443
```

Interpretation:

- timeout: packet loss, policy, route or silent endpoint;
- refusal: destination reached, no listener accepted;
- success: proceed to TLS/application.

### TLS

Evidence:

```bash
openssl s_client -connect host.example.com:443 -servername host.example.com </dev/null
```

Question: did the handshake complete with the expected identity and trust chain?

### HTTP or application protocol

Evidence:

```bash
curl -vkI --connect-timeout 5 https://host.example.com/
```

Question: does the application endpoint respond, redirect, reject or fail?

### Authorization

An HTTP `401` or `403` usually proves DNS, route, TCP and TLS are functioning. Move to credentials, signing, role assignment and resource policy instead of reopening the firewall.

## 4. Compare success and failure

A known-good path is powerful. Compare:

- resolver and answer;
- source address;
- route table association;
- security-group membership;
- proxy environment;
- TLS issuer and SAN;
- workload identity;
- availability zone or node.

Change one variable at a time where possible.

## 5. Preserve evidence before remediation

Before restarting, rebooting, flushing caches or replacing endpoints, capture:

- timestamps and full errors;
- DNS answers and TTL;
- route output;
- relevant flow-log records;
- firewall sessions;
- connection state;
- application and dependency logs;
- recent infrastructure changes.

Recovery may be urgent, but evidence capture often takes seconds and prevents repeated incidents.

## 6. Use controlled tests

Good diagnostic tests are:

- narrow in source, destination, port and time;
- read-only where possible;
- executed with the application’s identity;
- reversible;
- documented before broad policy changes.

Avoid permanent `0.0.0.0/0` rules, disabled certificate verification, ad hoc `/etc/hosts` entries and global proxy bypasses as “fixes.” They remove controls and hide the actual defect.

## 7. Build an evidence table

| Layer | Test | Result | Conclusion | Owner |
|---|---|---|---|---|
| DNS | `getent ahostsv4` | Private IP | Zone path works | Platform DNS |
| Route | `ip route get` | Transit next hop | Source route works | Cloud network |
| TCP | `nc` | Timeout | Failure before listener | Network/security |
| Flow logs | Source ACCEPT, no destination record | Packet lost in transit | Inspect firewall path | Network security |

This turns a cross-team debate into a shared technical timeline.

## 8. Verify the actual service

After remediation, validate:

1. the original client and operation;
2. customer-visible health;
3. forward and return paths;
4. monitoring and alert recovery;
5. removal of temporary exceptions;
6. a documented root cause and preventive action.
