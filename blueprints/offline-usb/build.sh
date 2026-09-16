#!/bin/bash
# Makes hpc-cluster-usb.iso: Ubuntu Server + offline package repo + one install menu entry per machine.
# Needs internet and docker (no sudo). Big files go to $BUILD.
# First download the server ISO into $BUILD (see README).
# Faster rebuild after editing scripts/cluster.env: SKIP_REPO=1 ./build.sh
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
BUILD="${BUILD:-$HOME/hpc-usb-build}"
ISO_IN="$BUILD/ubuntu-24.04.5-live-server-amd64.iso"
ISO_OUT="$BUILD/hpc-cluster-usb.iso"
STAGE="$BUILD/stage"          # becomes /cluster on the USB
SECRETS="$BUILD/secrets"      # kept between builds so all nodes share them
source "$SRC/cluster.env"

step() { echo; echo "=== $*"; }
dk() { docker run --rm -u "$(id -u):$(id -g)" -v "$BUILD:$BUILD" -w "$BUILD" "$@"; }

[ -f "$ISO_IN" ] || { echo "Missing $ISO_IN (download it, see README)"; exit 1; }

# ------------------------------------------------------------------ secrets
# Made once and reused, so machines installed on different days still trust each other. Never commit these.
step "secrets"
mkdir -p "$SECRETS"; chmod 700 "$SECRETS"
[ -f "$SECRETS/munge.key" ] || head -c 1024 /dev/urandom > "$SECRETS/munge.key"
[ -f "$SECRETS/admin_ed25519" ] || ssh-keygen -q -t ed25519 -N "" -C "$ADMIN_USER@$CLUSTER_NAME" -f "$SECRETS/admin_ed25519"
[ -f "$SECRETS/admin-password.txt" ] || openssl rand -base64 48 | tr -dc 'A-HJ-NP-Za-km-z2-9' | cut -c1-14 | tr -d '\n' > "$SECRETS/admin-password.txt"
PASS_HASH=$(openssl passwd -6 "$(cat "$SECRETS/admin-password.txt")")

