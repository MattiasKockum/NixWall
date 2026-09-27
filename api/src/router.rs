use axum::{
    Router, middleware,
    routing::{delete, get, post},
};

use crate::auth::auth_middleware;
use crate::auth::handlers::{create_ticket, create_token, delete_token, list_tokens};
use crate::handlers::apply::{apply_config, apply_logs, apply_status};
use crate::handlers::config_file::{get_config, put_config};
use crate::handlers::git::{git_commit, git_push};
use crate::handlers::interfaces::list_interfaces;
use crate::state::AppState;

pub fn build_router(ctx: AppState) -> Router {
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
