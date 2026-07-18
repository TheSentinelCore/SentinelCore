---
id: 5
title: "Performance: Add in-flight HTTP request deduplication to QueryClient"
state: open
labels: ["bug", "performance", "ready-for-agent", "area:quest"]
created: "2026-07-16T10:00:00Z"
updated: "2026-07-16T10:00:00Z"
---

## Description

`QueryClient:fetch_quest` is async and returns nil on first call while firing HTTP request. If called again before the callback completes, it fires another HTTP request. Since StatechartExecutor evaluates guards continuously, a guard checking quest data will spam http_get requests 60+ times per second.

## Code Context

File: `sentinel/modules/quest/query_client.lua` lines 42-69

```lua
function QueryClient:fetch_quest(quest_id)
    quest_id = tonumber(quest_id)
    if not quest_id or not core or not core.http_get then
        return nil
    end

    local cached = QueryClient.get_cached_quest(quest_id)
    if cached then return cached end

    -- BUG: No check for in-flight requests
    local url = self._base_url .. "/api/v1/quests/" .. quest_id
    pcall(function()
        core.http_get(url, function(code, content_type, body)
            -- ... caches result on callback
        end)
    end)

    return nil
end
```

## Impact

- DDoS of SentinelQueryServer from a single profile guard
- Rate limiting/banning by external services
- Severe performance degradation during guard evaluation spikes

## Acceptance Criteria

- [ ] Add `_pending` table to track in-flight quest requests
- [ ] Return nil immediately if request already pending for quest_id
- [ ] Clear pending flag in callback after cache is populated
- [ ] Stress test shows bounded HTTP requests (max 1 per quest until cache hit)

## References

- ADR-0004 - "QuestRegistry: On-Demand Query + Caching (Not Full Preload)"