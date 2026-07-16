---
title: "Game Events"
source: "https://docs.project-sylvanas.net/dev/api/events"
crawled: "2026-07-14"
---

# Game Events

## Overview

`core.register_on_game_event_callback` lets a plugin subscribe to native WoW game events (combat log, encounters, group changes, auction house, and more). The core buffers every event fired since the last tick and drains them once per frame on the main thread, then invokes your callback **once per event**.

Unlike the buff/combat helpers in the IZI SDK, there is **one callback for all events** — you register a single function and dispatch on the event name yourself. Register it once at load; do not register inside your update loop.

**How it differs from the other `register_on_*` callbacks:**

`register_on_spell_cast_callback` and friends hand you a structured data table for one specific concept. `register_on_game_event_callback` is a generic firehose: it forwards **any** registered WoW event, with its raw positional arguments, so you get breadth at the cost of having to interpret the `args` array per event.

---

## `core.register_on_game_event_callback`

**Syntax:**
```lua
core.register_on_game_event_callback(callback: fun(event_name: string, args: (string|number|boolean|nil)[]))
```

**Parameters:**
- `callback`: `function` - Invoked once per buffered event. It receives:
  - `event_name`: `string` - The WoW event name, e.g. `"ENCOUNTER_START"`.
  - `args`: `array` - A positional (1‑based) array of that event's arguments. Original types are preserved: `string`, `number`, `boolean`, or `nil` holes. Complex values (table / function / userdata) arrive as their `tostring()` representation.

**Description:** Registers a callback fired for each buffered game event. Each plugin has a maximum number of callbacks; exceeding it raises a Lua error, so register once.

> **Combat log special case**
> 
> For `COMBAT_LOG_EVENT_UNFILTERED`, the `args` array is **not** the raw event payload — it is the flattened result of `CombatLogGetCurrentEventInfo()` (`timestamp`, `sub_event`, `hide_caster`, `source_guid`, …). See the **combat‑log example** below.

---

## Registered events

The pump registers the events below. Adding an unknown name on a given client is harmless — it is simply ignored. The `args` column lists the positional arguments in order.

### Combat & encounters

| Event | `args` (in order) |
|-------|-------------------|
| `COMBAT_LOG_EVENT_UNFILTERED` | `CombatLogGetCurrentEventInfo()` — see below |
| `PLAYER_REGEN_DISABLED` | *(none)* — you entered combat |
| `PLAYER_REGEN_ENABLED` | *(none)* — you left combat |
| `ENCOUNTER_START` | `encounter_id`, `encounter_name`, `difficulty_id`, `group_size` |
| `ENCOUNTER_END` | `encounter_id`, `encounter_name`, `difficulty_id`, `group_size`, `success` |

### Player

| Event | `args` (in order) |
|-------|-------------------|
| `PLAYER_STARTED_MOVING` | *(none)* |
| `PLAYER_STOPPED_MOVING` | *(none)* |
| `PLAYER_EQUIPMENT_CHANGED` | `equipment_slot`, `has_current` |
| `PLAYER_FLAGS_CHANGED` | `unit_token` (e.g. `"player"`) |
| `PLAYER_LOGOUT` | *(none)* |
| `SPELLS_CHANGED` | *(none)* |
| `START_PLAYER_COUNTDOWN` | `initiated_by`, `time_remaining`, `total_time` |
| `CANCEL_PLAYER_COUNTDOWN` | `initiated_by` |

### Group

| Event | `args` (in order) |
|-------|-------------------|
| `GROUP_ROSTER_UPDATE` | *(none)* |
| `GROUP_JOINED` | `category`, `party_guid` |
| `GROUP_LEFT` | `category`, `party_guid` |

### Chat & UI

| Event | `args` (in order) |
|-------|-------------------|
| `CHAT_MSG_ADDON` | `prefix`, `message`, `channel`, `sender` |
| `UI_ERROR_MESSAGE` | `error_type`, `message` |

### Auction house

