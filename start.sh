#!/bin/bash

HOST_IP=$(hostname -i | awk '{ print $1 }')

# build netutils for testing
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

# HOST
if ! grep -q "${DNSMASQ_IP}" resolved.conf; then
  sed -i "s/{DNSMASQ_IP}/${DNSMASQ_IP}/g" resolved.conf
fi

if ! grep -q "${DNSMASQ_IP}" /etc/systemd/resolved.conf; then
    sudo mv /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak
    sudo mv resolved.conf /etc/systemd/resolved.conf
fi

if ! grep -q /etc/resolv.conf "127.0.0.53"; then
   # ensure /etc/resolv.conf points to the DNS stub-listener
   echo '/etc/resolv.conf should contain "nameserver 127.0.0.53"'
fi

# CoreDNS

if ! grep -q $DNSMASQ_IP dnsmasq.conf; then
  sed -i "s/{DNSMASQ_IP}/${DNSMASQ_IP}/g" coredns.configmap.yaml
fi

kubectl apply -f coredns.configmap.yaml