# ------------------------------------------------------------------ builder image
step "builder image"
docker build -q -t hpc-usb-builder - <<'EOF'
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends xorriso dpkg-dev ca-certificates && rm -rf /var/lib/apt/lists/*
EOF

# ------------------------------------------------------------------ ISO manifest
step "read server package manifest from ISO"
dk hpc-usb-builder xorriso -osirrox on -indev "$ISO_IN" \
  -extract /casper/ubuntu-server-minimal.manifest "$BUILD/server-minimal.manifest" \
  -extract /casper/ubuntu-server-minimal.ubuntu-server.manifest "$BUILD/server-delta.manifest" \
  -extract /boot/grub/grub.cfg "$BUILD/grub.orig.cfg" 2>/dev/null
chmod u+w "$BUILD/server-minimal.manifest" "$BUILD/server-delta.manifest" "$BUILD/grub.orig.cfg"

# ------------------------------------------------------------------ offline repo
step "offline package repo"
# Download every package (and all dependencies) so machines install with no internet.
# Sets are resolved one by one: the ISO list has systemd-timesyncd, which conflicts with chrony.
mkdir -p "$BUILD/sets" "$STAGE/repo"
# ISO manifests are diffs: keep the "+package" lines
cat "$BUILD/server-minimal.manifest" "$BUILD/server-delta.manifest" \
  | grep -E '^\+[a-z0-9]' | cut -c2- | cut -f1 | sed 's/:amd64$//' > "$BUILD/sets/1-server.txt"
if [ -f "$BUILD/manifests/filesystem.manifest" ]; then
  cut -f1 "$BUILD/manifests/filesystem.manifest" | sed 's/:amd64$//' > "$BUILD/sets/2-desktop.txt"
fi
echo $COMMON_PKGS $HEAD_PKGS openssh-server | tr ' ' '\n' > "$BUILD/sets/3-head.txt"
echo $COMMON_PKGS $COMPUTE_PKGS openssh-server | tr ' ' '\n' > "$BUILD/sets/4-compute.txt"
echo $COMMON_PKGS $BACKUP_PKGS openssh-server | tr ' ' '\n' > "$BUILD/sets/5-backup.txt"

if [ "${SKIP_REPO:-0}" = 1 ] && [ -f "$STAGE/repo/Packages.gz" ]; then
  echo "SKIP_REPO=1: reusing existing repo"
else
docker run --rm -v "$BUILD:$BUILD" ubuntu:24.04 bash -euc "
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq dpkg-dev >/dev/null
  : > /tmp/empty-status
  mkdir -p /tmp/cache/partial
  for set in '$BUILD'/sets/*.txt; do
    # keep names that exist in the archive; drop version-pinned kernel packages
    grep -E '^[a-z0-9][a-z0-9+.-]+\$' \"\$set\" | sort -u | xargs apt-cache policy 2>/dev/null \
      | awk '/^[^ ].*:\$/{p=substr(\$1,1,length(\$1)-1)} /Candidate:/{if(\$2!=\"(none)\") print p}' \
      | grep -Ev '^linux-(image|headers|modules|modules-extra|objects|signatures|tools|cloud-tools|buildinfo|hwe-[0-9.]+-(tools|headers))-[0-9]' \
      > /tmp/avail.txt
    echo \"\$(basename \$set): \$(sort -u \$set | grep -vc '^\$') requested, \$(wc -l < /tmp/avail.txt) available\"
    # empty dpkg status => apt downloads the complete closure, not only what this container lacks
    apt-get install -y --download-only \
      -o Dir::State::status=/tmp/empty-status -o Dir::Cache::archives=/tmp/cache \
      \$(cat /tmp/avail.txt) > /tmp/dl.log 2>&1 || { echo \"FAILED on \$set\"; tail -40 /tmp/dl.log; exit 1; }
  done
  cp /tmp/cache/*.deb '$STAGE/repo/'
  cd '$STAGE/repo'
  dpkg-scanpackages -m . /dev/null 2>/dev/null > Packages
  gzip -kf Packages
  chown -R $(id -u):$(id -g) '$STAGE/repo'
"
fi
echo "repo: $(ls "$STAGE/repo" | grep -c '\.deb$') packages, $(du -sh "$STAGE/repo" | cut -f1)"

# ------------------------------------------------------------------ cluster files
step "cluster config files"
rm -rf "$STAGE/scripts" "$STAGE/files" "$STAGE/secrets" "$STAGE/nocloud"
mkdir -p "$STAGE/files" "$STAGE/secrets"
cp -r "$SRC/payload/scripts" "$STAGE/"
cp "$SRC/../../platform/internet/cluster-internet" "$STAGE/scripts/"   # optional internet via a laptop
cp "$SRC/payload/setup-headnode.sh" "$SRC/cluster.env" "$STAGE/"
cp "$SECRETS/munge.key" "$SECRETS/admin_ed25519" "$SECRETS/admin_ed25519.pub" "$SECRETS/admin-password.txt" "$STAGE/secrets/"

compute_hosts=$(awk '$3=="compute"{print $1}' <<< "$NODES" | paste -sd,)
head_ip=$(awk '$3=="head"{print $2}' <<< "$NODES")
head_name=$(awk '$3=="head"{print $1}' <<< "$NODES")

cat > "$STAGE/files/slurm.conf" <<EOF
# Generated by build.sh from cluster.env - identical on every node
ClusterName=$CLUSTER_NAME
SlurmctldHost=$head_name($head_ip)
AuthType=auth/munge
SlurmUser=slurm
StateSaveLocation=/var/spool/slurmctld
SlurmdSpoolDir=/var/spool/slurmd
SlurmctldPidFile=/run/slurmctld.pid
SlurmdPidFile=/run/slurmd.pid
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
SwitchType=switch/none
MpiDefault=pmix
SrunPortRange=60001-63000
ReturnToService=2
SlurmdTimeout=120
TmpFS=/scratch
# Trust the node lines below over what slurmd detects (hybrid CPUs are miscounted)
SlurmdParameters=config_overrides

ProctrackType=proctrack/cgroup
# cgroup keeps jobs inside their CPUs/memory; no task/affinity (it mis-pins hybrid CPUs)
TaskPlugin=task/cgroup
JobAcctGatherType=jobacct_gather/cgroup

SchedulerType=sched/backfill
SelectType=select/cons_tres
# Hand out single threads, so 1-CPU jobs don't take a whole core
SelectTypeParameters=CR_CPU_Memory
DefMemPerCPU=$DEF_MEM_PER_CPU

NodeName=DEFAULT Sockets=$NODE_SOCKETS CoresPerSocket=$NODE_CORES ThreadsPerCore=$NODE_THREADS RealMemory=$NODE_REALMEM State=UNKNOWN
EOF
while read -r h ip r extra; do [ "$r" = compute ] && echo "NodeName=$h NodeAddr=$ip $extra" >> "$STAGE/files/slurm.conf"; done <<< "$NODES"
cat >> "$STAGE/files/slurm.conf" <<EOF
PartitionName=batch Nodes=$compute_hosts Default=YES DefaultTime=01:00:00 MaxTime=7-00:00:00 State=UP
EOF

cat > "$STAGE/files/cgroup.conf" <<'EOF'
CgroupPlugin=autodetect
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
AllowedRAMSpace=100
AllowedSwapSpace=0
EOF

# ------------------------------------------------------------------ autoinstall per node
step "autoinstall configs"
while read -r h ip r _; do
  [ -z "$h" ] && continue
  d="$STAGE/nocloud/$h"; mkdir -p "$d"
  echo "instance-id: $h" > "$d/meta-data"
  : > "$d/vendor-data"
  cat > "$d/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  interactive-sections: []
  refresh-installer: {update: false}
  locale: en_US.UTF-8
  keyboard: {layout: us}
  timezone: $TIMEZONE
  source: {id: ubuntu-server}
  early-commands:
    - bash /cdrom/cluster/scripts/pick-disk.sh $r
  storage:
    layout:
      name: direct
      match: {path: __TARGET_DISK__}
  network:
    version: 2
    ethernets:
      cluster0:
        match: {name: "en*"}
        dhcp4: false
        dhcp6: false
        link-local: []
        addresses: [$ip/$NETMASK_BITS]
  apt:
    fallback: offline-install
    geoip: false
  ssh:
    install-server: true
    allow-pw: true
  identity:
    hostname: $h
    username: $ADMIN_USER
    realname: HPC Admin
    password: '$PASS_HASH'
  shutdown: poweroff
  late-commands:
    - mkdir -p /target/opt/cluster-payload
    - cp -r /cdrom/cluster/scripts /cdrom/cluster/files /cdrom/cluster/secrets /cdrom/cluster/cluster.env /target/opt/cluster-payload/
    - mkdir -p /target/opt/cluster-repo
    - mount --bind /cdrom/cluster/repo /target/opt/cluster-repo
    - curtin in-target --target=/target -- bash /opt/cluster-payload/scripts/node-setup.sh $h /opt/cluster-payload /opt/cluster-repo || { echo "===== CLUSTER SETUP FAILED - last lines of /var/log/cluster-node-setup.log =====" > /dev/console; tail -40 /target/var/log/cluster-node-setup.log > /dev/console; exit 1; }
    - umount /target/opt/cluster-repo; rmdir /target/opt/cluster-repo
    - rm -rf /target/opt/cluster-payload/secrets
EOF
done <<< "$NODES"

# ------------------------------------------------------------------ boot menu
step "boot menu"
cat > "$BUILD/grub.cfg" <<'EOF'
set timeout=-1
set default=0
loadfont unicode
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

grub_platform
if [ "$grub_platform" = "efi" ]; then
menuentry "Do nothing - boot from this computer's disk" {
	exit 1
}
else
menuentry "Do nothing - remove the USB and restart" {
	halt
}
fi
EOF
while read -r h ip r _; do
  [ -z "$h" ] && continue
  label="WIPE DISK and install $h ($ip, $r)"
  [ "$r" = head ] && label="WIPE DISK and install $h as SERVER head node (only if not using a Desktop head node)"
  cat >> "$BUILD/grub.cfg" <<EOF
menuentry "$label" {
	set gfxpayload=keep
	linux	/casper/vmlinuz autoinstall 'ds=nocloud;s=/cdrom/cluster/nocloud/$h/' ---
	initrd	/casper/initrd
}
EOF
done <<< "$NODES"
cat >> "$BUILD/grub.cfg" <<'EOF'
menuentry "Manual Ubuntu Server install (normal installer)" {
	set gfxpayload=keep
	linux	/casper/vmlinuz  ---
	initrd	/casper/initrd
}
EOF

# ------------------------------------------------------------------ remaster ISO
step "write $ISO_OUT"
rm -f "$ISO_OUT"
dk hpc-usb-builder xorriso -indev "$ISO_IN" -outdev "$ISO_OUT" \
  -map "$STAGE" /cluster \
  -map "$BUILD/grub.cfg" /boot/grub/grub.cfg \
  -boot_image any replay 2>&1 | grep -Ev '^xorriso : (UPDATE|NOTE)' | tail -5
ls -lh "$ISO_OUT"
sha256sum "$ISO_OUT" | tee "$ISO_OUT.sha256"
