use std::process::{Command, Output};

use axum::{
    Json,
    http::{StatusCode, header},
    response::{IntoResponse, Response},
};
use serde::Serialize;
use serde_json::{Value, json};

pub fn run(cmd: &[&str], cwd: Option<&str>) -> Output {
    let mut builder = Command::new(cmd[0]);
    builder.args(&cmd[1..]);
    if let Some(dir) = cwd {
        builder.current_dir(dir);
    }
    builder.output().expect("failed to spawn process")
}

pub fn output_to_value(out: &Output) -> Value {
    json!({
        "rc": out.status.code().unwrap_or(-1),
        "stdout": String::from_utf8_lossy(&out.stdout),
        "stderr": String::from_utf8_lossy(&out.stderr),
    })
}

pub fn api_error(status: StatusCode, detail: impl Serialize) -> Response {
    (status, Json(json!({ "detail": detail }))).into_response()
}

pub fn unauthorized_basic_challenge() -> Response {
    (
        StatusCode::UNAUTHORIZED,
        [(header::WWW_AUTHENTICATE, "Basic realm=\"nixwall\"")],
        Json(json!({"detail": "Unauthorized"})),
    )
        .into_response()
}
