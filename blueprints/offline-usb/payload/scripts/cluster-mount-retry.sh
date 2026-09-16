#!/bin/bash
# Mount the shared filesystems if they are missing; start slurmd once both are present.
for m in /home /shared; do
  mountpoint -q "$m" || timeout 40 mount "$m" 2>/dev/null
done
if mountpoint -q /home && mountpoint -q /shared; then
  systemctl is-active -q slurmd || systemctl start slurmd
fi
exit 0
