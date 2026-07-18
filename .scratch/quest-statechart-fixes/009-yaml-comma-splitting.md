---
id: 9
title: "Parsing: Fix YAML comma-splitting to respect quoted strings"
state: open
labels: ["bug", "quality", "ready-for-agent", "area:quest"]
created: "2026-07-16T10:00:00Z"
updated: "2026-07-16T10:00:00Z"
---

## Description

The custom YAML parsers use `gmatch("([^,]+)")` for arrays and `gmatch` for arguments. This breaks string items containing commas natively.

## Code Context

File: `sentinel/modules/quest/profile_compiler.lua`

Line 59 (inline sequences):
```lua
for item in str:gmatch("([^,]+)") do  -- Breaks ["Kill 10 Boars, then return"]
    table.insert(result, parse_value(item))
end
```

Lines 622 and 665 (action arguments):
```lua
for arg in args_str:gmatch("([^,]+)") do
    -- ... parsing logic
end
```

File: `sentinel/modules/quest/routing_policy_loader.lua` line 94:
```lua
table.insert(current_array, array_item:match("^%s*(.-)%s*$"))  -- No quote handling
```

## Impact

- Profile authors cannot use commas in strings
- Arguments to actions like `followPolicy('kill 10 boars, then return')` are incorrectly split
- Routing policies with commas in values fail to parse

## Acceptance Criteria

- [ ] `parse_inline_sequence` handles quoted strings with commas
- [ ] Action argument parsing respects quoted strings
- [ ] Routing policy loader strips # comments and handles quotes
- [ ] Test cases for comma-containing strings parse correctly

## References

- ADR-0004 - "Profile DSL: YAML with Expression Strings"