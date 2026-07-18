-- sentinel/modules/quest/source_ast.lua
-- AST for the source YAML files (project, operation, blueprint)

local JSON = require("lib/JSON")
local SourceSchema = require("modules/quest/source_schema")
local SourceValidator = require("modules/quest/source_validator")
local ProfileCompiler = require("modules/quest/profile_compiler") -- for YAML parser

-- Forward declaration
local SourceAST = {}
SourceAST.__index = SourceAST

-- AST node types (we'll use tables with a 'type' field)
-- We'll create constructor functions for each node type

--[[
  Program node: represents the entire project (directory)
  fields:
    project: ProjectAST node
    operations: map of name -> OperationAST
    blueprints: map of name -> BlueprintAST
]]
function SourceAST:Program(project, operations, blueprints)
  return setmetatable({
    type = "Program",
    project = project,
    operations = operations or {},
    blueprints = blueprints or {},
  }, SourceAST)
end

-- Project node
function SourceAST:Project(data)
  return setmetatable({
    type = "Project",
    name = data.name,
    version = data.version,
    target = data.target,
    zone_id = data.zone_id,
    filiation = data.filiation,
    variables = data.variables or {}, -- map of name -> VariableAST
  }, SourceAST)
end

-- Operation node
function SourceAST:Operation(data)
  return setmetatable({
    type = "Operation",
    name = data.name,
    description = data.description,
    zone_ref = data.zone_ref,
    level_range = data.level_range, -- {min=, max=}
    variables = data.variables or {}, -- map of name -> VariableAST
    actions = data.actions or {}, -- list of ActionAST
  }, SourceAST)
end

-- Blueprint node
function SourceAST:Blueprint(data)
  return setmetatable({
    type = "Blueprint",
    name = data.name,
    description = data.description,
    params = data.params or {}, -- list of ParameterAST
    expands_to = data.expands_to or {}, -- list of ActionAST or BlueprintReferenceAST
  }, SourceAST)
end
-- Action node
function SourceAST:Action(data)
  return setmetatable({
    type = "Action",
    action_type = data.type, -- string, e.g., "TalkToNPC"
    id = data.id, -- optional string
    args = data.args or {}, -- map of arg name to value
    condition = data.condition, -- optional string (expression)
  }, SourceAST)
end

-- Parameter node (for blueprints)
function SourceAST:Parameter(data)
  return setmetatable({
    type = "Parameter",
    name = data.name,
    type = data.type, -- string, number, boolean
    default = data.default,
    description = data.description,
  }, SourceAST)
end

-- Variable node (for projects and operations)
function SourceAST:Variable(data)
  return setmetatable({
    type = "Variable",
    name = data.name,
    type = data.type, -- string, number, boolean
    default = data.default,
    description = data.description,
    bind = data.bind, -- optional string (blackboard path)
  }, SourceAST)
end

-- BlueprintReferenceNode (when an action in expands_to is a blueprint reference)
function SourceAST:BlueprintReference(data)
  return setmetatable({
    type = "BlueprintReference",
    blueprint_name = data.blueprint_name,
    -- TODO: store the actual mapping of parameters? We'll resolve during semantic analysis
  }, SourceAST)
end

-- We'll also need to represent expressions for conditions and variable references, but for simplicity
-- we'll keep them as strings and validate them later.

--- Parse a YAML file and return the AST root node (Program) for the given project directory.
--- @param project_dir string
--- @return table {ok=true, ast=Program, errors={}} or {ok=false, errors={string}}
function SourceAST:parse_project(project_dir)
  local errors = {}
  
  -- 1. Parse project.yaml
  local project_path = project_dir .. "/project.yaml"
  local project_ast, proj_err = self:parse_project_file(project_path)
  if not project_ast then
    table.insert(errors, proj_err)
    return {ok=false, errors=errors}
  end
  
  -- 2. Parse all operation.yaml files
  local operations = {}
  local ops_dir = project_dir .. "/operations"
  local op_files = self:_list_yaml_files(ops_dir)
  for _, filepath in ipairs(op_files) do
    print("DEBUG: Operation file: " .. filepath)
    local op_ast, op_err = self:parse_operation_file(filepath)
    if op_err then
      table.insert(errors, string.format("Error in %s: %s", filepath, op_err))
    else
      if operations[op_ast.name] then
        table.insert(errors, string.format("Duplicate operation name '%s' in %s", op_ast.name, filepath))
      else
        operations[op_ast.name] = op_ast
        print("DEBUG: Added operation: " .. op_ast.name)
      end
    end
  end
  
  -- 3. Parse all blueprint.yaml files
  local blueprints = {}
  local bp_dir = project_dir .. "/blueprints"
  local bp_files = self:_list_yaml_files(bp_dir)
  for _, filepath in ipairs(bp_files) do
    print("DEBUG: Blueprint file: " .. filepath)
    local bp_ast, bp_err = self:parse_blueprint_file(filepath)
    if bp_err then
      table.insert(errors, string.format("Error in %s: %s", filepath, bp_err))
    else
      if blueprints[bp_ast.name] then
        table.insert(errors, string.format("Duplicate blueprint name '%s' in %s", bp_ast.name, filepath))
      else
        blueprints[bp_ast.name] = bp_ast
        print("DEBUG: Added blueprint: " .. bp_ast.name)
      end
    end
  end
  
  if #errors > 0 then
    return {ok=false, errors=errors}
  end
  
  -- 4. Build the program AST
  local program = self:Program(project_ast, operations, blueprints)
  
  -- 5. Perform semantic analysis (symbol table, duplicate detection, etc.)
  local sem_errors = self:analyze_semantics(program)
  if #sem_errors > 0 then
    for _, err in ipairs(sem_errors) do
      table.insert(errors, err)
    end
    return {ok=false, errors=errors}
  end
  
  return {ok=true, ast=program, errors={}}
end

--- Parse a project.yaml file into a Project AST node
--- @param filepath string
--- @return ProjectAST|nil, error_string|nil
function SourceAST:parse_project_file(filepath)
  -- We'll use the existing YAML parser from profile_compiler, but we need to adapt it to return line numbers.
  -- For now, we'll use the simple parser and note that we don't have line numbers.
  local file, err = io.open(filepath, "r")
  if not file then
    return nil, "Could not open file: " .. tostring(err)
  end
  local content = file:read("*a")
  file:close()
  
  local success, data = pcall(function()
    return ProfileCompiler.parseYAML(content)
  end)
  if not success then
    return nil, "YAML parse error: " .. tostring(data)
  end
  
  -- Validate against the project schema (optional, but good to catch early)
  local ok, schema_errs = SourceSchema:validate_project(data)
  if not ok then
    return nil, "Schema validation failed: " .. table.concat(schema_errs, "; ")
  end
  
  return self:Project(data)
end

--- Parse an operation.yaml file into an Operation AST node
--- @param filepath string
--- @return OperationAST|nil, error_string|nil
function SourceAST:parse_operation_file(filepath)
  local file, err = io.open(filepath, "r")
  if not file then
    return nil, "Could not open file: " .. tostring(err)
  end
  local content = file:read("*a")
  file:close()
  
  local success, data = pcall(function()
    return ProfileCompiler.parseYAML(content)
  end)
  if not success then
    return nil, "YAML parse error: " .. tostring(data)
  end
  
  local ok, schema_errs = SourceSchema:validate_operation(data)
  if not ok then
    return nil, "Schema validation failed: " .. table.concat(schema_errs, "; ")
  end
  
  return self:Operation(data)
end

--- Parse a blueprint.yaml file into a Blueprint AST node
--- @param filepath string
--- @return BlueprintAST|nil, error_string|nil
function SourceAST:parse_blueprint_file(filepath)
  local file, err = io.open(filepath, "r")
  if not file then
    return nil, "Could not open file: " .. tostring(err)
  end
  local content = file:read("*a")
  file:close()
  
  local success, data = pcall(function()
    return ProfileCompiler.parseYAML(content)
  end)
  if not success then
    return nil, "YAML parse error: " .. tostring(data)
  end
  
  local ok, schema_errs = SourceSchema:validate_blueprint(data)
  if not ok then
    return nil, "Schema validation failed: " .. table.concat(schema_errs, "; ")
  end
  
  return self:Blueprint(data)
end

--- List all .yaml files in a directory
--- @param dir string
--- @return table array of file paths
function SourceAST:_list_yaml_files(dir)
  local files = {}
  local handle = io.popen('find "' .. dir .. '" -maxdepth 1 -type f -name "*.yaml" 2>/dev/null')
  if not handle then
    return files
  end
  for line in handle:lines() do
    table.insert(files, line)
  end
  handle:close()
  return files
end

--- Perform semantic analysis on the AST
--- @param program ProgramAST
--- @return table array of error messages
function SourceAST:analyze_semantics(program)
  local errors = {}
  
  -- 1. Check for duplicate variable names within project and each operation
  -- (we already checked for duplicate operation and blueprint names during parsing)
  
  -- 2. Check for circular blueprint expansions
  -- We'll build a graph of blueprint dependencies and check for cycles.
  
  -- 3. Validate references: 
  --   - action.type must be a known action (we'll have a list of known actions from the core)
  --   - variable references ($variable) must be defined in the current scope (project or operation)
  --   - blueprint references in expands_to must point to a defined blueprint
  
  -- For now, we'll return an empty error list and note that these checks are to be implemented.
  -- In a full implementation, we would do:
  
  -- Build blueprint dependency graph
  local graph = {}
  for name, bp in pairs(program.blueprints) do
    graph[name] = {}
    for _, item in ipairs(bp.expands_to) do
      if item.type == "BlueprintReference" then
        table.insert(graph[name], item.blueprint_name)
      end
    end
  end
  
  -- Check for cycles in the graph (using DFS)
  local visited = {}
  local rec_stack = {}
  
  local function is_cyclic(node)
    if not visited[node] then
      visited[node] = true
      rec_stack[node] = true
      
      for _, neighbor in ipairs(graph[node] or {}) do
        if not visited[neighbor] then
          if is_cyclic(neighbor) then
            return true
          elseif rec_stack[neighbor] then
            return true
          end
        elseif rec_stack[neighbor] then
          return true
        end
      end
    end
    rec_stack[node] = false
    return false
  end
  
  for node, _ in pairs(graph) do
    if is_cyclic(node) then
      table.insert(errors, string.format("Circular dependency detected in blueprint '%s'", node))
      break
    end
  end
  
  -- TODO: Validate action types against a list of known actions (from core_actions)
  -- TODO: Validate variable references in conditions and args
  
  return errors
end

return SourceAST