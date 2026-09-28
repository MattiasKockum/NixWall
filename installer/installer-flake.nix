{
  pkgs,
  lib,
  self,
}:
let
  outerLock = builtins.fromJSON (builtins.readFile ../flake.lock);

  innerLock = builtins.toJSON {
    inherit (outerLock) version;
    root = "root";
    nodes = (removeAttrs outerLock.nodes [ "root" ]) // {
      root.inputs = {
        nixpkgs = "nixpkgs";
        disko = "disko";
        nixwall = "nixwall";
      };
      nixwall = {
        inputs = outerLock.nodes.root.inputs // {
          nixpkgs = [ "nixpkgs" ];
          disko = [ "disko" ];
        };
        locked = {
          type = "github";
          owner = "MattiasKockum";
          repo = "NixWall";
          inherit (self) rev narHash lastModified;
        };
        original = {
          type = "github";
          owner = "MattiasKockum";
          repo = "NixWall";
        };
      };
    };
  };
in
assert lib.assertMsg (
  self ? rev
) "installer flake needs a clean git tree: commit your changes first (self.rev is missing)";
pkgs.runCommand "nixwall-installer-flake" { } ''
  mkdir -p $out
  cp -r ${./nixos}/. $out/
  rm -f $out/flake.lock
  cp ${pkgs.writeText "flake.lock" innerLock} $out/flake.lock
''
