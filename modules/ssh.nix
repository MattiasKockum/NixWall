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

  servicesCfg = parsed.services or {};
  sshCfg = servicesCfg.ssh or {};

  enabled = sshCfg.enable or false;
  passwordAuth = sshCfg.passwordAuth or false;
  permitRoot = sshCfg.permitRootLogin or "no";
  listenZones = sshCfg.listenZones or [];
  rootKeys = (sshCfg.root or {}).authorizedKeys or [];
  sshUsers = sshCfg.users or {};

  zoneToIface = parsed.interfaces or {};
  addresses = (parsed.network or {}).addresses or {};

  getIP = zone: let
    cidr = addresses.${zone} or null;
  in
    if cidr == null
    then null
    else lib.head (lib.splitString "/" cidr);

  listenAddrs =
    lib.filter (x: x.addr != null)
    (map (z: {
        addr = getIP z;
        port = 22;
      })
      listenZones);

  isStrList = xs: builtins.isList xs && lib.all lib.isString xs;

  sudoRules = lib.concatMap (
    name: let
      u = sshUsers.${name};
    in
      lib.optional (u.passwordlessSudo or false)
      {
        users = [name];
        commands = [
          {
            command = "ALL";
            options = ["NOPASSWD"];
          }
        ];
      }
  ) (lib.attrNames sshUsers);

  userKeyDecls =
    lib.mapAttrs (_name: u: {
      openssh.authorizedKeys.keys = u.sshAuthorizedKeys or [];
    })
    sshUsers;
in {
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = builtins.isAttrs parsed;
        message = "nixwall: parsed config must be a JSON object.";
      }
      {
        assertion = builtins.isList listenZones;
        message = "nixwall: services.ssh.listenZones must be a list of zone names (e.g., [\"LAN\"]).";
      }
      {
        assertion = lib.all (z: lib.hasAttr z zoneToIface) listenZones;
        message = "nixwall: every services.ssh.listenZones entry must exist in interfaces mapping.";
      }
      {
        assertion = isStrList rootKeys;
        message = "nixwall: services.ssh.root.authorizedKeys must be a list of strings.";
      }
      {
        assertion = lib.all (name: lib.hasAttr name config.users.users) (lib.attrNames sshUsers);
        message = "nixwall: every services.ssh.users.<name> must be declared in users.nix (users.users.<name>).";
      }
      {
        assertion = lib.elem permitRoot ["yes" "no" "prohibit-password" "without-password" "forced-commands-only"];
        message = "nixwall: services.ssh.permitRootLogin must be one of yes/no/prohibit-password/without-password/forced-commands-only.";
      }
    ];

    services.openssh = {
      enable = true;
      openFirewall = false;
      settings = {
        PasswordAuthentication = passwordAuth;
        PermitRootLogin = permitRoot;
        KbdInteractiveAuthentication = false;
      };
      listenAddresses = lib.mkIf (listenAddrs != []) listenAddrs;
    };

    users.users =
      userKeyDecls
      // lib.optionalAttrs (rootKeys != []) {
        root.openssh.authorizedKeys.keys = rootKeys;
      };
    security.sudo.enable = true;
    security.sudo.extraRules = sudoRules;
  };
}
