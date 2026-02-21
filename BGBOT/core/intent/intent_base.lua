---@module BGBOT.core.intent.intent_base
-- Base intent interface.
-- All intents must implement this contract per INTENT_SYSTEM_SPEC.md.

local intent_base = {}
intent_base.__index = intent_base

----------------------------------------------------------------------
-- Constructor (subclasses call this via intent_base.create)
----------------------------------------------------------------------

---@param id string  intent identifier (e.g. "roam", "carry_flag")
---@return Intent
function intent_base.create(id)
    local self = setmetatable({}, intent_base)
    self.id         = id
    self._active    = false
    self._start_time = 0
    return self
end

----------------------------------------------------------------------
-- Lifecycle (override in subclasses as needed)
----------------------------------------------------------------------

--- Called once when this intent becomes active.
---@param world_model WorldModel
---@param params table|nil  optional parameters from Strategist
function intent_base:enter(world_model, params)
    self._active     = true
    self._start_time = core.time()
end

--- Called every frame while this intent is active.
---@param world_model WorldModel
---@return IntentOutput
function intent_base:tick(world_model)
    return {
        nav_goal        = nil,
        interact_target = nil,
        face_target     = nil,
    }
end

--- Called once when this intent is deactivated.
function intent_base:exit()
    self._active = false
end

--- Returns true when the intent has completed its goal.
---@return boolean
function intent_base:is_complete()
    return false
end

--- Returns current navigation target position (or nil).
---@return table|nil  {x,y,z}
function intent_base:get_nav_goal()
    return nil
end

--- Returns context for Combat Micro.
---@return IntentContext
function intent_base:get_context()
    return {
        engage_allowed       = false,
        max_chase_range      = 0,
        priority_target      = nil,
        disengage_requested  = false,
    }
end

--- Whether this active intent allows immediate interruption by the next intent.
---@param _next_intent_id string
---@param _next_intent Intent|nil
---@return boolean
function intent_base:is_interruptible(_next_intent_id, _next_intent)
    return false
end

--- Whether this candidate intent can bypass controller switch gates.
---@param _current_intent_id string
---@param _current_intent Intent|nil
---@return boolean
function intent_base:can_bypass_gates(_current_intent_id, _current_intent)
    return false
end

--- Time (seconds) this intent has been active.
---@return number
function intent_base:time_active()
    if not self._active then return 0 end
    return core.time() - self._start_time
end

return intent_base
