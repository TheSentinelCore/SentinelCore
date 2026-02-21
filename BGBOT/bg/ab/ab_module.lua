---@module BGBOT.bg.ab.ab_module
-- Arathi Basin BG Module: implements BgModule interface.
-- Node-based scoring with ownership heuristics and 3-node hold policy.

local constants    = require("shared/constants")
local bg_constants = require("shared/bg_constants")
local config       = require("shared/config")
local utils        = require("shared/utils")

local ab_module = {}
ab_module.__index = ab_module

local max = math.max

----------------------------------------------------------------------
-- BgModule interface fields
----------------------------------------------------------------------

ab_module.id = "ab"
ab_module.map_ids = constants.AB_MAP_IDS

----------------------------------------------------------------------
-- AB node definitions (keyed by logical name)
----------------------------------------------------------------------

local AB_NODE_NAME = {
    stable     = "Stable",
    blacksmith = "Blacksmith",
    farm       = "Farm",
    lumber     = "Lumber Mill",
    mine       = "Mine",
}

-- Banner NPC IDs used for heuristic ownership detection.
local BANNER_IDS = {
    alliance  = { [180058] = true },
    horde     = { [180060] = true },
    contested = { [180061] = true, [180059] = true },
}

-- Named banner NPC → node key mapping.
local NAMED_BANNER_NODE = {
    [180087] = "stable",
    [180088] = "blacksmith",
    [180089] = "farm",
    [180090] = "lumber",
    [180091] = "mine",
}

-- Build AB nodes by iterating extracted constants.ARATHI_BASIN.NODES first.
-- Fallback to constants.AB_POSITIONS only if a node is missing from extracted data.
local function build_ab_nodes()
    local out = {}
    local src = ((bg_constants or {}).ARATHI_BASIN or {}).NODES or {}

    for _, entry in ipairs(src) do
        local id = tonumber(entry.id) or 0
        local key = NAMED_BANNER_NODE[id]
        if key and entry.x and entry.y and entry.z then
            out[key] = {
                name = AB_NODE_NAME[key] or key,
                pos = { x = entry.x, y = entry.y, z = entry.z },
            }
        end
    end

    local fallback = {
        stable     = constants.AB_POSITIONS and constants.AB_POSITIONS.stable,
        blacksmith = constants.AB_POSITIONS and constants.AB_POSITIONS.blacksmith,
        farm       = constants.AB_POSITIONS and constants.AB_POSITIONS.farm,
        lumber     = constants.AB_POSITIONS and constants.AB_POSITIONS.lumber,
        mine       = constants.AB_POSITIONS and constants.AB_POSITIONS.mine,
    }

    for key, pos in pairs(fallback) do
        if not out[key] and pos and pos.x and pos.y and pos.z then
            out[key] = {
                name = AB_NODE_NAME[key] or key,
                pos = { x = pos.x, y = pos.y, z = pos.z },
            }
        end
    end

    return out
end

local AB_NODES = build_ab_nodes()

-- Radius around a node position for nearby banner/entity scans.
local NODE_SCAN_RADIUS = 25

----------------------------------------------------------------------
-- BG Detection
----------------------------------------------------------------------

---@param map_id number|nil  current map ID from core.get_map_id()
---@return boolean
function ab_module:is_active(map_id)
    for _, id in ipairs(self.map_ids) do
        if map_id == id then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Ownership heuristic
----------------------------------------------------------------------

-- Ownership enum for internal scoring.
local OWNER_UNKNOWN  = 0
local OWNER_OURS     = 1
local OWNER_THEIRS   = 2
local OWNER_CONTESTED = 3

local OWNERSHIP_MIN_CONFIDENCE = 0.35
local OWNERSHIP_STABLE_WINDOW = 2.0
local OWNERSHIP_HOLD_SECS = 3.0
local ownership_state = {} -- { [node_key] = { owner, confidence, candidate_owner, candidate_since, last_seen } }

--- Infer node ownership from nearby banner objects in the world model.
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
                -- Check contested first (lower priority banner state)
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

    -- Confidence is inversely proportional to distance; unknown is low.
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

    -- Unknown observations fall back safely: hold last owner briefly, then decay to unknown.
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
-- Node weight evaluation
----------------------------------------------------------------------

--- Count friendlies and enemies near a position.
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

local function copy_pos(pos)
    if not pos or pos.x == nil or pos.y == nil or pos.z == nil then
        return nil
    end
    return { x = pos.x, y = pos.y, z = pos.z }
end

local function find_enemy_capping_near_node(world_model, node_pos)
    local best_ent = nil
    local best_node_dist = 999999

    for _, ent in pairs(world_model:get_all_entities()) do
        if ent.is_player and ent.is_enemy and not ent.is_dead and ent.position then
            local node_dist = utils.distance_3d(node_pos, ent.position)
            if node_dist <= 15 then
                if node_dist < best_node_dist then
                    best_ent = ent
                    best_node_dist = node_dist
                end
            end
        end
    end

    return best_ent
end

