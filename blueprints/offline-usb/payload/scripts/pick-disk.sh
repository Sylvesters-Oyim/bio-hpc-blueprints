#!/bin/bash
# Runs in the installer (early-commands). Picks the install disk and writes it
# into the autoinstall config, which the installer re-reads afterwards.
#   compute/head: NVMe, else an SSD (SATA), else the largest internal disk
#   backup:       largest internal disk
set -u
ROLE="$1"
CFG=/autoinstall.yaml

usb_src=$(findmnt -no SOURCE /cdrom 2>/dev/null | sed -E 's#/dev/##; s/[0-9]+$//; s/p$//')
candidates=$(lsblk -dnbo NAME,SIZE,TRAN,RM,TYPE,ROTA | awk -v skip="$usb_src" \
  '$5=="disk" && $4=="0" && $3!="usb" && $1!=skip && $1 !~ /^(loop|sr|zram)/ {print $1, $2, $6}')

echo "pick-disk: installer media=$usb_src"
echo "pick-disk: candidates:"; echo "$candidates"

largest=$(echo "$candidates" | sort -k2 -n | tail -1 | cut -d' ' -f1)
nvme=$(echo "$candidates" | grep '^nvme' | sort -k2 -n | tail -1 | cut -d' ' -f1)
ssd=$(echo "$candidates" | awk '$3=="0"' | sort -k2 -n | tail -1 | cut -d' ' -f1)

if [ "$ROLE" = backup ]; then disk=$largest
elif [ -n "$nvme" ]; then disk=$nvme
elif [ -n "$ssd" ]; then disk=$ssd
else disk=$largest; fi
if [ -z "$disk" ]; then
  echo "pick-disk: NO INTERNAL DISK FOUND - stopping so nothing is wiped" >&2
  exit 1
fi
echo "pick-disk: installing to /dev/$disk"
sed -i "s#__TARGET_DISK__#/dev/$disk#" "$CFG"
