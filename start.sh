#!/bin/bash

HOST_IP=$(hostname -i | awk '{ print $1 }')

if ! docker image ls | grep dnsmasq; then
  docker build -f Dockerfile.netutils -t netutils .
fi

if ! grep $HOST_IP dnsmasq.conf; then
  sed -i "s/{HOST_IP}/${HOST_IP}/g" dnsmasq.conf
fi

docker rm dnsmasq --force
docker build . -t dnsmasq
docker run -d --name dnsmasq dnsmasq # no need to port bind

DNSMASQ_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dnsmasq)

if ! grep "${DNSMASQ_IP}" /etc/systemd/resolved.conf; then
    sudo mv /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak
    cat <<-EOF > /etc/systemd/resolved.conf
        [Resolve]
        # docker dnsmasq IP
        DNS=${DNSMASQ_IP}
        # By default, systemd-resolved treats the .local domain as a special-use domain for Multicast DNS (mDNS) and doesn't forward these queries to your configured DNS servers.
        Domains=~local
        # disable MulticastDNS (mDNS)
        MulticastDNS=no
        # listen on 127.0.0.53
        DNSStubListener=yes
    EOF
fi

if ! grep /etc/resolv.conf "127.0.0.53"; then
    sudo mv /etc/resolv.conf /etc/resolv.conf.bak
    sudo echo 'nameserver 127.0.0.53' >> /etc/resolv.conf
    sudo echo 'options edns0 trust-ad' >> /etc/resolv.conf
    sudo echo 'search .' >> /etc/resolv.conf
fi
