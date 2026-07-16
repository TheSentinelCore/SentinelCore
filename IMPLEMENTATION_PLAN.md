# SentinelCore v2: Phases A & B Implementation Plan
## Comprehensive Architecture Improvement Plan

### Overview
This document details the implementation plan for **Phase A** (New Lua Capabilities) and **Phase B** (Combat Framework Redesign) of the SentinelCore v2 architecture improvements. The plan builds upon the completed Phases 1-5 and leverages the Sylvannas API documentation verified through direct inspection.

---

## PHASE A: NEW LUA CAPABILITIES

### A.1 — AoE Ground Targeting with Spell Prediction

**Goal**: Replace naive position-based AoE casting with intelligent placement using IZI SDK spell prediction to maximize target hits.

**Files to Create/Modify**:
- `sentinel/shared/aoe_helper.lua` **(NEW)** - Centralized AoE targeting logic
- `sentinel/modules/combat/spell_dispatcher.lua` **(MODIFY)** - Add position casting support
- `sentinel/modules/combat/profiles/mage/frost_actions.lua` **(MODIFY)** - Update Blizzard/Flamestrike
- `sentinel/modules/combat/profiles/paladin/retribution_actions.lua` **(MODIFY)** - Update Consecration

**Implementation Details**:
1. **AoE Helper Module** (`aoe_helper.lua`):
   ```lua
   local AoeHelper = {}
   
   function AoeHelper.find_optimal_position(spell_id, range, min_targets)
       -- Creates spell data for prediction
       local spell_data = spell_prediction:new_spell_data(
           spell_id, range, radius, cast_time, 0,
           spell_prediction.prediction_type.MOST_HITS,
           spell_prediction.geometry_type.CIRCLE,
           player_position
       )
       
       local result = spell_prediction:get_most_hits_position(spell_data)
       return result and result.cast_position, result and result.amount_of_hits or 0
   end
   
   function AoeHelper.cast_ground_optimal(spell_id, range, min_targets)
       local pos, hits = AoeHelper.find_optimal_position(spell_id, range, min_targets)
       if pos and hits >= min_targets then
           core.input.cast_position_spell(spell_id, pos)
           return true, hits
       end
       return false, 0
   end
   ```

2. **Spell Dispatcher Enhancement**:
   - Add `spell_dispatcher:queue_position(spell_id, position, priority, opts)`
   - Wraps `spell_queue:queue_spell_position()` with existing deduplication/GCD checks

3. **Profile Updates**:
   - Frost Mage: Blizzard (spell ID 10/10181), Flamestrike (spell ID 2120)
   - Paladin: Consecration (spell ID 26573)
   - Use configurable `min_targets` (default: 3) and spell-specific ranges/radii

**Acceptance Criteria**:
- [ ] Blizzard hits ≥3 targets in test scenario vs. ≤2 with legacy targeting
- [ ] No regression in single-target rotation DPS
- [ ] Configurable minimum target threshold via settings
- [ ] Graceful fallback to target position when prediction unavailable

---

### A.2 — Full Quest Engine

**Goal**: Complete quest automation including acceptance, objective tracking, completion, and turn-in using Sylvannas quest API and TBC database integration.

**New Module**: `sentinel/modules/quest/` with 6 files:
- `module.py` - Lifecycle, EventBus, settings
- `tracker.py` - Quest log scanning, objective tracking
- `objectives.py` - Kill/collect/talk/escort evaluators
- `gossip.py` - NPC interaction, reward selection
- `db_adapter.py` - SentinelQueryServer integration for quest/NPC data
- `quest_tree.py` - BT subtree for quest-driven behavior
- `settings.py` - User configuration (reward preferences, etc.)

**Key Features**:
- **Quest Tracking**: On `QUEST_LOG_UPDATE`, scan `core.quests.get_num_quest_log_entries()` and parse objectives via `get_quest_log_leader_board()`
- **Objective Types**: 
  - Kill: Track via combat events (mob GUID matching)
  - Collect: Monitor inventory counts via `core.inventory.get_item_count()`
  - Talk/NPC: Detect proximity to quest givers/turn-in NPCs
  - Escort: Follow NPC using `SentinelNavClient` waypoint system
