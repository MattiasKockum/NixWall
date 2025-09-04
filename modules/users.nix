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

  usersCfg = parsed.users or {};
  usersDefaults = parsed.usersDefaults or {};
  defaultInitPwd = usersDefaults.initialPassword or "changeme";

  referencedGroups =
    lib.unique (lib.flatten (lib.mapAttrsToList (_: u: (u.groups or [])) usersCfg));

  groupsAttrset = lib.listToAttrs (map (g: {
      name = g;
      value = {};
    })
    referencedGroups);

  userAttrs =
    lib.mapAttrs (
      name: u: let
        isWheel = u.wheel or false;
        extraGroups = (u.groups or []) ++ (lib.optional isWheel "wheel");
      in
        {
          isNormalUser = lib.mkDefault true;
          createHome = lib.mkDefault true;
          home = lib.mkDefault "/home/${name}";
          extraGroups = lib.unique extraGroups;
        }
        // lib.optionalAttrs (u ? shell) {inherit (u) shell;}
        // lib.optionalAttrs (u ? description) {inherit (u) description;}
        // lib.optionalAttrs (u ? uid) {inherit (u) uid;}
        // lib.optionalAttrs (u ? passwordHash) {hashedPassword = u.passwordHash;}
        // (
          if !(u ? passwordHash)
          then {
            initialPassword = u.initialPassword or defaultInitPwd;
          }
          else {}
        )
    )
    usersCfg;
in {
  config = lib.mkIf (usersCfg != {}) {
    assertions = [
      {
        assertion = builtins.isAttrs usersCfg;
        message = "nixwall.users must be an attribute set of user objects.";
      }
      {
        assertion = (defaultInitPwd != null) && (defaultInitPwd != "");
        message = "nixwall.usersDefaults.initialPassword must be non-empty (only for bootstrapping).";
      }
    ];

    users.groups = groupsAttrset;
    users.users = userAttrs;
    security.sudo.enable = true;
  };
}
