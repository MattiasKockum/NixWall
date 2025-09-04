#!/usr/bin/env bash
set -euo pipefail

run_disko() {
	header "Partition/format (disko)…"
	disko --mode disko /root/etc/nixos/installer/disko.nix
	disko --mode mount /root/etc/nixos/installer/disko.nix
}
