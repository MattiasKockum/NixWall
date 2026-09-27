use std::path::Path;

use axum::{
    Json,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde::Deserialize;
use serde_json::json;

use crate::state::AppState;
use crate::util::{api_error, output_to_value, run};

#[derive(Deserialize)]
pub struct CommitBody {
    pub message: String,
}

pub async fn git_commit(State(ctx): State<AppState>, Json(body): Json<CommitBody>) -> Response {
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
pub struct PushBody {
    #[serde(default = "default_remote")]
    pub remote: String,
    #[serde(default = "default_branch")]
    pub branch: String,
}
fn default_remote() -> String {
    "origin".into()
}
fn default_branch() -> String {
    "HEAD".into()
}

pub async fn git_push(State(ctx): State<AppState>, Json(body): Json<PushBody>) -> Response {
    if !Path::new(&ctx.cfg.repo_dir).join(".git").is_dir() {
        return api_error(StatusCode::BAD_REQUEST, "Not a git repository");
    }
    let out = run(
        &[&ctx.cfg.git_bin, "push", &body.remote, &body.branch],
        Some(&ctx.cfg.repo_dir),
    );
    Json(output_to_value(&out)).into_response()
}
