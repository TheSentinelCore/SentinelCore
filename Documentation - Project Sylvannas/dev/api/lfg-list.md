---
title: "LFG List"
source: "https://docs.project-sylvanas.net/dev/api/lfg-list"
crawled: "2026-07-14"
---

# LFG List Functions

## Overview

The `core.lfg_list` module wraps the WoW `C_LFGList` API, providing access to the Looking For Group search system. You can trigger searches, inspect results, apply to groups, and manage applicants for groups you are hosting.

> **note**: Search results arrive asynchronously. After calling `search()`, wait for the `LFG_LIST_SEARCH_RESULT_UPDATED` event before reading results.

---

### `core.lfg_list.search`

```
core.lfg_list.search(category_id, filter?, preferred_filters?) -> boolean
```

**Parameters**
- `category_id`: `integer` - The LFG category ID to search.
- `filter` (Optional): `integer` - Search filter bitmask. Default `0`.
- `preferred_filters` (Optional): `integer` - Preferred filter bitmask. Default `0`.

Returns:
- `boolean`: `true` if the search was issued, `false` if it was skipped (e.g. the Blizzard LFG or PVE frame is open).

Description: Triggers a Looking For Group search. The search is skipped if the Blizzard LFG or PVE frame is currently shown, because re-searching while those frames render tooltips would cause in-game Lua errors.

**Example Usage**

```lua
-- Search for M+ groups (category 2)
local issued = core.lfg_list.search(2)
if not issued then
    core.log("Search skipped — LFG frame is open")
end
```

---

### `core.lfg_list.get_search_results`

```
core.lfg_list.get_search_results() -> table
```

Returns:
- `table`: A results table with the following structure:

| Field | Type | Description |
|-------|------|-------------|
| `total_results` | `integer` | The total number of results |
| `result_ids` | `number[]` | Array of search result IDs |

Description: Returns the current LFG search results. Call this after a search has completed.

**Example Usage**

```lua
local results = core.lfg_list.get_search_results()
core.log("Found " .. results.total_results .. " groups")
for _, id in ipairs(results.result_ids) do
    core.log("Result ID: " .. id)
end
```

---

### `core.lfg_list.has_search_result_info`

```
core.lfg_list.has_search_result_info(result_id) -> boolean
```

**Parameters**
- `result_id`: `number` - The search result ID.

Returns:
- `boolean`: `true` if detailed info is available for this result.

Description: Checks whether detailed info has been loaded for a search result. Some results may not have their info available immediately after a search.

---

### `core.lfg_list.get_search_result_info`

```
core.lfg_list.get_search_result_info(result_id) -> table | nil
```

**Parameters**
- `result_id`: `number` - The search result ID.

Returns:
- `table | nil`: The result info table, or `nil` if unavailable. Contains the following fields:

| Field | Type | Description |
|-------|------|-------------|
| `search_result_id` | `number` | The search result ID |
| `activity_id` | `integer` | The activity ID |
| `leader_name` | `string` | The group leader's name |
| `name` | `string` | The group listing name |
| `comment` | `string` | The group listing comment |
| `voice_chat` | `string` | Voice chat info string |
| `required_ilvl` | `integer` | Required item level |
| `age` | `integer` | Listing age in seconds |
| `num_bnet_friends` | `integer` | Number of Battle.net friends in the group |
| `num_char_friends` | `integer` | Number of character friends in the group |
| `num_guildmates` | `integer` | Number of guildmates in the group |
| `is_delisted` | `boolean` | Whether the listing has been delisted |
| `num_members` | `integer` | Number of members in the group |
| `is_auto_accept` | `boolean` | Whether the group auto-accepts applicants |
| `required_honor_level` | `integer` | Required honor level |

Description: Returns detailed information about a search result, including group name, leader, comment, member count, and requirements.

**Example Usage**

```lua
local info = core.lfg_list.get_search_result_info(result_id)
if info then
    core.log(info.name .. " (leader: " .. info.leader_name .. ", members: " .. info.num_members .. ")")
end
```

---

### `core.lfg_list.get_search_result_member_counts`

```
core.lfg_list.get_search_result_member_counts(result_id) -> table | nil
```

**Parameters**
- `result_id`: `number` - The search result ID.

Returns:
- `table | nil`: Role slot counts for the search result, or `nil` if unavailable.

| Field | Type | Description |
|-------|------|-------------|
| `tank` | `integer` | Filled tank slots |
| `healer` | `integer` | Filled healer slots |
| `damager` | `integer` | Filled damage slots |
| `tank_remaining` | `integer` | Open tank slots |
| `healer_remaining` | `integer` | Open healer slots |
| `damager_remaining` | `integer` | Open damage slots |

Description: Returns filled and remaining role slot counts for a search result. This is useful for filtering groups by remaining role needs.

**Example Usage**

```lua
local counts = core.lfg_list.get_search_result_member_counts(result_id)
if counts and counts.healer_remaining > 0 then
    core.log("This group still needs a healer")
end
```

---

### `core.lfg_list.apply_to_group`

```
core.lfg_list.apply_to_group(result_id, tank, healer, damage) -> boolean, string | nil
```

