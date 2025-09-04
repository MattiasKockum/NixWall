{
  lib,
  config,
  ...
}: let
  cfg = config.nixwall;

  parsed =
    if cfg.config != null
    then cfg.config
    else lib.importJSON cfg.configFile;

  localeCfg = parsed.locale or {};

  timeZone = localeCfg.timeZone or "UTC";
  keyMap = localeCfg.consoleKeyMap or "us";
  font = localeCfg.consoleFont or null;
in {
  config = {
    assertions = [
      {
        assertion = builtins.isAttrs parsed;
        message = "nixwall: parsed config must be a JSON object.";
      }
      {
        assertion = builtins.isString timeZone;
        message = "nixwall: locale.timeZone must be a string like \"Europe/Paris\".";
      }
      {
        assertion = builtins.isString keyMap;
        message = "nixwall: locale.consoleKeyMap must be a string like \"fr\" or \"us\".";
      }
      {
        assertion = font == null || builtins.isString font;
        message = "nixwall: locale.consoleFont must be a string when set.";
      }
    ];

    time.timeZone = timeZone;

    console =
      {
        inherit keyMap;
      }
      // lib.optionalAttrs (font != null) {
        inherit font;
      };
  };
}
