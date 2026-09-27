use std::sync::Arc;

use tokio::sync::RwLock;

use crate::auth::token::ApiTokenRecord;
use crate::config::Config;

pub type TokenStore = Arc<RwLock<Vec<ApiTokenRecord>>>;

pub struct AppCtx {
    pub cfg: Config,
    pub ticket_secret: Vec<u8>,
    pub tokens: TokenStore,
}

pub type AppState = Arc<AppCtx>;
