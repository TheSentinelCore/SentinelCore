---@module BGBOT.bg.av.av_module
-- Alterac Valley BG Module: implements BgModule interface.
-- Dynamic rush-vs-turtle playbook with bunker assault priority for stealth classes.

local constants    = require("shared/constants")
local bg_constants = require("shared/bg_constants")
local config       = require("shared/config")
local utils        = require("shared/utils")

local av_module = {}
av_module.__index = av_module

local max = math.max
local min = math.min

----------------------------------------------------------------------
-- BgModule interface fields
----------------------------------------------------------------------

av_module.id = "av"
av_module.map_ids = constants.AV_MAP_IDS

----------------------------------------------------------------------
-- AV node / bunker definitions
----------------------------------------------------------------------

-- Ownership enum (same conventions as AB/EotS modules).
local OWNER_UNKNOWN   = 0
local OWNER_OURS      = 1
local OWNER_THEIRS    = 2
local OWNER_CONTESTED = 3
local OWNER_NEUTRAL   = 4

local OWNERSHIP_MIN_CONFIDENCE = 0.35
local OWNERSHIP_STABLE_WINDOW = 2.0
local OWNERSHIP_HOLD_SECS = 3.0
local ownership_state = {} -- { [node_key] = { owner, confidence, candidate_owner, candidate_since, last_seen } }

-- Banner NPC IDs for heuristic ownership detection.
local BANNER_IDS = {
    alliance  = {
        [178925] = true,   -- Alliance Banner (bunkers/GYs)
        [178365] = true,   -- Alliance Banner (GYs/towers)
        [179024] = true,   -- Stormpike Banner
    },
    horde     = {
        [178943] = true,   -- Horde Banner (bunkers/GYs)
        [178364] = true,   -- Horde Banner (GYs/towers)
        [179025] = true,   -- Frostwolf Banner
    },
    contested = {
        [178940] = true,   -- Contested Banner (Horde towers)
        [179435] = true,   -- Contested Banner (Alliance bunkers)
        [179286] = true,   -- Contested Banner (GYs variant A)
        [179287] = true,   -- Contested Banner (GYs variant B)
    },
    neutral   = {
        [180418] = true,   -- Snowfall Banner (neutral)
    },
}

-- Logical node keys → human readable names.
local AV_NODE_NAME = {
    stonehearth_gy  = "Stonehearth GY",
    stormpike_gy    = "Stormpike GY",
    snowfall_gy     = "Snowfall GY",
    iceblood_gy     = "Iceblood GY",
    frostwolf_gy    = "Frostwolf GY",
    dun_baldar_n    = "Dun Baldar North",
    dun_baldar_s    = "Dun Baldar South",
    icewing_bunker  = "Icewing Bunker",
    stonehearth_out = "Stonehearth Outpost",
    tower_point     = "Tower Point",
    west_frostwolf  = "West Frostwolf Tower",
    east_frostwolf  = "East Frostwolf Tower",
}

-- Map extracted bg_constants NPC IDs to logical node keys.
-- Uses the unique position as discriminator since many AV banners share the same NPC ID.
-- Format: { npc_id, x, y, z } → node_key (matched within radius tolerance).
local NODE_POSITION_MAP = {
    -- Graveyards (from bg_constants.ALTERAC_VALLEY.NODES banner positions)
    { key = "stormpike_gy",    x = 638.592,   y = -32.422,   z = 46.061 },
    { key = "stonehearth_gy",  x = 77.801,    y = -404.7,    z = 46.755 },
    { key = "snowfall_gy",     x = -202.581,  y = -112.73,   z = 78.488 },
    { key = "iceblood_gy",     x = -611.962,  y = -396.17,   z = 60.835 },
    { key = "frostwolf_gy",    x = -1082.45,  y = -346.823,  z = 54.922 },
    -- Towers/Bunkers
    { key = "dun_baldar_n",    x = 553.779,   y = -78.657,   z = 51.938 },
    { key = "dun_baldar_s",    x = 674.001,   y = -143.125,  z = 63.662 },
    { key = "icewing_bunker",  x = 203.281,   y = -360.366,  z = 56.387 },
    { key = "stonehearth_out", x = -152.437,  y = -441.758,  z = 40.398 },
    { key = "tower_point",     x = -571.88,   y = -262.777,  z = 75.009 },
    { key = "west_frostwolf",  x = -1302.9,   y = -316.981,  z = 113.867 },
    { key = "east_frostwolf",  x = -1297.5,   y = -266.767,  z = 114.15 },
    -- Relief GY at end (use Frostwolf RH Banner position)
    { key = "frostwolf_rh_gy", x = -1402.21,  y = -307.431,  z = 89.442 },
}

