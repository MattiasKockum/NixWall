#!/usr/bin/env bash
set -euo pipefail

do_offline_install() {
	header "Running nixos-install (offline)…"
	nixos-install --no-root-passwd --flake "/root/etc/nixos#${HOST}"

	mkdir -p /mnt/etc/nixos
	cp -a /root/etc/nixos/* /mnt/etc/nixos/

	echo
	echo "Install complete. You can now reboot."
}
