{ lib, config, ... }:
let
  cfg = config.nixwall;

  raw =
    if cfg.config != null then
      cfg.config
    else if cfg.configFile != null then
      lib.importTOML cfg.configFile
    else
      { };

  zones = raw.zones or { };

  pow2 = e: lib.foldl' (a: _: a * 2) 1 (lib.range 1 e);

  ipToInt = ip: lib.foldl' (acc: o: acc * 256 + lib.toInt o) 0 (lib.splitString "." ip);

  intToIp =
    n:
    lib.concatMapStringsSep "." (d: toString (builtins.bitAnd (n / d) 255)) [
      16777216
      65536
      256
      1
    ];

  networkOf =
    cidr:
    let
      parts = lib.splitString "/" cidr;
      prefix = lib.toInt (lib.elemAt parts 1);
      mask = 4294967296 - pow2 (32 - prefix);
    in
    "${intToIp (builtins.bitAnd (ipToInt (lib.head parts)) mask)}/${toString prefix}";

  ifaceOf = zone: z: z.name or (lib.toLower zone);

  modeOf = z: z.mode or "static";

  staticZones = lib.filterAttrs (_: z: modeOf z == "static") zones;
  dhcpClientZones = lib.filterAttrs (_: z: modeOf z == "dhcp") zones;
  natZones = lib.filterAttrs (_: z: z.masquerade or false) zones;
  serverZones = lib.filterAttrs (_: z: z ? dhcp) zones;
  gwZones = lib.filterAttrs (_: z: z ? gateway) zones;
  resolverZones = lib.filterAttrs (_: z: z ? dns) zones;

  gwZone = if gwZones == { } then null else lib.head (lib.attrValues gwZones);
  resolverZone = if resolverZones == { } then null else lib.head (lib.attrValues resolverZones);

  hasName = z: z ? name;
  hasMac = z: z ? mac;
in
{
  options.nixwall = {
    enable = lib.mkEnableOption "NixWall firewall";

    appliance.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable appliance mode. Activates the API, dashboard, git integration,
        TLS, PAM, seed-config, and boot configuration. Use this when NixWall
        owns the machine entirely. Leave disabled when adding NixWall to an
        existing NixOS configuration.
      '';
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the NixWall TOML configuration file.
        Required unless nixwall.config is set inline.
      '';
      example = "/etc/nixos/config.toml";
    };

    config = lib.mkOption {
      type = with lib.types; nullOr (attrsOf anything);
      default = null;
      description = "Inline configuration as Nix attrs. Overrides configFile. Useful in tests.";
    };

    parsedConfig = lib.mkOption {
      type = with lib.types; attrsOf anything;
      readOnly = true;
      internal = true;
      description = "Raw config, exactly as written on disk. Modules must not read this.";
      default = raw;
    };

    internal = lib.mkOption {
      type = with lib.types; attrsOf anything;
      readOnly = true;
      internal = true;
      description = ''
        Normalized view of the configuration. This is the ONLY thing core
        modules are allowed to read: it decouples them from the on-disk schema,
        so a future format change touches this file and nothing else.
      '';
      default = raw // {
        interfaces = lib.mapAttrs ifaceOf zones;

        network = {
          hostname = raw.hostname or "nixwall";
          addresses = lib.mapAttrs (_: z: z.address) (lib.filterAttrs (_: z: z ? address) staticZones);
          dhcpZones = lib.attrNames dhcpClientZones;
        }
        // lib.optionalAttrs (gwZone != null) { inherit (gwZone) gateway; }
        // lib.optionalAttrs (resolverZone != null) { inherit (resolverZone) dns; };

        dhcp.subnets = lib.mapAttrs (_: z: {
          cidr = z.dhcp.subnet or (networkOf z.address);
          inherit (z.dhcp) range;
          leaseSeconds = z.dhcp.leaseSeconds or 86400;
        }) serverZones;

        nat.masquerade = lib.attrNames natZones;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.config != null || cfg.configFile != null;
        message = "nixwall: you must set either nixwall.config (inline) or nixwall.configFile (path to TOML).";
      }
      {
        assertion = zones != { };
        message = "nixwall: at least one zone must be defined under [zones].";
      }
      {
        assertion = lib.all (z: (hasName z || hasMac z) && !(hasName z && hasMac z)) (lib.attrValues zones);
        message = "nixwall: each zone must set exactly one of `name` (kernel interface) or `mac` (renamed by MAC).";
      }
      {
        assertion = lib.all (z: z ? address) (lib.attrValues staticZones);
        message = "nixwall: a static zone must define `address`.";
      }
      {
        assertion = lib.all (z: !(z ? address)) (lib.attrValues dhcpClientZones);
        message = "nixwall: a zone with mode = \"dhcp\" must not define `address`.";
      }
      {
        assertion = lib.all (z: (z.dhcp ? range) && ((z.dhcp ? subnet) || (z ? address))) (
          lib.attrValues serverZones
        );
        message = "nixwall: a zone serving DHCP needs `dhcp.range`, plus either `address` or `dhcp.subnet`.";
      }
      {
        assertion = lib.length (lib.attrNames gwZones) <= 1;
        message = "nixwall: at most one zone may define `gateway`.";
      }
    ];
  };
}
