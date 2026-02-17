# CLAUDE.md — SentinelGather Movement & Navigation Client Rewrite

## What You're Building

Two Lua modules for a WoW gathering bot running on the Sylvannas scripting platform:

1. **NavigationClient.lua** (~300 lines) — HTTP client for the SentinelNavServer pathfinding server
2. **MovementModule.lua** (~500-600 lines) — Movement orchestrator using NavigationClient + simple_movement

## Required Reading (in order)

1. `01_CLAUDE_CODE_PROMPT.md` — **READ THIS FIRST**. Contains your role definition, all API constraints, architecture, code style, and implementation instructions. This is your primary reference.
2. `02_PRD.md` — Product requirements with exact API surfaces, state machine, and success criteria.
3. `03_IMPLEMENTATION_TICKETS.md` — Work breakdown with acceptance criteria for each ticket. Follow the dependency graph.
4. `04_SYLVANNAS_API_REFERENCE.md` — Quick reference cheatsheet for all allowed Sylvannas API calls.

## Implementation Order

Follow the ticket dependency graph:
```
TICKET-001 → TICKET-002 → TICKET-003 + TICKET-004 → TICKET-005 → TICKET-006 → TICKET-007 + TICKET-008 + TICKET-009 → TICKET-010
```

Write NavigationClient.lua first (tickets 001-004), then MovementModule.lua (tickets 005-009), then verify (ticket 010).

## Critical Rules (memorize these)

1. **ONLY Sylvannas API** — No WoW Lua functions. Ever. If you're not sure if something is Sylvannas API, check `04_SYLVANNAS_API_REFERENCE.md`.
2. **Colon syntax** — `module:method()` not `module.method()` for all Sylvannas modules.
3. **Nil-check player** — `core.object_manager.get_local_player()` can return nil. Always check.
4. **Async HTTP** — `core.http_get` is non-blocking. Design around callbacks.
5. **Call process() every frame** — `simple_movement:process()` MUST be called in `update()`.
6. **No external deps** — No EventBus, StateMachine, Settings, Logger, JSON library. Everything inline.

## Output Files

Place completed files in the project root:
- `NavigationClient.lua`
- `MovementModule.lua`

## Verification

After completing both files, run the checks from TICKET-010:
- Grep for WoW API leaks
- Count lines (NC ≤ 350, MM ≤ 600)
- Count MovementModule instance fields (≤ 20)
- Verify all public methods have LuaDoc annotations
