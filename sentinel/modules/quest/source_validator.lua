-- sentinel/modules/quest/source_validator.lua
-- Validates source YAML files (project, operation, blueprint) against the source schema

local JSON = require("sentinel.lib.JSON")
local SourceSchema = require("sentinel.modules.quest.source_schema")
local ProfileCompiler = require("sentinel.modules.quest.profile_compiler") -- for YAML parser

local SourceValidator = {}
SourceValidator.__index = SourceValidator

function SourceValidator.new()
    local o = setmetatable({}, SourceValidator)
    return o
end

---Load and parse a YAML file
---@param filepath string
---@return table|nil parsed nil if error
---@return string|nil error message
function SourceValidator:_load_yaml(filepath)
    local file, err = io.open(filepath, "r")
    if not file then
        return nil, "Could not open file: " .. tostring(err)
    end
    local content = file:read("*a")
    file:close()
    
    local success, parsed = pcall(function()
        return ProfileParser.parseYAML(content)
    end)
    if not success then
        return nil, "YAML parse error: " .. tostring(parsed)
    end
    return parsed, nil
end

---Validate a project.yaml file
---@param filepath string
---@return boolean ok
---@return table|string errors if not ok, otherwise nil
function SourceValidator:validate_project(filepath)
    local parsed, err = self:_load_yaml(filepath)
    if not parsed then
        return false, { err }
    end
    local ok, errors = SourceSchema:validate_project(parsed)
    if not ok then
        return false, errors
    end
    return true, nil
end

---Validate an operation.yaml file
---@param filepath string
---@return boolean ok
---@return table|string errors if not ok, otherwise nil
function SourceValidator:validate_operation(filepath)
    local parsed, err = self:_load_yaml(filepath)
    if not parsed then
        return false, { err }
    end
    local ok, errors = SourceSchema:validate_operation(parsed)
    if not ok then
        return false, errors
    end
    return true, nil
end

---Validate a blueprint.yaml file
---@param filepath string
---@return boolean ok
---@return table|string errors if not ok, otherwise nil
function SourceValidator:validate_blueprint(filepath)
    local parsed, err = self:_load_yaml(filepath)
    if not parsed then
        return false, { err }
    end
    local ok, errors = SourceSchema:validate_blueprint(parsed)
    if not ok then
        return false, errors
    end
    return true, nil
end

---Validate all source files in a project directory
---@param project_dir string path to the project directory (containing project.yaml, operations/, blueprints/)
---@return table results with keys: project, operations, blueprints, each being {ok=true/false, errors=...}
function SourceValidator:validate_project_directory(project_dir)
    local results = {
        project = {ok = false, errors = {}},
        operations = {},
        blueprints = {}
    }
    
    -- Validate project.yaml
    local project_path = project_dir .. "/project.yaml"
    local ok, err = self:validate_project(project_path)
    results.project.ok = ok
    if not ok then
        results.project.errors = err
    end
    
    -- Validate operations
    local ops_dir = project_dir .. "/operations"
    local op_files = self:_list_files(ops_dir, "%.yaml$")
    for _, filepath in ipairs(op_files) do
        local ok, err = self:validate_operation(filepath)
        table.insert(results.operations, {
            file = filepath,
            ok = ok,
            errors = err
        })
    end
    
    -- Validate blueprints
    local bp_dir = project_dir .. "/blueprints"
    local bp_files = self:_list_files(bp_dir, "%.yaml$")
    for _, filepath in ipairs(bp_files) do
        local ok, err = self:validate_blueprint(filepath)
        table.insert(results.blueprints, {
            file = filepath,
            ok = ok,
            errors = err
        })
    end
    
    return results
end

---Helper to list files in a directory matching a pattern
---@param dir string
---@param pattern string lua pattern
---@return table array of full file paths
function SourceValidator:_list_files(dir, pattern)
    local files = {}
    local handle = io.popen('find "' .. dir .. '" -maxdepth 1 -type f -name "' .. pattern .. '" 2>/dev/null')
    if not handle then
        return files
    end
    for line in handle:lines() do
        table.insert(files, line)
    end
    handle:close()
    return files
end

return SourceValidator