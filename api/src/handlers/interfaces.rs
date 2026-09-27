use axum::{
    Json,
    extract::State,
    http::{StatusCode, header},
    response::{IntoResponse, Response},
};
use serde_json::Value;

use crate::state::AppState;
use crate::util::{api_error, run};

pub async fn list_interfaces(State(ctx): State<AppState>) -> Response {
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
