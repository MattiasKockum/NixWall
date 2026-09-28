#!/usr/bin/env bash
set -euo pipefail

require_root() {
	if [ "${EUID:-$(id -u)}" -ne 0 ]; then
		echo "Elevating with sudo..."
		exec sudo --preserve-env=HOST,YES,ONLINE "$0" "$@"
	fi
}

header() { printf "\n==> %s\n" "$*"; }

set_defaults() {
	: "${HOST:=nixwall}"
	: "${YES:=0}"
	: "${ONLINE:=0}"
}

usage() {
	cat <<EOF
nixwall-install, the installer for NixWall

USAGE:
  nixwall-install [--host NAME] [--online] [-y]

OPTIONS:
  --host NAME    Flake host (default: nixwall)
  --online       Allow network access (binary caches, downloads); default is offline
  -y             Non-interactive (assume yes)
  -h, --help     Show this help
EOF
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--host)
			HOST="$2"
			shift 2
			;;
		--online)
			ONLINE=1
			shift
			;;
		-y)
			YES=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			echo "Unknown argument: $1"
			usage
			exit 1
			;;
		esac
	done
}
