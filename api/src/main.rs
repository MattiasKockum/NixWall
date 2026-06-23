use std::{
    path::Path,
    process::{Command, Output},
    sync::Arc,
};

use axum::{
    Json, Router,
    body::Body,
    extract::{Path as AxumPath, Query, State},
    http::{Request, StatusCode, header},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{get, post, put},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tracing::info;
use uuid::Uuid;

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
            config_path: e("NW_CONFIG_PATH", "/etc/nixos/config.json"),
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
        }
    }
}

type AppState = Arc<Config>;

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

async fn auth_middleware(State(cfg): State<AppState>, req: Request<Body>, next: Next) -> Response {
    let auth_header = req
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Basic "));

    let Some(encoded) = auth_header else {
        return (
            StatusCode::UNAUTHORIZED,
            [(header::WWW_AUTHENTICATE, "Basic realm=\"nixwall\"")],
            Json(json!({"detail": "Unauthorized"})),
        )
            .into_response();
    };

    let decoded = match base64::Engine::decode(&base64::engine::general_purpose::STANDARD, encoded)
    {
        Ok(b) => b,
        Err(_) => {
            return api_error(
                StatusCode::UNAUTHORIZED,
                "Invalid base64 in Authorization header",
            );
        }
    };

    let creds = match std::str::from_utf8(&decoded) {
        Ok(s) => s,
        Err(_) => return api_error(StatusCode::UNAUTHORIZED, "Invalid UTF-8 in credentials"),
    };

    let Some((username, password)) = creds.split_once(':') else {
        return api_error(StatusCode::UNAUTHORIZED, "Malformed credentials");
    };

    let service = cfg.pam_service.clone();
    let user = username.to_owned();
    let pass = password.to_owned();

    let ok = tokio::task::spawn_blocking(move || {
        let mut client = pam::Client::with_password(&service).expect("Failed to initialize PAM");
        client.conversation_mut().set_credentials(&user, &pass);
        client.authenticate().is_ok()
    })
    .await
    .unwrap_or(false);

    if !ok {
        return (
            StatusCode::UNAUTHORIZED,
            [(header::WWW_AUTHENTICATE, "Basic realm=\"nixwall\"")],
            Json(json!({"detail": "Unauthorized"})),
        )
            .into_response();
    }

    next.run(req).await
}

async fn list_interfaces(State(cfg): State<AppState>) -> Response {
    let out = run(&[&cfg.ip_bin, "-j", "addr", "show"], None);
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

async fn get_config(State(cfg): State<AppState>) -> Response {
    match std::fs::read_to_string(&cfg.config_path) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            api_error(StatusCode::NOT_FOUND, "config.json not found")
        }
        Err(e) => api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
        Ok(s) => match serde_json::from_str::<Value>(&s) {
            Ok(v) => Json(v).into_response(),
            Err(_) => (
                StatusCode::OK,
                [(header::CONTENT_TYPE, "application/json")],
                s,
            )
                .into_response(),
        },
    }
}

async fn put_config(State(cfg): State<AppState>, Json(body): Json<Value>) -> Response {
    let tmp = format!("{}.tmp", cfg.config_path);
    let serialized = match serde_json::to_string_pretty(&body) {
        Ok(s) => s + "\n",
        Err(e) => return api_error(StatusCode::BAD_REQUEST, e.to_string()),
    };
    if let Err(e) = std::fs::write(&tmp, &serialized) {
        return api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string());
    }
    if let Err(e) = std::fs::rename(&tmp, &cfg.config_path) {
        return api_error(StatusCode::INTERNAL_SERVER_ERROR, e.to_string());
    }
    Json(json!({"status": "ok"})).into_response()
}

#[derive(Deserialize)]
struct CommitBody {
    message: String,
}

async fn git_commit(State(cfg): State<AppState>, Json(body): Json<CommitBody>) -> Response {
    if !Path::new(&cfg.repo_dir).join(".git").is_dir() {
        return api_error(StatusCode::BAD_REQUEST, "Not a git repository");
    }
    let cmds: &[&[&str]] = &[
        &[&cfg.git_bin, "add", "-A"],
        &[&cfg.git_bin, "commit", "-m", &body.message],
    ];
    let mut steps = Vec::new();
    for cmd in cmds {
        let out = run(cmd, Some(&cfg.repo_dir));
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

async fn git_push(State(cfg): State<AppState>, Json(body): Json<PushBody>) -> Response {
    if !Path::new(&cfg.repo_dir).join(".git").is_dir() {
        return api_error(StatusCode::BAD_REQUEST, "Not a git repository");
    }
    let out = run(
        &[&cfg.git_bin, "push", &body.remote, &body.branch],
        Some(&cfg.repo_dir),
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

async fn apply_config(State(cfg): State<AppState>, Json(body): Json<ApplyBody>) -> Response {
    let mode = &body.mode;
    if !["switch", "boot", "test"].contains(&mode.as_str()) {
        return api_error(
            StatusCode::BAD_REQUEST,
            "mode must be one of: switch, boot, test",
        );
    }

    let target = detect_attr(&cfg, body.attr.as_deref());
    let job_id = Uuid::new_v4().simple().to_string()[..10].to_owned();
    let unit = format!("nixwall-apply-{job_id}.service");
    let flake_target = format!("{}#{}", cfg.flake, target);
    let extra: Vec<String> = body.extra_args.unwrap_or_default();

    let mut cmd_owned: Vec<String> = vec![
        cfg.sdr_bin.clone(),
        "--unit".into(),
        unit.clone(),
        "--description".into(),
        "NixWall apply via API".into(),
        "--collect".into(),
        "--property".into(),
        "After=network-online.target".into(),
        "--property".into(),
        "Wants=network-online.target".into(),
        cfg.nxr_bin.clone(),
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

fn unit_status(cfg: &Config, unit: &str) -> Result<Value, Response> {
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
        return Err(api_error(StatusCode::NOT_FOUND, "unit not found"));
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
    Ok(Value::Object(map))
}

async fn apply_status(State(cfg): State<AppState>, AxumPath(job_id): AxumPath<String>) -> Response {
    let unit = format!("nixwall-apply-{job_id}.service");
    match unit_status(&cfg, &unit) {
        Ok(status) => Json(json!({"id": job_id, "unit": unit, "status": status})).into_response(),
        Err(e) => e,
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
    State(cfg): State<AppState>,
    AxumPath(job_id): AxumPath<String>,
    Query(q): Query<LogsQuery>,
) -> Response {
    let lines = q.lines.clamp(1, 5000).to_string();
    let unit = format!("nixwall-apply-{job_id}.service");
    let out = run(
        &[
            &cfg.jct_bin,
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

fn build_router(cfg: AppState) -> Router {
    let protected = Router::new()
        .route("/interfaces", get(list_interfaces))
        .route("/config", get(get_config))
        .route("/config", put(put_config))
        .route("/git/commit", post(git_commit))
        .route("/git/push", post(git_push))
        .route("/apply", post(apply_config))
        .route("/apply/{job_id}", get(apply_status))
        .route("/apply/{job_id}/logs", get(apply_logs))
        .layer(middleware::from_fn_with_state(cfg.clone(), auth_middleware));

    Router::new().merge(protected).with_state(cfg)
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "nixwall_api=info,tower_http=info".into()),
        )
        .init();

    let cfg = Arc::new(Config::from_env());
    let addr = format!("{}:{}", cfg.host, cfg.port);
    let router = build_router(cfg.clone());

    match (&cfg.tls_cert, &cfg.tls_key) {
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
