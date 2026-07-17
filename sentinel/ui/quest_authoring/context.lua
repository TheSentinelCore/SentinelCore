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
