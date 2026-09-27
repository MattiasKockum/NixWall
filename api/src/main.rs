mod auth;
mod config;
mod handlers;
mod router;
mod state;
mod util;

use std::sync::Arc;

use tokio::sync::RwLock;
use tracing::info;

use crate::auth::ticket::load_or_create_ticket_secret;
use crate::auth::token::load_tokens;
use crate::config::Config;
use crate::router::build_router;
use crate::state::{AppCtx, AppState};

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
    let tokens = Arc::new(RwLock::new(load_tokens(&cfg.tokens_path)));
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
