# Proposal: Sentinel Lua Audit Remediation

## Intent

SentinelCore runs unattended. A static audit of `sentinel/` produced an evidence-backed
findings register (A1..F12) in which the P0 defects cause **silent wrong behavior**: the
questing executor reports `"success"` while doing nothing (A2, A3, A5, A6), one flaky action
kills a whole operation in ~1s (A1, PROVEN), a class-detection race runs the wrong rotation
for the whole session (B2), an uncaught throw in questing stops the survival combat module from
ever ticking (B1, PROVEN), the only runaway-chase leash is unreachable (B3), and castability
checks fail open (C1). Correctness on the unattended path is the driving value. This change
remediates the register by risk, not by convenience.

## Scope

### In Scope
- `sentinel/` Lua tree only: questing executor, runtime wiring, combat internals, shared
  helpers, EventBus observability, the offline test harness, dead code, and architecture debt
  named in the register.
- Lua-side handling of Rust contract fields the Lua **consumes**: `RuntimeKill.loot/ignore_elites`
  (A4) and `RuntimeFlight.destination` (A7). Fixed on the Lua side only.

### Out of Scope
- `Emulators/`, `graphify-out/`, `.codegraph/`.
- All Rust trees (`sentinel-questing`, `SentinelNavServer`, `SentinelQueryServer`) — no Rust edits.
- REFUTED items (register lines 117-129) — do not re-raise.
- The 34 unaudited files (register lines 133-147) — a follow-up audit is the right vehicle.

## Capabilities

### New Capabilities
- `combat-lifecycle-integrity`: class detection, engage/leash boundary, and tick isolation.
- `navigation-ownership`: single-owner protocol over the shared nav client.
- `runtime-event-observability`: subscribed diagnostics for the silent-failure surfaces.

### Modified Capabilities
- `questing-runtime-execution`: correct action-handler contracts, retry accounting, and
  completion gating.

## Approach

Deliver as **chained PRs**, each independently landable and verifiable, sequenced P0 first.
Behavior fixes are paired with the test-integrity fix that validates them, because several
current tests encode the bug (D1 asserts A3's broken contract and WILL fail once A3 is fixed).

| PR | Workstream | Findings | Verify |
|----|-----------|----------|--------|
| 1 | Tick isolation + registry order | B1, F2, F8 | offline (repro) |
| 2 | Questing action contracts + coupled tests | A2,A3,A5,A6,A8 + D1,D2 | offline + in-game |
| 3 | Questing retry/completion/nav accounting | A1,A4,A7,A9,A10,A11,B5 | offline (repro) |
| 4 | Combat lifecycle | B2,B3,B6,B7 | in-game |
| 5 | Nav ownership | B4 | in-game |
| 6 | spell_helper convention | C1,C2,C3 | in-game |
| 7 | EventBus observability | C4,C5,E6 | offline |
| 8 | Test integrity + harness | D3,D4,D5,D6 | offline |
| 9 | Dead code | E1-E5 | offline |
| 10 | Architecture debt | C6-C9,F1,F3-F7,F9-F12 | offline |

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `modules/questing/runtime_action.lua`, `runtime_profile.lua`, `module.lua` | Modified | Handler contracts, retry accounting, gating |
| `modules/combat/module.lua`, `chase_controller.lua`, `context_builder.lua` | Modified | Class race, leash, engage dedup |
| `runtime/module_registry.lua`, `runtime/app.lua` | Modified | Per-module tick isolation, order |
| `integrations/nav_client/adapter.lua` | Modified | Ownership protocol |
| `shared/spell_helper.lua`, `aoe_helper.lua` | Modified | Colon-call convention, fail-open |
| `core/event_bus.lua`, `main.lua` | Modified | Diagnostic subscribers |
| `tests/**` | Modified | Un-encode bugs, remove fictional mocks |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Fixing behavior makes green tests fail (D1↔A3) | High | Pair test fix with behavior fix in same PR |
| B6/C1/C3/D4 unverifiable offline (helpers nil) | High | In-game verify via `mcp__lx-debug__game_eval`; label per finding |
| Scope creep into 34 unaudited files | Medium | Any edit there needs its own read-first step; else deferred |
| Chained PRs drift from base | Medium | Rebase each slice on the prior; keep slices small |

**Verifiability split**: statically/offline verifiable — A1, A2, A9, A10, A11, B1, B5, C4, C5,
E*, D2, D5, D6, F2, F8. In-game only (injector-provided helpers nil offline) — A3, A4, A5, A6,
A7, A8, B2, B3, B4, B6, B7, C1, C2, C3, D4.

## Rollback Plan

Every PR is one coherent, independently revertible slice. Behavioral fixes are shipped-code
edits, so rollback = `git revert` of that PR's merge; because each slice is self-contained and
targets the prior slice's branch, reverting one does not orphan others. Where a behavior fix and
its test un-encoding ship together (PR 2), they revert together as a unit, restoring both the old
behavior and the old (bug-encoding) assertion so the suite stays internally consistent. No data
migrations, no schema changes, no Rust changes — rollback is code-only.

## Dependencies

- In-game verification requires a running client and the `lx-debug` eval bridge.
- Offline suite runs via `luajit sentinel/tests/run_offline.lua` (no `lua` binary; D6).

## Success Criteria

- [ ] No questing handler returns `"success"` for work it did not perform (A2,A3,A5,A6,A8).
- [ ] A1 repro no longer collapses an operation on a single flaky action.
- [ ] B1 repro shows combat still ticks when questing throws.
- [ ] Wrong-class-rotation race (B2) and unreachable leash (B3) closed and verified in-game.
- [ ] No offline test encodes a known-broken contract (D1,D2,D3); suite green and honest.
- [ ] Register items either remediated or explicitly deferred with rationale.
