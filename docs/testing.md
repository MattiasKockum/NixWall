# Test suite

To run all tests

```sh
nix flake check -L
```

To run a specific test

```sh
nix build .#checks.x86_64-linux.<test-name> -L
```

## Dyncamic test

```sh
nix build -L .#checks.x86_64-linux.<test-name>.driver
./result/bin/nixos-test-driver --interactive
```

Then in the REPL

```sh
start_all()
...
machine-name.shell_interact()
...
quit()
```

## Test the installer

### Full offline install

Requires having an offline vmbr1.

```sh
nix build .#nixosConfigurations.installerIso.config.system.build.isoImage
ISO_FILE=$(ls result/iso)
sudo virt-install \
  --name nixwall \
  --ram 8192 --vcpus 4 \
  --os-variant generic \
  --cdrom "result/iso/$ISO_FILE" \
  --disk size=20,format=qcow2,bus=virtio \
  --network bridge=vmbr1,model=virtio,mac=52:54:00:aa:00:01 \
  --network bridge=vmbr1,model=virtio,mac=52:54:00:aa:00:02 \
  --graphics spice \
  --boot useserial=off \
  --noautoconsole --wait 0
```

### Full online testing

Requires having a routed vmbr0 and an offline vmbr1.

```sh
nix build .#nixosConfigurations.installerIso.config.system.build.isoImage
ISO_FILE=$(ls result/iso)
sudo virt-install \
  --name nixwall \
  --ram 8192 --vcpus 4 \
  --os-variant generic \
  --cdrom "result/iso/$ISO_FILE" \
  --disk size=20,format=qcow2,bus=virtio \
  --network bridge=vmbr0,model=virtio,mac=52:54:00:aa:00:01 \
  --network bridge=vmbr1,model=virtio,mac=52:54:00:aa:00:02 \
  --graphics spice \
  --boot useserial=off \
  --noautoconsole --wait 0

nix build ./tests/virtual-machines/full-client-flake#nixosConfigurations.gnomeVm.config.system.build.qcow2
mkdir -p vm-disks
cp result/nixos.qcow2 vm-disks/gnome-vm.qcow2
chmod 664 vm-disks/gnome-vm.qcow2
sudo virt-install \
  --name gnome-vm \
  --ram 8192 --vcpus 4 \
  --os-variant generic \
  --import \
  --disk path=vm-disks/gnome-vm.qcow2,format=qcow2,bus=virtio \
  --network bridge=vmbr1,model=virtio,mac=52:54:00:aa:00:10 \
  --graphics spice \
  --boot useserial=off \
  --noautoconsole --wait 0
```

## Delete successful tests to re-run them

```sh
result=$(readlink -f ./result) rm ./result && nix-store --delete $result
```
