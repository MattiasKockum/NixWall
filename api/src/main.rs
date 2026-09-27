use std::{
    path::Path,
    process::{Command, Output},
    sync::Arc,
};

use axum::{
    Extension, Json, Router,
    body::Body,
    extract::{Path as AxumPath, Query, State},
    http::{Method, Request, StatusCode, header},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{delete, get, post},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio::sync::RwLock;
use toml_edit::{Array, ArrayOfTables, DocumentMut, InlineTable, Item, Table, Value as TomlValue};
use tracing::info;
use uuid::Uuid;

use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};

type HmacSha256 = Hmac<Sha256>;

#[derive(Clone, Debug)]
struct Config {
    pam_service: String,
    ip_bin: String,
    git_bin: String,
    nxr_bin: String,
    nix_bin: String,
    sdr_bin: String,
    sct_bin: String,
    jct_bin: String,
    config_path: String,
    repo_dir: String,
    flake: String,
    host: String,
    port: u16,
    tls_cert: Option<String>,
    tls_key: Option<String>,
    ticket_secret_path: String,
    tokens_path: String,
    ticket_ttl_secs: u64,
}

impl Config {
    fn from_env() -> Self {
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

#[derive(Clone, Serialize, Deserialize)]
struct ApiTokenRecord {
    user: String,
    token_id: String,
    salt: String,
    hash: String,
    created: u64,
    comment: Option<String>,
}

type TokenStore = Arc<RwLock<Vec<ApiTokenRecord>>>;

struct AppCtx {
    cfg: Config,
    ticket_secret: Vec<u8>,
    tokens: TokenStore,
}

type AppState = Arc<AppCtx>;

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn hex_decode(s: &str) -> Option<Vec<u8>> {
    if s.len() % 2 != 0 {
        return None;
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(s.get(i..i + 2)?, 16).ok())
        .collect()
}

fn hmac_sign(secret: &[u8], msg: &str) -> String {
    let mut mac = HmacSha256::new_from_slice(secret).expect("HMAC accepts a key of any size");
    mac.update(msg.as_bytes());
    hex_encode(&mac.finalize().into_bytes())
}

fn hmac_verify(secret: &[u8], msg: &str, sig_hex: &str) -> bool {
    let Some(sig_bytes) = hex_decode(sig_hex) else {
        return false;
    };
    let mut mac = HmacSha256::new_from_slice(secret).expect("HMAC accepts a key of any size");
    mac.update(msg.as_bytes());
    mac.verify_slice(&sig_bytes).is_ok()
}

fn now_unix() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

async fn pam_authenticate(service: &str, user: &str, pass: &str) -> bool {
    let service = service.to_owned();
    let user = user.to_owned();
    let pass = pass.to_owned();
    tokio::task::spawn_blocking(move || {
        let Ok(mut client) = pam::Client::with_password(&service) else {
            return false;
        };
        client.conversation_mut().set_credentials(&user, &pass);
        client.authenticate().is_ok()
    })
    .await
    .unwrap_or(false)
}

fn make_ticket(secret: &[u8], user: &str, ttl_secs: u64) -> (String, String, u64) {
    let expiry = now_unix() + ttl_secs;
    let payload = format!("{user}:{expiry}");
    let sig = hmac_sign(secret, &payload);
    let raw = format!("{payload}:{sig}");
    let ticket = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, raw.as_bytes());
    let csrf = expected_csrf(secret, user, expiry);
    (ticket, csrf, expiry)
}

fn verify_ticket(secret: &[u8], ticket: &str) -> Option<(String, u64)> {
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

fn expected_csrf(secret: &[u8], user: &str, expiry: u64) -> String {
    hmac_sign(secret, &format!("csrf:{user}:{expiry}"))
}

fn load_or_create_ticket_secret(path: &str) -> Vec<u8> {
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

fn hash_secret(salt: &str, secret: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(salt.as_bytes());
    hasher.update(secret.as_bytes());
    hex_encode(&hasher.finalize())
}

fn parse_api_token(s: &str) -> Option<(String, String, String)> {
    let (user, rest) = s.split_once('!')?;
    let (token_id, secret) = rest.split_once('=')?;
    Some((user.to_owned(), token_id.to_owned(), secret.to_owned()))
}

fn load_tokens(path: &str) -> Vec<ApiTokenRecord> {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn save_tokens(path: &str, tokens: &[ApiTokenRecord]) -> std::io::Result<()> {
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

#[derive(Clone)]
enum Principal {
    Basic(String),
    Ticket { user: String, expiry: u64 },
    ApiToken { user: String, token_id: String },
}

impl Principal {
    fn user(&self) -> &str {
        match self {
            Principal::Basic(u) => u,
            Principal::Ticket { user, .. } => user,
            Principal::ApiToken { user, .. } => user,
        }
    }
}

fn run(cmd: &[&str], cwd: Option<&str>) -> Output {
    let mut builder = Command::new(cmd[0]);
    builder.args(&cmd[1..]);
    if let Some(dir) = cwd {
        builder.current_dir(dir);
    }
    builder.output().expect("failed to spawn process")
}

fn output_to_value(out: &Output) -> Value {
    json!({
        "rc": out.status.code().unwrap_or(-1),
        "stdout": String::from_utf8_lossy(&out.stdout),
        "stderr": String::from_utf8_lossy(&out.stderr),
    })
}

fn api_error(status: StatusCode, detail: impl Serialize) -> Response {
    (status, Json(json!({ "detail": detail }))).into_response()
}

fn unauthorized_basic_challenge() -> Response {
    (
        StatusCode::UNAUTHORIZED,
        [(header::WWW_AUTHENTICATE, "Basic realm=\"nixwall\"")],
        Json(json!({"detail": "Unauthorized"})),
    )
        .into_response()
}

async fn auth_middleware(
    State(ctx): State<AppState>,
    mut req: Request<Body>,
    next: Next,
) -> Response {
    let path = req.uri().path().to_owned();
    let method = req.method().clone();

    let Some(auth_header) = req
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_owned())
    else {
        return unauthorized_basic_challenge();
    };

    if let Some(encoded) = auth_header.strip_prefix("Basic ") {
        let is_bootstrap_route =
            matches!(path.as_str(), "/auth/ticket" | "/auth/token") && method == Method::POST;
        if !is_bootstrap_route {
            return api_error(
                StatusCode::UNAUTHORIZED,
                "Basic auth is only accepted on POST /auth/ticket and POST /auth/token",
            );
        }

        let Ok(decoded) =
            base64::Engine::decode(&base64::engine::general_purpose::STANDARD, encoded)
        else {
            return api_error(
                StatusCode::UNAUTHORIZED,
                "Invalid base64 in Authorization header",
            );
        };
        let Ok(creds) = std::str::from_utf8(&decoded) else {
            return api_error(StatusCode::UNAUTHORIZED, "Invalid UTF-8 in credentials");
        };
        let Some((username, password)) = creds.split_once(':') else {
            return api_error(StatusCode::UNAUTHORIZED, "Malformed credentials");
        };

        if !pam_authenticate(&ctx.cfg.pam_service, username, password).await {
            return unauthorized_basic_challenge();
        }

        req.extensions_mut()
            .insert(Principal::Basic(username.to_owned()));
        return next.run(req).await;
    }

    if let Some(token) = auth_header.strip_prefix("Bearer ") {
        if let Some((user, expiry)) = verify_ticket(&ctx.ticket_secret, token) {
            let is_mutating = matches!(
                method,
                Method::POST | Method::PUT | Method::DELETE | Method::PATCH
            );
            if is_mutating {
                let csrf_header = req
                    .headers()
                    .get("CSRFPreventionToken")
                    .and_then(|v| v.to_str().ok())
                    .unwrap_or("");
                let expected = expected_csrf(&ctx.ticket_secret, &user, expiry);
                if csrf_header != expected {
                    return api_error(
                        StatusCode::FORBIDDEN,
                        "Missing or invalid CSRFPreventionToken",
                    );
                }
            }
            req.extensions_mut()
                .insert(Principal::Ticket { user, expiry });
            return next.run(req).await;
        }

        if let Some((user, token_id, secret)) = parse_api_token(token) {
            let tokens = ctx.tokens.read().await;
            let found = tokens
                .iter()
                .find(|r| r.user == user && r.token_id == token_id)
                .map(|r| hash_secret(&r.salt, &secret) == r.hash)
                .unwrap_or(false);
            drop(tokens);
            if found {
                req.extensions_mut()
                    .insert(Principal::ApiToken { user, token_id });
                return next.run(req).await;
            }
        }

        return api_error(StatusCode::UNAUTHORIZED, "Invalid or expired ticket/token");
    }

    unauthorized_basic_challenge()
}

async fn create_ticket(
    State(ctx): State<AppState>,
    Extension(principal): Extension<Principal>,
) -> Response {
    let Principal::Basic(user) = principal else {
        return api_error(
            StatusCode::FORBIDDEN,
            "must authenticate with username/password",
        );
    };
    let (ticket, csrf, expiry) = make_ticket(&ctx.ticket_secret, &user, ctx.cfg.ticket_ttl_secs);
    Json(json!({
        "ticket": ticket,
        "CSRFPreventionToken": csrf,
        "username": user,
        "expires": expiry,
    }))
    .into_response()
}

#[derive(Deserialize, Default)]
struct CreateTokenBody {
    comment: Option<String>,
}

async fn create_token(
    State(ctx): State<AppState>,
    Extension(principal): Extension<Principal>,
    body: Option<Json<CreateTokenBody>>,
) -> Response {
    let Principal::Basic(user) = principal else {
        return api_error(
            StatusCode::FORBIDDEN,
            "must authenticate with username/password to mint a new token",
        );
    };
    let comment = body.map(|Json(b)| b.comment).unwrap_or(None);

    let token_id = Uuid::new_v4().simple().to_string()[..8].to_owned();
    let secret_bytes: Vec<u8> = Uuid::new_v4()
        .as_bytes()
        .iter()
        .chain(Uuid::new_v4().as_bytes().iter())
        .copied()
        .collect();
    let secret = hex_encode(&secret_bytes);
    let salt = hex_encode(Uuid::new_v4().as_bytes());
    let hash = hash_secret(&salt, &secret);

    let record = ApiTokenRecord {
        user: user.clone(),
        token_id: token_id.clone(),
        salt,
        hash,
        created: now_unix(),
        comment,
    };

    let mut tokens = ctx.tokens.write().await;
    tokens.push(record);
    if let Err(e) = save_tokens(&ctx.cfg.tokens_path, &tokens) {
        tokens.pop();
        return api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string());
    }
    drop(tokens);

    Json(json!({
        "tokenid": token_id,
        "user": user,
        "full_token": format!("{user}!{token_id}={secret}"),
        "note": "Store this now! This token is secret and cannot be recovered later.",
    }))
    .into_response()
}

async fn list_tokens(
    State(ctx): State<AppState>,
    Extension(principal): Extension<Principal>,
) -> Response {
    let user = principal.user().to_owned();
    let tokens = ctx.tokens.read().await;
    let mine: Vec<Value> = tokens
        .iter()
        .filter(|t| t.user == user)
        .map(|t| {
            json!({
                "tokenid": t.token_id,
                "user": t.user,
                "created": t.created,
                "comment": t.comment,
            })
        })
        .collect();
    Json(json!(mine)).into_response()
}

async fn delete_token(
    State(ctx): State<AppState>,
    Extension(principal): Extension<Principal>,
    AxumPath(token_id): AxumPath<String>,
) -> Response {
    let user = principal.user().to_owned();
    let mut tokens = ctx.tokens.write().await;
    let before = tokens.len();
    tokens.retain(|t| !(t.token_id == token_id && t.user == user));
    if tokens.len() == before {
        return api_error(StatusCode::NOT_FOUND, "token not found");
    }
    if let Err(e) = save_tokens(&ctx.cfg.tokens_path, &tokens) {
        return api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string());
    }
    Json(json!({"status": "ok"})).into_response()
}

async fn list_interfaces(State(ctx): State<AppState>) -> Response {
    let out = run(&[&ctx.cfg.ip_bin, "-j", "addr", "show"], None);
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
        return api_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            if stderr.is_empty() {
                "ip failed".into()
            } else {
                stderr
            },
        );
    }
    match serde_json::from_slice::<Value>(&out.stdout) {
        Ok(v) => Json(v).into_response(),
        Err(_) => (
            StatusCode::OK,
            [(header::CONTENT_TYPE, "text/plain")],
            String::from_utf8_lossy(&out.stdout).into_owned(),
        )
            .into_response(),
    }
}

