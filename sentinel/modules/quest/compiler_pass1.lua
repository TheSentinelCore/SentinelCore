-- sentinel/modules/quest/compiler_pass1.lua
-- Compiler Pass 1: DB Resolution and Validation
-- Resolves names to IDs using a mock database (for testing)
-- In the real implementation, this would use the QueryClient to talk to the Mangos database.

local JSON = require("sentinel.lib.JSON")
local SourceAST = require("sentinel.modules.quest.source_ast")

local CompilerPass1 = {}
CompilerPass1.__index = CompilerPass1

-- Structured error factory.
-- Errors are returned as tables {message, code, severity} by the process_* helpers
-- so the IDE validation pane (Ticket 013) can filter/group them. `run` flattens
-- them to strings for the public {ok, errors} contract.
local function make_error(message, code)
  return {
    message = message,
    code = code or "PASS1_ERROR",
    severity = "error",
  }
end

-- Mock database for testing
-- In reality, these would be populated from the Mangos database via QueryClient
local MockDB = {
  creatures = {
    -- [entry] = { name, zone_id, faction, level, rank, ... }
    [1234] = { name = "Guard Maxwell", zone_id = 1, faction = "Alliance", level = 12 },
    [5678] = { name = "Innkeeper Allison", zone_id = 1, faction = "Alliance", level = 35 },
  },
  items = {
    -- [entry] = { name, quality, level, ... }
    [9012] = { name = "Rugged Leather Pants", quality = 1, level = 1 },
    [3456] = { name = "Iron Buckler", quality = 1, level = 5 },
  },
  quests = {
    -- [entry] = { name, zone_id, level, minlevel, raceclassflags }
    [100] = { name = "Gold Dust Exchange", zone_id = 1, level = 5, minlevel = 5, raceclassflags = 1 }, -- Alliance only
    [101] = { name = "A Farmer's Fortune", zone_id = 1, level = 10, minlevel = 8, raceclassflags = 0 }, -- All races
  },
  gameobjects = {
    -- [entry] = { name, zone_id, ... }
    [1122] = { name = "Old Tree Stump", zone_id = 1 },
  },
}

-- Helper to find creature by name
local function find_creature_by_name(name)
  for entry, data in pairs(MockDB.creatures) do
    if data.name == name then
      return entry, data
    end
  end
  return nil
end

-- Helper to find item by name
local function find_item_by_name(name)
  for entry, data in pairs(MockDB.items) do
    if data.name == name then
      return entry, data
    end
  end
  return nil
end

-- Helper to find quest by name
local function find_quest_by_name(name)
  for entry, data in pairs(MockDB.quests) do
    if data.name == name then
      return entry, data
    end
  end
  return nil
end

-- Helper to find gameobject by name
local function find_gameobject_by_name(name)
  for entry, data in pairs(MockDB.gameobjects) do
    if data.name == name then
      return entry, data
    end
  end
  return nil
end

function CompilerPass1.new()
  return setmetatable({}, CompilerPass1)
end

--- Run the Level 1 pass on the AST
--- @param ast table The AST from the source parser (Program node)
--- @return table {ok=true, ast=AST, errors={}} or {ok=false, errors={string}}
function CompilerPass1:run(ast)
  local errors = {}

  -- Process each operation
  for op_name, op in pairs(ast.operations) do
    local op_errs = self:process_operation(op)
    for _, err in ipairs(op_errs) do
      local msg = type(err) == "table" and err.message or tostring(err)
      table.insert(errors, string.format("Operation '%s': %s", op_name, msg))
    end
  end

  -- Process each blueprint
  for bp_name, bp in pairs(ast.blueprints) do
    local bp_errs = self:process_blueprint(ast, bp)
    for _, err in ipairs(bp_errs) do
      local msg = type(err) == "table" and err.message or tostring(err)
      table.insert(errors, string.format("Blueprint '%s': %s", bp_name, msg))
    end
  end

  if #errors > 0 then
    return { ok = false, errors = errors }
  end

  return { ok = true, ast = ast, errors = {} }
end

