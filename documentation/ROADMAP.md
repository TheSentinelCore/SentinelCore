# SentinelCore Roadmap

**Last Updated:** 2026-07-15

## Current Status

### ✅ Completed (Phase A - New Lua Capabilities)

1. **SentinelQueryServer (Rust)** - SQLite-backed quest/NPC query service
   - Endpoints: `/api/v1/quests/{id}`, `/api/v1/quests/{id}/npcs`
   - Verified working with tbcmangos.sqlite

2. **Questie Integration** - Live quest state abstraction
   - `questie_adapter.lua` - Wraps `core.addons.questie.*` APIs
   - `tracker.lua` - Quest log parsing + Questie merge
   - `query_client.lua` - HTTP client using `core.http_get`

3. **Quest Engine** - Route planning foundation
   - `engine.lua` - Quest giver/turn-in lookup, completion checks
   - `module.lua` - Event subscription, lifecycle management

4. **Combat DSL Migration (Retribution Paladin)**
   - `priority_builder.lua` - Fixed shared subtree injection
   - `retribution_tbc.lua` - Dual-path (legacy default, DSL opt-in)
   - Parity tests verified

5. **Mail Automation**
   - Gold/items auto-take from inbox
   - Spam detection/deletion
   - `callback_bridge.lua` event forwarding

6. **LFG Automation**
   - Search, apply, auto-accept invites
   - Role-based filtering

### 🔄 In Progress

7. **Quest Data Pack Generation**
   - Human starting zones (levels 1-10) generated: `human_1_10.json`
   - Need to expand to other races/zones

## Next Steps

### Priority 1 - Testing
- In-game verification of DSL rotation parity
- Mail/LFG module integration tests
- Query client timeout/error handling

### Priority 2 - Quest Engine Expansion
- Add quest objective resolution (item spawns, creature positions)
- Implement quest graph solver (optimal ordering)
- Add offline waypoints for quest POIs

### Priority 3 - Other Classes
- Migrate Fire Mage to DSL
- Migrate Affliction Warlock to DSL
- Shared subtrees expansion

### Priority 4 - Rust Backend Extensions
- Add `/api/v1/npcs/{id}` endpoint
- Add `/api/v1/zones/{id}/quests` endpoint
- Add `/api/v1/optimal-route` for quest pathing

## API Constraints

All Lua uses Sylvannas APIs only:
- ✅ `core.http_get` (GET-only HTTP)
- ✅ `core.quests.*` (quest log APIs)
- ✅ `core.mail.*` (mail automation)
- ✅ `core.lfg_list.*` (dungeon queue)
- ✅ `core.addons.questie.*` (questie integration)
- ❌ No `os.time`, `io.popen` in runtime code (offline tools only)

## Files Structure

```
sentinel/modules/quest/
├── module.lua         ✅ Module orchestrator
├── tracker.lua        ✅ Quest log parsing
├── questie_adapter.lua ✅ Questie wrapper
├── query_client.lua   ✅ HTTP client
├── engine.lua         ✅ Route planning
└── generate_data_pack.lua ✅ Offline tool

SentinelQueryServer/
├── Cargo.toml         ✅ Dependencies
├── src/main.rs        ✅ Server + endpoints
└── src/error.rs       (todo: thiserror)

sentinel/modules/mail/
├── module.lua         ✅ Mail automation
└── settings.lua       ✅ Configuration

sentinel/modules/lfg/
└── module.lua         ✅ LFG automation

sentinel/modules/combat/
├── priority_builder.lua ✅ DSL builder
└── condition_library.lua ✅ Reusable conditions

Tests:
├── test_questie_adapter.lua ✅
├── test_query_client.lua ✅
├── test_engine.lua ✅
└── test_module.lua (mail) ✅
```