The `AUCTION_HOUSE_*` and commodity/item‑search family are also registered: `AUCTION_HOUSE_SHOW`, `AUCTION_HOUSE_CLOSED`, `AUCTION_HOUSE_DISABLED`, `AUCTION_HOUSE_NEW_RESULTS_RECEIVED`, `AUCTION_HOUSE_BROWSE_RESULTS_UPDATED`, `AUCTION_HOUSE_BROWSE_RESULTS_ADDED`, `AUCTION_HOUSE_BROWSE_FAILURE`, `AUCTION_HOUSE_FAVORITES_UPDATED`, `AUCTION_HOUSE_AUCTIONS_EXPIRED`, `AUCTION_HOUSE_AUCTION_CREATED`, `AUCTION_HOUSE_THROTTLED_SYSTEM_READY`, `AUCTION_CANCELED`, `OWNED_AUCTIONS_UPDATED`, `BIDS_UPDATED`, `COMMODITY_SEARCH_RESULTS_UPDATED`, `COMMODITY_SEARCH_RESULTS_RECEIVED`, `COMMODITY_PRICE_UPDATED`, `COMMODITY_PRICE_UNAVAILABLE`, `COMMODITY_PURCHASE_SUCCEEDED`, `COMMODITY_PURCHASE_FAILED`, `COMMODITY_PURCHASED`, `ITEM_SEARCH_RESULTS_UPDATED`, `ITEM_SEARCH_RESULTS_ADDED`, `REPLICATE_ITEM_LIST_UPDATE`, `AUCTION_MULTISELL_START`, `AUCTION_MULTISELL_UPDATE`, `AUCTION_MULTISELL_FAILURE`.

Most carry no arguments (they signal "state changed — re‑query the AH API"); the commodity price and multisell events carry a small number of numeric arguments matching their Blizzard signatures.

---

## The dispatch pattern

Because one callback receives every event, the idiomatic structure is a **handler table** keyed by event name:

```lua
local handlers = {}

function handlers.ENCOUNTER_START(args)
    local encounter_id, encounter_name = args[1], args[2]
    core.log(("Pull! [%d] %s"):format(encounter_id or 0, encounter_name or "?"))
end

function handlers.PLAYER_REGEN_DISABLED()
    core.log("Entered combat")
end

core.register_on_game_event_callback(function(event_name, args)
    local handler = handlers[event_name]
    if handler then
        handler(args)
    end
end)
```

Everything below fits inside this pattern — each example is one `handlers.EVENT_NAME` function.

---

## Advanced example 1 — combat log (many arguments)

`COMBAT_LOG_EVENT_UNFILTERED` is the richest event. Its `args` are the flattened `CombatLogGetCurrentEventInfo()` payload: 11 fixed fields followed by sub‑event‑specific fields.

**Fixed prefix (always present):**

| # | Field | Type |
|---|-------|------|
| 1 | `timestamp` | number |
| 2 | `sub_event` | string (e.g. `SPELL_DAMAGE`, `SPELL_INTERRUPT`, `SPELL_AURA_APPLIED`) |
| 3 | `hide_caster` | boolean |
| 4 | `source_guid` | string |
| 5 | `source_name` | string |
| 6 | `source_flags` | number |
| 7 | `source_raid_flags` | number |
| 8 | `dest_guid` | string |
| 9 | `dest_name` | string |
| 10 | `dest_flags` | number |
| 11 | `dest_raid_flags` | number |

For `SPELL_*` sub‑events, fields 12‑14 are `spell_id`, `spell_name`, `spell_school`.

```lua
-- Log every interrupt that lands, and every big hit you deal.
local me_guid  -- resolved lazily; the local player's GUID

function handlers.COMBAT_LOG_EVENT_UNFILTERED(args)
    local sub_event   = args[2]
    local source_guid = args[4]
    local source_name = args[5]
    local dest_name   = args[9]

    if sub_event == "SPELL_INTERRUPT" then
        -- SPELL_* prefix: [12]=spell_id [13]=spell_name; extra: [15]=extra_spell_name
        local spell_name       = args[13]
        local interrupted_spell = args[15]
        core.log(("%s interrupted %s's %s (via %s)"):format(
            source_name or "?", dest_name or "?", interrupted_spell or "?", spell_name or "?"))

    elseif sub_event == "SPELL_DAMAGE" then
        -- SPELL_DAMAGE suffix after the [12..14] spell fields: [15]=amount
        local spell_name = args[13]
        local amount     = args[15] or 0
        me_guid = me_guid or (core.object_manager.get_local_player()
            and core.object_manager.get_local_player():get_guid())
        if source_guid == me_guid and amount >= 100000 then
            core.log(("Big hit: %s for %d to %s"):format(spell_name or "?", amount, dest_name or "?"))
        end
    end
end
```

