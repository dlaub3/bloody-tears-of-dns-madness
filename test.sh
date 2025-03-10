#!/bin/bash

if [[ "$1" == "docker" ]]; then
  echo "docker"
  docker run -d -ti --rm --dns=172.17.0.2 --name netutils netutils
  docker exec netutils cat /etc/resolv.conf # points to `DNSMASQ_IP`, IP of DNSMASQ container
  docker exec netutils dig traefik.kube-system.svc.cluster.local +short
  docker exec netutils dig example.internal +short
  docker exec netutils curl traefik.kube-system.svc.cluster.local
  docker rm --force netutils
fi

if [[ "$1" == "k8s" ]]; then
  echo "k8s"
  kubectl run netutils --image=netutils --restart=Never -- sleep infinity
  kubectl exec netutils -- cat /etc/resolv.conf # points to CoreDNS, but CoreDNS can forward to `DNSMASQ_IP`
  kubectl exec netutils -- dig traefik.kube-system.svc.cluster.local +short
  kubectl exec netutils -- dig example.internal +short
  kubectl exec netutils -- curl traefik.kube-system.svc.cluster.local
  kubectl delete pod netutils
fi
