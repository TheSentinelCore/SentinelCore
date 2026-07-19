---
id: 4
title: "QueryServer Configuration"
state: open
labels: ["enhancement", "ready-for-agent", "size:small"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 04 — QueryServer Configuration

**What to build:** Make the QueryServer fully configurable via CLI arguments with no hardcoded paths or addresses. Add a proper binary entry point with `--help`.

**Blocked by:** #1 (QueryServer Smoke Test — must compile and run first)

**Acceptance criteria:**

- [ ] `Cargo.toml` has a `[[bin]]` entry for `sentinel-queryserver`
- [ ] `--help` prints usage with all available flags
- [ ] `--db-path <path>` sets the SQLite database path (default: `./tbcmangos.sqlite`)
- [ ] `--bind <addr>` sets the bind address (default: `127.0.0.1:3000`)
- [ ] `--port <port>` sets the port (default: 3000, overrides `--bind` if both given)
- [ ] Zero hardcoded file paths or addresses in source code — all config flows through CLI args
- [ ] `cargo run -- --help` works from the workspace root
- [ ] Server starts correctly with custom args: `cargo run -- --db-path /tmp/test.db --port 8080`