local function write_ab_runtime_targets(world_model, target_key, target_pos, spin_meta)
    local bg = world_model:get_bg_state()
    if not bg or bg.bg_type ~= "ab" then
        return
    end

    bg.ab_target_node_key = target_key or ""
    bg.ab_target_node_pos = copy_pos(target_pos)
    bg.ab_spin_target_handle = spin_meta and spin_meta.enemy_handle or nil
    bg.ab_spin_target_pos = spin_meta and copy_pos(spin_meta.enemy_pos) or nil
    bg.ab_spin_node_pos = spin_meta and copy_pos(spin_meta.node_pos) or nil
    bg.ab_spin_node_key = spin_meta and (spin_meta.node_key or "") or ""

    world_model:update_bg_state(bg)
end

--- Evaluate weights for all AB nodes and return the best attack target.
---@param world_model WorldModel
---@param self_state table  world model self record
---@return string|nil best_node_key
---@return number best_weight
---@return table node_info  { owned=number, contested=number, theirs=number }
function ab_module:evaluate_node_weights(world_model, self_state)
    local self_faction = self_state.faction or constants.FACTION.UNKNOWN
    local self_pos = self_state.position

    local owned_count    = 0
    local contested_count = 0
    local theirs_count   = 0
    local best_key       = nil
    local best_weight    = -1

    for key, node in pairs(AB_NODES) do
        local owner, confidence = resolve_node_ownership(key, world_model, node.pos, self_faction)

        if owner == OWNER_OURS then
            owned_count = owned_count + 1
        elseif owner == OWNER_CONTESTED then
            contested_count = contested_count + 1
        elseif owner == OWNER_THEIRS then
            theirs_count = theirs_count + 1
        end

        -- Only consider attacking unowned (contested/theirs/unknown) nodes.
        if owner ~= OWNER_OURS then
            local friends, foes = count_nearby_players(world_model, node.pos, NODE_SCAN_RADIUS)
            -- Attack ratio per Stage 2 spec: Friendlies / (Enemies + 1).
            local ratio = friends / (foes + 1)
            local dist  = self_pos and utils.distance_3d(self_pos, node.pos) or 200
            -- Distance modifier: slightly prefer closer uncapped nodes.
            local dist_mod = max(0.3, 1.0 - (dist / 400))
            local weight = ratio * dist_mod

            -- Contested nodes get a slight urgency bonus.
            if owner == OWNER_CONTESTED then
                weight = weight * 1.25
            end

            -- Low-confidence unknown nodes get reduced weight (avoid blind dives).
            if owner == OWNER_UNKNOWN and confidence < 0.3 then
                weight = weight * 0.6
            end

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
    }
end

----------------------------------------------------------------------
-- Score Intents  (BgModule interface)
----------------------------------------------------------------------

---@param world_model WorldModel
---@param intent_registry table { [intent_id] = Intent }
---@return table { [intent_id] = score }
function ab_module:score_intents(world_model, intent_registry)
    local scores = {}
    local self_state = world_model:get_self()
    local bg = world_model:get_bg_state()

    -- Baseline fallback.
    scores.roam = 20

    if not self_state or not self_state.position or not bg or bg.bg_type ~= "ab" then
        return scores
    end

    local self_pos = self_state.position
    local low_hp = (self_state.health_pct or 100)
        <= (config.combat.retreat_hp_pct or constants.COMBAT.RETREAT_HEALTH_PCT)

    -- Evaluate node weights.
    local target_key, target_weight, info = self:evaluate_node_weights(world_model, self_state)

    -- 3-node hold policy: if we own >= 3 nodes, significantly deprioritize expansion.
    local expansion_multiplier = 1.0
    if info.owned >= 3 then
        expansion_multiplier = 0.35  -- strongly reduce urge to push 4th/5th node
    end

    -- Roam toward best attack target.
    if target_key and intent_registry.roam then
        local base_score = 40 + (target_weight * 15)
        scores.roam = max(scores.roam, base_score * expansion_multiplier)
    end

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

    -- Spin flag: emergency preempt when enemy is capping a friendly node.
    local spin_meta = nil
    if intent_registry.spin_flag then
        local spin_score, meta = self:_score_spin_flag(world_model, self_state)
        if spin_score > 0 then
            scores.spin_flag = spin_score
            spin_meta = meta
        end
    end

    local target_pos = nil
    if target_key and AB_NODES[target_key] then
        target_pos = AB_NODES[target_key].pos
    end
    write_ab_runtime_targets(world_model, target_key, target_pos, spin_meta)

    return scores
end

----------------------------------------------------------------------
-- Spin-flag scoring helper
----------------------------------------------------------------------

--- Check if an enemy appears to be capping one of our nodes within 30 yards.
---@param world_model WorldModel
---@param self_state table
---@return number score (0 if no emergency)
function ab_module:_score_spin_flag(world_model, self_state)
    local self_pos = self_state.position
    local self_faction = self_state.faction or constants.FACTION.UNKNOWN

    for key, node in pairs(AB_NODES) do
        local owner = select(1, resolve_node_ownership(key, world_model, node.pos, self_faction))
        if owner == OWNER_OURS then
            -- Check if enemies are near this friendly node (within 30 yards).
            local dist_to_node = utils.distance_3d(self_pos, node.pos)
            if dist_to_node <= 30 then
                local enemy = find_enemy_capping_near_node(world_model, node.pos)
                if enemy and enemy.position then
                    -- Emergency score: beats most other intents.
                    return 100, {
                        node_key = key,
                        node_pos = copy_pos(node.pos),
                        enemy_handle = enemy.handle,
                        enemy_pos = copy_pos(enemy.position),
                    }
                end
            end
        end
    end
    return 0, nil
end

return ab_module