- **Quest Flow**:
  1. Enter quest giver gossip → `core.quests.get_gossip_available_quests()`
  2. Select & accept → `core.quests.accept_quest()`
  3. Track objectives in real-time
  4. On completion → Locate turn-in NPC → `core.quests.complete_quest()`
  5. Choose reward → `core.quests.get_quest_reward(choice)` (vendor value maximization by default)
- **Database Integration**: 
  - Query SentinelQueryServer for: 
    - `/api/v1/quests/{id}` (quest template with objectives/rewards)
    - `/api/v1/npcs/quest_giver/{id}` 
    - `/api/v1/npcs/quest_turnin/{id}`
    - `/api/v1/gossip/{npc_id}` for dialogue options

**Grind Integration**:
- Target Boost: Increase threat score for quest-relevant mobs in `target_filter.lua`
- Navigation: When no combat target, navigate to nearest quest objective
- Phases: Add `QUEST_ACCEPT` (pre-Acquire) and `QUEST_TURNIN` (post-Loot) phases

**Acceptance Criteria**:
- [ ] Fully automated standard quest hub (accept → kill/collect → turn-in)
- [ ] Zero manual intervention for kill/collect quests ≤ level 60
- [ ] Database-driven quest data (no hardcoded IDs)
- [ ] Configurable reward selection (vendor value, upgrade check, etc.)
- [ ] Proper handling of quest item looting (bypasses quality filters)

---

### A.3 — Enhanced Looting

**Goal**: Improve looting with quality filtering, quest item preservation, and intelligent bag management.

**File to Modify**: `sentinel/modules/grind/phases/loot.lua`

**Enhancements**:
1. **Quality Filtering**:
   - Configurable minimum quality (0=Poor, 1=Common, 2=Uncommon, 3=Rare, 4=Epic)
   - Default: Skip Poor (grey) items unless overridden
   
2. **Item Lists**:
   - Keep-list: Always loot specific item IDs (quest items, profession mats)
   - Deny-list: Never loot specific item IDs (trash, soulbound gear to vendor)
   
3. **Smart Banking**:
   - `destroy_grey_when_full`: Auto-delete grey items when < 2 bag slots free
   - `vendor_white_when_full`: Auto-vendor white items when bags full
   
4. **Quest Item Detection**:
   - Use `core.quests.get_quest_log_item_link()` to identify quest items
   - Never filter quest items regardless of quality settings
   
5. **Auto-Loot All**:
   - Optional toggle to loot all corpses in AoE (useful for AoE grinding)

**Acceptance Criteria**:
- [ ] Grey items auto-deleted at ≤2 bag slots (configurable)
- [ ] Quest items always looted regardless of quality filter
- [ ] Keep/Deny lists functional via settings UI
- [ ] No looting during active combat (preserves chase controller priority)
- [ ] Maintain existing corpse scan throttling (1000ms) and short-circuit logic

---

### A.4 — Mail Automation

**Goal**: Automated mail processing for gold collection, item distribution, and alt management.

**New Module**: `sentinel/modules/mail/` with 3 files:
- `module.py` - Background service, EventBus integration
- `inbox.py` - Mail processing: take gold, auto-loot items, delete spam
- `outbox.py` - Outbound mail: send items/gold to alts with filtering
- `settings.py` - Alt name, item filters, gold reserve, etc.

**Features**:
- **Inbox Processing**:
  - On `MAIL_SHOW` or periodic check (5 min when near mailbox)
  - Take all attached gold via `core.mail.take_inbox_money()`
  - Auto-loot all items via `core.mail.auto_loot_mail_item(i, j)`
  - Delete read, zero-gold, zero-item mail (configurable)
  
