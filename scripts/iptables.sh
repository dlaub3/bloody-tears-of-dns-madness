#!/bin/bash

add_rules() {
    echo "Adding iptables rules..."
    sudo iptables -I INPUT -j LOG --log-prefix "DBG" --log-level 4
}

cleanup() {
    echo "Deleting iptables rules..."
    sudo iptables -D INPUT -j LOG --log-prefix "DBG" --log-level 4
    exit
}

trap cleanup ERR EXIT

add_rules

echo "Starting iptables monitoring..."
sudo journalctl -f -k | while read line; do
    if grep -q "DBG" <<< "$line" && grep -q "$1" <<< "$line"; then
        # monitor for DNS traffic to the IP specified in $1
        awk '{gsub(/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/, "\033[1;31m&\033[0m"); print}' <<< $line
    fi
done
