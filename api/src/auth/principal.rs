#[derive(Clone)]
pub enum Principal {
    Basic(String),
    Ticket {
        user: String,
        #[expect(dead_code)]
        expiry: u64,
    },
    ApiToken {
        user: String,
        #[expect(dead_code)]
        token_id: String,
    },
}

impl Principal {
    pub fn user(&self) -> &str {
        match self {
            Principal::Basic(u) => u,
            Principal::Ticket { user, .. } => user,
            Principal::ApiToken { user, .. } => user,
        }
    }
}
