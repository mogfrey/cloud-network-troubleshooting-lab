# Runbook: Private object-store endpoint timeout

## Symptom

An application resolves an object-store hostname to a private address but times out on TCP 443 or during an API operation such as listing objects.

## Working hypothesis

DNS has probably succeeded. The remaining fault domains include route association, endpoint state, packet policy, return routing, proxy handling and workload-level egress policy.

## Evidence sequence

Run from the same pod, container, VM or subnet as the failing process:

```bash
HOST=object-store.example.com
getent ahostsv4 "$HOST"
ip route get "$(getent ahostsv4 "$HOST" | awk '$2=="STREAM"{print $1; exit}')"
nc -vz -w 5 "$HOST" 443
openssl s_client -connect "$HOST:443" -servername "$HOST" </dev/null
curl -vkI --connect-timeout 5 "https://$HOST/"
```

Interpret the first failing layer:

- no DNS answer: resolver, zone association or forwarding;
- unexpected address: split-horizon DNS or endpoint selection;
- TCP timeout: routes, SG/NSG, NACL, firewall, return path or endpoint health;
- TLS failure: SNI, certificate trust, proxy interception or MTU/path issue;
- HTTP 403: network path works; inspect identity and resource policy;
- API timeout after successful HEAD/GET: SDK proxy, addressing mode, request size or service-specific path.

## Cloud checks

### Route association

Confirm the failing workload subnet—not merely another subnet in the VPC/VNet—is associated with the route table that contains the object-store endpoint or approved egress path.

### Endpoint state and placement

Confirm:

- endpoint state is healthy/available;
- endpoint subnets exist in the intended zones;
- private DNS is enabled where required;
- endpoint security policy permits the workload source;
- endpoint policy allows the target bucket/container and operations.

### Packet policy

Review all applicable controls:

- source security group or NSG egress;
- endpoint security group ingress;
- subnet NACLs and ephemeral return ports;
- centralized firewall policy;
- Kubernetes NetworkPolicy or CNI policy;
- host firewall and container bridge rules.

Use flow logs to search the exact source IP, destination IP, protocol and port. A broad search for the hostname will not appear in IP flow records.

### Routing symmetry

In transit or inspection designs, verify forward and return routes. A forward route through a firewall with a direct return route can produce a timeout even when every individual route looks plausible.

## Identity check

After TCP/TLS succeeds, test with the same workload identity. Do not substitute an administrator profile:

```bash
aws sts get-caller-identity
aws s3api list-objects-v2 --bucket example-private-bucket --max-keys 1
```

Equivalent Azure tests should use the same managed identity or service principal as the application.

## Proxy check

Inspect uppercase and lowercase proxy variables. Private endpoint names and address ranges may need to be present in `NO_PROXY`. Confirm this rather than disabling the enterprise proxy globally.

## Recovery

Apply the narrowest proven fix, then verify DNS, TCP, TLS, authorization and the actual application operation. Remove temporary broad network or policy exceptions before closure.
