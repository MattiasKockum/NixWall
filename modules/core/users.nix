{ lib, config, ... }:
let
  parsed = config.nixwall.internal;
  usersCfg = parsed.users or { };

  hasRoot = usersCfg ? root;
  rootCfg = usersCfg.root or { };
  normalUsers = lib.filterAttrs (name: _: name != "root") usersCfg;

  passwordAttrs =
    u:
    if u ? passwordHash then
      { hashedPassword = u.passwordHash; }
    else if u ? initialPassword then
      { inherit (u) initialPassword; }
    else
      { hashedPassword = "!"; };

  commonAttrs =
    u:
    passwordAttrs u
    // lib.optionalAttrs (u ? shell) { inherit (u) shell; }
    // lib.optionalAttrs (u ? description) { inherit (u) description; }
    // {
      openssh.authorizedKeys.keys = (u.ssh or { }).authorizedKeys or [ ];
    };

  normalAttrs =
    name: u:
    let
      isWheel = u.wheel or false;
      extraGroups = lib.unique ((u.groups or [ ]) ++ lib.optional isWheel "wheel");
    in
    commonAttrs u
    // {
      isNormalUser = lib.mkDefault true;
      createHome = lib.mkDefault true;
      home = lib.mkDefault "/home/${name}";
      inherit extraGroups;
    }
    // lib.optionalAttrs (u ? uid) { inherit (u) uid; };

  rootAttrs = commonAttrs rootCfg;

  referencedGroups = lib.unique (
    lib.flatten (lib.mapAttrsToList (_: u: u.groups or [ ]) normalUsers)
  );
  groupsAttrset = lib.genAttrs referencedGroups (_: { });

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
in
{
  config = lib.mkIf (config.nixwall.enable && usersCfg != { }) {
    assertions = [
      {
        assertion = !((rootCfg ? initialPassword) && (rootCfg ? passwordHash));
        message = "nixwall: [users.root] cannot set both initialPassword and passwordHash.";
      }
      {
        assertion = lib.all (u: !((u ? initialPassword) && (u ? passwordHash))) (
          lib.attrValues normalUsers
        );
        message = "nixwall: a user cannot set both initialPassword and passwordHash.";
      }
      {
        assertion = !(rootCfg ? wheel);
        message = "nixwall: [users.root] cannot set `wheel`, root already has full privilege.";
      }
      {
        assertion = !(rootCfg ? groups);
        message = "nixwall: [users.root] cannot set `groups`.";
      }
    ];

    users.groups = groupsAttrset;

    users.users =
      lib.mapAttrs normalAttrs normalUsers
      // lib.optionalAttrs hasRoot {
        root = rootAttrs;
      };

    security.sudo = {
      enable = lib.mkDefault true;
      extraRules = sudoRules;
    };
  };
}
