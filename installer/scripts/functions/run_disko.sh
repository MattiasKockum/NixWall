#!/usr/bin/env bash
set -euo pipefail

run_disko() {
	header "Partition/format (disko)…"
	local script
	script="$(nix build --no-link --print-out-paths --no-write-lock-file \
		"/root/etc/nixos#nixosConfigurations.${HOST}.config.system.build.diskoScript")"
	"$script"
}
