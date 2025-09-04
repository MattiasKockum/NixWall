{pkgs, ...}: {
  services.resolved.enable = false;
  services.dnsmasq.enable = false;

  networking.firewall.allowedUDPPorts = [53];
  networking.firewall.allowedTCPPorts = [53];

  environment.etc."coredns/Corefile".text = ''
    .:53 {
      hosts {
        10.100.100.100 website.net
        fallthrough
      }
      log
      errors
    }
  '';

  systemd.services.dns = {
    description = "Tiny DNS server (CoreDNS)";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig = {
      DynamicUser = true;
      ExecStart = "${pkgs.coredns}/bin/coredns -conf /etc/coredns/Corefile";
      Restart = "always";
      AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
      CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
      NoNewPrivileges = true;
    };
  };
}
