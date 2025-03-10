## Learning DNS via trail and error

-  Kubernetes (CoreDNS) will resolve host names to the host IP and Docker container IPs.
-  Docker will resolve host names to the host IP and k8s POD IPs.
-  Host will resolve host names to k8s POD IPs and Docker container IPs.

Sample `dnsmasq.conf`, read on for more details.

```
log-queries
no-resolv
cache-size=1000

server=/.docker/127.0.0.11 # docker
server=/.k8s.local/10.43.0.10 # coredns mDNS uses .local, this must be accounted for
server=/.cluster.local/10.43.0.10 # coredns mDNS uses .local, this must be accounted for
server=1.1.1.1
server=8.8.4.4

address=/.test/{HOST_IP} # computer
```
In my use case I configured a VPN gateway, which I could easily use from my host, docker, and k8s by simply using
`HTTPS_PROXY=socks5h://gateway.docker curl https://ipinfo.io/json`

## DNSMASQ

dnsmasq is a _fantastic_ piece of software that will make you cry (actually DNS will make you cry).

For this configuration to work we create a docker network specifically for DNS. `dnsmasq` will be able to resolve the IP
of any container in this network using hostname alias and the default docker DNS of `127.0.0.11` which the config is set
to resolve for any `.docker` domain. This means when you want to resolve DNS for a docker container ensure it's in the
`dns` network and has an appropriate host alias `<container>.docker`. The `.docker` alias is the real trick. Most
container names `<container>` do not look like hostnames to DNS resolvers. And sticking with a convention allows them to
be easily targeted with `server=/.docker/127.0.0.11`.

```
if ! grep -q $HOST_IP dnsmasq.conf; then
  sed -i "s/{HOST_IP}/${HOST_IP}/g" dnsmasq.conf
fi

if ! grep -q dns <(docker network ls); then
  docker network create dns
fi

docker rm dnsmasq --force
docker build . -t dnsmasq
docker run -d --name dnsmasq dnsmasq # no need to port bind

DNSMASQ_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dnsmasq)
```

## Linux (host) DNS

Now that dnsmasq is up and running we need to configure the host. This _could_ configure Docker and Kubernetes too if
the DNSMASQ_IP was added to `/etc/resolv.conf`. But I'm taking a different
approach. If you do use `/etc/resolv.conf` you'll run into fewer issues by also disabling `sudo systemctl stop
systemd-resolved`. However, I prefer working with `systemd-resolved`. So I will be editing `/etc/systemd/resolved.conf`.

```
[Resolve]
DNS={DNSMASQ_IP}
# By default, systemd-resolved treats the .local domain as a special-use domain for Multicast DNS (mDNS) and doesn't forward these queries to your configured DNS servers.
Domains=~local
# disable MulticastDNS (mDNS)
MulticastDNS=no
# listen on 127.0.0.53 (where /etc/resolv.conf usually points)
DNSStubListener=yes
```

Now `sudo systemctl restart systemd-resolved && sudo systemctl status systemd-resolved`

These changes also allow Docker container DNS to work since Docker should forward DNS to the host when
`/etc/resolv.conf` in the container isn't set to anything. But you can also set DNS for a container `docker run -d -ti
--rm --dns={DNSMASQ_IP} --name netutils netutils`.

## Kubernetes

Because CoreDNS is likely already running we need to update the config to forward DNS to the dnsmasq docker container.
You should update this patch to suit your needs.

```
if ! grep -q $DNSMASQ_IP dnsmasq.conf; then
  sed -i "s/{DNSMASQ_IP}/${DNSMASQ_IP}/g" coredns.configmap.yaml
fi

kubectl apply -f coredns.configmap.yaml
```


## Routing

There are two sets of IPs for Kubernetes pods.

- CLUSTER_IP: `kubectl get svc -o wide -A`  typically 10.43.0.0/24 CoreDNS  resolves to `CLUSTER_IP` not `IP`
- IP: `kubectl get pods -o wide -A` typically 10.42.0.0/24

Most likely you can already ping the IP. But CoreDNS resolved to the CLUSTER_IP. If you cannot ping the CLUSTER_IP you
may need to add a route.

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

I've spent less time testing these routes, so use them at your own risk. They
exist here to highlight the fact that routing to the `CLUSTER_IP` can be fixed.
If it's not working in your environment, you'll know because dnsmasq will not be able to resolve the IP of any k8s
services since it forwards to CoreDNS. By the way this does create a loop, since CoreDNS hands off to dnsmasq which may
query CoreDNS, but only for hostnames which match the correct pattern.


## Notes

Multiple processes can listen on the same host port as long as the `HOST:PORT` combo do not match.
For example, `127.0.0.53:53`, `127.0.0.1:53`, `<host ip>:53`.


## Debugging

After updating `/etc/systemd/resolved.conf` and restarting run `resolvectl dns` and ensure that it lists the IP of
dnsmasq.

For troubleshooting specific DNS resolution use `dig +short <domain> @$DNSMASQ_IP` to ensure dnsmasq is working. If it
is and `dig +short <domain>` does not work, then DNS resolution isn't forwarding to `dnsmasq` properly.

This first section of `starts.sh` creates the debugging container and loads it into `k3s` you will need to modify this for
your Kubernetes cluster or choose a container from `docker.io`.

```
if ! docker image ls | grep netutils; then
  docker build -f Dockerfile.netutils -t netutils .
  docker run -d --rm --name netutils netutils -c "sleep infinity"
  docker save netutils -o netutils.tar
  sudo k3s ctr images import netutils.tar
  # sudo k3s ctr images list | grep netutils
  k run netutils --image=netutils --restart=Never --image-pull-policy=Never --command -- sleep infinity
  # docker exec -ti netutils /bin/bash
  # k exec -ti netutils -- /bin/bash
fi
```

**IMPORTANT**

If DNS stops working

Option 1. Run `sudo systemctl systemd-resolved` and add external DNS line to `/etc/resolv.conf`. `echo
"nameserver 1.1.1.1" >> /etc/resolv.conf`.

Option 2. Add external DNS to `/etc/systemd/resolved.conf` `DNS=1.1.1.1`

