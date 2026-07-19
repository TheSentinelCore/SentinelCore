-- sentinel/modules/quest/compiler_pass3.lua
-- Compiler Pass 3: Dead Code Elimination
-- Removes unreachable/redundant nodes from the compiled AST:
--   - unused blueprints (never referenced)
--   - unused variables (declared but never referenced)
--   - actions whose condition is statically impossible (literal `false`)
--   - operations whose prerequisite quest chain is disconnected (flagged)
-- Elimination is recorded into `ast._debug.eliminated` for IDE traceability.

local CompilerPass3 = {}
CompilerPass3.__index = CompilerPass3

-- Optional no-op quest provider.
local function default_provider()
  local p = {}
  function p:getQuest(_) return nil end
  return p
end

function CompilerPass3.new(provider)
  return setmetatable({
    _provider = provider or default_provider(),
  }, CompilerPass3)
end

--- Run the Level 3 pass on the AST.
--- @param ast table AST after pass 2 (implied actions inserted)
--- @return table {ok=true, ast=AST, errors={}, eliminated={...}}
function CompilerPass3:run(ast)
  self._last_ast = ast
  local eliminated = {
    blueprints = {},
    variables = {},
    actions = {},
    operations = {},
  }

  -- 1. Determine which blueprints are referenced anywhere.
  local used_blueprints = self:_collect_used_blueprints(ast)

  -- 2. Determine which variable names are referenced anywhere.
  local used_vars = self:_collect_used_variables(ast)

  -- 3. Eliminate unused blueprints.
  for bp_name, bp in pairs(ast.blueprints) do
    if not used_blueprints[bp_name] then
      ast.blueprints[bp_name] = nil
      table.insert(eliminated.blueprints, bp_name)
    end
  end

  -- 4. Eliminate unused variables (project + per-operation).
  self:_eliminate_unused_variables(ast, used_vars, eliminated)

  -- 5. Process operations: impossible conditions + disconnected chains.
  for op_name, op in pairs(ast.operations) do
    self:_process_operation(op, op_name, eliminated)
  end

  ast._debug = ast._debug or {}
  ast._debug.eliminated = eliminated

  return { ok = true, ast = ast, errors = {}, eliminated = eliminated }
end

--- Build the set of blueprint names referenced by operations or other blueprints.
function CompilerPass3:_collect_used_blueprints(ast)
  local used = {}
  local function scan_list(list)
    if type(list) ~= "table" then return end
    for _, item in ipairs(list) do
      if item then
        -- A blueprint reference node inside an operation's actions.
        if item.type == "BlueprintReference" or item.action_type == "BlueprintReference" then
          used[item.blueprint_name] = true
        elseif item.type == "Action" or item.action_type then
          -- Some action types may carry a blueprint reference argument.
          local args = item.args or {}
          if args.blueprint_ref then used[args.blueprint_ref] = true end
        end
      end
    end
  end

  for _, op in pairs(ast.operations) do
    scan_list(op.actions)
  end
  for _, bp in pairs(ast.blueprints) do
    scan_list(bp.expands_to)
  end
  return used
end

--- Collect every variable name referenced by args/conditions across the project.
function CompilerPass3:_collect_used_variables(ast)
  local used = {}
  local function note_refs(text)
    if type(text) ~= "string" then return end
    for name in text:gmatch("%$([%w_]+)") do
      used[name] = true
    end
  end

  local function scan_list(list)
    if type(list) ~= "table" then return end
    for _, item in ipairs(list) do
      if item then
        local args = item.args or {}
        for _, v in pairs(args) do
          if type(v) == "string" then note_refs(v) end
        end
        note_refs(item.condition)
      end
    end
  end

  for _, op in pairs(ast.operations) do
    scan_list(op.actions)
  end
  for _, bp in pairs(ast.blueprints) do
    scan_list(bp.expands_to)
  end
  -- Routing policies and variables' bind expressions may reference vars too.
  local proj = ast.project or {}
  for _, v in pairs(proj.variables or {}) do
    note_refs(v and v.bind)
  end
  return used
end

--- Remove variables declared at project/operation scope that are never referenced.
function CompilerPass3:_eliminate_unused_variables(ast, used_vars, eliminated)
  local proj = ast.project
  if proj and proj.variables then
    for vname, _ in pairs(proj.variables) do
      if not used_vars[vname] then
        proj.variables[vname] = nil
        table.insert(eliminated.variables, "project." .. vname)
      end
    end
  end
  for _, op in pairs(ast.operations) do
    if op.variables then
      for vname, _ in pairs(op.variables) do
        if not used_vars[vname] then
          op.variables[vname] = nil
          table.insert(eliminated.variables, (op.name or "?") .. "." .. vname)
        end
      end
    end
  end
end

--- Process a single operation: drop statically-impossible actions, flag
--- operations whose quest prerequisite chain is disconnected.
function CompilerPass3:_process_operation(op, op_name, eliminated)
  local actions = op.actions
  if type(actions) ~= "table" then
    return
  end

  local kept = {}
  for i = 1, #actions do
    local action = actions[i]
    if action and self:_is_impossible(action) then
      table.insert(eliminated.actions, {
        operation = op_name,
        index = i,
        type = action.action_type or action.type,
        reason = "statically impossible condition",
      })
    else
      kept[#kept + 1] = action
    end
  end
  op.actions = kept

  -- Disconnected prerequisite chain detection.
  local disconnected = self:_check_chain_disconnected(op)
  if disconnected then
    table.insert(eliminated.operations, {
      name = op_name,
      reason = "disconnected prerequisite quest chain",
      missing = disconnected,
    })
  end
end

--- A condition that is literally `false` can never execute.
function CompilerPass3:_is_impossible(action)
  local cond = action.condition
  if type(cond) == "string" then
    local trimmed = cond:match("^%s*(.-)%s*$")
    if trimmed == "false" then
      return true
    end
  end
  return false
end

--- Walk referenced quest prerequisites; if a prerequisite is known (in the DB)
--- but not referenced anywhere in the project, the chain is disconnected.
function CompilerPass3:_check_chain_disconnected(op)
  local missing = {}
  local actions = op.actions or {}
  for _, action in ipairs(actions) do
    local args = action.args or {}
    local quest_id = args.quest_id
    if quest_id then
      local current = quest_id
      -- Walk backwards through PrevQuestId at most 20 steps (cycle guard).
      for _ = 1, 20 do
        local quest = self._provider:getQuest(current)
        if not quest then break end
        local prev = quest.prev_quest_id or 0
        if prev == 0 then break end
        -- Is `prev` referenced by any action in the whole project?
        if not self:_quest_referenced_anywhere(prev) then
          missing[#missing + 1] = prev
        end
        current = prev
      end
    end
  end
  return #missing > 0 and missing or nil
end

function CompilerPass3:_quest_referenced_anywhere(quest_id)
  local function scan_list(list)
    if type(list) ~= "table" then return false end
    for _, item in ipairs(list) do
      if item then
        local args = item.args or {}
        if args.quest_id == quest_id then return true end
      end
    end
    return false
  end
  for _, op in pairs(self._last_ast.operations) do
    if scan_list(op.actions) then return true end
  end
  for _, bp in pairs(self._last_ast.blueprints) do
    if scan_list(bp.expands_to) then return true end
  end
  return false
end

-- Keep a reference to the AST for cross-operation queries during a run.
local _orig_run = CompilerPass3.run
function CompilerPass3:run(ast)
  self._last_ast = ast
  return _orig_run(self, ast)
end

return CompilerPass3
