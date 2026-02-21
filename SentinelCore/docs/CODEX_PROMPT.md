# Production Codex Prompt (SentinelCore P0 -> P1.5)

Use the prompt below verbatim when ready to implement.

```text
You are implementing SentinelCore in this repository.

Scope lock:
- Implement only P0, P1, and P1.5.
- Do not implement questing, PvP/BG automation, or gathering mode execution.

Hard constraints:
- TBC only.
- Canonical world identity uses cmangos IDs (`map_id`, `zone_id`, `area_id`).
- No phased-content logic.
- Fail-closed policy for uncertainty or invalid context.
- Vendor selection must stay on same canonical `map_id`.
- No startup Wowhead scraping.
- Use Sylvannas APIs only (no WoW Lua API).
- Integrate with `_G.SentinelNavClient.client` for movement/navigation.
- Primary optimization goal is XP/hr.

Repository docs to follow as source of truth:
- `SentinelCore/docs/PRD.md`
- `SentinelCore/docs/TDD.md`
- `SentinelCore/docs/DATA_MODEL.md`
- `SentinelCore/docs/ARCHITECTURE.md`
- `SentinelCore/docs/NAVCLIENT_PARITY.md`
- `SentinelCore/docs/API_DESIGN.md`
- `SentinelCore/docs/IMPLEMENTATION_TICKETS.md`

Delivery requirements:
1. Implement tickets in dependency order from `SC-001` through `SC-014`.
2. Keep modules cohesive and testable.
3. Add LuaDoc annotations for public modules and methods.
4. Emit structured events and explicit error codes.
5. Ensure no critical fail-open paths remain.
6. Add/update tests for each completed ticket.

Core runtime architecture:
- Client facade + EventBus + Blackboard + StateMachine + Config + Telemetry.
- NavClient-style behavior layer:
  - `behaviors/actions`
  - `behaviors/conditions`
  - `behaviors/trees`
- Service layer:
  - NavigationAdapter
  - WorldDataAdapter
  - TargetingService
  - RotationEngine
  - CombatService
  - LootService
  - InventoryService
  - VendorService
  - RecoveryService
- Mode layer: GrindMode only for this phase.
- Future mode stubs must exist for Quest/Gather/Bg, but remain non-functional placeholders in this scope.

Rotation framework:
- Build generic rotation provider contract.
- Add initial Paladin Retribution module skeleton and integration path.
- Paladin Retribution module must support both single-target and AoE plans.
- Use queue-first casting adapter when available; guarded fallback otherwise.

Vendor behavior:
- Trigger default `min_free_slots=2`.
- Apply sell blacklist/whitelist policy.
- Fetch nearby same-map vendor candidates.
- Filter by capability/faction.
- Rank by reachable path cost (not straight-line only).
- If no viable vendor, fail closed with explicit reason.

Persistence behavior:
- Use `scripts_data/SentinelCore` only.
- Implement schemas defined in `SentinelCore/docs/SCRIPTS_DATA_SCHEMA.md`.
- Validate schema versions and use atomic writes.

Quality gates:
- Deterministic state transitions.
- Clear stop/pause/resume semantics.
- Failure escalation semantics:
  - pause
  - bounded self-restart attempts (exactly 3 max)
  - hard-stop + failed state
- Runtime dependency health checks for NavClient and SentinelQueryServer.
- Rich snapshot/telemetry payload for UI and diagnostics.

Output format:
- Show ticket-by-ticket progress.
- For each ticket: files changed, tests added, acceptance criteria status.
- End with open risks and next recommended ticket.
```
