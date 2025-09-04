{
  pkgs,
  lib ? pkgs.lib,
}:
pkgs.stdenv.mkDerivation {
  pname = "nixwall-installer";
  version = "1.0";

  src = ./.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/nixwall-installer/lib
    mkdir -p $out/lib/nixwall-installer/functions
    mkdir -p $out/bin

    install -m 0755 nixwall-install $out/bin/nixwall-install
    install -m 0644 lib/common.sh $out/lib/nixwall-installer/lib/common.sh

    for f in functions/*.sh; do
      install -m 0644 "$f" "$out/lib/nixwall-installer/functions/$(basename "$f")"
    done

    substituteInPlace $out/bin/nixwall-install \
      --replace "__NIXWALL_SELF_DIR__" "$out/lib/nixwall-installer"

    runHook postInstall
  '';

  nativeBuildInputs = [pkgs.makeWrapper];

  postFixup = let
    runtime = with pkgs; [
      nix
      git
      disko
      parted
      e2fsprogs
      util-linux
      coreutils
      gawk
      gnugrep
      vim
    ];
  in ''
    wrapProgram $out/bin/nixwall-install \
      --prefix PATH : ${lib.makeBinPath runtime}
  '';
}
