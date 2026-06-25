#!/usr/bin/env bash
set -euo pipefail

do_install() {
	header "Running nixos-install"
	nixos-install --no-root-passwd --flake "/root/etc/nixos#${HOST}"

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
