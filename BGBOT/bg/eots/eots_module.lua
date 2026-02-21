---@module BGBOT.bg.eots.eots_module
-- Eye of the Storm BG Module: implements BgModule interface.
-- Tower-based scoring with faction-spawn bias and mid-flag gating.

local constants    = require("shared/constants")
local bg_constants = require("shared/bg_constants")
local config       = require("shared/config")
local utils        = require("shared/utils")

local eots_module = {}
eots_module.__index = eots_module

local max = math.max

----------------------------------------------------------------------
-- BgModule interface fields
----------------------------------------------------------------------

eots_module.id = "eots"
eots_module.map_ids = constants.EOTS_MAP_IDS

----------------------------------------------------------------------
-- EotS tower/flag definitions
----------------------------------------------------------------------

-- Cap-point NPC IDs used for heuristic ownership detection.
local CAP_POINT_IDS = {
    [184080] = "be_tower",
    [184081] = "fe_tower",
    [184083] = "draenei_tower",
    [184082] = "human_tower",
}

-- Visual banner NPC IDs for ownership heuristic (appear at each tower).
local BANNER_IDS = {
    alliance = { [184381] = true },
    horde    = { [184380] = true },
    neutral  = { [184382] = true },
}

-- Netherstorm Flag NPC IDs (both dropped-at-tower variants and center spawn).
local FLAG_IDS = {
    [184141] = true,   -- center spawn
    [184493] = true,   -- carried/dropped variants at tower positions
}

-- Towers that are closer to each faction's spawn.
local SPAWN_ADJACENT = {
    [constants.FACTION.ALLIANCE] = { human_tower = true, draenei_tower = true },
    [constants.FACTION.HORDE]    = { be_tower = true, fe_tower = true },
}

-- Build tower table from extracted bg_constants, with fallback to EOTS_POSITIONS.
local function build_eots_towers()
    local out = {}
    local src = ((bg_constants or {}).EYE_OF_THE_STORM or {}).NODES or {}

    -- Map cap-point entries from extracted data.
    for _, entry in ipairs(src) do
        local id = tonumber(entry.id) or 0
        local key = CAP_POINT_IDS[id]
        if key and entry.x and entry.y and entry.z then
            out[key] = {
                name = entry.name or key,
                pos  = { x = entry.x, y = entry.y, z = entry.z },
            }
        end
    end

    -- Fallback to constants.EOTS_POSITIONS for any towers missing.
    local fallback = {
        be_tower      = constants.EOTS_POSITIONS and constants.EOTS_POSITIONS.be_tower,
        draenei_tower = constants.EOTS_POSITIONS and constants.EOTS_POSITIONS.draenei_tower,
        human_tower   = constants.EOTS_POSITIONS and constants.EOTS_POSITIONS.human_tower,
        fe_tower      = constants.EOTS_POSITIONS and constants.EOTS_POSITIONS.fe_tower,
    }

    for key, pos in pairs(fallback) do
        if not out[key] and pos and pos.x and pos.y and pos.z then
            out[key] = {
                name = key,
                pos  = { x = pos.x, y = pos.y, z = pos.z },
            }
        end
    end

    return out
end

local EOTS_TOWERS = build_eots_towers()

-- Mid-flag position (center of the map, z is lower than towers).
local MID_FLAG_POS = constants.EOTS_POSITIONS and constants.EOTS_POSITIONS.mid_flag
    or { x = 2174.78, y = 1569.05, z = 1160.36 }

-- Radius around a tower position for nearby banner/entity scans.
local NODE_SCAN_RADIUS = 25

----------------------------------------------------------------------
-- BG Detection
----------------------------------------------------------------------

---@param map_id number|nil  current map ID from core.get_map_id()
---@return boolean
function eots_module:is_active(map_id)
    for _, id in ipairs(self.map_ids) do
        if map_id == id then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Ownership heuristic (visual banners near towers)
----------------------------------------------------------------------

local OWNER_UNKNOWN  = 0
local OWNER_OURS     = 1
local OWNER_THEIRS   = 2
local OWNER_NEUTRAL  = 3

