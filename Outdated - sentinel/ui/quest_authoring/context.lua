-- sentinel/ui/quest_authoring/context.lua
-- Shared IDE application context: the in-memory project model, current
-- selection, compile results, and a tiny publish/subscribe event bus used to
-- keep the panes decoupled.

local Context = {}
Context.__index = Context

function Context.new()
  local self = setmetatable({}, Context)
  -- model: { name, operations = {name -> op}, blueprints = {name -> bp}, variables = {} }
  self.project = nil
  -- selection: { kind = "operation"|"action"|"blueprint"|"project", opName, actionIndex, bpName }
  self.selection = { kind = nil }
  -- last compile result from CompilerService
  self.compileResult = nil
  -- dirty = project changed since last successful compile
  self._dirty = false
  self._listeners = {}
  return self
end

-- ---- Event bus ----
function Context:on(event, cb)
  self._listeners[event] = self._listeners[event] or {}
  table.insert(self._listeners[event], cb)
end

function Context:emit(event, payload)
  local ls = self._listeners[event]
  if not ls then return end
  for _, cb in ipairs(ls) do
    local ok, err = pcall(cb, payload)
    if not ok and self.logError then
      self.logError("event '" .. tostring(event) .. "': " .. tostring(err))
    end
  end
end

-- ---- Project model ----
function Context:loadProject(model)
  self.project = model
  self:clearDirty()
  self:emit("project_loaded", { model = model })
end

function Context:markDirty()
  self._dirty = true
  self:emit("project_dirty", {})
end

function Context:isDirty() return self._dirty end
function Context:clearDirty() self._dirty = false end

-- ---- Selection ----
-- select(kind, id, extra): build a structured selection.
--   operation -> {kind="operation", id=opName}
--   action    -> {kind="action", id=actionId, opName=opName}
--   blueprint -> {kind="blueprint", id=bpName}
--   project   -> {kind="project"}
function Context:select(kind, id, extra)
  local sel = { kind = kind, id = id }
  if extra then for k, v in pairs(extra) do sel[k] = v end end
  self.selection = sel
  self:emit("selection_changed", sel)
end

function Context:clearSelection()
  self.selection = { kind = nil }
  self:emit("selection_changed", self.selection)
end

function Context:getSelected() return self.selection end

function Context:getOperation(opName) return self.project and self.project.operations[opName] end

function Context:getAction(opName, key)
  local op = self:getOperation(opName)
  if not op or not op.actions then return nil end
  for i, a in ipairs(op.actions) do
    if i == key or a.id == key then return a, i end
  end
  return nil
end

function Context:getSelectedAction()
  local sel = self.selection
  if sel.kind ~= "action" then return nil end
  return self:getAction(sel.opName, sel.id)
end

function Context:deleteAction(opName, key)
  local op = self:getOperation(opName)
  if not op or not op.actions then return false end
  for i, a in ipairs(op.actions) do
    if i == key or a.id == key then
      table.remove(op.actions, i)
      self:markDirty()
      self:emit("actions_changed", { opName = opName })
      if self.selection.kind == "action" and self.selection.opName == opName and self.selection.id == i then
        self:clearSelection()
      end
      return true
    end
  end
  return false
end


-- ---- Compile results ----
function Context:setCompileResult(result)
  self.compileResult = result
  if result and result.ok then self:clearDirty() end
  self:emit("compile_done", { result = result })
end

-- ---- YAML Serialization (simple subset) ----
-- Produces source-format YAML that SourceAST:parse_project can consume back.

local function yaml_escape_str(s)
  if s == nil then return "null" end
  if type(s) == "boolean" then return s and "true" or "false" end
  if type(s) == "number" then return tostring(s) end
  s = tostring(s)
  -- Quote if it contains special chars or looks like a number/bool
  if s == "" or s:match("[%[%]{},:|#&*!>%%'\"@`]") or s:match("^[%d%.%-]") or s:match("^(true|false|null|yes|no)$") then
    return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
  end
  return s
end

local yaml_indent = function(n) return string.rep("  ", n) end

