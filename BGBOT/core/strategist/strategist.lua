---@module BGBOT.core.strategist.strategist
-- Strategist: scores all possible intents and recommends the best one.
-- BG-module scoring is delegated when a module is active.
-- Global intents (follow_herd, grab_bg_buff, failsafe) are scored unconditionally.

local FollowHerd  = require("core/intent/intents/follow_herd")
local GrabBgBuff  = require("core/intent/intents/grab_bg_buff")
local Failsafe    = require("core/intent/intents/failsafe")
local constants   = require("shared/constants")
local utils       = require("shared/utils")

local strategist = {}
strategist.__index = strategist

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------

---@param intent_registry table { [intent_id] = intent_instance }
function strategist.new(intent_registry)
    local self = setmetatable({}, strategist)
    self.intent_registry = intent_registry or {}
    self.bg_module       = nil    -- set via set_bg_module()
    self.intent_blacklist = {}    -- { [intent_id] = { until_at, reason } }
    self.last_role_assignment = {
        role = "attack",
        lane = "frontline",
        overcommit = false,
    }
    return self
end

----------------------------------------------------------------------
-- Set BG-specific module (WSG, AB, etc.)
----------------------------------------------------------------------

---@param module BgModule
function strategist:set_bg_module(module)
    self.bg_module = module
end

local function get_now()
    if core and core.time then
        return core.time()
    end
    return 0
end

local function prune_blacklist(self, now)
    for intent_id, entry in pairs(self.intent_blacklist) do
        if not entry or (tonumber(entry.until_at) or 0) <= now then
            self.intent_blacklist[intent_id] = nil
        end
    end
end

---Temporarily block an intent from being selected.
---@param intent_id string
---@param duration_secs number
---@param reason string|nil
function strategist:blacklist_intent(intent_id, duration_secs, reason)
    local id = tostring(intent_id or "")
    if id == "" then
        return
    end

    local now = get_now()
    local duration = tonumber(duration_secs) or 20.0
    if duration < 0 then
        duration = 0
    end
    local until_at = now + duration

    local current = self.intent_blacklist[id]
    if current and (tonumber(current.until_at) or 0) > until_at then
        return
    end

    self.intent_blacklist[id] = {
        until_at = until_at,
        reason = tostring(reason or "temporary_unavailable"),
    }
end

---@param intent_id string
---@return boolean, number
function strategist:is_intent_blacklisted(intent_id)
    local id = tostring(intent_id or "")
    local entry = self.intent_blacklist[id]
    if not entry then
        return false, 0
    end

    local now = get_now()
    local until_at = tonumber(entry.until_at) or 0
    if until_at <= now then
        self.intent_blacklist[id] = nil
        return false, 0
    end

    return true, until_at
end

local function count_nearby_allies(world_model, self_pos, radius)
    if not world_model or not world_model.get_allies or not self_pos then
        return 0
    end
    local allies = world_model:get_allies() or {}
    local count = 0
    for _, ally in ipairs(allies) do
        if ally.position and utils.distance_3d(self_pos, ally.position) <= radius then
            count = count + 1
        end
    end
    return count
end

local function compute_role_assignment(world_model)
    local self_state = world_model and world_model.get_self and world_model:get_self() or nil
    local bg = world_model and world_model.get_bg_state and world_model:get_bg_state() or nil

    local role = "attack"
    local lane = "frontline"
    local overcommit = false

    if bg and bg.bg_type == "wsg" then
        if bg.their_flag_carrier then
            role = "intercept"
            lane = "carrier_hunt"
        elseif bg.our_flag_carrier and not (self_state and self_state.has_flag) then
            role = "escort"
            lane = "carrier_escort"
        elseif bg.our_flag_state == "carried" then
            role = "defend"
            lane = "home_defense"
        end
    end

    if self_state and self_state.position then
        local nearby_allies = count_nearby_allies(world_model, self_state.position, 35)
        if nearby_allies >= 6 then
            overcommit = true
            if role == "attack" then
                role = "defend"
                lane = "spread_defense"
            end
        end
    end

    return {
        role = role,
        lane = lane,
        overcommit = overcommit,
    }
end

