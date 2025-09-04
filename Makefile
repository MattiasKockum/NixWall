.PHONY: all update system

all: secrets system

update:
	@echo "Updating flake.lock..."
	nix flake update

system:
	@echo "Updating NixOS configuration..."
	nixos-rebuild switch --flake
