#!/usr/bin/env bash
set -euo pipefail

_script_dir() {
	local SOURCE="${BASH_SOURCE[0]}"
	while [ -h "$SOURCE" ]; do
		local DIR
		DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
		SOURCE="$(readlink "$SOURCE")"
		[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
	done
	cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1
	pwd
}

require_root() {
	if [ "${EUID:-$(id -u)}" -ne 0 ]; then
		echo "Elevating with sudo..."
		exec sudo --preserve-env=FLAKE_DIR,DISKO_FILE,HOST,YES "$0" "$@"
	fi
}

header() { printf "\n==> %s\n" "$*"; }

set_defaults() {
	: "${HOST:=nixwall}"
	: "${FLAKE_DIR:=}"
	: "${DISKO_FILE:=}"
	: "${YES:=0}"
}

usage() {
	cat <<EOF
nixwall-install — installer for NixWall

USAGE:
  nixwall-install [--flake PATH] [--disko PATH] [--host NAME] [-y]

OPTIONS:
  --flake PATH   Path to flake directory (default: auto: /nixwall or /iso/nixwall)
  --disko PATH   Path to disko file (default: \$FLAKE_DIR/installer/disko.nix)
  --host NAME    Flake host (default: nixwall), used as: --flake <dir>#<host>
  -y             Non-interactive (assume yes)
  -h, --help     Show this help
EOF
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--flake)
			FLAKE_DIR="$2"
			shift 2
			;;
		--disko)
			DISKO_FILE="$2"
			shift 2
			;;
		--host)
			HOST="$2"
			shift 2
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
