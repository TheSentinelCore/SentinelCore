---
title: "Auction House Functions"
source: "https://docs.project-sylvanas.net/dev/api/auction-house"
crawled: "2026-07-14"
---

# Auction House Functions

## Overview

The `core.auction_house` module provides functions for interacting with the World of Warcraft auction house. This includes scanning and replicating auction data, searching for items, managing owned auctions, posting new listings, purchasing items, and querying auction state.

---

## Scanning / Replication Functions

### `core.auction_house.replicate_items`

**Syntax:** `core.auction_house.replicate_items() -> nil`

**Description:** Initiates a full replication of all auction house items.

---

### `core.auction_house.get_num_replicate_items`

**Syntax:** `core.auction_house.get_num_replicate_items() -> integer`

**Returns:** `integer` - The number of items available from the last replication scan.

---

### `core.auction_house.get_replicate_item_info`

**Syntax:** `core.auction_house.get_replicate_item_info(index: integer) -> table`

**Parameters:**
- `index`: `integer` - The index of the replicated item.

**Returns:** `table` - A table containing item details from the replication scan.

---

### `core.auction_house.get_replicate_item_link`

**Syntax:** `core.auction_house.get_replicate_item_link(index: integer) -> string`

**Returns:** `string` - The item link for the replicated item.

---

### `core.auction_house.get_replicate_item_time_left`

**Syntax:** `core.auction_house.get_replicate_item_time_left(index: integer) -> integer`

**Returns:** `integer` - The time-left category for the auction.

---

### `core.auction_house.batch_get_replicate_items`

**Syntax:** `core.auction_house.batch_get_replicate_items() -> table`

**Returns:** `table` - An array of replicated item data.

**Example Usage:**
```lua
core.auction_house.replicate_items()
local items = core.auction_house.batch_get_replicate_items()
core.log("Total auctions scanned: " .. #items)
```

---

## Search Functions

### `core.auction_house.send_search_query`

**Syntax:** `core.auction_house.send_search_query() -> nil`

**Description:** Sends a search query to the auction house.

---

### `core.auction_house.send_sell_search_query`

**Syntax:** `core.auction_house.send_sell_search_query() -> nil`

---

### `core.auction_house.get_num_commodity_search_results`

**Syntax:** `core.auction_house.get_num_commodity_search_results() -> integer`

---

### `core.auction_house.get_commodity_search_result_info`

**Syntax:** `core.auction_house.get_commodity_search_result_info(index: integer) -> table`

---

### `core.auction_house.has_full_commodity_search_results`

**Syntax:** `core.auction_house.has_full_commodity_search_results() -> boolean`

---

### `core.auction_house.get_num_item_search_results`

**Syntax:** `core.auction_house.get_num_item_search_results() -> integer`

---

### `core.auction_house.get_item_search_result_info`

**Syntax:** `core.auction_house.get_item_search_result_info(index: integer) -> table`

---

### `core.auction_house.has_full_item_search_results`

**Syntax:** `core.auction_house.has_full_item_search_results() -> boolean`

---

## Owned Auction Functions

### `core.auction_house.query_owned_auctions`

**Syntax:** `core.auction_house.query_owned_auctions() -> nil`

---

### `core.auction_house.get_num_owned_auctions`

**Syntax:** `core.auction_house.get_num_owned_auctions() -> integer`

---

### `core.auction_house.get_owned_auction_info`

**Syntax:** `core.auction_house.get_owned_auction_info(index: integer) -> table`

---

## Posting Functions

### `core.auction_house.post_commodity`

**Syntax:** `core.auction_house.post_commodity(bag: integer, slot: integer, duration: integer, quantity: integer, unit_price: integer) -> nil`

**Parameters:**
- `bag`: `integer` - The bag index containing the item.
- `slot`: `integer` - The slot index within the bag.
- `duration`: `integer` - The auction duration (1 = 12h, 2 = 24h, 3 = 48h).
- `quantity`: `integer` - The number of items to post.
- `unit_price`: `integer` - The price per unit in copper.

---

### `core.auction_house.post_item`

**Syntax:** `core.auction_house.post_item(bag: integer, slot: integer, duration: integer, quantity: integer, bid: integer, buyout: integer) -> nil`

---

### `core.auction_house.pickup_container_item`

**Syntax:** `core.auction_house.pickup_container_item(bag: integer, slot: integer) -> nil`

---

### `core.auction_house.click_auction_sell_button`

**Syntax:** `core.auction_house.click_auction_sell_button() -> nil`

---

### `core.auction_house.do_post_auction`

**Syntax:** `core.auction_house.do_post_auction() -> nil`

---

### `core.auction_house.get_auction_sell_item_info`

**Syntax:** `core.auction_house.get_auction_sell_item_info() -> table`

---

### `core.auction_house.get_cursor_item_name`