local OWNERSHIP_MIN_CONFIDENCE = 0.35
local OWNERSHIP_STABLE_WINDOW = 2.0
local OWNERSHIP_HOLD_SECS = 3.0
local ownership_state = {} -- { [tower_key] = { owner, confidence, candidate_owner, candidate_since, last_seen } }

--- Infer tower ownership from nearby visual banner objects.
---@param world_model WorldModel
---@param tower_pos table {x,y,z}
---@param self_faction number  constants.FACTION.HORDE or ALLIANCE
---@return number  OWNER_* enum
---@return number  confidence 0.0-1.0
local function infer_tower_ownership(world_model, tower_pos, self_faction)
    local best_owner = OWNER_UNKNOWN
    local best_dist  = NODE_SCAN_RADIUS + 1

    for _, ent in pairs(world_model:get_all_entities()) do
        if ent.position and ent.npc_id then
            local dist = utils.distance_3d(tower_pos, ent.position)
            if dist <= NODE_SCAN_RADIUS then
                -- Neutral banner
                if BANNER_IDS.neutral[ent.npc_id] then
                    if dist < best_dist then
                        best_owner = OWNER_NEUTRAL
                        best_dist  = dist
                    end
                end

                -- Alliance banner
                if BANNER_IDS.alliance[ent.npc_id] then
                    if dist < best_dist then
                        if self_faction == constants.FACTION.ALLIANCE then
                            best_owner = OWNER_OURS
                        else
                            best_owner = OWNER_THEIRS
                        end
                        best_dist = dist
                    end
                end

                -- Horde banner
                if BANNER_IDS.horde[ent.npc_id] then
                    if dist < best_dist then
                        if self_faction == constants.FACTION.HORDE then
                            best_owner = OWNER_OURS
                        else
                            best_owner = OWNER_THEIRS
                        end
                        best_dist = dist
                    end
                end
            end
        end
    end

    local confidence = 0.0
    if best_owner ~= OWNER_UNKNOWN then
        confidence = max(0.1, 1.0 - (best_dist / NODE_SCAN_RADIUS))
    end

    return best_owner, confidence
end

local function now_secs()
    if core and core.time then
        return core.time()
    end
    return 0
end

local function resolve_tower_ownership(tower_key, world_model, tower_pos, self_faction)
    local observed_owner, observed_confidence = infer_tower_ownership(world_model, tower_pos, self_faction)
    local now = now_secs()

    local state = ownership_state[tower_key]
    if not state then
        state = {
            owner = OWNER_UNKNOWN,
            confidence = 0,
            candidate_owner = OWNER_UNKNOWN,
            candidate_since = now,
            last_seen = now,
        }
        ownership_state[tower_key] = state
    end

    if observed_owner == OWNER_UNKNOWN then
        if state.owner ~= OWNER_UNKNOWN and (now - (state.last_seen or now)) <= OWNERSHIP_HOLD_SECS then
            state.confidence = max(0.1, (state.confidence or 0) * 0.9)
            return state.owner, state.confidence
        end
        state.owner = OWNER_UNKNOWN
        state.confidence = 0
        return OWNER_UNKNOWN, 0
    end

    state.last_seen = now

    if state.owner == observed_owner then
        state.confidence = max(state.confidence or 0, observed_confidence or 0)
        state.candidate_owner = observed_owner
        state.candidate_since = now
        return state.owner, state.confidence
    end

    if (observed_confidence or 0) < OWNERSHIP_MIN_CONFIDENCE then
        return state.owner, state.confidence
    end

    if state.candidate_owner ~= observed_owner then
        state.candidate_owner = observed_owner
        state.candidate_since = now
        return state.owner, state.confidence
    end

    local stable_for = now - (state.candidate_since or now)
    if stable_for >= OWNERSHIP_STABLE_WINDOW then
        state.owner = observed_owner
        state.confidence = observed_confidence or state.confidence or 0
    end

    return state.owner, state.confidence
end

