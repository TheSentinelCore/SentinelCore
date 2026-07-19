---
id: 1
title: "Security: Sandbox guard expressions in profile compiler"
state: open
labels: ["bug", "security", "ready-for-agent", "area:quest"]
created: "2026-07-16T10:00:00Z"
updated: "2026-07-16T10:00:00Z"
---

## Description

When compiling transition guards from YAML strings, `loadstring` is used without applying an environment sandbox (`setfenv`). While inline actions correctly receive a sandboxed environment on execution, guards run in the global environment (`_G`). A malicious or poorly written profile could execute arbitrary Lua code or modify WoW global state.

## Code Context

File: `sentinel/modules/quest/profile_compiler.lua` (lines 578-585)

```lua
local fn, err = loadstring("return function(event, bb, profile, state) return " .. trans.guard .. " end")
if not fn then
    table.insert(compiled.diagnostics.errors, {...})
else
    trans.guard_fn = fn() -- Returns function running in _G
end
```

## Impact

Arbitrary code execution. A shared profile could contain a payload in a guard that deletes files, steals data, or pollutes the Sylvannas global namespace.

## Acceptance Criteria

- [ ] Guard expressions are compiled with `setfenv` to restrict available globals
- [ ] Whitelist of safe globals (math, string, tonumber, tostring, etc.) is defined
- [ ] Security tests verify that malicious guard expressions (attempting `os.execute`, `io.read`, etc.) throw errors
- [ ] Inline actions also use the same sandbox (currently partially implemented at line 646)

## References

- ADR-0004, Section "Action Registry: Hybrid (Core + Profile-Local)" - mentions sandbox requirement
- CONTEXT.md - Guard: "a boolean Lua expression evaluated when an event fires"