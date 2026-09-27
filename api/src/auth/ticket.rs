use std::path::Path;

use uuid::Uuid;

use super::crypto::{hex_decode, hex_encode, hmac_sign, hmac_verify, now_unix};

pub fn make_ticket(secret: &[u8], user: &str, ttl_secs: u64) -> (String, String, u64) {
    let expiry = now_unix() + ttl_secs;
    let payload = format!("{user}:{expiry}");
    let sig = hmac_sign(secret, &payload);
    let raw = format!("{payload}:{sig}");
    let ticket = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, raw.as_bytes());
    let csrf = expected_csrf(secret, user, expiry);
    (ticket, csrf, expiry)
}

pub fn verify_ticket(secret: &[u8], ticket: &str) -> Option<(String, u64)> {
    let raw = base64::Engine::decode(&base64::engine::general_purpose::STANDARD, ticket).ok()?;
    let raw = String::from_utf8(raw).ok()?;
    let mut parts = raw.splitn(3, ':');
    let user = parts.next()?.to_owned();
    let expiry: u64 = parts.next()?.parse().ok()?;
    let sig = parts.next()?;

    if now_unix() > expiry {
        return None;
    }
    let payload = format!("{user}:{expiry}");
    if !hmac_verify(secret, &payload, sig) {
        return None;
    }
    Some((user, expiry))
}

pub fn expected_csrf(secret: &[u8], user: &str, expiry: u64) -> String {
    hmac_sign(secret, &format!("csrf:{user}:{expiry}"))
}

pub fn load_or_create_ticket_secret(path: &str) -> Vec<u8> {
    if let Ok(s) = std::fs::read_to_string(path) {
        if let Some(bytes) = hex_decode(s.trim()) {
            if bytes.len() == 32 {
                return bytes;
            }
        }
    }
    let secret: Vec<u8> = Uuid::new_v4()
        .as_bytes()
        .iter()
        .chain(Uuid::new_v4().as_bytes().iter())
        .copied()
        .collect();

    if let Some(parent) = Path::new(path).parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::write(path, hex_encode(&secret));
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
    }
    secret
}
