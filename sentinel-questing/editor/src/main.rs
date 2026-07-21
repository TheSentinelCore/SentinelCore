//! Sentinel Questing Editor HTTP API Server
//!
//! Run:
//!   cargo run -p sentinel-editor
//!   SENTINEL_EDITOR_PORT=3032 SENTINEL_PROJECTS_DIR=/my/projects cargo run -p sentinel-editor
//!
//! The server starts on `0.0.0.0:3031` by default and serves the editor API
//! at `/editor/projects/*`. The Lua UI in the game talks to this server.

use sentinel_editor::server;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();
    server::start_server(None).await;
}
