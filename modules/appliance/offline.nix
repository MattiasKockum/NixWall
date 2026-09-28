{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.nixwall.appliance.offlineRebuilds.enable =
    lib.mkEnableOption "keeping build-time dependencies in the system closure so config.toml edits rebuild without network access"
    // {
      default = true;
    };

  config =
    lib.mkIf (config.nixwall.appliance.enable && config.nixwall.appliance.offlineRebuilds.enable)
      {
        system.extraDependencies = [
          pkgs.stdenvNoCC
          pkgs.jq
          pkgs.lndir
          pkgs.libredirect
          pkgs.lklWithFirewall.lib
          config.system.build.etc.inputDerivation
          (pkgs.perl.withPackages (
            p: with p; [
              ConfigIniFiles
              FileSlurp
            ]
          ))
          (config.system.build.initialRamdisk.overrideAttrs (_: {
            unsafeDiscardReferences.out = false;
          })).inputDerivation
        ];
      };
}