----------------------------------------------------------------------
-- Player counting helper
----------------------------------------------------------------------

---@param world_model WorldModel
---@param pos table {x,y,z}
---@param radius number
---@return number friendlies, number enemies
local function count_nearby_players(world_model, pos, radius)
    local friends, foes = 0, 0
    for _, ent in pairs(world_model:get_all_entities()) do
        if ent.is_player and not ent.is_dead and ent.position then
            local dist = utils.distance_3d(pos, ent.position)
            if dist <= radius then
                if ent.is_ally then
                    friends = friends + 1
                elseif ent.is_enemy then
                    foes = foes + 1
                end
            end
        end
    end
    return friends, foes
end

----------------------------------------------------------------------
-- Utility
----------------------------------------------------------------------

local function copy_pos(pos)
    if not pos or pos.x == nil or pos.y == nil or pos.z == nil then
        return nil
    end
    return { x = pos.x, y = pos.y, z = pos.z }
end

local function write_eots_runtime_targets(world_model, target_key, target_pos)
    local bg = world_model:get_bg_state()
    if not bg or bg.bg_type ~= "eots" then
        return
    end

    bg.eots_target_node_key = target_key or ""
    bg.eots_target_node_pos = copy_pos(target_pos)

    world_model:update_bg_state(bg)
end

----------------------------------------------------------------------
-- Tower weight evaluation
----------------------------------------------------------------------

--- Evaluate weights for all EotS towers and determine the best target.
---@param world_model WorldModel
---@param self_state table  world model self record
---@return string|nil best_tower_key
---@return number best_weight
---@return table info { owned, neutral, theirs }
function eots_module:evaluate_tower_weights(world_model, self_state)
    local self_faction = self_state.faction or constants.FACTION.UNKNOWN
    local self_pos = self_state.position

    local owned_count   = 0
    local neutral_count = 0
    local theirs_count  = 0
    local best_key      = nil
    local best_weight   = -1
    local owner_by_key  = {}
    local confidence_by_key = {}

    -- Determine which towers are spawn-adjacent for this faction.
    local adjacent_set = SPAWN_ADJACENT[self_faction] or {}

    -- Pass 1: ownership tally for deterministic gating.
    for key, tower in pairs(EOTS_TOWERS) do
        local owner, confidence = resolve_tower_ownership(key, world_model, tower.pos, self_faction)
        owner_by_key[key] = owner
        confidence_by_key[key] = confidence

        if owner == OWNER_OURS then
            owned_count = owned_count + 1
        elseif owner == OWNER_NEUTRAL then
            neutral_count = neutral_count + 1
        elseif owner == OWNER_THEIRS then
            theirs_count = theirs_count + 1
        end
    end

    -- Pass 2: weight non-owned towers using stable owned_count.
    for key, tower in pairs(EOTS_TOWERS) do
        local owner = owner_by_key[key] or OWNER_UNKNOWN
        local confidence = confidence_by_key[key] or 0

        -- Only consider capturing non-owned towers.
        if owner ~= OWNER_OURS then
            local friends, foes = count_nearby_players(world_model, tower.pos, NODE_SCAN_RADIUS)
            local ratio = friends / (foes + 1)
            local dist  = self_pos and utils.distance_3d(self_pos, tower.pos) or 200
            local dist_mod = max(0.3, 1.0 - (dist / 400))
            local weight = ratio * dist_mod

            -- Neutral towers get a slight urgency bonus.
            if owner == OWNER_NEUTRAL then
                weight = weight * 1.15
            end

            -- Low-confidence unknown towers get reduced weight.
            if owner == OWNER_UNKNOWN and confidence < 0.3 then
                weight = weight * 0.6
            end

            -- Early-game bias: if we own fewer than 2, heavily prioritize
            -- spawn-adjacent towers to secure the opening.
            if owned_count < 2 and adjacent_set[key] then
                weight = weight * 2.5
            end

            if weight > best_weight then
                best_weight = weight
                best_key    = key
            end
        end
    end

    return best_key, best_weight, {
        owned   = owned_count,
        neutral = neutral_count,
        theirs  = theirs_count,
    }
