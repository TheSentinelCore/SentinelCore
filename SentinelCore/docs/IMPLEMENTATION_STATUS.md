# SentinelCore Implementation Status (SC-001 -> SC-014)

Last updated: 2026-02-21

## Summary
- Scope baseline is implemented for P0 -> P1.5 grind operations.
- Recent parity additions include:
  - Runtime in-window event feed.
  - Settings tab with live tuning and profile-backed persistence.
  - Profile manager persistence (`runtime_profiles.v1`) with load/save/create/delete/rename.
  - Vendor return-to-grind-anchor policy.
  - Expanded inventory `special_rules` matching and validation.
  - Event payload enrichment (`timestamp`, `session_id`, `state`, canonical IDs when available).

## Ticket Status

### SC-001 Repo Skeleton + Module Layout
- Status: Complete
- Notes: Core/services/modes/behaviors/ui/test layout exists.

### SC-002 EventBus + Blackboard + StateMachine
- Status: Complete
- Notes: EventBus, Blackboard, and guarded state machine transitions present.

### SC-003 Config + Defaults + Validation
- Status: Complete (extended)
- Notes:
  - Added profiles persistence schema `runtime_profiles.v1`.
  - Added monotonic write guard on `updated_at_unix`.
  - Added vendor cache startup prune/cap behavior.

### SC-004 Client Facade + Tick Orchestration
- Status: Complete (extended)
- Notes:
  - Public lifecycle methods implemented.
  - Added runtime/profile/policy management APIs and log-feed APIs.

### SC-005 NavigationAdapter (SentinelNavClient)
- Status: Complete

### SC-006 WorldDataAdapter + Context Resolve
- Status: Complete

### SC-007 TargetingService + Scoring Engine
- Status: Complete

### SC-008 RotationEngine Contracts + Paladin Retribution Skeleton
- Status: Complete

### SC-009 CombatService (Pull -> Kill Confirm)
- Status: Complete

### SC-010 LootService
- Status: Complete

### SC-011 InventoryService + Policy Rules
- Status: Complete (extended)
- Notes:
  - Added richer `special_rules` matching (item IDs, quality range, stack range, rule keep floor).

### SC-012 VendorService (Same Map Only)
- Status: Complete (extended)
- Notes:
  - Same-map enforcement and ranking present.
  - Added return-to-grind-anchor post-vendor behavior with timeout/fail-closed.

### SC-013 GrindMode + RecoveryService
- Status: Complete
- Notes: Escalation path pause -> bounded restart -> fail is implemented.

### SC-014 Telemetry + Docs Sync + Smoke Suite
- Status: In Progress (substantially implemented)
- Notes:
  - Telemetry + snapshots present.
  - Runtime diagnostics improved with in-window feed.
  - Additional docs sync still ongoing as parity hardening continues.

## Residual Risks / Remaining Gaps
- Vendor interaction verification is still bounded by currently available Sylvannas runtime APIs; true sell/repair confirmation remains best-effort.
- Profile rename is implemented in API and UI action, but free-form text input UX is still basic.
- Full end-to-end smoke execution could not be re-run in this shell because `lua/luajit/luac` executables are unavailable.
