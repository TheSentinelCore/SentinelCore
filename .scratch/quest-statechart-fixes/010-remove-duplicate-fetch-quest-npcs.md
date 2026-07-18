---
id: 10
title: "Cleanup: Remove duplicate fetch_quest_npcs function in QueryClient"
state: open
labels: ["quality", "ready-for-agent", "area:quest"]
created: "2026-07-16T10:00:00Z"
updated: "2026-07-16T10:00:00Z"
---

## Description

The exact same implementation of `fetch_quest_npcs` is defined twice back-to-back in query_client.lua (lines 77-110 and 112-145). The second definition overwrites the first.

## Code Context

File: `sentinel/modules/quest/query_client.lua` lines 77-145

```lua
function QueryClient:fetch_quest_npcs(quest_id, relation)  -- Line 77
    quest_id = tonumber(quest_id)
    -- ... identical implementation ...
    return nil
end

function QueryClient:fetch_quest_npcs(quest_id, relation)  -- Line 112 - duplicate!
    quest_id = tonumber(quest_id)
    -- ... identical implementation ...
    return nil
end
```

## Impact

- Code bloat with duplicated logic
- Maintenance burden - fix must be applied to both copies
- Potential for divergence if one is edited and not the other

## Acceptance Criteria

- [ ] Remove duplicate function definition (lines 112-145)
- [ ] Verify no other duplicate definitions exist in the module

## References

- Code quality best practices