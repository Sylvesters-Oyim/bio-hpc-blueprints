#!/bin/bash
# Nightly snapshot of the head node's /home onto the backup machine's own disk.
# Unchanged files are hard-linked to the previous snapshot, so each day costs
# only the changed data. Keeps the newest $KEEP snapshots.
set -euo pipefail
SRC=/mnt/head-home/
DEST=/backup/home
KEEP=14

mountpoint -q /mnt/head-home || mount /mnt/head-home   # fails if the head node is down
mkdir -p "$DEST"
today=$(date +%F)
latest=$(ls -1d "$DEST"/20* 2>/dev/null | tail -1 || true)

rsync -aHAX --numeric-ids --delete ${latest:+--link-dest="$latest"} "$SRC" "$DEST/$today.partial/"
rm -rf "${DEST:?}/$today"
mv "$DEST/$today.partial" "$DEST/$today"

ls -1d "$DEST"/20* | head -n -"$KEEP" | xargs -r rm -rf
echo "$(date -Is) backup ok -> $DEST/$today"
