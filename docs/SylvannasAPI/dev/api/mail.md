---
title: "Mail Functions"
source: "https://docs.project-sylvanas.net/dev/api/mail"
crawled: "2026-07-14"
---

# Mail Functions

## Overview

The `core.mail` module provides functions for interacting with the in-game mail system.

---

## Inbox Functions

### `core.mail.check_inbox`

**Syntax:** `core.mail.check_inbox() -> nil`

### `core.mail.get_num_inbox_items`

**Syntax:** `core.mail.get_num_inbox_items() -> integer`

### `core.mail.get_inbox_header_info`

**Syntax:** `core.mail.get_inbox_header_info(index: integer) -> mail_header_info`

| Field | Type | Description |
|-------|------|-------------|
| `sender` | `string` | The name of the sender |
| `subject` | `string` | The mail subject line |
| `money` | `number` | Amount of money attached (in copper) |
| `cod_amount` | `number` | Cash-on-delivery amount (in copper) |
| `days_left` | `number` | Days remaining before the mail expires |
| `item_count` | `integer` | Number of item attachments |
| `was_read` | `boolean` | Whether the mail has been read |
| `was_returned` | `boolean` | Whether the mail was returned to sender |

### `core.mail.get_inbox_item`

**Syntax:** `core.mail.get_inbox_item(index: integer, item_index: integer) -> mail_item_info`

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | The item name |
| `item_id` | `integer` | The item ID |
| `count` | `integer` | The stack count |
| `quality` | `integer` | The item quality |

### `core.mail.get_inbox_text`

**Syntax:** `core.mail.get_inbox_text(index: integer) -> string`

### `core.mail.take_inbox_item`

**Syntax:** `core.mail.take_inbox_item(index: integer, item_index: integer) -> nil`

### `core.mail.take_inbox_money`

**Syntax:** `core.mail.take_inbox_money(index: integer) -> nil`

### `core.mail.take_inbox_text_item`

**Syntax:** `core.mail.take_inbox_text_item(index: integer) -> nil`

### `core.mail.delete_inbox_item`

**Syntax:** `core.mail.delete_inbox_item(index: integer) -> nil`

### `core.mail.return_inbox_item`

**Syntax:** `core.mail.return_inbox_item(index: integer) -> nil`

### `core.mail.auto_loot_mail_item`

**Syntax:** `core.mail.auto_loot_mail_item(index: integer) -> nil`

### `core.mail.inbox_item_can_delete`

**Syntax:** `core.mail.inbox_item_can_delete(index: integer) -> boolean`

---

## Sending Functions

### `core.mail.send_mail`

**Syntax:** `core.mail.send_mail(recipient: string, subject?: string, body?: string) -> nil`

### `core.mail.set_send_mail_money`

**Syntax:** `core.mail.set_send_mail_money(money: integer) -> nil`

### `core.mail.get_send_mail_price`

**Syntax:** `core.mail.get_send_mail_price() -> number`

---

## Utility Functions

### `core.mail.has_new_mail`

**Syntax:** `core.mail.has_new_mail() -> boolean`

---

## Complete Examples

### Example: Mail Processing Workflow

```lua
local function process_all_mail()
    core.mail.check_inbox()
    local num_mail = core.mail.get_num_inbox_items()
    for i = num_mail, 1, -1 do
        local header = core.mail.get_inbox_header_info(i)
        if header.money > 0 then core.mail.take_inbox_money(i) end
        if header.item_count > 0 then core.mail.auto_loot_mail_item(i) end
        if core.mail.inbox_item_can_delete(i) then core.mail.delete_inbox_item(i) end
    end
end
```

### Example: Send Gold to Alt

```lua
local function send_gold_to_alt(alt_name, gold_amount)
    core.mail.set_send_mail_money(gold_amount * 10000)
    core.mail.send_mail(alt_name, "Gold Transfer", "Automated gold transfer.")
end
```
