{ lib, config, ... }:
let
  parsed = config.nixwall.parsedConfig;
  sshCfg = (parsed.services or { }).ssh or { };
  enabled = sshCfg.enable or false;
  passwordAuth = sshCfg.passwordAuth or false;
  permitRoot = sshCfg.permitRootLogin or "no";
  listenZones = sshCfg.listenZones or [ ];
  rootKeys = (sshCfg.root or { }).authorizedKeys or [ ];
  sshUsers = sshCfg.users or { };

  zoneToIface = parsed.interfaces or { };
  addresses = (parsed.network or { }).addresses or { };

  getIP =
    zone:
    let
      cidr = addresses.${zone} or null;
    in
    if cidr == null then null else lib.head (lib.splitString "/" cidr);

  listenAddrs = lib.filter (x: x.addr != null) (
    map (z: {
      addr = getIP z;
      port = 22;
    }) listenZones
  );

  userKeyDecls = lib.mapAttrs (_: u: {
    openssh.authorizedKeys.keys = u.sshAuthorizedKeys or [ ];
  }) sshUsers;
in
{
  config = lib.mkIf (config.nixwall.enable && enabled) {
    assertions = [
      {
        assertion = lib.all (z: lib.hasAttr z zoneToIface) listenZones;
        message = "nixwall: every services.ssh.listenZones entry must exist in interfaces mapping.";
      }
      {
        assertion = builtins.isList rootKeys && lib.all lib.isString rootKeys;
        message = "nixwall: services.ssh.root.authorizedKeys must be a list of strings.";
      }
      {
        assertion = lib.all (name: lib.hasAttr name config.users.users) (lib.attrNames sshUsers);
        message = "nixwall: every services.ssh.users.<name> must be declared in nixwall users config.";
      }
      {
        assertion = lib.elem permitRoot [
          "yes"
          "no"
          "prohibit-password"
          "without-password"
          "forced-commands-only"
        ];
        message = "nixwall: services.ssh.permitRootLogin must be one of: yes, no, prohibit-password, without-password, forced-commands-only.";
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
      listenAddresses = listenAddrs;
    };

    users.users =
      userKeyDecls
      // lib.optionalAttrs (rootKeys != [ ]) {
        root.openssh.authorizedKeys.keys = rootKeys;
      };
  };
}