fn json_to_value(v: &Value) -> TomlValue {
    match v {
        Value::Null => TomlValue::from(""),
        Value::Bool(b) => TomlValue::from(*b),
        Value::Number(n) => match n.as_i64() {
            Some(i) => TomlValue::from(i),
            None => TomlValue::from(n.as_f64().unwrap_or(0.0)),
        },
        Value::String(s) => TomlValue::from(s.as_str()),
        Value::Array(a) => {
            let mut arr = Array::new();
            for e in a {
                arr.push(json_to_value(e));
            }
            TomlValue::Array(arr)
        }
        Value::Object(o) => {
            let mut t = InlineTable::new();
            for (k, val) in o {
                t.insert(k, json_to_value(val));
            }
            TomlValue::InlineTable(t)
        }
    }
}

fn json_to_item(v: &Value) -> Item {
    match v {
        Value::Object(o) => {
            let mut t = Table::new();
            for (k, val) in o {
                t.insert(k, json_to_item(val));
            }
            Item::Table(t)
        }
        Value::Array(a) if !a.is_empty() && a.iter().all(Value::is_object) => {
            let mut aot = ArrayOfTables::new();
            for e in a {
                if let Value::Object(o) = e {
                    let mut t = Table::new();
                    for (k, val) in o {
                        t.insert(k, json_to_item(val));
                    }
                    aot.push(t);
                }
            }
            Item::ArrayOfTables(aot)
        }
        _ => Item::Value(json_to_value(v)),
    }
}