- **Outbound Sending**:
  - `send_to_alt(alt_name, item_filter_fn)` 
  - Filters: skip soulbound, equipped, quest, deny-list items
  - Respect gold reserve setting (don't send last X gold)
  - Optional COD and item quantity specification
  
- **Safety Features**:
  - Verify mailbox open before operations
  - Re-check inventory pre/post send to prevent race conditions
  - Rate limiting to avoid spam detection
  - Never send unsolicited mail (requires explicit configuration)

**Acceptance Criteria**:
- [ ] 100% gold collection from mailbox when open
- [ ] Configured items sent to alt without manual intervention
- [ ] Soulbound/equipped/quest items never auto-sent
- [ ] No mail sent during combat or while silenced
- [ ] Configurable safety delays and limits

---

### A.5 — LFG + Auction House Automation

**Goal**: Automated dungeon queuing and AH trading for consumables and profit.

#### A.5.1 — LFG Automation

**New Module**: `sentinel/modules/lfg/` with 2 files:
- `module.py` - Service lifecycle, state machine
- `settings.py` - Dungeon selection, role preference, auto-accept

**Features**:
- **Role-Based Queuing**: Tank/Heal/DPS based on class/spec
- **State Machine**:
  ```
  SEARCH → APPLY → WAIT_INVITE → ACCEPT → SUSPEND_GRIND → INSTANCE
  ```
- **Event-Driven**: 
  - `LFG_LIST_SEARCH_RESULT_UPDATED` → Evaluate groups
  - `LFG_LIST_APPLICATION_STATUS_UPDATED` → Track application status
- **Auto-Accept**: Optional instant accept for qualifying groups
- **Grind Suspension**: Pause grinding during queue/accept/entry process
- **Role Validation**: Check `core.lfg_list.get_search_result_member_counts()` for slot availability

#### A.5.2 — Auction House Automation

**New Module**: `sentinel/modules/auction/` with 2 files:
- `module.py` - Service lifecycle, scanning, posting logic
- `settings.py` - Posting thresholds, buy lists, undercut settings

**Features**:
- **Smart Scanning**:
  - On `AUCTION_HOUSE_SHOW`, call `core.auction_house.replicate_items()`
  - Process `core.auction_house.batch_get_replicate_items()` for deals
  
- **Automatic Posting**:
  - Post greens/blues above vendor price + 20% (configurable)
  - Post stackables (ore, cloth, herbs) in optimal stack sizes
  - Respect deposit costs to avoid losing money on low-value items
  
- **Smart Buying**:
  - Auto-purchase consumables when below threshold:
    - Health/Mana potions (< 5 stack)
    - Food/water (< 10)
    - Buff food (based on main stat)
  - Never buy above max price setting
  
- **Undercut Protection** (Optional):
  - Cancel and repost undercut auctions
  - Only enable during active play to avoid constant camping

**Acceptance Criteria**:
- [LFG] Auto-queues for selected dungeon with correct role
- [LFG] Accepts invitations when auto-accept enabled
- [LFG] Suspends grinding during queue/accept/transition
- [AH] Posts 10+ items/hour when AH visited with appropriate inventory
- [AH] Buys consumables when below threshold
- [AH] Never posts items at a loss (accounts for deposit)

---

## PHASE B: COMBAT FRAMEWORK REDESIGN

### B.1 — Condition Library

**Goal**: Eliminate ~200+ lines of duplicated condition logic across combat profiles.

**File Created**: `sentinel/modules/combat/condition_library.lua`

**Key Features**:
- **Factory Pattern**: All conditions return `function(blackboard) -> boolean`
- **Parameterized**: `ConditionLibrary.health_below(0.3)` returns ready-to-use function
- **Comprehensive Coverage**: 
  - Health/Mana/Resource checks
  - Target validation, range, casting status
  - Aura/buff/debuff detection (single & multiple)
  - Cooldown readiness (spell & GCD)
  - Combat state (in_combat, moving, casting)
  - Prediction-based (TTD, incoming damage)
  - Movement & positioning
  - PvP flags (target_is_player, etc.)
  - Class/spec specific (seals, forms, etc.)
- **Compound Conditions**: `ConditionLibrary.and_()`, `ConditionLibrary.or_()`, `ConditionLibrary.not_()`
- **Zero Runtime Overhead**: Functions are pure lookups/callables, no table creation per call

**Usage Example**:
```lua
-- Old (duplicated in every profile):
function Cond.health_below(threshold)
    return function(blackboard)
        return num(blackboard:get("player.health_pct", 0)) < threshold
    end
end

-- New (single source of truth):
local should_emergency_heal = ConditionLibrary.health_below(0.25)
-- Usage: if should_emergency_heal(blackboard) then ... end
```

### B.2 — Action Library

**Goal**: Eliminate duplicated action wrapper logic across combat profiles.

**File Created**: `sentinel/modules/combat/action_library.lua`

**Key Features**:
- **Unified Action Wrappers**: Standardized interfaces for all action types
- **Consistent Error Handling**: Safe nil-checks and fallback behaviors
- **Action Types**:
  - `cast_target(spell_key, target_fn, priority, opts)` - Standard targeted cast
  - `cast_self(spell_key, priority, opts)` - Self-buff/heal
  - `cast_position(spell_key, position_fn, priority, opts)` - Ground-targeted AoE
  - `use_item(item_id, priority)` - Inventory item use
  - `use_item_on_target(item_id, target_fn, priority)` - Targeted item use
  - `interrupt(spell_key, priority, opts)` - High-priority interrupt
  - `cancel_cast()` - Emergency cast cancellation
  - Pet, movement, buff, loot helpers
- **Queue Integration**: All actions route through `SpellDispatcher` for deduplication/GCD
- **Flexible Targeting**: Accept functions for dynamic target selection
- **Zero Wrapper Overhead**: Inlinable functions where possible

**Usage Example**:
```lua
-- Old (copy-pasted in every actions file):
function Act.queue_frostbolt(blackboard)
    local _, target = player_and_target(blackboard)
    return queue_target(blackboard, "frostbolt", "frostbolt", target, QueuePriorities.DEFAULT)
end

-- New (single implementation + reuse):
local frostbolt_action = ActionLibrary.cast_target("frostbolt", nil, QueuePriorities.DEFAULT)
-- Usage in priority builder: action = frostbolt_action
```

### B.3 — Shared Subtrees

**Goal**: Eliminate duplicated logic for common combat patterns (interrupts, defensives, executes, etc.).

**File Created**: `sentinel/modules/combat/shared_subtrees.lua`

**Pre-Built Subtrees**:
- **Interrupt**: Configurable interrupt with range, priority, and enable conditions
- **Defensive**: Smart cooldown usage based on health, TTD, or incoming damage
- **Execute**: Finishers that scale with target health % or time-to-die
- **AoE**: Intelligent placement with enemy counting and optional spell prediction
- **Buff Maintenance**: Auto-refresh for buffs with uptime tracking
- **Kite Assist**: Movement helpers for ranged kiting (basic framework)

**Usage Example**:
```lua
local interrupt_subtree = SharedSubtrees.interrupt("counterspell", {
    range = 28,
    priority = 7,
    enabled_condition = function(bb) 
        return bb:get("player.talent_spec") == "FROST" 
    end
})
```

### B.4 — Priority Builder DSL

**Goal**: Enable data-driven rotation construction replacing imperative BT node nesting.

**File Created**: `sentinel/modules/combat/priority_builder.lua`

**Features**:
- **Fluent Interface**: Chainable methods for readable configuration
- **Declaration Over Implementation**: Describe *what* to do, not *how* to build the tree
- **Automatic Validation**: Catch configuration errors at build time
- **Priority Sorting**: Automatically sorts by priority level (lower = higher priority)
- **Shared Subtree Injection**: Flexible insertion points for cross-cutting concerns
- **Custom Extensions**: Add project-specific conditions/actions as needed
- **Clear Separation**: Logic (conditions/actions) vs. Orchestration (priority builder)

**Usage Example**:
```lua
local function build_frost_mage_rotation()
    local builder = PriorityBuilder.new("MAGE", "FROST")
    builder:set_icon(135846)  -- Frostbolt
    
    -- High Priority: Defensive
    builder:add_priority(
        "Ice Block Emergency",
        ConditionLibrary.health_below(0.15),
        ActionLibrary.cast_self("ice_block", 6)
    )
    
    -- High Priority: Interrupt
    builder:add_priority(
        "Counterspell",
        ConditionLibrary.and_({
            ConditionLibrary.target_casting_interruptible,
            ConditionLibrary.spell_ready("counterspell"),
            ConditionLibrary.target_in_range(30)
        }),
        ActionLibrary.cast_target("counterspell", nil, 7)
    )
    
    -- Medium Priority: Proc Usage
    builder:add_priority(
        "Ice Lance Proc",
        ConditionLibrary.has_buff("fingers_of_frost"),
        ActionLibrary.cast_target("ice_lance", nil, 2)
    )
    
    -- Low Priority: Standard Spell
    builder:add_priority(
        "Frostbolt",
        ConditionLibrary.and_({
            ConditionLibrary.target_valid,
            ConditionLibrary.spell_ready("frostbolt")
        }),
        ActionLibrary.cast_target("frostbolt", nil, 1)
    )
    
    return builder:build(blackboard)
end
```

### B.5 — Profile Migration

**Goal**: Migrate existing profiles to the new system while maintaining 100% behavioral compatibility.

**Profiles to Migrate**:
- `sentinel/modules/combat/profiles/mage/frost_*` (8 files)
- `sentinel/modules/combat/profiles/paladin/retribution_*` (6 files)

**Migration Strategy**:
1. **Phase 1: Library Extraction**
   - Move duplicate conditions to `ConditionLibrary`
   - Move duplicate actions to `ActionLibrary`
   - Replace inline logic with library calls
   - Verify zero behavioral change through existing tests

2. **Phase 2: Subtree Identification**  
   - Identify common patterns (interrupt sequences, defensive rotations, etc.)
   - Extract to `SharedSubtrees` with configurable parameters
   - Replace instances in profiles with subtree calls

3. **Phase 3: Priority-Based Reconstruction**
   - For each spec, build `PriorityBuilder` version of rotation
   - Match exact priority ordering and conditions of original
   - Validate mechanical equivalence via combat testing
   - Gradually replace legacy condition/action files

4. **Phase 4: Optimization & Tuning**
   - Leverage new flexibility to refine rotations
   - Add missing procs/synergies that were impractical to implement before
   - Maintain backward compatibility via fallback to original if needed

**Acceptance Criteria**:
- [ ] Zero regression in damage/healing output vs. original implementation
- [ ] All existing unit tests pass
- [ ] Manual gameplay verification (leveling, dungeons, raids)
- [ ] Configurable to switch between legacy and new implementations
- [ ] Clear migration path for remaining 25 Classic specs

---

## IMPLEMENTATION ROADMAP

### Phase 1: Foundation Libraries (Weeks 1-2)
1. ✅ Condition Library (completed)
2. ✅ Action Library (completed) 
3. ✅ Shared Subtrees (completed)
4. ✅ Priority Builder DSL (completed)
5. ✅ Unit tests for all libraries

### Phase 2: Phase A - New Capabilities (Weeks 3-6)
**Order of Implementation** (by complexity/risk):
1. **A.3 Enhanced Looting** (Lowest risk - modifies single file)
2. **A.1 AoE Ground Targeting** (Moderate risk - well-contained changes)
3. **A.4 Mail Automation** (Low risk - new module, minimal integration)
4. **A.5 LFG/AH Automation** (Moderate risk - new modules, event integration)
5. **A.2 Quest Engine** (Highest risk - complex state, DB integration)

### Phase 3: Phase B - Combat Framework (Weeks 7-10)
**Order of Implementation**:
1. **B.1 & B.2 Library Integration** (Replace duplicates in existing profiles)
2. **B.3 Subtree Adoption** (Replace common patterns with shared subtrees)
3. **B.4 Migration Template** (Create Frost Mage & Ret Paladin examples)
4. **B.5 Full Profile Migration** (Convert both profiles to PriorityBuilder)
5. **B.6 Validation & Tuning** (Ensure parity, then optimize)

### Phase 4: Testing & Validation (Ongoing)
- Unit test coverage for new libraries
- Integration test scenarios for each capability
- Manual QA verification of gameplay impact
- Performance benchmarking (ensure no regression)

---

## FILES SUMMARY

### New Files Created:
```
sentinel/
├── shared/
│   └── aoe_helper.lua                    # A.1: AoE targeting helper
├── modules/
├── combat/
│   ├── condition_library.lua             # B.1: Shared condition factories
│   ├── action_library.lua                # B.2: Shared action factories
│   ├── shared_subtrees.lua               # B.3: Reusable combat subtrees
│   ├── priority_builder.lua              # B.4: DSL for rotation building
│   └── examples/
│       └── frost_mage_priority_example.lua # Demonstration of new approach
├── quest/                                # A.2: Quest engine (6 files)
├── mail/                                 # A.4: Mail automation (3 files)
├── lfg/                                  # A.5.1: LFG automation (2 files)
└── auction/                              # A.5.2: Auction house (2 files)
```

### Modified Files:
```
sentinel/
├── modules/
│   ├── combat/
│   │   ├── spell_dispatcher.lua          # A.1: Add position casting support
│   │   ├── profiles/
│   │   │   ├── mage/
│   │   │   │   ├── frost_actions.lua     # A.1, B.1-B.4: Update actions
│   │   │   │   └── frost_conditions.lua  # B.1-B.4: Update conditions
│   │   │   ├── paladin/
│   │   │   │   ├── retribution_actions.lua # A.1, B.1-B.4: Update actions
│   │   │   │   └── retribution_conditions.lua # B.1-B.4: Update conditions
│   │   └── ... (other profiles updated similarly)
│   ├── grind/
│   │   └── phases/
│   │       └── loot.lua                  # A.3: Enhanced looting logic
│   └── runtime/
│       └── app.lua                       # A.2, A.4, A.5: Module registration
```

### Configuration Changes:
- Add new settings sections for:
  - Quest behavior (A.2)
  - Loot filters (A.3)
  - Mail automation (A.4)
  - LFG preferences (A.5.1)
  - AH trading rules (A.5.2)
  - Combat framework toggles (B.6: legacy vs new)

---

## RISKS & MITIGATION

### Technical Risks:
1. **Performance Regression** 
   - Mitigation: Libraries designed for zero-allocation hot paths; benchmark critical paths
   
2. **Integration Complexity**
   - Mitigation: Modular design with clear interfaces; feature flags for rollback
   
3. **Behavioral Drift**
   - Mitigation: Comprehensive unit tests + manual verification checklist
   
4. **Database Latency** (Quest Engine)
   - Mitigation: Cache quest data; background prefetch; offline fallback

### Scope Risks:
1. **Quest Engine Complexity**
   - Mitigation: MVP first (accept/complete at NPC), then add objective tracking
   
2. **Permission Creep** (Mail/AH Automation)
   - Mitigation: Opt-in features with clear warnings; never act without explicit config

### Dependencies:
- **SentinelQueryServer**: Required for Quest Engine full functionality
  - Fallback: Local database queries or gossip-only mode
- **IZI SDK**: Required for advanced prediction and health features
  - Fallback: Basic heuristics when IZI unavailable (graceful degradation)

---

## CONCLUSION

This plan delivers:
- **Phase A**: 5 major new capabilities expanding bot functionality beyond combat
- **Phase B**: Modern, maintainable combat architecture reducing duplication by ~70%
- **Zero Breaking Changes**: Existing configurations and workflows preserved
- **Clear Migration Path**: Incremental adoption with fallback mechanisms
- **Foundation for 25+ Specs**: Template for rapid deployment of remaining class/spec combos

The implementation leverages verified Sylvannas APIs, follows established code patterns, and maintains the project's commitment to deterministic, rule-based automation suitable for Classic WoW gameplay.

--- 
*End of Plan*