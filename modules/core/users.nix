{ lib, config, ... }:
let
  parsed = config.nixwall.parsedConfig;
  usersCfg = parsed.users or { };
  defaultInitPwd = (parsed.usersDefaults or { }).initialPassword or "changeme";

  referencedGroups = lib.unique (lib.flatten (lib.mapAttrsToList (_: u: u.groups or [ ]) usersCfg));

  groupsAttrset = lib.listToAttrs (
    map (g: {
      name = g;
      value = { };
    }) referencedGroups
  );

  sudoRules = lib.concatMap (
    name:
    lib.optional (usersCfg.${name}.passwordlessSudo or false) {
      users = [ name ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ) (lib.attrNames usersCfg);

  userAttrs = lib.mapAttrs (
    name: u:
    let
      isWheel = u.wheel or false;
      extraGroups = lib.unique ((u.groups or [ ]) ++ lib.optional isWheel "wheel");
    in
    {
      isNormalUser = lib.mkDefault true;
      createHome = lib.mkDefault true;
      home = lib.mkDefault "/home/${name}";
      inherit extraGroups;
    }
    // lib.optionalAttrs (u ? shell) { inherit (u) shell; }
    // lib.optionalAttrs (u ? description) { inherit (u) description; }
    // lib.optionalAttrs (u ? uid) { inherit (u) uid; }
    // lib.optionalAttrs (u ? passwordHash) { hashedPassword = u.passwordHash; }
    // lib.optionalAttrs (!(u ? passwordHash)) {
      initialPassword = u.initialPassword or defaultInitPwd;
    }
  ) usersCfg;
in
{
  config = lib.mkIf (config.nixwall.enable && usersCfg != { }) {
    assertions = [
      {
        assertion = defaultInitPwd != "";
        message = "nixwall: usersDefaults.initialPassword must not be empty.";
      }
    ];

    users.groups = groupsAttrset;
    users.users = userAttrs;

    security.sudo = {
      enable = lib.mkDefault true;
      extraRules = sudoRules;
    };
  };
}