local function add_or_seed_score(scores, registry, intent_id, amount)
    if not registry[intent_id] then
        return
    end
    scores[intent_id] = (scores[intent_id] or 0) + amount
end

local function scale_score(scores, intent_id, factor)
    if scores[intent_id] then
        scores[intent_id] = scores[intent_id] * factor
    end
end

local function apply_role_adjustments(scores, registry, assignment)
    local role = assignment and assignment.role or "attack"
    local overcommit = assignment and assignment.overcommit == true or false

    if role == "escort" then
        add_or_seed_score(scores, registry, "escort_carrier", 25)
        scale_score(scores, "roam", 0.85)
        scale_score(scores, "fight", 1.1)
    elseif role == "intercept" then
        add_or_seed_score(scores, registry, "intercept_carrier", 25)
        add_or_seed_score(scores, registry, "return_flag", 12)
        scale_score(scores, "fight", 1.2)
    elseif role == "defend" then
        add_or_seed_score(scores, registry, "return_flag", 15)
        add_or_seed_score(scores, registry, "spin_flag", 20)
        scale_score(scores, "carry_flag", 0.6)
        scale_score(scores, "roam", 0.9)
    else
        add_or_seed_score(scores, registry, "carry_flag", 12)
        scale_score(scores, "roam", 1.05)
    end

    if overcommit then
        scale_score(scores, "roam", 0.7)
        scale_score(scores, "fight", 0.75)
        add_or_seed_score(scores, registry, "intercept_carrier", 8)
        add_or_seed_score(scores, registry, "return_flag", 8)
    end
end

---Latest role allocation for telemetry/inspection.
---@return table
function strategist:get_role_assignment()
    return {
        role = self.last_role_assignment.role,
        lane = self.last_role_assignment.lane,
        overcommit = self.last_role_assignment.overcommit == true,
    }
end

----------------------------------------------------------------------
-- Evaluate: score all intents, return highest recommendation
----------------------------------------------------------------------

---@param world_model WorldModel
---@return table { intent_id, score, intent_instance }
function strategist:evaluate(world_model)
    local scores = {}
    local now = get_now()
    prune_blacklist(self, now)

    -- If we have a BG module, delegate scoring
    if self.bg_module and self.bg_module.score_intents then
        scores = self.bg_module:score_intents(world_model, self.intent_registry)
    end

    -- Ensure roam always has a baseline score
    if not scores.roam then
        scores.roam = 20
    end

    ----------------------------------------------------------------
    -- Global intents: scored even when bg_module is nil.
    -- Only apply if the intent is registered and score exceeds any
    -- existing value from the BG module.
    ----------------------------------------------------------------

    if self.intent_registry.follow_herd then
        local herd_score = FollowHerd.compute_score(world_model)
        if herd_score > (scores.follow_herd or 0) then
            scores.follow_herd = herd_score
        end
    end

    if self.intent_registry.grab_bg_buff then
        local buff_score = GrabBgBuff.compute_score(world_model)
        if buff_score > (scores.grab_bg_buff or 0) then
            scores.grab_bg_buff = buff_score
        end
    end

    if self.intent_registry.failsafe then
        local failsafe_score = Failsafe.compute_score(world_model)
        if failsafe_score > (scores.failsafe or 0) then
            scores.failsafe = failsafe_score
        end
    end

    local role_assignment = compute_role_assignment(world_model)
    self.last_role_assignment = role_assignment
    apply_role_adjustments(scores, self.intent_registry, role_assignment)

    for intent_id, score in pairs(scores) do
        if self.intent_registry[intent_id] then
            local blacklisted = select(1, self:is_intent_blacklisted(intent_id))
            if blacklisted then
                scores[intent_id] = -999
            else
                scores[intent_id] = score
            end
        end
    end

    -- Find highest scorer
    local best_id    = "roam"
    local best_score = scores.roam or 20

    for intent_id, score in pairs(scores) do
        if score > best_score and self.intent_registry[intent_id] then
            best_id    = intent_id
            best_score = score
        end
    end

    return {
        intent_id       = best_id,
        score           = best_score,
        intent_instance = self.intent_registry[best_id],
    }
end

return strategist
