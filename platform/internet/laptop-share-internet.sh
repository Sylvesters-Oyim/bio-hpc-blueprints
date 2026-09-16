#!/bin/bash
# Share this laptop's Wi-Fi with the cluster.   bash laptop-share-internet.sh on|off admin@head-node-ip
# The laptop must be on the cluster switch with a NetworkManager profile called cluster-lan.
set -e
HEAD="${2:?usage: bash laptop-share-internet.sh on|off admin@head-node-ip}"
LAPTOP_IP=10.0.0.250/24

case "$1" in
on)
    # "shared" = NetworkManager forwards traffic from the switch out through Wi-Fi (NAT)
    nmcli con modify cluster-lan ipv4.method shared ipv4.addresses $LAPTOP_IP
    nmcli con up cluster-lan
    ssh -t "$HEAD" sudo cluster-internet on ;;
off)
    ssh -t "$HEAD" sudo cluster-internet off || true
    nmcli con modify cluster-lan ipv4.method manual ipv4.addresses $LAPTOP_IP
    nmcli con up cluster-lan ;;
*) echo "usage: $0 on|off admin@head-node-ip"; exit 1 ;;
esac