**Parameters**
- `result_id`: `number` - The search result ID to apply to.
- `tank`: `boolean` - Whether to apply as tank.
- `healer`: `boolean` - Whether to apply as healer.
- `damage`: `boolean` - Whether to apply as damage.

Returns:
- `boolean`: `true` if the apply call was issued without error.
- `string | nil`: Error message if the call failed, `nil` on success.

Description: Applies to a group listing with the specified roles. The actual application outcome arrives via the `LFG_LIST_APPLICATION_STATUS_UPDATED` event — `success` here only means the call was issued without a Lua error.

**Example Usage**

```lua
-- Apply as DPS
local success, err = core.lfg_list.apply_to_group(result_id, false, false, true)
if not success then
    core.log("Apply failed: " .. (err or "unknown"))
end
```

---

### `core.lfg_list.get_applicants`

```
core.lfg_list.get_applicants() -> integer[]
```

Returns:
- `integer[]`: Array of applicant IDs for a group you are hosting.

Description: Returns the list of applicant IDs for a group you are currently hosting.

**Example Usage**

```lua
local applicants = core.lfg_list.get_applicants()
core.log("Pending applicants: " .. #applicants)
```

---

### `core.lfg_list.get_applicant_info`

```
core.lfg_list.get_applicant_info(applicant_id) -> table | nil
```

**Parameters**
- `applicant_id`: `number` - The applicant ID.

Returns:
- `table | nil`: The applicant info table, or `nil` if unavailable. Contains the following fields:

| Field | Type | Description |
|-------|------|-------------|
| `applicant_id` | `number` | The applicant ID |
| `application_status` | `string` | The current application status |
| `pending_application_status` | `string` | The pending application status |
| `num_members` | `integer` | Number of members in the applicant's group |
| `is_new` | `boolean` | Whether the applicant is new |
| `comment` | `string` | The applicant's comment |
| `display_order_id` | `integer` | The display order ID |

Description: Returns detailed information about an applicant to your hosted group.

**Example Usage**

```lua
local info = core.lfg_list.get_applicant_info(applicant_id)
if info then
    core.log("Applicant: " .. info.comment .. " (status: " .. info.application_status .. ")")
end
```

---

### `core.lfg_list.cancel_application`

```
core.lfg_list.cancel_application(result_id) -> boolean, string | nil
```

**Parameters**
- `result_id`: `number` - The search result ID of the group to cancel the application for.

Returns:
- `boolean`: `true` if the cancel call was issued without error.
- `string | nil`: Error message if the call failed, `nil` on success.

Description: Cancels a pending application to a group listing.

**Example Usage**

```lua
local success, err = core.lfg_list.cancel_application(result_id)
if not success then
    core.log("Cancel failed: " .. (err or "unknown"))
end
```

---

### `core.lfg_list.accept_invite`

```
core.lfg_list.accept_invite(result_id) -> boolean, string | nil
```

**Parameters**
- `result_id`: `number` - The search result ID of the group invite to accept.

Returns:
- `boolean`: `true` if the accept call was issued without error.
- `string | nil`: Error message if the call failed, `nil` on success.

Description: Accepts a group invite from the LFG system.

**Example Usage**

```lua
local success, err = core.lfg_list.accept_invite(result_id)
if not success then
    core.log("Accept failed: " .. (err or "unknown"))
end
```

---

### `core.lfg_list.get_application_info`

```
core.lfg_list.get_application_info(result_id) -> table | nil
```

**Parameters**
- `result_id`: `number` - The search result ID.

Returns:
- `table | nil`: The application info table, or `nil` if unavailable. Contains:

| Field | Type | Description |
|-------|------|-------------|
| `app_id` | `number` | The application ID |
| `app_status` | `string` | The current application status |
| `pending_status` | `string` | The pending application status |
| `app_duration` | `number` | The application duration in seconds |

**Application status values:** `"none"`, `"applied"`, `"invited"`, `"failed"`, `"cancelled"`, `"declined"`, `"declined_full"`, `"declined_delisted"`, `"timedout"`, `"inviteaccepted"`, `"invitedeclined"`

Description: Returns the application status for a search result. Use this to track whether your application is pending, has been invited, declined, etc.

**Example Usage**

```lua
local app = core.lfg_list.get_application_info(result_id)
if app and app.app_status == "invited" then
    core.lfg_list.accept_invite(result_id)
end
```

---

### `core.lfg_list.refresh_search_panel`

```
core.lfg_list.refresh_search_panel() -> boolean, string | nil
```

Returns:
- `boolean`: `true` if the click was issued without error.
- `string | nil`: Error message if the call failed, `nil` on success.

Description: Programmatically clicks the refresh button on the Blizzard LFG search panel. Requires the search panel to be open.

**Example Usage**

```lua
local success, err = core.lfg_list.refresh_search_panel()
if not success then
    core.log("Refresh failed: " .. (err or "unknown"))
end
```

---

### `core.lfg_list.search_panel_is_visible`

```
core.lfg_list.search_panel_is_visible() -> boolean
```

Returns:
- `boolean`: `true` if the Blizzard LFG search panel is currently visible.

Description: Checks whether the Blizzard LFG search panel (`LFGListFrame.SearchPanel`) is currently visible.

**Example Usage**

```lua
if core.lfg_list.search_panel_is_visible() then
    core.lfg_list.refresh_search_panel()
end
```
