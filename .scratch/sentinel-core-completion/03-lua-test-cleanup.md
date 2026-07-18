---
id: 3
title: "Lua Test Cleanup & Offline Harness"
state: open
labels: ["enhancement", "ready-for-agent", "size:small"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 03 — Lua Test Cleanup & Offline Harness

**What to build:** Remove dead tests that reference deleted modules (grind, quest, BG, LFG, mail), verify the remaining test suite passes, and create an out-of-game test harness with mock Sylvannas APIs.

**Blocked by:** None — can start immediately.

**Acceptance criteria:**

- [ ] All test files referencing deleted modules (`modules/grind/`, `modules/quest/`, `modules/battleground/`, `modules/lfg/`, `modules/mail/`) are removed
- [ ] `sentinel/tests/` contains only tests for existing code (core, combat, runtime, shared)
- [ ] Running the test suite via the Sylvannas console (`_G.SentinelCore.run_tests()`) passes with zero failures (verified in-game, or documented if not runnable offline)
- [ ] `tests/run_offline.lua` exists and provides mock implementations of key Sylvannas APIs: `core.object_manager.*`, `core.input.*`, `core.spell.*`, `core.geometry.*`, `core.unit.*`
- [ ] At least 5 unit tests pass via `lua tests/run_offline.lua` (or `busted` if available) using the mock harness
- [ ] `tests/integration/` has at least one test that exercises combat-vs-dummy through the full BT tick cycle using mocked APIs
