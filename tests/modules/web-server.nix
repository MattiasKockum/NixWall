{pkgs, ...}: {
  networking.firewall.allowedTCPPorts = [80];

  environment.etc."web-index.html".text = ''
    hello from server
  '';

  systemd.services.web = {
    description = "Test web server";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];

    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "web";
      WorkingDirectory = "/var/lib/web";

      ExecStartPre = "${pkgs.coreutils}/bin/install -m0644 /etc/web-index.html /var/lib/web/index.html";
      ExecStart = "${pkgs.python3}/bin/python3 -m http.server 80 --directory /var/lib/web";
      Restart = "always";

      AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
      CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
    };
  };
}