end

----------------------------------------------------------------------
-- Score Intents  (BgModule interface)
----------------------------------------------------------------------

---@param world_model WorldModel
---@param intent_registry table { [intent_id] = Intent }
---@return table { [intent_id] = score }
function eots_module:score_intents(world_model, intent_registry)
    local scores = {}
    local self_state = world_model:get_self()
    local bg = world_model:get_bg_state()

    -- Baseline fallback.
    scores.roam = 20

    if not self_state or not self_state.position or not bg or bg.bg_type ~= "eots" then
        return scores
    end

    local self_pos = self_state.position
    local low_hp = (self_state.health_pct or 100)
        <= (config.combat.retreat_hp_pct or constants.COMBAT.RETREAT_HEALTH_PCT)

    -- Evaluate tower weights.
    local target_key, target_weight, info = self:evaluate_tower_weights(world_model, self_state)

    -- Roam toward best attack target (tower).
    if target_key and intent_registry.roam then
        local base_score = 40 + (target_weight * 15)
        scores.roam = max(scores.roam, base_score)
    end

    ----------------------------------------------------------------
    -- Mid-flag scoring: gated by base ownership count.
    --   owned == 2  → strongly boost mid-flag capture priority
    --   owned <= 1  → mid-flag priority forced to ZERO (anti-troll)
    --   owned >= 3  → no special mid-flag boost (defend towers)
    ----------------------------------------------------------------
    if info.owned == 2 then
        -- With exactly 2 bases, mid-flag captures grant bonus points.
        -- Check if mid-flag is available (a Netherstorm Flag object exists at center).
        local mid_available = false
        for _, ent in pairs(world_model:get_all_entities()) do
            if ent.npc_id and FLAG_IDS[ent.npc_id] and ent.position then
                local dist_to_center = utils.distance_3d(MID_FLAG_POS, ent.position)
                if dist_to_center <= 30 then
                    mid_available = true
                    break
                end
            end
        end

        if mid_available then
            -- Override roam target to mid-flag when it's available and we own 2 bases.
            local dist_to_mid = utils.distance_3d(self_pos, MID_FLAG_POS)
            local mid_score = 60 + max(0, 20 - (dist_to_mid / 10))
            scores.roam = max(scores.roam, mid_score)

            -- Write mid-flag as the nav target instead of the tower.
            target_key = "mid_flag"
            target_weight = mid_score
        end
    end
    -- owned <= 1 or owned >= 3: mid_flag gets no boost → tower targeting stays.

    -- Fight intent: engage enemies near current position.
    if intent_registry.fight then
        local enemies_near = 0
        for _, ent in pairs(world_model:get_all_entities()) do
            if ent.is_player and ent.is_enemy and not ent.is_dead and ent.position then
                local dist = utils.distance_3d(self_pos, ent.position)
                if dist <= 35 then
                    enemies_near = enemies_near + 1
                end
            end
        end
        if enemies_near > 0 then
            scores.fight = 42 + max(0, enemies_near * 8)
        end
    end

    -- Retreat when low HP or heavily outnumbered.
    if intent_registry.retreat then
        if low_hp then
            scores.retreat = max(scores.retreat or 0,
                70 + max(0, (30 - (self_state.health_pct or 0))))
        end
        local friends, foes = count_nearby_players(world_model, self_pos,
            constants.WSG.LOCAL_RISK_RADIUS)
        local outnumbered = foes > (friends + 2)
        if outnumbered then
            local disadvantage = foes - friends
            scores.retreat = max(scores.retreat or 0, 60 + (disadvantage * 8))
        end
    end

    -- Write runtime targets for roam intent consumption.
    local target_pos = nil
    if target_key == "mid_flag" then
        target_pos = MID_FLAG_POS
    elseif target_key and EOTS_TOWERS[target_key] then
        target_pos = EOTS_TOWERS[target_key].pos
    end
    write_eots_runtime_targets(world_model, target_key, target_pos)

    return scores
end

return eots_module
