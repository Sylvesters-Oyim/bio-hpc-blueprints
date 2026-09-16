#!/bin/bash
# Try the USB image in a virtual machine first (no network, like a real node). Needs docker + KVM.
#   bash test-vm.sh install eep      # unattended install onto a fake NVMe disk
#   bash test-vm.sh boot eep         # boot it; ssh on localhost:2299
#   bash test-vm.sh screenshot eep   # save the VM screen
#   NET=cluster bash test-vm.sh boot grug   # VMs started with NET=cluster share one virtual switch
set -euo pipefail
BUILD="${BUILD:-$HOME/hpc-usb-build}"
ISO="$BUILD/hpc-cluster-usb.iso"
VM="$BUILD/vm"
MODE="${1:?install|boot}"; HOST="${2:?hostname from cluster.env}"
source "$(dirname "$0")/cluster.env"
IP=$(awk -v h="$HOST" '$1==h{print $2}' <<< "$NODES")
mkdir -p "$VM"

docker build -q -t hpc-usb-qemu - <<'EOF' >/dev/null
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends qemu-system-x86 qemu-utils xorriso socat ovmf && rm -rf /var/lib/apt/lists/*
EOF
q() { docker run --rm -i --device /dev/kvm -u "$(id -u):$(id -g)" --group-add "$(stat -c %g /dev/kvm)" \
        -v "$BUILD:$BUILD" -w "$VM" "$@"; }

if [ "$MODE" = install ]; then
  rm -f "$VM/$HOST.qcow2"
  if [ ! -f "$VM/initrd" ] || [ "$ISO" -nt "$VM/initrd" ]; then
    rm -f "$VM/vmlinuz" "$VM/initrd"
    q hpc-usb-qemu xorriso -osirrox on -indev "$ISO" -extract /casper/vmlinuz "$VM/vmlinuz" -extract /casper/initrd "$VM/initrd" 2>/dev/null
  fi
  q hpc-usb-qemu qemu-img create -f qcow2 "$VM/$HOST.qcow2" 40G >/dev/null
  q hpc-usb-qemu cp /usr/share/OVMF/OVMF_VARS_4M.fd "$VM/$HOST-vars.fd"
  echo "Installing $HOST in VM (serial log: $VM/$HOST-install.log) ..."
  q hpc-usb-qemu timeout 90m qemu-system-x86_64 -enable-kvm -m 4096 -smp 4 -cpu host -nographic -no-reboot \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd -drive if=pflash,format=raw,file="$VM/$HOST-vars.fd" \
    -nic none \
    -drive file="$VM/$HOST.qcow2",if=none,id=d0 -device nvme,drive=d0,serial=testnvme \
    -drive file="$ISO",if=none,id=usb,format=raw,readonly=on -device qemu-xhci -device usb-storage,drive=usb,removable=on \
    -kernel "$VM/vmlinuz" -initrd "$VM/initrd" \
    -append "autoinstall ds=nocloud;s=/cdrom/cluster/nocloud/$HOST/ console=ttyS0,115200 ---" \
    > "$VM/$HOST-install.log" 2>&1 || true
  tail -25 "$VM/$HOST-install.log"
elif [ "$MODE" = screenshot ]; then
  q hpc-usb-qemu bash -c "printf 'screendump $VM/screen-$HOST.ppm\n' | timeout 5 socat - UNIX-CONNECT:$VM/monitor-$HOST.sock >/dev/null; sleep 1"
  echo "$VM/screen.ppm"
else
  echo "Booting $HOST; ssh -p 2299 -i $BUILD/secrets/admin_ed25519 $ADMIN_USER@localhost"
  rm -f "$VM/monitor-$HOST.sock"
  docker rm -f "hpc-vm-$HOST" >/dev/null 2>&1 || true
  if [ "${NET:-}" = cluster ]; then
    mac=$(printf '52:54:00:10:00:%02x' "${IP##*.}")
    NIC="-nic socket,mcast=230.0.0.1:12345,model=e1000e,mac=$mac"; NETARGS="--network host"
  else
    NIC="-nic user,model=e1000e,net=10.0.0.0/24,host=10.0.0.254,hostfwd=tcp::2299-$IP:22"; NETARGS="-p 2299:2299"
  fi
  q --name "hpc-vm-$HOST" $NETARGS hpc-usb-qemu qemu-system-x86_64 -enable-kvm -m 4096 -smp 4 -cpu host \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd -drive if=pflash,format=raw,file="$VM/$HOST-vars.fd" \
    -display none -vga std -monitor unix:"$VM/monitor-$HOST.sock",server,nowait -serial file:"$VM/$HOST-serial.log" \
    -drive file="$VM/$HOST.qcow2",if=none,id=d0 -device nvme,drive=d0,serial=testnvme,bootindex=0 \
    $NIC \
    > "$VM/$HOST-boot.log" 2>&1
fi
