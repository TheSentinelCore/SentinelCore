---
id: 1
title: "QueryServer Smoke Test"
state: open
labels: ["enhancement", "ready-for-agent", "size:small"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 01 — QueryServer Smoke Test

**What to build:** Verify the existing QueryServer crate compiles, starts, and serves real data from `tbcmangos.sqlite`. Fix any runtime issues found.

**Blocked by:** None — can start immediately.

**Acceptance criteria:**

- [ ] `cargo build` passes with zero warnings in the `sentinel-queryserver` crate
- [ ] Server starts and binds to a configurable address (see #4 for full config, but basic startup works here)
- [ ] `GET /health` returns HTTP 200 with status JSON
- [ ] `GET /api/v1/quests/search?query=wolves` returns a JSON array of quest objects with `id`, `title`, `level`, `zone` fields
- [ ] At least one integration test: start server → query quest → assert response shape and non-empty results
- [ ] Server shuts down cleanly on SIGINT/SIGTERM
