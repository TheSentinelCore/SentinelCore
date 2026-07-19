-- sentinel/ui/quest_authoring/compiler_service.lua
-- Ties the four compiler passes (1-4) into a single compile step for the IDE.
-- Produces a normalized result the Validation pane consumes:
--   { ok, profile, errors={ {severity,pass,message,location?} }, eliminated, ast }

local SourceAST = require("modules/quest/source_ast")
local CompilerPass1 = require("modules/quest/compiler_pass1")
local CompilerPass2 = require("modules/quest/compiler_pass2")
local CompilerPass3 = require("modules/quest/compiler_pass3")
local CompilerPass4 = require("modules/quest/compiler_pass4")
local ActionSchema = require("ui/quest_authoring/action_schema")

local CompilerService = {}
CompilerService.__index = CompilerService

--- @param providers table { quest_data = questProvider }
function CompilerService.new(providers)
  local self = setmetatable({}, CompilerService)
  providers = providers or {}
  self._qprovider = providers.quest_data
  self._profile = nil
  return self
end

--- Compile an IDE project model into a StatechartExecutor profile.
--- @param model table { name, operations, blueprints, variables }
function CompilerService:compile(model)
  local errors = {}

  local ast = SourceAST:Program(
    SourceAST:Project({ name = model.name, variables = model.variables or {} }),
    model.operations or {},
    model.blueprints or {}
  )

  -- Schema validation: check all actions against their schema
  for opName, op in pairs(model.operations or {}) do
    if op.actions then
      for i, act in ipairs(op.actions) do
        local atype = act.action_type or act.type
        if atype then
          local ok, errs = ActionSchema.validate(atype, act.args)
          if not ok then
            for _, e in ipairs(errs) do
              errors[#errors + 1] = {
                severity = "error",
                pass = 0,  -- pre-pass (schema)
                message = e,
                operation = opName,
                action_index = i,
              }
            end
          end
        end
      end
    end
  end

  local p1 = CompilerPass1.new()
  local r1 = p1:run(ast)
  if not r1.ok then
    for _, e in ipairs(r1.errors) do
      errors[#errors + 1] = { severity = "error", pass = 1, message = e }
    end
  end

  local p2 = CompilerPass2.new(self._qprovider)
  local r2 = p2:run(ast)
  if not r2.ok then
    for _, e in ipairs(r2.errors) do
      errors[#errors + 1] = { severity = "error", pass = 2, message = e }
    end
  end

  local p3 = CompilerPass3.new(self._qprovider)
  local r3 = p3:run(ast)
  local elim = r3.eliminated or {}
  for _, b in ipairs(elim.blueprints or {}) do
    errors[#errors + 1] = { severity = "warning", pass = 3, message = "Unused blueprint eliminated: " .. tostring(b) }
  end
  for _, v in ipairs(elim.variables or {}) do
    errors[#errors + 1] = { severity = "warning", pass = 3, message = "Unused variable eliminated: " .. tostring(v) }
  end
  for _, a in ipairs(elim.actions or {}) do
    errors[#errors + 1] = { severity = "warning", pass = 3, message = "Impossible action eliminated in '" .. tostring(a.operation) .. "'" }
  end
  for _, o in ipairs(elim.operations or {}) do
    errors[#errors + 1] = { severity = "warning", pass = 3, message = "Operation '" .. tostring(o.name) .. "' has a disconnected quest chain" }
  end

  local p4 = CompilerPass4.new()
  local r4 = p4:run(ast)
  self._profile = r4.profile

  local ok = (#errors == 0) and r1.ok and r2.ok
  return {
    ok = ok,
    profile = self._profile,
    errors = errors,
    eliminated = elim,
    ast = ast,
  }
end

function CompilerService:getProfile()
  return self._profile
end

return CompilerService
