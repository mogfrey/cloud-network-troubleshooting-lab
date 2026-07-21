# Runbook: Transit or hub connectivity failure

## Scenario

A workload in one VPC/VNet cannot reach a service through AWS Transit Gateway, Azure hub-and-spoke routing, a virtual WAN hub or a centralized inspection network.

## Principle

Prove the complete forward and return path. A route in the source network is only one link in a chain that may cross several accounts, subscriptions and teams.

## Define the flow

Record the exact five-tuple and context:

```text
Source workload: 10.42.10.25
Destination:     172.20.8.40
Protocol/port:   TCP/443
Source network:  workload spoke
Destination:     shared service network
Expected path:   spoke → transit/hub → inspection → destination
```

Also record the hostname, resolved address, test timestamp and whether the application runs on a host, VM, pod or container.

## 1. Source host or pod

```bash
ip addr
ip route
ip route get 172.20.8.40
nc -vz -w 5 172.20.8.40 443
traceroute -T -p 443 172.20.8.40 2>/dev/null || true
```

Check local firewall, container namespace routes and Kubernetes NetworkPolicy. A VM route does not automatically prove a pod route when overlays, proxies or eBPF policies are involved.

## 2. Source subnet route table

Confirm the destination CIDR uses the intended next hop:

- Transit Gateway attachment;
- virtual network gateway;
- virtual appliance/firewall;
- virtual hub connection;
- peering, where appropriate.

Look for a more-specific route overriding the expected path. Route selection uses longest-prefix match before operational intent.

## 3. Transit or hub routing

For AWS Transit Gateway, verify:

- source and destination attachments are available;
- the source attachment is associated with the correct TGW route table;
- destination CIDR is propagated or statically present;
- return CIDR is present in the destination-side TGW route table;
- blackhole routes do not supersede the path;
- appliance mode is configured when stateful inspection requires symmetric flows.

For Azure, inspect effective routes on the source and destination NICs/subnets and confirm:

- peering allows forwarded traffic where required;
- gateway transit and remote gateway settings are intentional;
- user-defined routes point to the expected virtual appliance or hub;
- the virtual appliance can forward traffic;
- Azure Firewall or NVA route propagation does not create asymmetry.

## 4. Inspection layer

A stateful firewall must see both directions of a connection. Confirm:

- policy permits source, destination, protocol and port;
- NAT behaviour is expected;
- forward and return routes traverse the same inspection state;
- health probes and route failover have not selected different appliances;
- firewall logs show allow, deny or no session.

“No firewall log” is evidence: the traffic may never have reached the firewall.

## 5. Destination network

Validate the destination subnet route back to the source CIDR. Then inspect:

- destination security group or NSG ingress;
- destination host firewall;
- listener address and port;
- load-balancer target health;
- network ACLs;
- service mesh or workload policy.

On the destination:

```bash
ss -lntp | grep ':443 '
ip route get 10.42.10.25
sudo tcpdump -ni any host 10.42.10.25 and tcp port 443
```

Packet capture interpretation:

- no SYN arrives: failure is before the destination;
- SYN arrives, no SYN-ACK: destination policy/listener or return routing;
- SYN and SYN-ACK leave, client still times out: return path or middlebox;
- TCP completes, TLS fails: move to certificate/SNI investigation.

## 6. Flow logs

Query source VPC/VNet flow logs, transit/firewall logs and destination flow logs using the same timestamp and addresses. Build a hop-by-hop evidence table:

| Hop | Evidence | Result | Owner |
|---|---|---|---|
| Source interface | SYN sent | Pass | Workload team |
| Source subnet | Route to transit | Pass | Cloud platform |
| Transit route table | Destination route | Pass | Network team |
| Firewall | Session allowed | Unknown | Security network |
| Destination interface | SYN received | Fail | Destination team |

This prevents circular hand-offs based on assumptions.

## Recovery and verification

Change only the proven missing or incorrect control. Verify both connection directions, the application protocol and at least one failure scenario. Remove temporary test routes and broad firewall rules.
