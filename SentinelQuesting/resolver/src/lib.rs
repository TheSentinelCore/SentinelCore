//! Sentinel resolver — lowers authored intent into a runtime execution plan.
//!
//! This is a LIBRARY, not a service (ADR 09 §5). QueryServer, a CLI, CI, and batch generation all
//! call it; HTTP is one transport among several, never the home of the logic.
//!
//! Resolution is PURE: the same intent plus the same `db_fingerprint` must produce byte-identical
//! output. That is what makes bulk re-resolution diffable and the whole pipeline testable with no
//! game client.
