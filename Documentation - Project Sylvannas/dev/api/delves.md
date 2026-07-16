---
title: "Delves"
source: "https://docs.project-sylvanas.net/dev/api/delves"
crawled: "2026-07-14"
---

# Delve Functions

## Overview

The `core.delves` module provides functions for managing delve instances, including entering, completing, and leaving delves.

---

### `core.delves.is_in_delve`

Syntax

```
core.delves.is_in_delve() -> boolean
```

Returns

-   `boolean`: Whether the player is currently inside a delve instance.

Description

Returns whether the player is currently inside a delve. Use this to gate delve-specific logic.

---

### `core.delves.is_delve_complete`

Syntax

```
core.delves.is_delve_complete() -> boolean
```

Returns

-   `boolean`: Whether the current delve has been completed.

Description

Returns whether the current delve instance has been completed. A delve is considered complete when all objectives have been fulfilled and rewards are available.

---

### `core.delves.enter_delve`

Syntax

```
core.delves.enter_delve() -> nil
```

Returns

-   `nil`

Description

Enters a delve instance. The player must be at a valid delve entrance for this to work.

---

### `core.delves.teleport_out`

Syntax

```
core.delves.teleport_out() -> nil
```

Returns

-   `nil`

Description

Teleports the player out of the current delve instance. This returns the player to the delve entrance in the open world.

---

### `core.delves.leave_delve`

Syntax

```
core.delves.leave_delve() -> nil
```

Returns

-   `nil`

Description

Leaves the current delve instance entirely. Unlike `teleport_out`, this fully exits the delve group and instance.

---

## Complete Example

### Delve Completion Handler

```
local function handle_delve()    if not core.delves.is_in_delve() then        return    end    if core.delves.is_delve_complete() then        core.log("Delve complete! Teleporting out...")        core.delves.teleport_out()    endend
```