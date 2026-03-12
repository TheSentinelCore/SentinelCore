use std::sync::Arc;

use parking_lot::RwLock;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StartupState {
    Init,
    Importing,
    Ready,
    Failed,
}

#[derive(Debug, Clone)]
pub struct StartupStatus {
    state: Arc<RwLock<StartupState>>,
    message: Arc<RwLock<Option<String>>>,
}

impl StartupStatus {
    pub fn new() -> Self {
        Self {
            state: Arc::new(RwLock::new(StartupState::Init)),
            message: Arc::new(RwLock::new(None)),
        }
    }

    pub fn set_importing(&self) {
        *self.state.write() = StartupState::Importing;
        *self.message.write() = None;
    }

    pub fn set_ready(&self) {
        *self.state.write() = StartupState::Ready;
        *self.message.write() = None;
    }

    pub fn set_failed(&self, message: impl Into<String>) {
        *self.state.write() = StartupState::Failed;
        *self.message.write() = Some(message.into());
    }

    pub fn snapshot(&self) -> (StartupState, Option<String>) {
        (self.state.read().clone(), self.message.read().clone())
    }
}

impl Default for StartupStatus {
    fn default() -> Self {
        Self::new()
    }
}