fn sync_table(table: &mut Table, obj: &serde_json::Map<String, Value>) {
    let existing: Vec<String> = table.iter().map(|(k, _)| k.to_owned()).collect();
    for k in existing {
        if !obj.contains_key(&k) || obj[&k].is_null() {
            table.remove(&k);
        }
    }

    for (k, v) in obj {
        if v.is_null() {
            continue;
        }
        match (table.get_mut(k), v) {
            (Some(Item::Table(t)), Value::Object(o)) => sync_table(t, o),
            (Some(Item::Value(old)), _) if !v.is_object() => {
                let decor = old.decor().clone();
                *old = json_to_value(v);
                *old.decor_mut() = decor;
            }
            _ => {
                table.insert(k, json_to_item(v));
            }
        }
    }
}

async fn get_config(State(ctx): State<AppState>) -> Response {
    match std::fs::read_to_string(&ctx.cfg.config_path) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            api_error(StatusCode::NOT_FOUND, "config.toml not found")
        }
        Err(e) => api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
        Ok(s) => match toml::from_str::<Value>(&s) {
            Ok(v) => Json(v).into_response(),
            Err(e) => api_error(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("invalid TOML in {}: {e}", ctx.cfg.config_path),
            ),
        },
    }
}

async fn put_config(State(ctx): State<AppState>, Json(body): Json<Value>) -> Response {
    let Value::Object(obj) = &body else {
        return api_error(StatusCode::BAD_REQUEST, "body must be a JSON object");
    };

    let mut doc = match std::fs::read_to_string(&ctx.cfg.config_path) {
        Ok(s) => match s.parse::<DocumentMut>() {
            Ok(d) => d,
            Err(e) => {
                return api_error(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("invalid TOML in {}: {e}", ctx.cfg.config_path),
                );
            }
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => DocumentMut::new(),
        Err(e) => return api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };

    sync_table(doc.as_table_mut(), obj);

    let tmp = format!("{}.tmp", ctx.cfg.config_path);
    if let Err(e) = std::fs::write(&tmp, doc.to_string()) {
        return api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string());
    }
    if let Err(e) = std::fs::rename(&tmp, &ctx.cfg.config_path) {
        return api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string());
    }
    Json(json!({"status": "ok"})).into_response()
}

