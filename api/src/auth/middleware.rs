use axum::{
    body::Body,
    extract::State,
    http::{Method, Request, StatusCode, header},
    middleware::Next,
    response::Response,
};

use crate::state::AppState;
use crate::util::{api_error, unauthorized_basic_challenge};

use super::basic_auth::pam_authenticate;
use super::principal::Principal;
use super::ticket::{expected_csrf, verify_ticket};
use super::token::{hash_secret, parse_api_token};

pub async fn auth_middleware(
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
