# Contributing

This repository is a public troubleshooting portfolio. Use documentation-only domains, TEST-NET addresses and generated output. Never submit internal DNS records, production flow logs, certificates, account IDs or confidential network diagrams.

## Diagnostic expectations

- Reproduce from the same network namespace and identity as the failing process.
- Separate DNS, routing, packet policy, TCP, TLS, application protocol and authorization.
- Prefer read-only evidence collection before disruptive remediation.
- Explain forward and return paths in transit or inspection designs.
- Remove temporary broad firewall, proxy or certificate-verification exceptions.

## Validation

```bash
bash -n scripts/cloud-netdiag.sh
```

Run live diagnostics only against systems you are authorized to test. Redact output before sharing it outside the owning organization.
