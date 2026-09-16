#!/bin/bash
# Write the cluster image to a USB stick.   bash write-usb.sh /dev/sdX
# Erases the stick. Refuses anything that isn't a removable USB disk.
set -euo pipefail
DEV="${1:?usage: bash write-usb.sh /dev/sdX   (find it with: lsblk -o NAME,SIZE,TRAN,MODEL)}"
ISO="${BUILD:-$HOME/hpc-usb-build}/hpc-cluster-usb.iso"

[ -f "$ISO" ] || { echo "Missing $ISO - run ./build.sh first"; exit 1; }
[ "$(lsblk -dno TRAN "$DEV")" = usb ] || { echo "$DEV is not a USB disk - stopping"; exit 1; }
lsblk -o NAME,SIZE,MODEL,LABEL "$DEV"
read -r -p "ERASE $DEV and write the cluster image? Type YES: " a; [ "$a" = YES ] || exit 1

for p in $(lsblk -lnpo NAME "$DEV"); do sudo umount "$p" 2>/dev/null || true; done
sudo dd if="$ISO" of="$DEV" bs=4M conv=fsync oflag=direct status=progress
sudo cmp -n "$(stat -c %s "$ISO")" "$ISO" "$DEV" && echo "Written and verified. The stick holds cluster secrets: keep it safe, wipe it when done."