--- Process an operation node, resolving names in its actions.
--- @param op table OperationAST node (or a raw table with an `actions` list)
--- @return table array of structured error tables (empty if valid)
function CompilerPass1:process_operation(op)
  local errors = {}

  if op == nil then
    return { make_error("process_operation called with a nil operation node", "NIL_OPERATION") }
  end

  -- Snapshot the actions list once. This is the critical fix: we never read
  -- `op.actions` again inside the loop, and we never reassign `op` or `op.actions`
  -- here, so the operations table cannot be "inadvertently modified during
  -- iteration" nor can a shared/aliased table nil out underneath us.
  local actions = op.actions
  if type(actions) ~= "table" then
    table.insert(errors, make_error(
      string.format("operation is missing a valid 'actions' list (got %s)", type(actions)),
      "STRUCT_ACTIONS"
    ))
    actions = {}
  end

  -- Index-based iteration over the snapshot. ipairs-style semantics, but robust
  -- to any accidental growth/shrink because we only read `actions[i]`.
  for i = 1, #actions do
    local action = actions[i]
    if action == nil then
      -- Sparse nil in the middle of the list: record and skip rather than crash.
      table.insert(errors, make_error(
        string.format("action at index %d is nil", i),
        "NIL_ACTION"
      ))
    else
      local action_errs = self:process_action(action)
      for _, err in ipairs(action_errs) do
        table.insert(errors, make_error(
          string.format("Action %d: %s", i, type(err) == "table" and err.message or tostring(err)),
          err.code or "ACTION_ERROR"
        ))
      end
    end
  end

  return errors
end

--- Process a blueprint node, resolving names in its expands_to actions.
--- @param ast table Program AST (for resolving BlueprintReference nodes)
--- @param bp table BlueprintAST node
--- @return table array of structured error tables
function CompilerPass1:process_blueprint(ast, bp)
  local errors = {}

  if bp == nil then
    return { make_error("process_blueprint called with a nil blueprint node", "NIL_BLUEPRINT") }
  end

  local items = bp.expands_to
  if type(items) ~= "table" then
    return { make_error(
      string.format("blueprint is missing a valid 'expands_to' list (got %s)", type(items)),
      "STRUCT_EXPANDS_TO"
    ) }
  end

  for i = 1, #items do
    local item = items[i]
    if item == nil then
      table.insert(errors, make_error(
        string.format("expands_to item at index %d is nil", i),
        "NIL_EXPAND_ITEM"
      ))
    elseif item.type == "Action" then
      local action_errs = self:process_action(item)
      for _, err in ipairs(action_errs) do
        table.insert(errors, make_error(
          string.format("ExpandsTo action %d: %s", i, type(err) == "table" and err.message or tostring(err)),
          err.code or "ACTION_ERROR"
        ))
      end
    elseif item.type == "BlueprintReference" then
      -- Resolve blueprint reference by name to a blueprint in the AST.
      local ref_name = item.blueprint_name
      if ast == nil or ast.blueprints == nil or not ast.blueprints[ref_name] then
        table.insert(errors, make_error(
          string.format("Undefined blueprint reference '%s'", tostring(ref_name)),
          "UNDEF_BLUEPRINT"
        ))
      end
      -- The actual expansion is left to later passes.
    else
      table.insert(errors, make_error(
        string.format("expands_to item at index %d has unknown type '%s'", i, tostring(item and item.type)),
        "UNKNOWN_EXPAND_ITEM"
      ))
    end
  end

  return errors
end

