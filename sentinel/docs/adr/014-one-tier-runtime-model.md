# SentinelCore — One-Tier Runtime Model

Version: 1.0
Status: Accepted
Date: 2026-07-19

Supersedes the two-tier authoring/compilation model implicit in ADR 002 §4
(ProfileManager.load→compile→activate), ADR 006 (Blueprints as a
compile-time expansion stage), and ADR 008 (seven-stage compiler lowering
an authoring Profile to a RuntimeProfile). Ratified by the project owner
on 2026-07-19, alongside ADR 013 (Lua-canonical; Rust = QueryServer only).

---

# 1. The Decision

> **Authors edit the executable form directly. There is no separate
> compile tier. "Compilation" is a thin pre-activation pass:
> validate → resolve references → cross-Operation merge. The
> RuntimeAction is the single canonical data model — both authored and
> executed.**

## 1.1 What this replaces

ADR 008 describes a seven-stage pipeline that lowers an *authoring Profile*
(Operations holding Blueprints, goals, conditions, dependencies) into a
*RuntimeProfile* (flat RuntimeActions). That two-tier split is removed.

| ADR 008 stage | Disposition |
|---------------|-------------|
| 1 Structural Validation | **Kept** — runs as pre-activation validate pass. |
| 2 Reference Resolution | **Kept** — runs at author/save time (eager), not compile time. |
| 3 Blueprint Expansion | **Deleted as a stage** — Blueprints become eager editor macros (see §2). |
| 4 Operation Dependency Resolution | **Kept** — topology check at validate time. |
| 5 Goal Coverage Validation | **Kept** — validate pass. |
| 6 Cross-Operation Optimization | **Kept** — thin merge pass before activation (SENT-6.6/6.7). |
| 7 Lowering to RuntimeProfile | **Deleted** — authoring form *is* the runtime form. |

## 1.2 Why this is best practice for WoW botting

Reference engines (Honorbuddy, WRobot) author the *executable* behavior
tree / action list directly. There is no separate compile step that
transforms a high-level profile into a runtime profile — what the author
sees is what executes. Reasons this fits our case:

- **Debuggability:** in-game, "what executed" must equal "what I authored."
  A two-tier model introduces a class of bugs where the compiled artifact
  diverges from the authored profile (exactly the `action_executor` vs
  `runtime_action_executor` contract split we had — flat `action_type` vs
  nested `payload.type`). One tier removes that entire class.
- **Single source of truth:** no RuntimeProfile cache to invalidate, no
  content-hash to keep in sync with the authoring file.
- **Sylvanas is Lua, single-threaded, in-game:** there is no build step in
  the load path. Forcing one wastes the only thing a compiler buys a
  multi-author IDE — which we are not.

## 1.3 The single RuntimeAction contract

There is exactly **one** RuntimeAction shape, consumed by exactly **one**
executor (`runtime/action_executor.lua`):

```lua
{
  action_type = "pickup_quest",   -- snake_case, flat (NOT payload.type)
  -- ... action-specific params at top level or under `params`
  retry_policy = { ... },         -- optional
  timeout_ms = 30000,             -- optional
}
```

`runtime/runtime_action_executor.lua` (nested `payload.type`, ADR 008 §14
shape) is **retired** — its handlers are merged into `action_executor.lua`.
The snake_case vocabulary (`pickup_quest`, `turn_in_quest`, `quest_hub`,
`flight_path`, `train`, `talk_to_npc`) already used by
`blueprint_registry.lua` and normalized by `goal_coverage.lua` /
`route_analysis.lua` is the canonical vocabulary.

---

# 2. Blueprints become eager editor macros

ADR 006's Blueprints (Quest Hub, Vendor Stop, Grind Area, ...) are kept as
**authoring helpers**, not a compile stage:

- Clicking "Insert Quest Hub" in the editor **eagerly expands** the
  Blueprint into RuntimeActions and inserts them inline into the Operation's
  action list at author time.
- There is no `generated_from` provenance tracking, no "generated actions
  are not directly editable" rule (ADR 006 §18–21). Once expanded, the
  actions are ordinary authored actions. If the author wants to change
  them, they edit the actions.
- This drops ADR 006 §18–21's collapse/expand semantics. For a
  single-author Lua tool that is the right trade: those semantics exist to
  support re-expanding edited generated actions across a large team, which
  we are not.

`runtime/blueprint_registry.lua` already implements `expand` per Blueprint
and emits RuntimeActions. The editor's "insert blueprint" path calls
`expand` and appends the result directly. No compiler stage calls it.

---

# 3. Reference resolution moves to author/save time

ADR 008 §5 resolved `{ entry: 197 }` against QueryServer at compile time.
Under one-tier, resolution happens when an action is **authored or saved**
(the editor calls QueryServer and bakes the resolved NPC/quest/vendor into
the RuntimeAction). This matches ADR 011 §7's Capture workflow (resolve
once on capture). The pre-activation pass only validates that references
are already resolved (no dangling `{ entry: ... }` left).

---

# 4. Cross-Operation merge (SENT-6.6 / SENT-6.7) survives

The one optimization that *cannot* be done at author time — merging a
trailing Vendor Stop in Operation A with a leading Vendor Stop in
Operation B — remains, but as a **thin pre-activation pass** over the
already-flat RuntimeActions (not over lowered RuntimeProfile).
`route_analysis.lua:reorder_actions` + `stage_optimization.lua`'s
vendor+repair collapse are reused; they already operate on the action
lists.

---

# 5. Consequences

- `runtime/compile_pipeline.lua` and `runtime/compiler_bridge.lua`'s
  lowering/expansion stages are removed. `profile_manager:compile` becomes
  `profile_manager:prepare(profile)` = validate + (refs already resolved) +
  cross-op merge → activate directly.
- `runtime/runtime_action_executor.lua` retired; handlers merged into
  `action_executor.lua`.
- The offline harness's `test_compiler_stages` / `test_compiler_bridge`
  tests are rewritten to cover the validate+merge pass, not the 7 stages.
- `test_northshire_e2e.lua` still passes end-to-end, but the "lowering /
  provenance" sub-test becomes a "validate + merge" sub-test.
- ADR 008 remains a useful *spec of what validation/optimization must do*;
  only its two-tier mechanism is superseded.

---

End of Volume 14
