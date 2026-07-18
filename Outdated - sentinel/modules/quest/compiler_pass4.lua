-- sentinel/modules/quest/compiler_pass4.lua
-- Compiler Pass 4: Backend Emit (JSON)
-- Converts the resolved/compiled AST (post passes 1-3) into the final
-- StatechartExecutor-compatible profile.
--
-- Profile shape (consumed by statechart_executor.lua):
--   schemaVersion : string
--   metadata      : { projectName, generatedAt, source }
--   variables     : map name -> { type, init, bind }
--   regions       : map regionName -> { initial = stateId }
--   states        : map stateId -> { id, type, parent, region, onEnter, transitions, guard?, _debug? }
--   routingPolicies : map id -> policy table
--   _debug        : source-mapping info for traceability
--
-- Each operation becomes a region; each action becomes an atomic state whose
-- onEnter runs a `core` action descriptor. Actions chain via "advance"
-- transitions into the region's final state. `guard` expressions are stored
-- as serializable strings; bindGuards() converts the simple ones to closures.

local JSON = require("lib/JSON")

local CompilerPass4 = {}
CompilerPass4.__index = CompilerPass4

function CompilerPass4.new(opts)
  return setmetatable({ _opts = opts or {} }, CompilerPass4)
end

--- Run the Level 4 pass: emit the final profile.
--- @param ast table AST after pass 3
--- @return table {ok=true, profile=table, errors={}}
function CompilerPass4:run(ast)
  local profile = {
    schemaVersion = "1.0.0",
    metadata = {
      projectName = (ast.project and ast.project.name) or "unnamed",
      generatedAt = self._opts.generatedAt or 0,
      source = "sentinel-quest-authoring",
    },
    variables = {},
    regions = {},
    states = {},
    routingPolicies = {},
    _debug = { states = {}, operations = {}, blueprints = {} },
  }

  -- Project-scope variables.
  if ast.project and ast.project.variables then
    for name, v in pairs(ast.project.variables) do
      profile.variables[name] = self:_var_def(v)
    end
  end

  -- Operations -> regions + state chains.
  for op_name, op in pairs(ast.operations) do
    self:_emit_operation(profile, op_name, op)
  end

  -- Record surviving blueprints (their expansions are already inline in actions).
  for bp_name, _ in pairs(ast.blueprints or {}) do
    profile._debug.blueprints[bp_name] = true
  end

  return { ok = true, profile = profile, errors = {} }
end

--- Serialize the emitted profile to JSON (functions stripped; guards are strings).
function CompilerPass4:toJSON(result)
  local ok, str, err = pcall(function()
    return JSON.encode(result.profile)
  end)
  if not ok then
    return nil, tostring(str)
  end
  if str == "" and err then
    return nil, tostring(err)
  end
  return str
end

--- Convert literal `guard` expressions into `guard_fn` closures so the profile
--- is directly runnable by StatechartExecutor. Non-literal guards are left as
--- strings for a hardened runtime binder to process; the executor treats a nil
--- guard as "always pass".
function CompilerPass4.bindGuards(profile)
  for _, state in pairs(profile.states) do
    local transitions = state.transitions or {}
    for _, transList in pairs(transitions) do
      for _, trans in ipairs(transList) do
        if trans.guard and not trans.guard_fn then
          local g = trans.guard
          if g == "true" then
            trans.guard_fn = function() return true end
          elseif g == "false" then
            trans.guard_fn = function() return false end
          else
            trans.guard_fn = nil -- deferred to a hardened runtime binder
          end
        end
      end
    end
  end
  return profile
end

-- Internal helpers -----------------------------------------------------------

function CompilerPass4:_var_def(v)
  return {
    type = v.type,
    init = v.default,
    bind = v.bind,
  }
end

function CompilerPass4:_emit_operation(profile, op_name, op)
  local region_name = "op:" .. op_name
  local actions = op.actions or {}

  profile.regions[region_name] = { initial = nil }
  profile._debug.operations[op_name] = {
    region = region_name,
    actionCount = #actions,
  }

  if #actions == 0 then
    -- Empty operation collapses to a single final state.
    local final_id = region_name .. "#final"
    profile.states[final_id] = {
      id = final_id,
      type = "final",
      parent = nil,
      region = region_name,
      onEnter = {},
      transitions = {},
    }
    profile.regions[region_name].initial = final_id
    return
  end

  local prev_state_id = nil
  for i, action in ipairs(actions) do
    local state_id = region_name .. "#" .. i
    local core_action = {
      type = "core",
      name = action.action_type or action.type,
      args = action.args or {},
    }

    -- Routing policy reference, if the action supplies one.
    if action.args and action.args.routing_policy then
      local rp = action.args.routing_policy
      local rp_id = type(rp) == "string" and rp or (rp.id or (region_name .. "#rp" .. i))
      profile.routingPolicies[rp_id] = rp
      core_action.routingPolicy = rp_id
    end

    local state = {
      id = state_id,
      type = "atomic",
      parent = nil,
      region = region_name,
      onEnter = { core_action },
      transitions = {},
      _debug = {
        operation = op_name,
        actionIndex = i,
        actionType = action.action_type or action.type,
        generated_by = (action._debug and action._debug.generated_by) or "author",
      },
    }

    if action.condition then
      state.guard = action.condition
    end

    profile.states[state_id] = state
    profile._debug.states[state_id] = state._debug

    -- Chain previous action state -> this one on "advance".
    if prev_state_id then
      profile.states[prev_state_id].transitions["advance"] = {
        {
          target = state_id,
          guard = state.guard,
          guard_fn = nil,
          actions = {},
        },
      }
    end
    prev_state_id = state_id
  end

  -- Last action transitions into the region final state.
  local final_id = region_name .. "#final"
  profile.states[final_id] = {
    id = final_id,
    type = "final",
    parent = nil,
    region = region_name,
    onEnter = {},
    transitions = {},
  }
  if prev_state_id then
    profile.states[prev_state_id].transitions["advance"] = {
      {
        target = final_id,
        guard = nil,
        guard_fn = nil,
        actions = {},
      },
    }
  end

  profile.regions[region_name].initial = region_name .. "#1"
end

return CompilerPass4