--- Process an action node, resolving names in its args based on the action type.
--- @param action table Action node (raw YAML shape `type`/`args`, or AST shape `action_type`/`args`)
--- @return table array of structured error tables
function CompilerPass1:process_action(action)
  local errors = {}

  if action == nil then
    return { make_error("process_action called with a nil action", "NIL_ACTION_NODE") }
  end

  -- Normalize action type: raw YAML uses `type`, the AST Action node uses `action_type`.
  local atype = action.action_type or action.type
  if type(atype) ~= "string" then
    return { make_error(
      string.format("action is missing a string 'type' (got %s)", type(atype)),
      "ACTION_NO_TYPE"
    ) }
  end

  -- Ensure args exists before we read/write resolution results.
  if action.args == nil then
    action.args = {}
  end
  local args = action.args
  if type(args) ~= "table" then
    return { make_error(
      string.format("action '%s' has a non-table 'args' (got %s)", atype, type(args)),
      "ACTION_BAD_ARGS"
    ) }
  end

  -- Mapping from action type to the list of argument keys that hold names to resolve.
  -- This is a heuristic; expand it as more action types are learned.
  local name_args = {}
  if atype == "TalkToNPC" then
    name_args = { "npc_name" }
  elseif atype == "KillCreature" then
    name_args = { "creature_name" }
  elseif atype == "CollectItem" then
    name_args = { "item_name" }
  elseif atype == "GoToGameObject" then
    name_args = { "gameobject_name" }
  -- Add more as needed
  end

  -- For each argument that is a name, try to resolve it.
  for _, arg_key in ipairs(name_args) do
    if args[arg_key] ~= nil then
      local val = args[arg_key]
      if type(val) == "string" then
        -- Try to resolve as a name
        local resolved_id, err = self:resolve_name_by_action_type(atype, arg_key, val)
        if not resolved_id then
          table.insert(errors, make_error(
            string.format("Failed to resolve %s '%s': %s", arg_key, val, err or "unknown error"),
            "RESOLVE_FAIL"
          ))
        else
          -- Store the resolved ID in the args under a new key, e.g., npc_id.
          -- We also keep the original name for reference and stash the entity data.
          args[arg_key .. "_id"] = resolved_id
          args[arg_key .. "_data"] = self:get_entity_data(atype, arg_key, resolved_id)
        end
      elseif type(val) == "number" then
        -- It's already an ID; validate that it exists.
        local valid, err = self:validate_id_by_action_type(atype, arg_key, val)
        if not valid then
          table.insert(errors, make_error(
            string.format("Invalid %s ID %d: %s", arg_key, val, err or "unknown error"),
            "INVALID_ID"
          ))
        else
          args[arg_key .. "_data"] = self:get_entity_data(atype, arg_key, val)
        end
      else
        table.insert(errors, make_error(
          string.format("%s must be a string or number, got %s", arg_key, type(val)),
          "BAD_ARG_TYPE"
        ))
      end
    end
  end

  return errors
end

--- Resolve a name to an ID based on the action type and argument key.
--- @param action_type string
--- @param arg_key string
--- @param name string
--- @return number|nil id, string|nil error
function CompilerPass1:resolve_name_by_action_type(action_type, arg_key, name)
  if action_type == "TalkToNPC" and arg_key == "npc_name" then
    local entry = find_creature_by_name(name)
    if entry then
      return entry
    else
      return nil, "NPC not found"
    end
  elseif action_type == "KillCreature" and arg_key == "creature_name" then
    local entry = find_creature_by_name(name)
    if entry then
      return entry
    else
      return nil, "Creature not found"
    end
  elseif action_type == "CollectItem" and arg_key == "item_name" then
    local entry = find_item_by_name(name)
    if entry then
      return entry
    else
      return nil, "Item not found"
    end
  elseif action_type == "GoToGameObject" and arg_key == "gameobject_name" then
    local entry = find_gameobject_by_name(name)
    if entry then
      return entry
    else
      return nil, "GameObject not found"
    end
  else
    return nil, "Unsupported action type or argument for name resolution"
  end
end

--- Validate that an ID exists for the given action type and argument key.
--- @param action_type string
--- @param arg_key string
--- @param id number
--- @return boolean ok, string|nil error
function CompilerPass1:validate_id_by_action_type(action_type, arg_key, id)
  if action_type == "TalkToNPC" or action_type == "KillCreature" then
    if arg_key:match(".*_name$") then
      -- We expect a creature ID
      if MockDB.creatures[id] then
        return true
      else
        return false, "Creature ID not found"
      end
    end
  elseif action_type == "CollectItem" then
    if arg_key:match(".*_name$") then
      if MockDB.items[id] then
        return true
      else
        return false, "Item ID not found"
      end
    end
  elseif action_type == "GoToGameObject" then
    if arg_key:match(".*_name$") then
      if MockDB.gameobjects[id] then
        return true
      else
        return false, "GameObject ID not found"
      end
    end
  end
  -- If we don't know how to validate, we assume it's valid
  return true
end

--- Get the entity data for a given ID and action type/argument.
--- @param action_type string
--- @param arg_key string
--- @param id number
--- @return table|nil data
function CompilerPass1:get_entity_data(action_type, arg_key, id)
  if action_type == "TalkToNPC" or action_type == "KillCreature" then
    if arg_key:match(".*_name$") then
      return MockDB.creatures[id]
    end
  elseif action_type == "CollectItem" then
    if arg_key:match(".*_name$") then
      return MockDB.items[id]
    end
  elseif action_type == "GoToGameObject" then
    if arg_key:match(".*_name$") then
      return MockDB.gameobjects[id]
    end
  end
  return nil
end

return CompilerPass1
