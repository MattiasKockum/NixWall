{
  lib,
  rustPlatform,
  pam,
  pkg-config,
}:
rustPlatform.buildRustPackage {
  pname = "nixwall-api";
  version = "0.1.0";
  src = ../api;
  cargoLock.lockFile = ../api/Cargo.lock;
  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
  ];
  buildInputs = [ pam ];
  meta = {
    description = "REST API for NixWall";
    license = lib.licenses.mit;
    maintainers = [ ];
    platforms = lib.platforms.linux;
  };
}
