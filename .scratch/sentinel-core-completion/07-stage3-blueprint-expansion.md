---
id: 7
title: "Stage 3 — Blueprint Expansion"
state: open
labels: ["enhancement", "ready-for-agent", "size:medium"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 07 — Stage 3: Blueprint Expansion

**What to build:** Implement the third compiler stage — expand all Blueprint references into primitive ActionPayloads, injecting smart defaults from the QueryServer and handling recursive expansion.

**Blocked by:** #6 (Stage 2 — references must be resolved before blueprints can expand)

**Acceptance criteria:**

- [ ] Stage 3 runs after Stage 2 succeeds
- [ ] For each Blueprint reference in an Operation's action list:
  - Parameters (NPC, Quest, Waypoint, etc.) are resolved from the resolved IR
  - Smart defaults injected from QueryServer: nearest vendor, nearest trainer, nearest flight master when parameters unset
  - Recursive expansion: Blueprints containing Blueprints are fully flattened
  - Actions for unset optional parameters are removed from the expansion
  - Each expanded action is tagged with `generated_from: blueprint_id`
- [ ] After Stage 3, only primitive `ActionPayload` variants remain in the IR (no Blueprint references)
- [ ] `ExpansionCache` implemented: keyed on `(blueprint_id, parameter_hash)`, avoids re-expanding identical blueprints
- [ ] Error codes `C-3xxx` for: blueprint not found, required parameter missing, recursive depth exceeded
- [ ] Unit tests: expand a blueprint with all parameters → correct primitives, expand with missing optional → pruning, nested blueprints → full recursion, circular blueprint reference → error