#[derive(Deserialize)]
struct CommitBody {
    message: String,
}

async fn git_commit(State(ctx): State<AppState>, Json(body): Json<CommitBody>) -> Response {
    if !Path::new(&ctx.cfg.repo_dir).join(".git").is_dir() {
        return api_error(StatusCode::BAD_REQUEST, "Not a git repository");
    }
    let cmds: &[&[&str]] = &[
        &[&ctx.cfg.git_bin, "add", "-A"],
        &[&ctx.cfg.git_bin, "commit", "-m", &body.message],
    ];
    let mut steps = Vec::new();
    for cmd in cmds {
        let out = run(cmd, Some(&ctx.cfg.repo_dir));
        steps.push(json!({
            "cmd": cmd.join(" "),
            "rc": out.status.code().unwrap_or(-1),
            "stdout": String::from_utf8_lossy(&out.stdout),
            "stderr": String::from_utf8_lossy(&out.stderr),
        }));
    }
    Json(json!({"steps": steps})).into_response()
}

#[derive(Deserialize)]
struct PushBody {
    #[serde(default = "default_remote")]
    remote: String,
    #[serde(default = "default_branch")]
    branch: String,
}
fn default_remote() -> String {
    "origin".into()
}
fn default_branch() -> String {
    "HEAD".into()
}

