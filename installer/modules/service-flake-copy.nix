_: {
  systemd.tmpfiles.rules = [
    "d /root 0700 root root - -"
    "d /root/etc 0755 root root - -"
    "d /root/etc/nixos 0755 root root - -"
  ];

  systemd.services.nixwall-copy-flake = {
    description = "Prepare editable NixWall flake on boot";

    wantedBy = ["multi-user.target"];
    after = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };

    script = ''
      set -eu
      SRC="/iso/nixwall"
      DEST="/root/etc/nixos"

      echo "[nixwall] Preparing editable flake at $DEST"

      if [ -z "$(ls -A "$DEST" 2>/dev/null)" ]; then
        cp -r "$SRC"/* "$DEST"/

        chown -R root:root "$DEST"
        chmod -R u+rwX "$DEST"

        echo "[nixwall] Flake copied and made writable."
      else
        echo "[nixwall] $DEST not empty, skipping copy."
      fi
    '';
  };
}
