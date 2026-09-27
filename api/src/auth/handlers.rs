use axum::{
    Extension, Json,
    extract::{Path as AxumPath, State},
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::state::AppState;
use crate::util::api_error;

use super::crypto::{hex_encode, now_unix};
use super::principal::Principal;
use super::ticket::make_ticket;
use super::token::{ApiTokenRecord, hash_secret, save_tokens};

pub async fn create_ticket(
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
pub struct CreateTokenBody {
    pub comment: Option<String>,
}

pub async fn create_token(
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

pub async fn list_tokens(
    State(ctx): State<AppState>,
    Extension(principal): Extension<Principal>,
) -> Response {
    let user = principal.user().to_owned();
    let tokens = ctx.tokens.read().await;
    let mine: Vec<serde_json::Value> = tokens
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

pub async fn delete_token(
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
