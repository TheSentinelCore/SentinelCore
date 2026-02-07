//! GatherMate2 Lua file parser
//!
//! Parses GatherMate2_Data Lua files using regex (no Lua VM needed).
//!
//! # Data Format
//!
//! GatherMate2 stores data in Lua tables:
//! ```lua
//! GatherMateData2HerbDB = {
//!     [zone_id] = {
//!         [packed_coord] = node_id,
//!     }
//! }
//! ```
//!
//! Packed coordinates are 10-digit integers in XXXXYYYY00 format.

mod lua_parser;

pub use lua_parser::{DecodedNode, NodeDatabase, Parser, RawNode, ZoneData};
