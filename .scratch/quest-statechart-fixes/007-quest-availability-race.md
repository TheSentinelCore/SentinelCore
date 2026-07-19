---
id: 7
title: "Logic: Fix non-deterministic quest availability filtering race condition"
state: open
labels: ["bug", "correctness", "ready-for-agent", "area:quest"]
created: "2026-07-16T10:00:00Z"
updated: "2026-07-16T10:00:00Z"
---

## Description

In `_filter_available`, the graph determines quest availability by iterating over `pairs(self.nodes)`. For each quest, it checks prerequisites by reading `self.available[req_id]`. Since `pairs()` has undefined, non-deterministic iteration order in Lua, a quest may be evaluated before its prerequisite has been processed, incorrectly marking itself unavailable.

## Code Context

File: `sentinel/modules/quest/quest_graph.lua` lines 327-366

```lua
function QuestGraph:_filter_available(faction)
    for qid, node in pairs(self.nodes) do  -- pairs() = undefined order!
        local available = true
        
        -- ... level/race/class checks ...
        
        if available then
            for _, req_id in ipairs(self.edges[qid].requires) do
                if not self.is_completed(req_id) and not self.available[req_id] then
                    available = false  -- Race: req may not be processed yet!
                end
            end
        end
        
        self.available[qid] = available
    end
end
```

## Impact

Quest availability randomly breaks depending on hash table distribution. A quest that should be available (all prerequisites complete) is incorrectly marked unavailable, preventing the bot from picking it up.

## Acceptance Criteria

- [ ] Separate evaluation into two passes
- [ ] Pass 1: Evaluate level/race/class limits (no dependency on other quests)
- [ ] Pass 2: Resolve dependency chains using visited set or topological sort
- [ ] Unit tests verify correct behavior regardless of node iteration order
- [ ] Stress test with shuffled table order shows consistent results

## References

- ADR-0004 - QuestGraph is read-only data accessor for quest/NPC data