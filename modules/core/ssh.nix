{ lib, config, ... }:
let
  parsed = config.nixwall.internal;
  sshCfg = (parsed.services or { }).ssh or { };
  enabled = sshCfg.enable or false;
  passwordAuth = sshCfg.passwordAuth or false;
  permitRoot = sshCfg.permitRootLogin or "no";
  listenZones = sshCfg.listenZones or [ ];

  users = parsed.users or { };
  sshUsers = lib.filterAttrs (_: u: (u.ssh or { }) ? authorizedKeys) users;

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
in
{
  config = lib.mkIf (config.nixwall.enable && enabled) {
    assertions = [
      {
        assertion = lib.all (z: lib.hasAttr z zoneToIface) listenZones;
        message = "nixwall: every services.ssh.listenZones entry must exist in interfaces mapping.";
      }
      {
        assertion = lib.all (name: lib.hasAttr name config.users.users) (lib.attrNames sshUsers);
        message = "nixwall: every user with a [users.<name>.ssh] block must be declared in nixwall users config.";
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
  };
}
