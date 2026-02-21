---@module BGBOT.core.intent.controller
-- Intent Controller: gates intent switches to prevent thrashing.
-- M1 scaffold: simplified (holds active intent, no anti-thrash yet).
-- Anti-thrash policy (min-commit, margin, cooldown, emergency) wired in M2.

local constants = require("shared/constants")
local config    = require("shared/config")

local controller = {}
controller.__index = controller

local function intent_can_bypass_gates(current_intent, current_id, new_intent, new_id)
    if new_intent and type(new_intent.can_bypass_gates) == "function" then
        local ok, bypass = pcall(function()
            return new_intent:can_bypass_gates(current_id, current_intent)
        end)
        if ok and bypass == true then
            return true
        end
    end

    if current_intent and type(current_intent.is_interruptible) == "function" then
        local ok, interruptible = pcall(function()
            return current_intent:is_interruptible(new_id, new_intent)
        end)
        if ok and interruptible == true then
            return true
        end
    end

    return false
end

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------

function controller.new(default_intent)
    local self = setmetatable({}, controller)
    self.current_intent    = default_intent
    self.current_intent_id = default_intent and default_intent.id or "none"
    self.current_score     = 0
    self.switch_time       = 0
    self.commit_start      = 0
    self.cooldown_until    = 0
    self.emergency_pending = nil
    return self
end

----------------------------------------------------------------------
-- Process Strategist recommendation  (M1: simplified pass-through)
----------------------------------------------------------------------

---@param recommendation table { intent_id, score, intent_instance }
---@return Intent  the approved active intent
function controller:process(recommendation)
    if not recommendation then
        return self.current_intent
    end

    local now = core.time()

    -- Emergency overrides bypass all gates
    if self.emergency_pending then
        local emergency = self.emergency_pending
        self.emergency_pending = nil
        return self:do_switch(emergency.intent, emergency.score, now)
    end

    -- M2 will add: min-commit check, cooldown check, margin check
    -- For M1: just accept the recommendation if it has a higher score

    local new_id    = recommendation.intent_id
    local new_score = recommendation.score or 0
    local new_inst  = recommendation.intent_instance

    -- No switch if same intent
    if new_id == self.current_intent_id then
        self.current_score = new_score
        return self.current_intent
    end

    -- Gate 1: Min-commit duration
    local bypass_gates = intent_can_bypass_gates(
        self.current_intent,
        self.current_intent_id,
        new_inst,
        new_id
    )

    local min_commit = constants.MIN_COMMIT[self.current_intent_id] or 0
    if not bypass_gates and (now - self.commit_start) < min_commit then
        return self.current_intent
    end

    -- Gate 2: Switch cooldown
    if not bypass_gates and now < self.cooldown_until then
        return self.current_intent
    end

    -- Gate 3: Switch margin
    local margin = config.intent.switch_margin
    if not bypass_gates and new_score <= self.current_score * (1 + margin) then
        return self.current_intent
    end

    -- Passed all gates — switch
    return self:do_switch(new_inst or self.current_intent, new_score, now)
end

----------------------------------------------------------------------
-- Force an emergency intent switch (bypasses all gates)
----------------------------------------------------------------------

---@param intent Intent
---@param score number
function controller:force_emergency(intent, score)
    if not intent then
        return
    end

    local emergency_score = score or 999
    if self.current_intent == intent
        or (self.current_intent_id ~= nil and intent.id ~= nil and self.current_intent_id == intent.id) then
        if emergency_score > (self.current_score or 0) then
            self.current_score = emergency_score
        end
        return
    end

    self.emergency_pending = { intent = intent, score = emergency_score }
end

----------------------------------------------------------------------
-- Internal: Execute switch
----------------------------------------------------------------------

function controller:do_switch(new_intent, score, now)
    if not new_intent then
        return self.current_intent
    end

    if self.current_intent == new_intent
        or (self.current_intent_id ~= nil and new_intent.id ~= nil and self.current_intent_id == new_intent.id) then
        self.current_score = score or self.current_score
        return self.current_intent
    end

    -- Exit current
    if self.current_intent and self.current_intent.exit then
        self.current_intent:exit()
    end

    -- Set new
    self.current_intent    = new_intent
    self.current_intent_id = new_intent.id
    self.current_score     = score
    self.switch_time       = now
    self.commit_start      = now
    self.cooldown_until    = now + config.intent.switch_cooldown

    if config.debug.log_intent then
        core.log(string.format("[BGBOT][Intent] Switched to: %s (score=%.1f)", new_intent.id, score))
    end

    return new_intent
end

----------------------------------------------------------------------
-- Getters
----------------------------------------------------------------------

function controller:get_current()
    return self.current_intent
end

function controller:get_current_id()
    return self.current_intent_id
end

return controller
