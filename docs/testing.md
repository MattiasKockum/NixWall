# Test suite

To run all tests

```sh
nix flake check
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

## Delete successful tests to re-run them

```sh
result=$(readlink -f ./result) rm ./result && nix-store --delete $result
```
