# Cloud Network Troubleshooting Lab

A hands-on diagnostic toolkit for cloud and Kubernetes connectivity failures. The repository demonstrates a layered, evidence-driven method for DNS, routing, TCP, TLS, private endpoints, transit connectivity and application authorization.

## Troubleshooting model

```text
Name resolution → route selection → packet policy → TCP → TLS → HTTP → identity/authorization
```

Do not collapse all of those layers into “the firewall.” Each produces different evidence and has different owners.

## Included content

- Read-only endpoint diagnostic script for Linux and WSL
- Generic S3/private-endpoint timeout runbook
- Transit Gateway and hub/transit connectivity runbook
- Private DNS and split-horizon runbook
- TLS certificate and SNI runbook
- A repeatable investigation method and evidence checklist

## Repository layout

```text
.
├── scripts/cloud-netdiag.sh
├── runbooks/private-object-store-endpoint.md
├── runbooks/transit-connectivity.md
├── runbooks/private-dns.md
├── runbooks/tls-and-sni.md
├── docs/troubleshooting-method.md
└── examples/sample-output.txt
```

## Run the diagnostic script

```bash
chmod +x scripts/cloud-netdiag.sh
./scripts/cloud-netdiag.sh example.com 443 /
```

For a private service:

```bash
./scripts/cloud-netdiag.sh api.internal.example.com 8443 /health
```

The script performs only read operations. It records DNS answers, selected routes, TCP reachability, TLS certificate metadata and an HTTP response. It does not change routes, DNS, firewall rules or certificates.

## Interpreting common outcomes

| Evidence | Likely layer |
|---|---|
| Name does not resolve | DNS zone, forwarding, resolver or search-domain problem |
| Resolves to an unexpected public/private address | Split-horizon DNS or endpoint association problem |
| TCP timeout | Route, security group/NSG, NACL, firewall or asymmetric return path |
| Connection refused | Destination reached, but no listener accepted the port |
| TLS hostname mismatch | Missing/incorrect SNI, DNS alias or certificate SAN |
| HTTP 403 | Network and TLS work; investigate identity, signing or resource policy |
| HTTP 5xx | Application or dependency reached but failed |

## Cloud operating principle

Always test from the same execution context as the failing application. A host-level `curl` does not prove that a Kubernetes pod, Podman container, private subnet or workload identity has the same DNS, routes and policy.

## Data-safety note

All names, CIDRs, addresses, account references and outputs are synthetic. Do not paste production flow logs, internal DNS records, certificates or cloud exports into a public issue.