Note how the meaning of `args[15]` depends on `sub_event` — always branch on `args[2]` first.

---

## Advanced example 2 — encounters (named positional arguments)

`ENCOUNTER_START` and `ENCOUNTER_END` carry a fixed, well‑defined argument list, so you can unpack them directly into named locals. `ENCOUNTER_END` adds a `success` flag (WoW sends `1`/`0`).

```lua
function handlers.ENCOUNTER_START(args)
    local encounter_id, encounter_name, difficulty_id, group_size =
        args[1], args[2], args[3], args[4]
    core.log(("ENCOUNTER_START: [%d] %s (difficulty %d, %d players)"):format(
        encounter_id or 0, encounter_name or "?", difficulty_id or 0, group_size or 0))
end

function handlers.ENCOUNTER_END(args)
    local encounter_id, encounter_name = args[1], args[2]
    local success = args[5]  -- 1 = kill, 0 = wipe
    if success == 1 then
        core.log(("Killed [%d] %s"):format(encounter_id or 0, encounter_name or "?"))
    else
        core.log(("Wiped on [%d] %s"):format(encounter_id or 0, encounter_name or "?"))
    end
end
```

---

## Advanced example 3 — addon messages (`CHAT_MSG_ADDON`)

`CHAT_MSG_ADDON` is useful for talking to WeakAuras / other addons. Its args are `prefix`, `message`, `channel`, `sender`.

```lua
function handlers.CHAT_MSG_ADDON(args)
    local prefix, message, channel, sender = args[1], args[2], args[3], args[4]
    if prefix == "MyPluginSync" then
        core.log(("Sync from %s (%s): %s"):format(sender or "?", channel or "?", message or ""))
    end
end
```

---

## Simple example — no‑argument events (for contrast)

Many events carry **no arguments at all** — the event name *is* the whole message. For these the `args` array is empty and you simply react to the fact that the event fired. Combat start/stop is the classic pair:

```lua
function handlers.PLAYER_REGEN_DISABLED()  -- entered combat (args is empty)
    core.log("Combat started")
end

function handlers.PLAYER_REGEN_ENABLED()   -- left combat (args is empty)
    core.log("Combat ended")
end

function handlers.PLAYER_STARTED_MOVING()  -- args is empty
    core.log("Started moving")
end
```

Contrast this with the combat‑log handler above: same registration, same callback — but here the `args` table is empty and there is nothing to unpack. That is the whole spectrum of the API, from a 14+‑field firehose down to a bare notification.

---

## Complete plugin

Putting the dispatch pattern and a few handlers together into a runnable plugin:

```lua
--------------------------------------------------------------------------------
-- Game events demo
--------------------------------------------------------------------------------
local handlers = {}

-- Simple, no-arg events -------------------------------------------------------
function handlers.PLAYER_REGEN_DISABLED()
    core.log("[events] entered combat")
end

function handlers.PLAYER_REGEN_ENABLED()
    core.log("[events] left combat")
end

-- Fixed-arg event -------------------------------------------------------------
function handlers.ENCOUNTER_START(args)
    core.log(("[events] pull: %s (%d players)"):format(args[2] or "?", args[4] or 0))
end

-- Many-arg event --------------------------------------------------------------
function handlers.COMBAT_LOG_EVENT_UNFILTERED(args)
    if args[2] == "SPELL_INTERRUPT" then
        core.log(("[events] %s interrupted %s"):format(args[5] or "?", args[9] or "?"))
    end
end

core.register_on_game_event_callback(function(event_name, args)
    local handler = handlers[event_name]
    if handler then
        handler(args)
    end
end)

core.log("[events] demo loaded")
```

A ready‑to‑run copy of this lives in the `playground_events` example plugin.
