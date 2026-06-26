#!/usr/bin/env bash
set -euo pipefail

export LIBVIRT_DEFAULT_URI="qemu:///system"

ISO_NAME="$(basename "$NIXWALL_ISO")"
ISO_DEST="/var/lib/libvirt/images/$ISO_NAME"
CLIENT_DISK="/var/lib/libvirt/images/demo-client.qcow2"
CLIENT_TMPDIR="$(mktemp -d)"

cleanup() {
  echo "> Tearing down demo..."
  virsh destroy nixwall-fw 2>/dev/null || true
  virsh undefine nixwall-fw --remove-all-storage 2>/dev/null || true
  virsh destroy demo-client 2>/dev/null || true
  virsh undefine demo-client --remove-all-storage 2>/dev/null || true
  virsh net-destroy demo-lan 2>/dev/null || true
  virsh net-undefine demo-lan 2>/dev/null || true
  rm -f "$ISO_DEST"
  rm -f "$CLIENT_DISK"
  rm -rf "$CLIENT_TMPDIR"
}
trap cleanup EXIT

echo "> Copying ISO to libvirt images..."
cp "$NIXWALL_ISO" "$ISO_DEST"

echo "> Creating client VM disk..."
qemu-img create -f raw /tmp/demo-client-raw.img 8G
mkfs.ext4 -L nixos /tmp/demo-client-raw.img
qemu-img convert -f raw -O qcow2 /tmp/demo-client-raw.img "$CLIENT_DISK"
rm /tmp/demo-client-raw.img
chmod 644 "$CLIENT_DISK"

virsh net-define /dev/stdin <<'EOF'
<network>
  <name>demo-lan</name>
  <bridge name="virbr-tb" stp="on" delay="0"/>
</network>
EOF
virsh net-start demo-lan
virsh net-autostart demo-lan --disable

virt-install \
  --name nixwall-fw \
  --memory 4096 \
  --vcpus 2 \
  --disk "size=20,format=qcow2,bus=virtio" \
  --cdrom "$ISO_DEST" \
  --boot "cdrom,hd" \
  --network "network=default,model=virtio" \
  --network "network=demo-lan,model=virtio" \
  --os-variant "generic" \
  --graphics "spice" \
  --noautoconsole

echo "> Launching Gnome client VM..."
CLIENT_KERNEL="$(readlink -f "$CLIENT_VM_DISK/system/kernel")"
CLIENT_INITRD="$(readlink -f "$CLIENT_VM_DISK/system/initrd")"
CLIENT_INIT="$(readlink -f "$CLIENT_VM_DISK/system/init")"
CLIENT_PARAMS="$(tr -d '%' < "$CLIENT_VM_DISK/system/kernel-params")"
mkdir -p "$CLIENT_TMPDIR/xchg"
mkdir -p "$CLIENT_TMPDIR/shared"

virt-install \
  --name demo-client \
  --memory 2048 \
  --vcpus 2 \
  --disk "$CLIENT_DISK,format=qcow2,bus=virtio" \
  --boot "kernel=$CLIENT_KERNEL,initrd=$CLIENT_INITRD,kernel_args=$CLIENT_PARAMS init=$CLIENT_INIT" \
  --network "network=demo-lan,model=virtio" \
  --os-variant "generic" \
  --graphics "spice" \
  --noautoconsole \
  --qemu-commandline="-fsdev local,id=fsdev0,path=/nix/store,security_model=none" \
  --qemu-commandline="-device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=nix-store,addr=0x10" \
  --qemu-commandline="-fsdev local,id=fsdev1,path=$CLIENT_TMPDIR/shared,security_model=none" \
  --qemu-commandline="-device virtio-9p-pci,id=fs1,fsdev=fsdev1,mount_tag=shared,addr=0x11" \
  --qemu-commandline="-fsdev local,id=fsdev2,path=$CLIENT_TMPDIR/xchg,security_model=none" \
  --qemu-commandline="-device virtio-9p-pci,id=fs2,fsdev=fsdev2,mount_tag=xchg,addr=0x12"

echo ""
echo "> Demo is up."
echo "    NixWall : virt-viewer nixwall-fw"
echo "    Client  : virt-viewer demo-client"
echo ""
echo "Press Ctrl-C to destroy everything."

sleep infinity
