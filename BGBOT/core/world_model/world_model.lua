---@module BGBOT.core.world_model.world_model
-- Single source of truth for all decision-making layers.
-- Perception writes; all other layers read.
-- Entity table keyed by tostring(game_object) per DEC-011.

local constants    = require("shared/constants")
local utils        = require("shared/utils")
local bg_state_mod = require("core/world_model/bg_state")

local world_model = {}
world_model.__index = world_model

local function new_flag_inference()
    return {
        our_flag_state     = "unknown",
        their_flag_state   = "unknown",
        our_flag_carrier   = nil,
        their_flag_carrier = nil,
    }
end

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------

function world_model.new()
    local self = setmetatable({}, world_model)
    self.self_state = nil                  -- SelfState
    self.entities   = {}                   -- { [handle_key] = EntityRecord }
    self.bg_state   = bg_state_mod.new_state()
    self.flag_inference = new_flag_inference()
    self.temporal   = {
        tick_count        = 0,
        last_full_scan    = 0,
        last_visible_scan = 0,
    }
    return self
end

----------------------------------------------------------------------
-- Write Methods  (called by Perception only)
----------------------------------------------------------------------

--- Update self-state snapshot.
---@param state SelfState
function world_model:update_self(state)
    self.self_state = state
end

--- Update (or insert) an entity. Keyed by tostring(handle).
--- Implements name+class reconciliation per DEC-011:
--- When a handle changes for the same player (left/re-entered visibility),
--- the old stale entry is evicted and critical state (has_flag) is migrated.
---@param handle game_object
---@param record EntityRecord
function world_model:update_entity(handle, record)
    local key = utils.handle_key(handle)

    -- Fast path: key already exists (same handle) → overwrite
    local existing = self.entities[key]
    if existing then
        self.entities[key] = record
        return
    end

    -- Slow path: new key — check for stale entry with same name+class
    if record.name and record.name ~= "" then
        for old_key, old_ent in pairs(self.entities) do
            if old_key ~= key
                and old_ent.name == record.name
                and old_ent.class_id == record.class_id
                and old_ent.is_player == record.is_player
                and old_ent.is_enemy == record.is_enemy then

                -- Migrate critical state from old entry
                if old_ent.has_flag then
                    record.has_flag = true
                end

                -- Evict stale entry
                self.entities[old_key] = nil
                break
            end
        end
    end

    self.entities[key] = record
end

--- Update BG state (overwrites entire struct).
---@param state BgState
function world_model:update_bg_state(state)
    -- Do not carry stale flag-carrier data outside WSG context.
    if state.bg_type ~= "wsg" then
        self.flag_inference = new_flag_inference()
    end

    -- Preserve independently-inferred flag state if scanner provided "unknown".
    if state.our_flag_state == "unknown" and self.flag_inference.our_flag_state ~= "unknown" then
        state.our_flag_state   = self.flag_inference.our_flag_state
        state.our_flag_carrier = self.flag_inference.our_flag_carrier
    end
    if state.their_flag_state == "unknown" and self.flag_inference.their_flag_state ~= "unknown" then
        state.their_flag_state   = self.flag_inference.their_flag_state
        state.their_flag_carrier = self.flag_inference.their_flag_carrier
    end
    self.bg_state = state
end

--- Update flag inference (called after aura scans).
---@param inference table { our_flag_carrier, their_flag_carrier, our_flag_state, their_flag_state }
function world_model:update_flag_inference(inference)
    self.flag_inference.our_flag_carrier   = inference.our_flag_carrier
    self.flag_inference.their_flag_carrier = inference.their_flag_carrier
    self.flag_inference.our_flag_state     = inference.our_flag_state or "unknown"
    self.flag_inference.their_flag_state   = inference.their_flag_state or "unknown"

    self.bg_state.our_flag_carrier   = self.flag_inference.our_flag_carrier
    self.bg_state.their_flag_carrier = self.flag_inference.their_flag_carrier
    self.bg_state.our_flag_state     = self.flag_inference.our_flag_state
    self.bg_state.their_flag_state   = self.flag_inference.their_flag_state
