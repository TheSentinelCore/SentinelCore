use axum::extract::FromRef;

use crate::{config::Config, state::SharedState};

/// Combined application state passed to all route handlers.
/// Handlers extract `SharedState` or `Config` individually via `FromRef`.
#[derive(Clone)]
pub struct AppState {
    pub session: SharedState,
    pub config: Config,
}

impl FromRef<AppState> for SharedState {
    fn from_ref(app: &AppState) -> Self {
        app.session.clone()
    }
}

impl FromRef<AppState> for Config {
    fn from_ref(app: &AppState) -> Self {
        app.config.clone()
    }
}