async fn git_push(State(ctx): State<AppState>, Json(body): Json<PushBody>) -> Response {
    if !Path::new(&ctx.cfg.repo_dir).join(".git").is_dir() {
        return api_error(StatusCode::BAD_REQUEST, "Not a git repository");
    }
    let out = run(
        &[&ctx.cfg.git_bin, "push", &body.remote, &body.branch],
        Some(&ctx.cfg.repo_dir),
    );
    Json(output_to_value(&out)).into_response()
}

fn detect_attr(cfg: &Config, preferred: Option<&str>) -> String {
    if let Some(p) = preferred {
        return p.to_owned();
    }
    let out = run(
        &[
            &cfg.nix_bin,
            "eval",
            "--json",
            &format!("{}#nixosConfigurations", cfg.flake),
            "--apply",
            "builtins.attrNames",
        ],
        None,
    );
    if !out.status.success() {
        return "nixwall".into();
    }
    let names: Vec<String> = serde_json::from_slice(&out.stdout).unwrap_or_default();
    if names.contains(&"nixwall".to_owned()) {
        return "nixwall".into();
    }
    if names.contains(&"machine".to_owned()) {
        return "machine".into();
    }
    names.into_iter().next().unwrap_or_else(|| "nixwall".into())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ApplyBody {
    #[serde(default = "default_mode")]
    mode: String,
    attr: Option<String>,
    extra_args: Option<Vec<String>>,
}
fn default_mode() -> String {
    "switch".into()
}

async fn apply_config(State(ctx): State<AppState>, Json(body): Json<ApplyBody>) -> Response {
    let mode = &body.mode;
    if !["switch", "boot", "test"].contains(&mode.as_str()) {
        return api_error(
            StatusCode::BAD_REQUEST,
            "mode must be one of: switch, boot, test",
        );
    }

    let target = detect_attr(&ctx.cfg, body.attr.as_deref());
    let job_id = Uuid::new_v4().simple().to_string()[..10].to_owned();
    let unit = format!("nixwall-apply-{job_id}.service");
    let flake_target = format!("{}#{}", ctx.cfg.flake, target);
    let extra: Vec<String> = body.extra_args.unwrap_or_default();

    let mut cmd_owned: Vec<String> = vec![
        ctx.cfg.sdr_bin.clone(),
        "--unit".into(),
        unit.clone(),
        "--description".into(),
        "NixWall apply via API".into(),
        "--collect".into(),
        "--property".into(),
        "After=network-online.target".into(),
        "--property".into(),
        "Wants=network-online.target".into(),
        ctx.cfg.nxr_bin.clone(),
        mode.clone(),
        "--flake".into(),
        flake_target,
        "-L".into(),
    ];
    cmd_owned.extend(extra);

    let cmd_refs: Vec<&str> = cmd_owned.iter().map(|s| s.as_str()).collect();
    let out = run(&cmd_refs, None);
    if !out.status.success() {
        return api_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({
                "message": "systemd-run failed",
                "rc": out.status.code().unwrap_or(-1),
                "stderr": String::from_utf8_lossy(&out.stderr),
                "stdout": String::from_utf8_lossy(&out.stdout),
            }),
        );
    }

    (
        StatusCode::ACCEPTED,
        Json(json!({
            "status": "queued",
            "id": job_id,
            "unit": unit,
            "mode": mode,
            "attr": target,
        })),
    )
        .into_response()
}

fn unit_status(cfg: &Config, unit: &str) -> Option<Value> {
    let out = run(
        &[
            &cfg.sct_bin,
            "show",
            unit,
            "-p",
            "ActiveState",
            "-p",
            "SubState",
            "-p",
            "ExecMainStatus",
            "-p",
            "Result",
        ],
        None,
    );
    if !out.status.success() {
        return None;
    }
    let mut map = serde_json::Map::new();
    for line in String::from_utf8_lossy(&out.stdout).lines() {
        if let Some((k, v)) = line.split_once('=') {
            let val = if k == "ExecMainStatus" {
                v.parse::<i64>()
                    .map(Value::from)
                    .unwrap_or_else(|_| Value::String(v.into()))
            } else {
                Value::String(v.into())
            };
            map.insert(k.to_owned(), val);
        }
    }
    Some(Value::Object(map))
}

