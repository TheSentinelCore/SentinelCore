---
id: 2
title: "Schema Serialization Round-Trip"
state: open
labels: ["enhancement", "ready-for-agent", "size:small"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 02 — Schema Serialization Round-Trip

**What to build:** Prove every `sentinel-schema` type survives a JSON serialize→deserialize round-trip without data loss. Create a sample profile exercising all action types.

**Blocked by:** None — can start immediately.

**Acceptance criteria:**

- [ ] `serde_json::to_string` → `from_str` round-trip test for every schema type: Profile, Operation, Action, Blueprint, Condition, ConditionExpression, NpcReference, QuestReference, CreatureReference, GameObjectReference, Variable, VariableScope, Polygon2D, RecordPath, RetryPolicy, GoToPayload, GrindAreaPayload, VendorPayload, PickupQuestPayload, TurnInQuestPayload, TrainPayload, FlightPayload, RepairPayload, MailboxPayload, BankPayload, UseItemPayload, WaitPayload, SetVariablePayload, BranchPayload, DungeonMarkerPayload, DeathSkipPayload, KillTargetPayload, OperationGoal variants, SchemaMetadata, OperationMetadata, ActionMetadata
- [ ] Each test asserts field-by-field equality after round-trip (not just `assert_eq!` on the struct — verify nested enums, Option fields, Vec fields)
- [ ] A sample file `profiles/northshire_example.json` exists that constructs a full Profile with at least 3 Operations containing every ActionPayload variant, all Blueprint types, conditions, variables, and goals
- [ ] The sample file round-trips through the schema types with no data loss
