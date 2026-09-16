#!/bin/bash
# Turns an existing Ubuntu 24.04 Desktop into the head node (keeps your desktop, files and Wi-Fi).
# Run from the USB:
#   sudo bash /media/$USER/<usb-name>/cluster/setup-headnode.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo bash \"$0\""; exit 1; }
. /etc/os-release
[ "$VERSION_ID" = "24.04" ] || { echo "This machine runs Ubuntu $VERSION_ID; the USB repo is for 24.04 only."; exit 1; }

source "$HERE/cluster.env"
HEAD=$(awk '$3=="head"{print $1}' <<< "$NODES")
echo "This will configure THIS computer as head node '$HEAD' ($(awk '$3=="head"{print $2}' <<< "$NODES"))."
echo "It adds a fixed IP on the wired port."
read -r -p "Type YES to continue: " ans
[ "$ans" = YES ] || exit 1

LIVE=1 bash "$HERE/scripts/node-setup.sh" "$HEAD" "$HERE" "$HERE/repo" 2>&1 | tee /var/log/cluster-headnode-setup.log
echo
echo "Head node ready. Log: /var/log/cluster-headnode-setup.log"
echo "Next: install the other machines from the USB, then run:  sudo -iu $ADMIN_USER cluster-check"
