# Runbook: Private DNS or split-horizon failure

## Symptoms

- a private service name does not resolve;
- the same name resolves differently from a laptop, VM and pod;
- a cloud service name resolves publicly when a private endpoint is expected;
- resolution works on the host but fails inside WSL, Podman or Kubernetes;
- intermittent answers point to different networks.

## Capture the resolver context

Run in the failing execution environment:

```bash
cat /etc/resolv.conf
getent hosts service.internal.example.com
getent ahostsv4 service.internal.example.com
```

When available:

```bash
resolvectl status
resolvectl query service.internal.example.com
```

Use `dig` to inspect the answer path:

```bash
dig service.internal.example.com A
dig +short service.internal.example.com A
dig @<resolver-ip> service.internal.example.com A
```

Record:

- resolver IP;
- search domains;
- requested FQDN;
- returned addresses and TTL;
- CNAME chain;
- whether the response is `NXDOMAIN`, `SERVFAIL`, timeout or an unexpected valid answer.

## Interpret failure types

### NXDOMAIN

The resolver answered authoritatively that the name does not exist. Check zone name, record name, private-zone association and whether a more-specific private zone shadows a public zone.

### SERVFAIL

The resolver could not complete resolution. Investigate forwarding loops, DNSSEC validation, unreachable authoritative servers or conditional forwarder failures.

### Timeout

Check UDP/TCP 53 reachability, security policy, resolver health and return routing. Large responses may fall back from UDP to TCP, so permit both where required.

### Unexpected valid address

This often indicates split-horizon behaviour, stale caching, the wrong resolver path or a missing private-zone link. Do not overwrite `/etc/hosts` as the permanent fix; that hides the control-plane issue and creates drift.

## Cloud private DNS checks

### AWS

Confirm:

- VPC DNS support and DNS hostnames are enabled;
- the private hosted zone is associated with the correct VPCs;
- interface endpoint private DNS is enabled;
- Route 53 Resolver inbound/outbound endpoints are healthy;
- forwarding rules are associated with the correct VPC;
- on-premises DNS forwards the exact private zone to the intended resolver;
- no overlapping private hosted zone returns an incomplete answer.

### Azure

Confirm:

- the Private DNS zone name matches the service subresource;
- an A record exists for the private endpoint;
- the zone is linked to the workload VNet or centrally reachable through DNS forwarding;
- Private Resolver rulesets and VNet links are correct;
- custom DNS servers forward Azure private zones to the approved Azure resolver path;
- duplicate zones in separate subscriptions are not creating inconsistent answers.

## Kubernetes checks

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
kubectl -n kube-system get configmap coredns -o yaml
kubectl run dns-test --rm -it --restart=Never --image=registry.k8s.io/e2e-test-images/dnsutils:1.3 -- nslookup service.internal.example.com
```

Review CoreDNS logs, forwarding targets, stub domains, NetworkPolicies and node resolver configuration. Compare resolution from:

1. the node;
2. a normal pod;
3. the affected pod;
4. a pod in another namespace or node pool.

Differences identify where policy or configuration diverges.

## WSL and container checks

WSL may regenerate `/etc/resolv.conf` from Windows networking. Containers may use an internal DNS proxy or inherit a different resolver set.

Compare:

```bash
# WSL
cat /etc/wsl.conf
cat /etc/resolv.conf

# Podman
podman inspect <container> --format '{{json .HostConfig.Dns}}'
podman exec <container> cat /etc/resolv.conf

# Docker
docker inspect <container> --format '{{json .HostConfig.Dns}}'
```

Fix the authoritative configuration source rather than repeatedly editing generated files.

## Cache considerations

Flush caches only after recording current answers and TTLs. A cache flush can restore service while erasing evidence of which resolver supplied the stale record.

Potential caches include:

- application and JVM DNS cache;
- systemd-resolved or nscd;
- CoreDNS;
- enterprise DNS appliances;
- browser or proxy cache.

## Verification

Confirm the intended answer from every relevant execution context, then test TCP/TLS to the returned address. Correct DNS is necessary but does not prove network reachability.
