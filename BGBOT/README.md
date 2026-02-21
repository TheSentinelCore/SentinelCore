# BGBOT

BGBOT is a battleground automation module for SentinelCore (TBC-focused) built to play objectives with stable, human-like pacing instead of perfect min-max behavior.

This README is for players/testers and explains what BGBOT does today, how to run it, and what "correct" behavior should look like in real matches.

## Current State

- Status: pre-release branch seed (not production-approved yet)
- Branch: `feature/bgbot-branch-seed`
- Review gate issue: https://github.com/TheSentinelCore/SentinelCore/issues/20
- Supported battlegrounds:
  - Warsong Gulch (WSG)
  - Arathi Basin (AB)
  - Eye of the Storm (EotS)
  - Alterac Valley (AV)

## What BGBOT Is Supposed To Do

At runtime, BGBOT should:

1. Detect battleground context and match phase.
2. Build a live world snapshot (self, allies, enemies, objectives).
3. Pick one objective-driven intent at a time (carry, escort, intercept, return, fight, retreat, roam, etc.).
4. Move through SentinelNavClient while avoiding command spam and stuck loops.
5. Use lightweight combat targeting when allowed by current intent.
6. Apply small humanization delays/jitter so actions do not look perfectly robotic.

## High-Level Behavior By Battleground

### WSG

- Prioritizes flag game intents:
  - `carry_flag`
  - `escort_carrier`
  - `intercept_carrier`
  - `return_flag`
- Falls back to `fight`, `retreat`, or `roam` based on local pressure and HP.
- Handles dropped/home flag object interaction when in range.

### AB

- Scores capture nodes with ownership heuristics.
- Uses hold policy logic (do not over-expand blindly after securing key control).
- Can trigger emergency `spin_flag` behavior when enemies pressure friendly nodes.

### EotS

- Scores towers and can prioritize mid-flag based on owned-base state.
- Uses fallback roam targets when objective certainty is low.

### AV

- Uses rush-vs-turtle style weighting.
- Applies node/tower targeting with class-aware bunker pressure preference.

## How It Thinks (Simple Version)

BGBOT loop in plain language:

1. Scan world.
2. Update world model.
3. Score all candidate intents.
4. Keep current intent unless switching is clearly better and allowed.
5. Generate movement/objective action.
6. Add combat intent if valid.
7. Resolve conflicts (objective actions outrank most combat actions).
8. Apply final timing/jitter filters.
9. Execute.

This means BGBOT should look "committed" for short windows instead of twitch-switching every frame.

## In-Game Controls

Menu controls in `main.lua` currently expose:

- `Enabled`: hard on/off.
- `Role Profile`: Auto / DPS / Healer / Tankish.
- `Buff Detours`: allow nearby buff detours when judged safe.
- `Force Action Phase`: fallback for servers with broken phase APIs.
- Debug toggles: perception/world/intent/combat/nav logging.
- Diagnostics capture: snapshot/event NDJSON for troubleshooting.

## Installation and Runtime Requirements

You need:

1. SentinelCore runtime with plugin loading enabled.
2. SentinelNavClient configured and reachable.
3. SentinelNavServer with map/nav data for the battlegrounds you plan to test.
4. Correct in-client API availability (`core.*`, `core.game_ui.*`, `core.input.*`, object methods).

If NavClient/NavServer is down or map IDs mismatch navmesh availability, movement will fail even if strategy logic is working.

## Expected Match Lifecycle

### Queue/Prep

- Bot should avoid active objective pushes during prep.
- Should not spam movement if phase is unknown and not forced.

### Action Phase

- Bot should begin objective scoring and movement.
- Should switch intents only when scoring + anti-thrash rules allow.

### Death/Resurrect

- Should release spirit with delay and return cleanly.
- Should reset confidence after resurrect and rebuild perception.

### Match End

- Should stop navigation and avoid stale actions after finish.

## What "Healthy" Behavior Looks Like

- Intent changes happen, but not every second.
- Nav requests are throttled; no continuous move-to spam for tiny coordinate changes.
- Objective interactions fire only when in valid range.
- Low HP/outnumbered situations result in retreat/regroup behavior.
- Bot recovers from temporary nav failures without hard lock.

## Known Limitations (Current Branch)

- Combat policy depth is still baseline compared to specialized class bots.
- Humanization is present but still early-stage tuning.
- Some private-server map/phase edge-cases may still require server-specific validation.
- Long-session telemetry write behavior needs optimization.

## Troubleshooting

### Bot does nothing in BG

Check:

1. `Enabled` toggle is true.
2. BG detection is not `unknown`.
3. Match phase is actionable or `Force Action Phase` is intentionally enabled for your server.
4. Local player object is valid.

### Bot sees BG but does not move

Check:

1. SentinelNavClient is loaded and connected.
2. NavServer is reachable.
3. Current BG map is supported by nav data.
4. Nav state is not stuck in failed mode.

### Bot keeps stopping/starting

Likely causes:

1. Intent anti-thrash gates plus close score competition.
2. Unknown/broken phase API causing repeated gates.
3. Repeated nav failures causing objective down-weight/blacklist behavior.

### Objective interactions fail

Check:

1. Interaction distance is actually within range.
2. Target object still exists/is valid at interaction time.
3. Server/client supports chosen interaction call path.

## Log and Diagnostic Output

BGBOT can emit diagnostic and telemetry files under the scripts data area:

- Telemetry events and match summaries (when enabled in config/menu).
- Diagnostics snapshots/events for runtime transitions.

Use diagnostics to validate:

- Detected `bg_type`
- Match `phase` source
- Current intent and recommendation
- Nav state and repath behavior
- Entity/object counts

## Safe Review Workflow Before Merge

Follow issue #20 and do not treat this branch as release-ready until:

1. Approval gates A-F are complete.
2. P0 risks are closed.
3. Test matrix evidence is attached (including private-server cases).
4. Maintainer sign-off confirms merge readiness.

## Claude Opus Context Pack (for Main Dev Workflow)

Use this directly with Claude Opus for branch review:

```text
Review branch feature/bgbot-branch-seed for release readiness.
Focus on runtime correctness, objective logic safety, intent stability, and nav resilience.

Deliver:
1) Severity-ordered findings with exact file:line references.
2) Minimal safe patch plan (no broad rewrites).
3) Test plan with pass/fail criteria.
4) Merge/no-merge recommendation with rationale.

Critical files:
- BGBOT/main.lua
- BGBOT/core/perception/*
- BGBOT/core/world_model/*
- BGBOT/core/strategist/strategist.lua
- BGBOT/core/intent/controller.lua
- BGBOT/core/intent/intents/*
- BGBOT/bg/*/*_module.lua
- BGBOT/core/action_arbiter.lua
- BGBOT/core/combat_micro/*
- BGBOT/core/humanization/*
```

## User Expectations

BGBOT is not intended to be unbeatable or perfect. It is intended to be:

- objective aware
- stable under normal match conditions
- recoverable under failure conditions
- reviewable and improvable via structured gates

If your observed behavior diverges from this README, capture logs/diagnostics and record it against issue #20 as a concrete repro.
