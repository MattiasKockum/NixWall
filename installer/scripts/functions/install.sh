#!/usr/bin/env bash
set -euo pipefail

do_install() {
	header "Building system"
	local system
	system="$(nix build --no-link --print-out-paths --no-write-lock-file \
		"/root/etc/nixos#nixosConfigurations.${HOST}.config.system.build.toplevel")"

	header "Running nixos-install"
	nixos-install --no-root-passwd --system "$system"


	mkdir -p /mnt/etc/nixos
	cp -a /root/etc/nixos/* /mnt/etc/nixos/

	cd /mnt/etc/nixos

	git init -b main

	git config user.name "NixWall Installer"
	git config user.email "installer@nixwall.local"

	git add .
	git commit -m "feat(install): initial system configuration"

	echo
	echo "Install complete. You can now reboot."
}
