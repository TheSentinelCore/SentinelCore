---
id: 5
title: "Core Action Registry — Engine methods exposed as profile actions"
state: done
labels: ["enhancement", "ready-for-agent", "area:quest", "priority:high", "size:medium"]
created: "2026-07-16T00:00:00Z"
updated: "2026-07-16T00:00:00Z"
---

## What to build

Define the **core action API** — engine methods that profiles reference by name (e.g., `"engine:acceptQuest(questId)"`). Implemented as a table `CoreActions` in `modules/quest/profile_actions.lua` with methods that return coroutine functions compatible with `StatechartExecutor` action context (`ctx` with `engine`, `profile`, `awaitEvent`, `publish`).

Core actions to implement:

| Action | Purpose |
|--------|---------|
| `nav.followPolicy(policyName)` | Start dynamic route following via NavAdapter |
| `nav.stop()` | Cancel current navigation |
| `combat.setTargetFilter(npcIds)` | Restrict combat to specific NPCs |
| `combat.clearTargetFilter()` | Remove combat filter |
| `combat.engage()` | Start combat rotation |
| `interact.acceptQuest(questId, npcId)` | Accept quest from NPC |
| `interact.turnInQuest(questId, rewardChoice)` | Turn in quest, select reward |
| `interact.bindHearthstone(npcId)` | Set hearthstone |
| `consume.useFood()` / `useWater()` / `useBandage()` | Consumable management |
| `vendor.sellJunk()` / `vendor.repairAll()` / `vendor.buyConsumables(list)` | Vendor operations |
| `trainer.trainAvailable()` | Learn available spells |
| `loot.lootAll()` | Loot nearby corpses |
| `movement.mount()` / `dismount()` | Mount handling |
| `log(message)` | Debug logging |

Each action returns a coroutine function(ctx, args...) that uses `ctx:awaitEvent` for async completion.

## Acceptance criteria

- [ ] `CoreActions` table exports all 15+ actions as functions returning coroutine functions
- [ ] Actions use `ctx:awaitEvent` with appropriate event names and timeouts
- [ ] Actions handle errors gracefully (timeout → return false, error → log + return false)
- [ ] `nav.followPolicy` resolves policy name → calls `NavAdapter:followPolicy(policy)`
- [ ] `interact.*` actions use Sylvannas APIs via `core.input.*` and `core.object_manager.*`
- [ ] `vendor.*` actions integrate with existing `VendorStateMachine`
- [ ] `consume.*` actions integrate with existing `ConsumeManager`
- [ ] `trainer.trainAvailable` uses existing `Trainer` module
- [ ] ProfileCompiler validates action names against `CoreActions` registry
- [ ] Unit tests: each action returns coroutine, awaits correct event, handles timeout

## Blocked by

- **02-statechart-executor** — needs `ctx` API for actions
- **03-engine-event-system** — actions await events published by engine