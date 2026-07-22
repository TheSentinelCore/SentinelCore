---
title: "Party Functions"
source: "https://docs.project-sylvanas.net/dev/api/party"
crawled: "2026-07-14"
---

# Party Functions

## Overview

The `core.party` namespace wraps party and group actions that are normally exposed through Blizzard's party APIs.

---

### `core.party.can_invite`

**Syntax:**
```lua
core.party.can_invite() -> boolean
```

**Returns:** `boolean` - True if the local player can invite another player to the group.

**Description:** Returns whether the current character is allowed to invite other players. This checks the active Blizzard party API and returns false when that API is not available.

**Example Usage:**
```lua
if core.party.can_invite() then
    core.party.invite_unit("Playername")
end
```

---

### `core.party.invite_unit`

**Syntax:**
```lua
core.party.invite_unit(name: string) -> boolean
```

**Parameters:**
- `name`: `string` - The player name to invite.

**Returns:** `boolean` - True if an invite API was available and called.

**Description:** Invites a player by name using the current client's party invite API. Returns false when the name is empty or no compatible invite function is available.

**Example Usage:**
```lua
local player_name = "Playername"
if core.party.can_invite() then
    local sent = core.party.invite_unit(player_name)
    core.log("Invite sent: " .. tostring(sent))
end
```