local function yaml_serialize(value, indent)
  indent = indent or 0
  local t = type(value)
  if t == "nil" then return "null" end
  if t == "boolean" or t == "number" then return tostring(value) end
  if t == "string" then return yaml_escape_str(value) end
  if t ~= "table" then return tostring(value) end

  -- Check if array (sequential integer keys)
  local is_arr = #value > 0
  if is_arr then
    local parts = {}
    for i, v in ipairs(value) do
      if type(v) == "table" then
        -- Inline short tables; multi-line for longer ones
        local inner = yaml_serialize(v, indent + 1)
        if inner:find("\n") then
          parts[#parts + 1] = yaml_indent(indent) .. "-\n" .. inner
        else
          parts[#parts + 1] = yaml_indent(indent) .. "- " .. inner
        end
      else
        parts[#parts + 1] = yaml_indent(indent) .. "- " .. yaml_serialize(v, indent + 1)
      end
    end
    return table.concat(parts, "\n")
  end

  -- Map
  local parts = {}
  -- Deterministic key order: sort alphabetically
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local v = value[k]
    local ks = yaml_escape_str(tostring(k))
    if type(v) == "table" then
      local inner = yaml_serialize(v, indent + 1)
      parts[#parts + 1] = yaml_indent(indent) .. ks .. ":\n" .. inner
    else
      parts[#parts + 1] = yaml_indent(indent) .. ks .. ": " .. yaml_serialize(v, indent + 1)
    end
  end
  return table.concat(parts, "\n")
end

--- Serialize the entire project model to a single YAML string.
--- Uses the source-format convention: project fields at top level,
--- operations and blueprints as sub-tables.
function Context:serializeProject()
  local p = self.project
  if not p then return nil end
  local doc = {}
  -- Project-level fields
  doc.name = p.name or "Untitled"
  doc.version = p.version or "1.0.0"
  doc.target = p.target or "TBC"
  doc.zone_id = p.zone_id or 1
  doc.filiation = p.filiation or "Alliance"
  if p.variables and next(p.variables) then
    doc.variables = p.variables
  end
  -- Operations
  if p.operations and next(p.operations) then
    doc.operations = {}
    -- Deterministic order
    local names = {}
    for name in pairs(p.operations) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      local op = p.operations[name]
      doc.operations[name] = op
    end
  end
  -- Blueprints
  if p.blueprints and next(p.blueprints) then
    doc.blueprints = {}
    local names = {}
    for name in pairs(p.blueprints) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      doc.blueprints[name] = p.blueprints[name]
    end
  end
  return yaml_serialize(doc, 0)
end

--- Save the project to disk as YAML. Returns true on success, false+err on failure.
function Context:saveToDisk(path)
  if not path then return false, "no path" end
  local yaml_str = self:serializeProject()
  if not yaml_str then return false, "no project" end
  -- Ensure directory exists
  local dir = path:match("^(.+)/[^/]+$")
  if dir and os then
    os.execute('mkdir -p "' .. dir .. '"')
  end
  local f, err = io.open(path, "w")
  if not f then return false, tostring(err) end
  f:write(yaml_str)
  f:close()
  self:clearDirty()
  self:emit("project_saved", { path = path })
  return true
end

--- Load a project from disk (YAML file). Returns true on success.
function Context:loadFromDisk(path)
  if not path then return false, "no path" end
  local SourceAST = require("modules/quest/source_ast")
  local ok, result = pcall(function() return SourceAST:parse_project(path) end)
  if ok and result and result.ok and result.ast then
    self.projectPath = path
    self:loadProject(result.ast)
    return true
  end
  local msg = result and result.errors and result.errors[1] or "parse failed"
  if self.logError then self.logError("loadFromDisk: " .. tostring(msg)) end
  return false, tostring(msg)
end

-- ---- Mutation helpers (all mark dirty + notify) ----
function Context:addOperation(name, op)
  if not self.project then return end
  op = op or { name = name, actions = {}, variables = {} }
  self.project.operations[name] = op
  self:markDirty()
  self:emit("structure_changed", {})
end

function Context:removeOperation(name)
  if not self.project then return end
  self.project.operations[name] = nil
  self:markDirty()
  self:emit("structure_changed", {})
end

function Context:renameOperation(oldName, newName)
  if not self.project then return end
  local op = self.project.operations[oldName]
  if op then
    self.project.operations[oldName] = nil
    op.name = newName
    self.project.operations[newName] = op
    self:markDirty()
    self:emit("structure_changed", {})
  end
end

function Context:addAction(opName, action)
  if not self.project then return end
  local op = self.project.operations[opName]
  if op then
    op.actions = op.actions or {}
    table.insert(op.actions, action)
    self:markDirty()
    self:emit("actions_changed", { opName = opName })
  end
end

function Context:removeAction(opName, index)
  if not self.project then return end
  local op = self.project.operations[opName]
  if op and op.actions then
    table.remove(op.actions, index)
    self:markDirty()
    self:emit("actions_changed", { opName = opName })
  end
end

function Context:moveAction(opName, fromIndex, toIndex)
  if not self.project then return end
  local op = self.project.operations[opName]
  if not op or not op.actions then return end
  if fromIndex < 1 or fromIndex > #op.actions then return end
  if toIndex < 1 then toIndex = 1 end
  if toIndex > #op.actions then toIndex = #op.actions end
  local a = table.remove(op.actions, fromIndex)
  table.insert(op.actions, toIndex, a)
  self:markDirty()
  self:emit("actions_changed", { opName = opName })
end

return Context
