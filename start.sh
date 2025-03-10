#!/bin/bash

set -x
set -o pipefail

HOST_IP=$(hostname -i | awk '{ print $1 }')

if ! grep -E -q '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' <<<$HOST_IP; then
  echo "HOST_IP is not a valid IP: " + $HOST_IP
  exit 1
fi

# build netutils for testing
if ! docker image ls | grep netutils; then
  docker build -f Dockerfile.netutils -t netutils .
  docker run -d --rm --name netutils --network dns netutils sleep infinity
  docker save netutils -o netutils.tar
  sudo k3s ctr images import netutils.tar
  # sudo k3s ctr images list | grep netutils
  k run netutils --image=netutils --restart=Never --image-pull-policy=Never -- sleep infinity
  # docker exec -ti netutils /bin/bash
  # k exec -ti netutils -- /bin/bash
fi

if ! grep -q $HOST_IP dnsmasq.conf; then
  sed -i "s/{HOST_IP}/${HOST_IP}/g" dnsmasq.conf
fi

if ! grep -q dns <(docker network ls); then
  docker network create dns
fi

if ! docker ps -a | grep dnsmasq; then
  docker run -d --name dnsmasq -v ./dnsmasq.conf:/etc/dnsmasq.conf --network dns netutils \
    dnsmasq -k --log-queries --log-facility=-
fi

DNSMASQ_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dnsmasq)

if ! grep -E -q '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' <<<$DNSMASQ_IP; then
  echo "DNSMASQ_IP is not a valid IP: " + $DNSMASQ_IP
  exit 1
fi

# HOST
if ! grep -q "${DNSMASQ_IP}" resolved.conf; then
  sed -i "s/{DNSMASQ_IP}/${DNSMASQ_IP}/g" resolved.conf
fi

if ! grep -q "${DNSMASQ_IP}" /etc/systemd/resolved.conf; then
    sudo scripts/swap.sh /etc/systemd/resolved.conf
    sudo systemctl restart systemd-resolved
fi

if ! grep -q "127.0.0.53" /etc/resolv.conf ; then
   # ensure /etc/resolv.conf points to the DNS stub-listener
   echo '/etc/resolv.conf should contain "nameserver 127.0.0.53"'
   exit 1
fi

# CoreDNS

if ! grep -q $DNSMASQ_IP dnsmasq.conf; then
  sed -i "s/{DNSMASQ_IP}/${DNSMASQ_IP}/g" coredns.configmap.yaml
fi

kubectl apply -f coredns.configmap.yaml

