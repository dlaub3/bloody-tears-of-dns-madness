#!/bin/bash

docker rm --force $(docker container ls --filter "ancestor=netutils" --format "{{.Names}}")
docker rmi netutils
sudo scripts/swap.sh /etc/systemd/resolved.conf
