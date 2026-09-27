use std::path::Path;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::crypto::hex_encode;

#[derive(Clone, Serialize, Deserialize)]
pub struct ApiTokenRecord {
    pub user: String,
    pub token_id: String,
    pub salt: String,
    pub hash: String,
    pub created: u64,
    pub comment: Option<String>,
}

pub fn hash_secret(salt: &str, secret: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(salt.as_bytes());
    hasher.update(secret.as_bytes());
    hex_encode(&hasher.finalize())
}

pub fn parse_api_token(s: &str) -> Option<(String, String, String)> {
    let (user, rest) = s.split_once('!')?;
    let (token_id, secret) = rest.split_once('=')?;
    Some((user.to_owned(), token_id.to_owned(), secret.to_owned()))
}

pub fn load_tokens(path: &str) -> Vec<ApiTokenRecord> {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

pub fn save_tokens(path: &str, tokens: &[ApiTokenRecord]) -> std::io::Result<()> {
    if let Some(parent) = Path::new(path).parent() {
        std::fs::create_dir_all(parent)?;
    }
    let tmp = format!("{path}.tmp");
    std::fs::write(
        &tmp,
        serde_json::to_string_pretty(tokens).unwrap_or_default(),
    )?;
    std::fs::rename(&tmp, path)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
    }
    Ok(())
}
