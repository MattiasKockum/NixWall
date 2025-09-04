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

```sh
nix build .#nixosConfigurations.installerIso.config.system.build.isoImage
ISO_FILE=$(ls result/iso)
sudo virt-install \
  --name nixos-test \
  --ram 8192 --vcpus 4 \
  --os-variant generic \
  --cdrom result/iso/$ISO_FILE \
  --disk size=20,format=qcow2,bus=virtio \
  --network network=default,model=virtio,mac=52:54:00:aa:00:01 \
  --network network=default,model=virtio,mac=52:54:00:aa:00:02 \
  --graphics spice \
  --boot useserial=off \
  --noautoconsole --wait 0

```

## Delete successful tests to re-run them

```sh
result=$(readlink -f ./result) rm ./result && nix-store --delete $result
```