async fn apply_status(State(ctx): State<AppState>, AxumPath(job_id): AxumPath<String>) -> Response {
    let unit = format!("nixwall-apply-{job_id}.service");
    match unit_status(&ctx.cfg, &unit) {
        Some(status) => Json(json!({"id": job_id, "unit": unit, "status": status})).into_response(),
        None => api_error(StatusCode::NOT_FOUND, "unit not found"),
    }
}

#[derive(Deserialize)]
struct LogsQuery {
    #[serde(default = "default_lines")]
    lines: u32,
}
fn default_lines() -> u32 {
    200
}

async fn apply_logs(
    State(ctx): State<AppState>,
    AxumPath(job_id): AxumPath<String>,
    Query(q): Query<LogsQuery>,
) -> Response {
    let lines = q.lines.clamp(1, 5000).to_string();
    let unit = format!("nixwall-apply-{job_id}.service");
    let out = run(
        &[
            &ctx.cfg.jct_bin,
            "-u",
            &unit,
            "--no-pager",
            "--output=short-iso",
            "-n",
            &lines,
        ],
        None,
    );
    if !out.status.success() {
        return api_error(StatusCode::NOT_FOUND, "unit not found or no logs");
    }
    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "text/plain")],
        String::from_utf8_lossy(&out.stdout).into_owned(),
    )
        .into_response()
}

fn build_router(ctx: AppState) -> Router {
    Router::new()
        .route("/auth/ticket", post(create_ticket))
        .route("/auth/token", post(create_token).get(list_tokens))
        .route("/auth/token/{token_id}", delete(delete_token))
        .route("/interfaces", get(list_interfaces))
        .route("/config", get(get_config).put(put_config))
        .route("/git/commit", post(git_commit))
        .route("/git/push", post(git_push))
        .route("/apply", post(apply_config))
        .route("/apply/{job_id}", get(apply_status))
        .route("/apply/{job_id}/logs", get(apply_logs))
        .layer(middleware::from_fn_with_state(ctx.clone(), auth_middleware))
        .with_state(ctx)
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "nixwall_api=info,tower_http=info".into()),
        )
        .init();

    let cfg = Config::from_env();
    let ticket_secret = load_or_create_ticket_secret(&cfg.ticket_secret_path);
    let tokens: TokenStore = Arc::new(RwLock::new(load_tokens(&cfg.tokens_path)));
    let ctx: AppState = Arc::new(AppCtx {
        cfg,
        ticket_secret,
        tokens,
    });

    let addr = format!("{}:{}", ctx.cfg.host, ctx.cfg.port);
    let router = build_router(ctx.clone());

    match (&ctx.cfg.tls_cert, &ctx.cfg.tls_key) {
        (Some(cert_path), Some(key_path)) => {
            use hyper_util::rt::{TokioExecutor, TokioIo};
            use hyper_util::server::conn::auto::Builder as HyperBuilder;
            use hyper_util::service::TowerToHyperService;
            use std::io::BufReader;
            use tokio_rustls::TlsAcceptor;
            use tokio_rustls::rustls::ServerConfig;

            let cert_file = std::fs::File::open(cert_path).expect("Cannot open cert file");
            let key_file = std::fs::File::open(key_path).expect("Cannot open key file");

            let certs: Vec<_> = rustls_pemfile::certs(&mut BufReader::new(cert_file))
                .collect::<Result<_, _>>()
                .expect("Failed to parse certs");

            let key = rustls_pemfile::private_key(&mut BufReader::new(key_file))
                .expect("Failed to read key file")
                .expect("No private key found");

            let tls_config = ServerConfig::builder()
                .with_no_client_auth()
                .with_single_cert(certs, key)
                .expect("Failed to build TLS config");

            let acceptor = TlsAcceptor::from(Arc::new(tls_config));
            let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
            info!("NixWall API listening on {addr} (TLS)");

            loop {
                let (stream, _) = listener.accept().await.unwrap();
                let acceptor = acceptor.clone();
                let router = router.clone();
                tokio::spawn(async move {
                    match acceptor.accept(stream).await {
                        Ok(tls_stream) => {
                            let io = TokioIo::new(tls_stream);
                            if let Err(e) = HyperBuilder::new(TokioExecutor::new())
                                .serve_connection(io, TowerToHyperService::new(router))
                                .await
                            {
                                tracing::warn!("Connection error: {e}");
                            }
                        }
                        Err(e) => tracing::warn!("TLS accept error: {e}"),
                    }
                });
            }
        }
        _ => {
            let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
            info!("NixWall API listening on {addr} (plain HTTP)");
            axum::serve(listener, router).await.unwrap();
        }
    }
}