-- Which nodes are bunkers/towers (can be assaulted).
local BUNKER_NODES = {
    dun_baldar_n    = true,
    dun_baldar_s    = true,
    icewing_bunker  = true,
    stonehearth_out = true,
    tower_point     = true,
    west_frostwolf  = true,
    east_frostwolf  = true,
}

-- Faction affiliation for nodes: which faction initially owns each node.
local FACTION_NODE_INITIAL = {
    [constants.FACTION.ALLIANCE] = {
        stormpike_gy    = true,
        stonehearth_gy  = true,
        dun_baldar_n    = true,
        dun_baldar_s    = true,
        icewing_bunker  = true,
        stonehearth_out = true,
    },
    [constants.FACTION.HORDE] = {
        iceblood_gy     = true,
        frostwolf_gy    = true,
        frostwolf_rh_gy = true,
        tower_point     = true,
        west_frostwolf  = true,
        east_frostwolf  = true,
    },
}

-- Defensive chokepoint positions per faction — used by turtle-factor scoring.
local DEFENSIVE_CHOKEPOINTS = {
    [constants.FACTION.ALLIANCE] = {
        { x = 638.592,  y = -32.422,  z = 46.061 },   -- Stormpike GY
        { x = 553.779,  y = -78.657,  z = 51.938 },   -- Dun Baldar N
        { x = 674.001,  y = -143.125, z = 63.662 },   -- Dun Baldar S
        { x = 873.0,    y = -489.0,   z = 96.5 },     -- Alliance start area
    },
    [constants.FACTION.HORDE] = {
        { x = -1082.45, y = -346.823, z = 54.922 },   -- Frostwolf GY
        { x = -1302.9,  y = -316.981, z = 113.867 },  -- West Frostwolf Tower
        { x = -1297.5,  y = -266.767, z = 114.15 },   -- East Frostwolf Tower
        { x = -1370.0,  y = -219.0,   z = 98.5 },     -- Horde start area
    },
}

local CHOKE_RADIUS       = 120   -- herd within this radius of a chokepoint = turtling
local TURTLE_FULL_RADIUS = CHOKE_RADIUS * 0.65
local TURTLE_FADE_RADIUS = CHOKE_RADIUS * 1.75
local NODE_SCAN_RADIUS   = 30    -- larger than AB/EotS; AV banners can be offset
local HERD_NEARBY_RADIUS = 150   -- wider scan for AV since map is much larger
local HERD_MIN_ALLIES    = 3     -- need at least 3 for meaningful CoM
local BUNKER_ASSAULT_RANGE = 80  -- max distance from self to bunker to apply assault multiplier
local POSITION_MATCH_TOLERANCE = 5  -- yards tolerance for matching extracted data to keyed positions

----------------------------------------------------------------------
-- Build AV Nodes from extracted bg_constants (primary) + fallback
----------------------------------------------------------------------

--- Match an extracted entry position against NODE_POSITION_MAP to find
--- the logical key. Returns nil if no match within tolerance.
local function match_position_to_key(x, y, z)
    for _, nmap in ipairs(NODE_POSITION_MAP) do
        local dx = (x or 0) - (nmap.x or 0)
        local dy = (y or 0) - (nmap.y or 0)
        local dz = (z or 0) - (nmap.z or 0)
        local dist_sq = dx * dx + dy * dy + dz * dz
        if dist_sq <= (POSITION_MATCH_TOLERANCE * POSITION_MATCH_TOLERANCE) then
            return nmap.key
        end
    end
    return nil
end