**Syntax:** `core.auction_house.get_cursor_item_name() -> string`

---

## Purchasing Functions

### `core.auction_house.place_bid`

**Syntax:** `core.auction_house.place_bid(auction_id: integer, bid_amount: integer) -> nil`

---

### `core.auction_house.start_commodities_purchase`

**Syntax:** `core.auction_house.start_commodities_purchase(item_id: integer, quantity: integer) -> nil`

---

### `core.auction_house.confirm_commodities_purchase`

**Syntax:** `core.auction_house.confirm_commodities_purchase() -> nil`

---

### `core.auction_house.cancel_commodities_purchase`

**Syntax:** `core.auction_house.cancel_commodities_purchase() -> nil`

**Example Usage:**
```lua
core.auction_house.start_commodities_purchase(168586, 200)
core.auction_house.confirm_commodities_purchase()
```

---

## Management Functions

### `core.auction_house.cancel_auction`

**Syntax:** `core.auction_house.cancel_auction(auction_id: integer) -> nil`

---

### `core.auction_house.can_cancel_auction`

**Syntax:** `core.auction_house.can_cancel_auction(auction_id: integer) -> boolean`

---

### `core.auction_house.calculate_commodity_deposit`

**Syntax:** `core.auction_house.calculate_commodity_deposit(item_id: integer, duration: integer, quantity: integer) -> integer`

**Returns:** `integer` - The deposit cost in copper.

---

### `core.auction_house.get_cancel_cost`

**Syntax:** `core.auction_house.get_cancel_cost(auction_id: integer) -> integer`

---

## State Functions

### `core.auction_house.is_throttled_message_system_ready`

**Syntax:** `core.auction_house.is_throttled_message_system_ready() -> boolean`

---

### `core.auction_house.is_auction_house_shown`

**Syntax:** `core.auction_house.is_auction_house_shown() -> boolean`

---

### `core.auction_house.close_auction_house`

**Syntax:** `core.auction_house.close_auction_house() -> nil`

---

### `core.auction_house.get_quote_duration_remaining`

**Syntax:** `core.auction_house.get_quote_duration_remaining() -> integer`

---

### `core.auction_house.get_item_commodity_status`

**Syntax:** `core.auction_house.get_item_commodity_status(item_id: integer) -> integer`

---

## Item Info Functions

### `core.auction_house.get_item_info`

**Syntax:** `core.auction_house.get_item_info(item_id: integer) -> table`

---

### `core.auction_house.get_item_icon_name`

**Syntax:** `core.auction_house.get_item_icon_name(item_id: integer) -> string`

---

### `core.auction_house.get_item_tooltip`

**Syntax:** `core.auction_house.get_item_tooltip(item_id: integer) -> table`

---

## Complete Examples

### Example: Auction House Price Scanner

```lua
local function scan_commodity_prices(item_id)
    if not core.auction_house.is_auction_house_shown() then
        core.log("Auction house is not open")
        return
    end
    if not core.auction_house.is_throttled_message_system_ready() then
        core.log("Auction house throttled, try again later")
        return
    end
    core.auction_house.send_search_query()
    local num_results = core.auction_house.get_num_commodity_search_results()
    if num_results == 0 then
        core.log("No listings found")
        return
    end
    local cheapest = core.auction_house.get_commodity_search_result_info(1)
    core.log(string.format("Cheapest listing: %s copper/unit", tostring(cheapest)))
end
```

### Example: Cancel Undercut Auctions

```lua
local function cancel_all_owned_auctions()
    core.auction_house.query_owned_auctions()
    local num = core.auction_house.get_num_owned_auctions()
    local cancelled = 0
    for i = 1, num do
        local info = core.auction_house.get_owned_auction_info(i)
        if core.auction_house.can_cancel_auction(info.auction_id) then
            local cost = core.auction_house.get_cancel_cost(info.auction_id)
            local gold = math.floor(cost / 10000)
            core.log(string.format("Cancelling auction %d (cancel cost: %dg)", info.auction_id, gold))
            core.auction_house.cancel_auction(info.auction_id)
            cancelled = cancelled + 1
        end
    end
    core.log(string.format("Cancelled %d/%d auctions", cancelled, num))
end
```

### Example: Post Commodity Items

```lua
local function post_commodity(bag, slot, quantity, unit_price_copper)
    if not core.auction_house.is_auction_house_shown() then
        core.log("Open the auction house first")
        return
    end
    local deposit = core.auction_house.calculate_commodity_deposit(0, 2, quantity)
    local deposit_gold = math.floor(deposit / 10000)
    core.log(string.format("Deposit cost: %dg", deposit_gold))
    core.auction_house.post_commodity(bag, slot, 2, quantity, unit_price_copper)
    core.log(string.format("Posted %d items at %d copper each", quantity, unit_price_copper))
end
```