end

--- Update temporal metadata.
---@param meta table { tick_count, last_full_scan, last_visible_scan }
function world_model:update_temporal(meta)
    self.temporal = meta
end

----------------------------------------------------------------------
-- Finalize  (called after Perception tick, before Strategist reads)
----------------------------------------------------------------------

function world_model:finalize()
    local now = core.time()
    self:evict_stale(now)
    self:decay_confidence(now)
end

----------------------------------------------------------------------
-- Staleness Eviction
----------------------------------------------------------------------

function world_model:evict_stale(now)
    local evict_threshold = constants.ENTITY.STALE_EVICT_SECS
    local keys_to_remove = {}

    for key, ent in pairs(self.entities) do
        local should_remove = false

        -- Evict if handle invalid
        if ent.handle then
            local ok_valid, valid = pcall(function()
                return ent.handle:is_valid()
            end)
            should_remove = (not ok_valid) or (not valid)
        end

        -- Evict if not seen for > threshold
        if not should_remove and (now - ent.last_seen) > evict_threshold then
            should_remove = true
        end

        if should_remove then
            keys_to_remove[#keys_to_remove + 1] = key
        end
    end

    for _, key in ipairs(keys_to_remove) do
        self.entities[key] = nil
    end
end

----------------------------------------------------------------------
-- Confidence Decay
----------------------------------------------------------------------

function world_model:decay_confidence(now)
    for _, ent in pairs(self.entities) do
        ent.confidence = utils.compute_confidence(
            ent.last_seen, now, constants.ENTITY.CONFIDENCE_DECAY
        )
        -- Mark ring as stale if very low confidence
        if ent.confidence < 0.3 then
            ent.ring = "stale"
        end
    end
end

----------------------------------------------------------------------
-- Read Methods  (called by Strategist, Intent, Combat Micro, etc.)
----------------------------------------------------------------------

---@return SelfState|nil
function world_model:get_self()
    return self.self_state
end

---@return BgState
function world_model:get_bg_state()
    return self.bg_state
end

--- Get entity by game_object handle.
---@param handle game_object
---@return EntityRecord|nil
function world_model:get_entity(handle)
    if not handle then return nil end
    return self.entities[utils.handle_key(handle)]
end

--- Get all tracked entities (raw table).
---@return table { [handle_key] = EntityRecord }
function world_model:get_all_entities()
    return self.entities
end

--- Get list of allied player entities.
---@return EntityRecord[]
function world_model:get_allies()
    local out = {}
    for _, ent in pairs(self.entities) do
        if ent.is_ally and ent.is_player and not ent.is_dead then
            out[#out + 1] = ent
        end
    end
    return out
end

--- Get list of enemy player entities.
---@return EntityRecord[]
function world_model:get_enemies()
    local out = {}
    for _, ent in pairs(self.entities) do
        if ent.is_enemy and ent.is_player and not ent.is_dead then
            out[#out + 1] = ent
        end
    end
    return out
end

--- Get entity counts (for debug logging).
---@return table { allies, enemies, total }
function world_model:get_entity_counts()
    local allies, enemies, total = 0, 0, 0
    for _, ent in pairs(self.entities) do
        total = total + 1
        if ent.is_ally then allies = allies + 1 end
        if ent.is_enemy then enemies = enemies + 1 end
    end
    return { allies = allies, enemies = enemies, total = total }
end

--- Get current BG phase.
---@return number
function world_model:get_bg_phase()
    return self.bg_state.phase
end

--- Reset all entity confidence (used post-death per WSG_STRATEGY_V1).
function world_model:reset_confidence()
    for _, ent in pairs(self.entities) do
        ent.confidence = 0
    end
end

return world_model
