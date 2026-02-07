//! Event handling for the TUI

use anyhow::Result;
use crossterm::event::{self, Event};
use std::time::Duration;

/// Poll for input events with a timeout
pub fn poll_event() -> Result<Option<Event>> {
    if event::poll(Duration::from_millis(100))? {
        Ok(Some(event::read()?))
    } else {
        Ok(None)
    }
}
