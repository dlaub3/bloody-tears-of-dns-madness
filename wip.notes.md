
There are more special use domain names. https://www.rfc-editor.org/rfc/rfc2606.html
- .local: Used by mDNS (Multicast DNS) for local network name resolution without a DNS server (RFC 6762). Devices on the
same network can discover each other this way.
- .localhost: Refers to the local loopback address (127.0.0.1 for IPv4 and ::1 for IPv6). Any DNS query for a .localhost name should resolve to the local machine (RFC 6761).
- .example, .test, .invalid: Reserved for documentation and testing purposes (RFC 2606).

```
Domains=~local
# disable MulticastDNS (mDNS)
MulticastDNS=no
```

Not all applications resolve DNS the same way. When `systemd-resolved` is enabled many applications use
`systemd-resolved` even when `/etc/resolv.conf` does not point to `127.0.0.53`. This leaves two options.

Option 1. Set `nameserver 127.0.0.53` in `/etc/resolv.conf` and the DNS IP in `/etc/systemd/resolved.conf`.

Option 2. Set the DNS IP in `/etc/resolv.conf` and `sudo systemctl stop systemd-resolved`.

**NOTE** When running dnsmasq locally it can be configured to handle DNS before `systemd-resolved` and use
`systemd-resolved` as a server.

## Routing

There are two sets of IPs for Kubernetes pods. pods in the 10.42.0.0/24 range

CLUSTER_IP: `kubectl get svc -o wide -A`  typically 10.43.0.0/24 CoreDNS  resolves to `CLUSTER_IP` not `IP`

IP: `kubectl get pods -o wide -A` typically 10.42.0.0/24

If a ping from a docker container to a POD IP or POD CLUSTER_IP fails it may be necessary to add a route.

**CLUSTER_IP**
```
CLUSTER_IP_CIDR=$(echo
'{"apiVersion":"v1","kind":"Service","metadata":{"name":"tst"},"spec":{"clusterIP":"1.1.1.1","ports":[{"port":443}]}}'
| kubectl apply -f - 2>&1 | sed 's/.*valid IPs is //') # https://stackoverflow.com/a/61685899

ip route add "${CLUSTER_IP_CIDR}" dev lo
```
**IP**
```
HOST_IP=$(hostname -i | awk '{ print $1 }')
POD_IP_CIDR=$(k3s kubectl get nodes -o json | jq -r '.items[].spec.podCIDR')

ip route add "${POD_IP_CIDR}" via "${HOST_IP}"
```

### Docker DNS

Docker resolves DNS using the contents of `/etc/resolv.conf` if it's not `localhost/127.0.0.1`, or by providing a DNS
resolver.

**Option 1**. use `--dns=`
```
docker run -d -ti --rm --dns=172.17.0.2 --name netutils netutils
```

**Option 2.** use `/etc/resolv.conf`

```
DNSMASQ_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dnsmasq)

echo "nameserver $DNSMASQ_IP >> /etc/resolv.conf"
```

Double check `/etc/resolv.conf` within the container if there is trouble, a container restart may be required.

## Notes

Multiple processes can listen on the same host port as long as the `HOST:PORT` combo do not match.
For example, `127.0.0.53:53`, `127.0.0.1:53`, `<host ip>:53`.


### Debugging Tools

```
resolvectl dns
resolvectl query example.internal

dig example.internal
dig @172.17.0.2 example.internal
```


**DNSMASQ**

```
docker rm dnsmasq --force
docker build . -t dnsmasq -f Dockerfile.dnsmasq
docker run -d --name dnsmasq --network dns dnsmasq
export DNSMSAQ_IP=(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dnsmasq)
```

From Kubernetes `netutils` container

```
HTTPS_PROXY=socks5h://gateway.docker curl https://ipinfo.io/json
```

