# NixWall

![NixWall logo](./assets/logo/nixwall-colour.svg)

This project aims to create a modern, declarative and reproductible Firewall
based on NixOS.
WARNING : This project is still in alpha and not yet fit for production.
Expect important and breaking changes.

## About the project

NixWall is built with the intention of solving the most annoying problems
today's firewalls have which:

- Are easy to be locked out of
- Are hard to update
- Are hard to rollback to an earlier configuration
- Are hard to reproduce accross machines
- Are hard to configure correctly
- Are hard to test
- Lack modern features Linux offer that FreeBSD doesn't

That's where NixOS comes in, with it's native declarative system and rollbacks,
it is the perfect base for a firewall to be built upon.
However, NixOS can be hard to learn. That is why NixWall comes with a simple
json as an abstraction layer, to store all the configuration specific to a
firewall that the user needs.
That way:

- The end user never has to write Nix code.
- The Nix developper only writes Nix modules and don't touch the specific
json configuration.
- The API can easely talk with the json configuration.
- The json configuration is easier to debug.

## How to start

**[Download the latest NixWall ISO](https://github.com/MattiasKockum/NixWall/releases)**
Download the ISO, create a VM with that ISO and follow the instructions from
the installer.

## Getting involved

If you find interest in the project and want to get involved, feel free to
drop a PR.

Anything from documentation to tests and development of features would be
highly regarded.

## Documentation

- [Test suite](docs/testing.md)
