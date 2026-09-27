#[derive(Clone, Debug)]
pub struct Config {
    pub pam_service: String,
    pub ip_bin: String,
    pub git_bin: String,
    pub nxr_bin: String,
    pub nix_bin: String,
    pub sdr_bin: String,
    pub sct_bin: String,
    pub jct_bin: String,
    pub config_path: String,
    pub repo_dir: String,
    pub flake: String,
    pub host: String,
    pub port: u16,
    pub tls_cert: Option<String>,
    pub tls_key: Option<String>,
    pub ticket_secret_path: String,
    pub tokens_path: String,
    pub ticket_ttl_secs: u64,
}

impl Config {
    pub fn from_env() -> Self {
        let e =
            |name: &str, default: &str| std::env::var(name).unwrap_or_else(|_| default.to_owned());
        Self {
            pam_service: e("NW_PAM_SERVICE", "nixwall-auth"),
            ip_bin: e("NW_IP_BIN", "ip"),
            git_bin: e("NW_GIT_BIN", "git"),
            nxr_bin: e("NW_NIXOS_REBUILD_BIN", "nixos-rebuild"),
            nix_bin: e("NW_NIX_BIN", "nix"),
            sdr_bin: e("NW_SYSTEMD_RUN_BIN", "systemd-run"),
            sct_bin: e("NW_SYSTEMCTL_BIN", "systemctl"),
            jct_bin: e("NW_JOURNALCTL_BIN", "journalctl"),
            config_path: e("NW_CONFIG_PATH", "/etc/nixos/config.toml"),
            repo_dir: e("NW_REPO_DIR", "/etc/nixos"),
            flake: e("NW_FLAKE", "/etc/nixos"),
            host: e("NW_API_HOST", "127.0.0.1"),
            port: e("NW_API_PORT", "8080").parse().unwrap_or(8080),
            tls_cert: {
                let v = e("NW_API_TLS_CERT", "");
                if v.is_empty() { None } else { Some(v) }
            },
            tls_key: {
                let v = e("NW_API_TLS_KEY", "");
                if v.is_empty() { None } else { Some(v) }
            },
            ticket_secret_path: e("NW_TICKET_SECRET_PATH", "/var/lib/nixwall/ticket-secret"),
            tokens_path: e("NW_TOKENS_PATH", "/var/lib/nixwall/tokens.json"),
            ticket_ttl_secs: e("NW_TICKET_TTL_SECS", "7200").parse().unwrap_or(7200),
        }
    }
}
