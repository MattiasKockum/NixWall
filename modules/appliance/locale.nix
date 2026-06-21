{ lib, config, ... }:
let
  parsed = config.nixwall.parsedConfig;
  localeCfg = parsed.locale or { };
  timeZone = localeCfg.timeZone or "UTC";
  keyMap = localeCfg.consoleKeyMap or "us";
  font = localeCfg.consoleFont or null;
in
{
  config = lib.mkIf (config.nixwall.enable && config.nixwall.appliance.enable) {
    time.timeZone = timeZone;

    console = {
      inherit keyMap;
    }
    // lib.optionalAttrs (font != null) { inherit font; };
  };
}