local function build_av_nodes()
    local out = {}
    local src = ((bg_constants or {}).ALTERAC_VALLEY or {}).NODES or {}

    -- Primary source: iterate extracted bg_constants data.
    -- Match each entry's position to a logical node key via proximity.
    for _, entry in ipairs(src) do
        if entry.x and entry.y and entry.z then
            local key = match_position_to_key(entry.x, entry.y, entry.z)
            if key and not out[key] then
                out[key] = {
                    name = AV_NODE_NAME[key] or entry.name or key,
                    pos  = { x = entry.x, y = entry.y, z = entry.z },
                }
            end
        end
    end

    -- Fallback: fill any keyed positions still missing from NODE_POSITION_MAP.
    for _, nmap in ipairs(NODE_POSITION_MAP) do
        if nmap.key and not out[nmap.key] and nmap.x and nmap.y and nmap.z then
            out[nmap.key] = {
                name = AV_NODE_NAME[nmap.key] or nmap.key,
                pos  = { x = nmap.x, y = nmap.y, z = nmap.z },
            }
        end
    end

    -- Last-resort fallback: constants.AV_POSITIONS for key GYs.
    local fb = constants.AV_POSITIONS
    if fb then
        local fallback_map = {
            stormpike_gy = fb.stormpike_gy,
            frostwolf_gy = fb.frostwolf_gy,
            snowfall_gy  = fb.snowfall_gy,
        }
        for key, pos in pairs(fallback_map) do
            if not out[key] and pos and pos.x and pos.y and pos.z then
                out[key] = {
                    name = AV_NODE_NAME[key] or key,
                    pos  = { x = pos.x, y = pos.y, z = pos.z },
                }
            end
        end
    end

    return out
end

local AV_NODES = build_av_nodes()

----------------------------------------------------------------------
-- BG Detection
----------------------------------------------------------------------

---@param map_id number|nil  current map ID from core.get_map_id()
---@return boolean
function av_module:is_active(map_id)
    for _, id in ipairs(self.map_ids) do
        if map_id == id then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Ownership heuristic (visual banners near nodes)
----------------------------------------------------------------------

--- Infer node ownership from nearby banner objects.
---@param world_model WorldModel
---@param node_pos table {x,y,z}
---@param self_faction number  constants.FACTION.HORDE or ALLIANCE
---@return number  OWNER_* enum
---@return number  confidence 0.0-1.0
local function infer_node_ownership(world_model, node_pos, self_faction)
    local best_owner = OWNER_UNKNOWN
    local best_dist  = NODE_SCAN_RADIUS + 1

    for _, ent in pairs(world_model:get_all_entities()) do
        if ent.position and ent.npc_id then
            local dist = utils.distance_3d(node_pos, ent.position)
            if dist <= NODE_SCAN_RADIUS then
                -- Neutral banner (Snowfall)
                if BANNER_IDS.neutral[ent.npc_id] then
                    if dist < best_dist then
                        best_owner = OWNER_NEUTRAL
                        best_dist  = dist
                    end
                end

                -- Contested banner
                if BANNER_IDS.contested[ent.npc_id] then
                    if dist < best_dist then
                        best_owner = OWNER_CONTESTED
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

local function resolve_node_ownership(node_key, world_model, node_pos, self_faction)
    local observed_owner, observed_confidence = infer_node_ownership(world_model, node_pos, self_faction)
    local now = now_secs()

    local state = ownership_state[node_key]
    if not state then
        state = {
            owner = OWNER_UNKNOWN,
            confidence = 0,
            candidate_owner = OWNER_UNKNOWN,
            candidate_since = now,
            last_seen = now,
        }
        ownership_state[node_key] = state
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

local function write_av_runtime_targets(world_model, target_key, target_pos, av_mode, turtle_factor)
    local bg = world_model:get_bg_state()
    if not bg or bg.bg_type ~= "av" then
        return
    end

    bg.av_target_node_key = target_key or ""
    bg.av_target_node_pos = copy_pos(target_pos)
    bg.av_mode            = av_mode or "rush"
    bg.av_turtle_factor   = turtle_factor or 0

    world_model:update_bg_state(bg)
end

----------------------------------------------------------------------
-- Herd center-of-mass (replicates follow_herd CoM concept)
----------------------------------------------------------------------

--- Compute center-of-mass of nearby allies.
---@param world_model WorldModel
---@param self_pos table|nil {x,y,z}
---@return table|nil {x,y,z}
---@return number ally_count
local function compute_herd_center(world_model, self_pos)
    local allies = world_model:get_allies()
    local sum_x, sum_y, sum_z = 0, 0, 0
    local count = 0

    for _, ally in ipairs(allies) do
        if ally.position and ally.position.x then
            local keep = true
            if self_pos and self_pos.x then
                keep = utils.distance_3d(self_pos, ally.position) <= HERD_NEARBY_RADIUS
            end
            if keep then
                sum_x = sum_x + ally.position.x
                sum_y = sum_y + ally.position.y
                sum_z = sum_z + ally.position.z
                count = count + 1
            end
        end
    end

    if count < HERD_MIN_ALLIES then
        return nil, count
    end

    return {
        x = sum_x / count,
        y = sum_y / count,
        z = sum_z / count,
    }, count
