#!/usr/bin/env bash
set -euo pipefail

confirm_or_exit() {
	echo "This will WIPE the target disk(s) as defined by the disko file."
	if [ "${YES:-0}" -ne 1 ]; then
		read -r -p "Proceed? [yes/NO] " ans
		case "$ans" in
		[Yy][Ee][Ss]) ;;
		*)
			echo "Aborted."
			exit 1
			;;
		esac
	fi
}