end

----------------------------------------------------------------------
-- Turtle pressure factor
----------------------------------------------------------------------

--- Compute turtle pressure factor based on herd center proximity to own
--- defensive chokepoints. 0.0 = rush posture, 1.0 = full turtle posture.
---@param world_model WorldModel
---@param self_state table
---@return number turtle_factor
---@return string|nil closest_choke_key (debug info)
local function compute_turtle_factor(world_model, self_state)
    local self_faction = self_state.faction or constants.FACTION.UNKNOWN
    local self_pos = self_state.position

    local herd_center = compute_herd_center(world_model, self_pos)
    if not herd_center then
        return 0.0, nil
    end

    local chokes = DEFENSIVE_CHOKEPOINTS[self_faction]
    if not chokes then
        return 0.0, nil
    end

    local best_dist = nil
    local best_index = nil
    for i, choke in ipairs(chokes) do
        local dist = utils.distance_3d(herd_center, choke)
        if not best_dist or dist < best_dist then
            best_dist = dist
            best_index = i
        end
    end

    if not best_dist then
        return 0.0, nil
    end

    local factor
    if best_dist <= TURTLE_FULL_RADIUS then
        factor = 1.0
    elseif best_dist >= TURTLE_FADE_RADIUS then
        factor = 0.0
    else
        local span = max(1.0, TURTLE_FADE_RADIUS - TURTLE_FULL_RADIUS)
        factor = 1.0 - ((best_dist - TURTLE_FULL_RADIUS) / span)
    end

    factor = min(1.0, max(0.0, factor))
    return factor, (best_index and ("choke_" .. tostring(best_index)) or nil)
end

----------------------------------------------------------------------
-- Bunker assault scoring helper
----------------------------------------------------------------------

--- Score bonus for assaulting enemy bunkers/towers.
--- Rogues (class 4) and Druids (class 11) get a large priority multiplier,
--- but only when the player is within BUNKER_ASSAULT_RANGE of the objective.
---@param self_state table
---@param node_key string
---@param node_pos table {x,y,z}
---@param owner number OWNER_* enum
---@param enemy_defenders_near number
---@return number multiplier  (1.0 normal, 2.0 for stealth or undefended assault windows)
local function bunker_assault_multiplier(self_state, node_key, node_pos, owner, enemy_defenders_near)
    -- Only applies to enemy-owned bunker nodes.
    if not BUNKER_NODES[node_key] then
        return 1.0
    end
    if owner ~= OWNER_THEIRS and owner ~= OWNER_CONTESTED then
        return 1.0
    end

    -- Proximity gate: player must be within range of the bunker.
    local self_pos = self_state.position
    if not self_pos or not node_pos then
        return 1.0
    end
    local dist_to_bunker = utils.distance_3d(self_pos, node_pos)
    if dist_to_bunker > BUNKER_ASSAULT_RANGE then
        return 1.0
    end

    if (enemy_defenders_near or 0) <= 0 then
        return 2.0
    end

    local class_id = self_state.class_id or 0
    if class_id == constants.CLASS.ROGUE or class_id == constants.CLASS.DRUID then
        return 2.0
    end

    return 1.0
end

----------------------------------------------------------------------
-- Node weight evaluation
----------------------------------------------------------------------

--- Evaluate weights for all AV nodes and determine the best target.
---@param world_model WorldModel
---@param self_state table
---@param turtle_factor number
---@return string|nil best_node_key
---@return number best_weight
---@return table info { owned, contested, theirs, neutral }
function av_module:evaluate_node_weights(world_model, self_state, turtle_factor)
    local turtle = max(0.0, min(1.0, turtle_factor or 0.0))
    local self_faction = self_state.faction or constants.FACTION.UNKNOWN
    local self_pos = self_state.position

    local owned_count     = 0
    local contested_count = 0
    local theirs_count    = 0
    local neutral_count   = 0
    local best_key        = nil
    local best_weight     = -1

    -- Determine which nodes initially belong to the enemy faction.
    local enemy_faction = (self_faction == constants.FACTION.ALLIANCE)
        and constants.FACTION.HORDE
        or constants.FACTION.ALLIANCE
    local enemy_initial = FACTION_NODE_INITIAL[enemy_faction] or {}

    for key, node in pairs(AV_NODES) do
        local owner, confidence = resolve_node_ownership(key, world_model, node.pos, self_faction)

        if owner == OWNER_OURS then
            owned_count = owned_count + 1
        elseif owner == OWNER_CONTESTED then
            contested_count = contested_count + 1
        elseif owner == OWNER_THEIRS then
            theirs_count = theirs_count + 1
        elseif owner == OWNER_NEUTRAL then
            neutral_count = neutral_count + 1
        end

        -- Only consider capturing non-owned nodes.
        if owner ~= OWNER_OURS then
            local friends, foes = count_nearby_players(world_model, node.pos, NODE_SCAN_RADIUS)
            local ratio = friends / (foes + 1)
            local dist  = self_pos and utils.distance_3d(self_pos, node.pos) or 500
            -- AV is much larger than AB/EotS; use wider distance scaling.
            local dist_mod = max(0.2, 1.0 - (dist / 800))
            local weight = ratio * dist_mod

            -- Contested nodes get urgency bonus.
            if owner == OWNER_CONTESTED then
                weight = weight * 1.25
            end

            -- Neutral nodes (Snowfall) get a slight bonus.
            if owner == OWNER_NEUTRAL then
                weight = weight * 1.15
            end

            -- Low-confidence unknown nodes: reduce weight.
            if owner == OWNER_UNKNOWN and confidence < 0.3 then
                weight = weight * 0.6
            end

            -- Rush mode preference scales down smoothly as turtle pressure rises.
            if enemy_initial[key] then
                weight = weight * (1.0 + ((1.0 - turtle) * 0.5))
            end

            -- Turtle mode preference scales up smoothly on own-side contested nodes.
            if owner == OWNER_CONTESTED and not enemy_initial[key] then
                weight = weight * (1.0 + (turtle * 0.8))
            end

            -- Bunker assault: class-based + proximity-gated priority for stealth classes.
            local assault_mult = bunker_assault_multiplier(self_state, key, node.pos, owner, foes)
            weight = weight * assault_mult

            if weight > best_weight then
                best_weight = weight
                best_key    = key
            end
        end
    end

    return best_key, best_weight, {
        owned     = owned_count,
        contested = contested_count,
        theirs    = theirs_count,
        neutral   = neutral_count,
    }
end

----------------------------------------------------------------------
-- Score Intents  (BgModule interface)
----------------------------------------------------------------------

---@param world_model WorldModel
---@param intent_registry table { [intent_id] = Intent }
---@return table { [intent_id] = score }
function av_module:score_intents(world_model, intent_registry)
    local scores = {}
    local self_state = world_model:get_self()
    local bg = world_model:get_bg_state()

    -- Baseline fallback.
    scores.roam = 20

    if not self_state or not self_state.position or not bg or bg.bg_type ~= "av" then
        return scores
    end

    local self_pos = self_state.position
    local low_hp = (self_state.health_pct or 100)
        <= (config.combat.retreat_hp_pct or constants.COMBAT.RETREAT_HEALTH_PCT)

    -- Turtle pressure factor (0.0 rush .. 1.0 turtle).
    local turtle_factor, choke_key = compute_turtle_factor(world_model, self_state)
    local av_mode = "rush"
    if turtle_factor >= 0.66 then
        av_mode = "turtle"
    elseif turtle_factor >= 0.33 then
        av_mode = "balanced"
    end

    -- Evaluate node weights (turtle factor influences weighting).
    local target_key, target_weight, info =
        self:evaluate_node_weights(world_model, self_state, turtle_factor)

    ----------------------------------------------------------------
    -- Roam scoring
    ----------------------------------------------------------------
    if target_key and intent_registry.roam then
        local base_score = 40 + (target_weight * 15)

        -- Smoothly reduce push score as turtle pressure increases.
        base_score = base_score * (1.0 - (0.5 * turtle_factor))

        scores.roam = max(scores.roam, base_score)
    end

    ----------------------------------------------------------------
    -- Fight scoring
    ----------------------------------------------------------------
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
            local fight_score = 42 + max(0, enemies_near * 8)
            -- Smoothly boost fight/defend score as turtle pressure increases.
            fight_score = fight_score * (1.0 + (0.3 * turtle_factor))
            scores.fight = fight_score
        end
    end

    ----------------------------------------------------------------
    -- Retreat scoring
    ----------------------------------------------------------------
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

    ----------------------------------------------------------------
    -- Runtime target export
    ----------------------------------------------------------------
    local target_pos = nil
    if target_key and AV_NODES[target_key] then
        target_pos = AV_NODES[target_key].pos
    end
    write_av_runtime_targets(world_model, target_key, target_pos, av_mode, turtle_factor)

    return scores
end

return av_module
