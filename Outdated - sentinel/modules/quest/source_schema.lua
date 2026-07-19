-- sentinel/modules/quest/source_schema.lua
-- Defines the schema and validation rules for source YAML files (project, operation, blueprint)

local JSON = require("lib/JSON")

local SourceSchema = {}
SourceSchema.__index = SourceSchema

-- Data types
local TYPES = {
  string = "string",
  number = "number",
  boolean = "boolean",
}

-- Helper to check if a value is in an enum
local function in_enum(value, enum_list)
  for _, v in ipairs(enum_list) do
    if v == value then return true end
  end
  return false
end

-- Helper to check if a table is an array (all numeric keys from 1 to #)
local function is_array(t)
  if type(t) ~= "table" then return false end
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil then return false end
  end
  return true
end

-- Project schema definition
SourceSchema.PROJECT_SCHEMA = {
  name = { type = TYPES.string, required = true },
  version = { type = TYPES.string, required = true, pattern = "^%d+%.%d+%.%d+$" }, -- semver
  target = { type = TYPES.string, required = true, enum = { "Classic", "TBC", "WotLK" } },
  zone_id = { type = TYPES.number, required = true, min = 1 },
  filiation = { type = TYPES.string, required = true, enum = { "Alliance", "Horde", "Neutral" } },
  variables = { type = "table", required = false }, -- map of variable definitions (to be validated separately)
}

-- Operation schema definition
SourceSchema.OPERATION_SCHEMA = {
  name = { type = TYPES.string, required = true },
  description = { type = TYPES.string, required = false },
  zone_ref = { type = TYPES.number, required = true }, -- references a zone id from the world DB
  level_range = { 
    type = "table", 
    required = true,
    schema = { 
      min = { type = TYPES.number, required = true, min = 1, max = 80 },
      max = { type = TYPES.number, required = true, min = 1, max = 80 }
    }
  },
  variables = { type = "table", required = false }, -- map of variable definitions
  actions = { type = "table", required = true, schema = "array", item_schema = "action" }, -- array of action objects
}

-- Blueprint schema definition
SourceSchema.BLUEPRINT_SCHEMA = {
  name = { type = TYPES.string, required = true },
  description = { type = TYPES.string, required = false },
  params = { type = "table", required = false, schema = "array", item_schema = "parameter" }, -- array of parameter definitions
  expands_to = { type = "table", required = true, schema = "array", item_schema = "action_or_blueprint" }, -- array of action objects or blueprint references
}

-- Action structure (common to operations and blueprints)
SourceSchema.ACTION_SCHEMA = {
  type = { type = TYPES.string, required = true }, -- e.g., "TalkToNPC", "CollectItem", "TravelTo", etc.
  id = { type = TYPES.string, required = false }, -- optional identifier for the action within its container
  args = { type = "table", required = false }, -- arguments specific to the action type
  condition = { type = TYPES.string, required = false }, -- optional Lua expression that must evaluate to true for the action to execute
}

-- Parameter definition (for blueprints)
SourceSchema.PARAM_SCHEMA = {
  name = { type = TYPES.string, required = true },
  type = { type = TYPES.string, required = true, enum = { "string", "number", "boolean" } },
  default = { type = "any", required = false }, -- must match the type
  description = { type = TYPES.string, required = false },
}

-- Variable definition (for projects and operations)
SourceSchema.VARIABLE_SCHEMA = {
  type = { type = TYPES.string, required = true, enum = { "string", "number", "boolean" } },
  default = { type = "any", required = false }, -- must match the type
  description = { type = TYPES.string, required = false },
  bind = { type = TYPES.string, required = false }, -- blackboard path to bind to (e.g., "player.level")
}

-- Create a new validator instance
function SourceSchema.new()
  return setmetatable({}, SourceSchema)
end

-- Validate a table against a schema definition
-- schema_def: a table where keys are field names and values are schema rules
-- data: the table to validate
-- returns: true if valid, false and a list of errors otherwise
function SourceSchema:validate(schema_def, data)
  local errors = {}
  
  -- Check required fields
  for field, rules in pairs(schema_def) do
    if rules.required and data[field] == nil then
      table.insert(errors, string.format("Missing required field: %s", field))
    end
  end
  
  -- Check each field that exists in data
  for field, value in pairs(data) do
    local rules = schema_def[field]
    if rules then
      -- Type checking
      if rules.type then
        if rules.type == TYPES.string and type(value) ~= "string" then
          table.insert(errors, string.format("Field '%s' must be a string", field))
        elseif rules.type == TYPES.number and type(value) ~= "number" then
          table.insert(errors, string.format("Field '%s' must be a number", field))
        elseif rules.type == TYPES.bound and type(value) ~= "boolean" then
          table.insert(errors, string.format("Field '%s' must be a boolean", field))
        elseif rules.type == "table" then
          if type(value) ~= "table" then
            table.insert(errors, string.format("Field '%s' must be a table", field))
          else
            -- If there's a sub-schema, validate it
            if rules.schema then
              if rules.schema == "array" then
                if not is_array(value) then
                  table.insert(errors, string.format("Field '%s' must be an array", field))
                else
                  -- Validate array items if there's an item schema
                  if rules.item_schema then
                    for i, item in ipairs(value) do
                      local item_ok, item_errs = self:validate_item(rules.item_schema, item)
                      if not item_ok then
                        for _, err in ipairs(item_errs) do
                          table.insert(errors, string.format("Field '%s[%d]': %s", field, i, err))
                        end
                      end
                    end
                  end
                end
              else
                -- Assume it's an object schema (like level_range)
                local obj_ok, obj_errs = self:validate(rules.schema, value)
                if not obj_ok then
                  for _, err in ipairs(obj_errs) do
                    table.insert(errors, string.format("Field '%s': %s", field, err))
                  end
                end
              end
            end
          end
        end
      end
      
      -- Enum validation
      if rules.enum then
        if not in_enum(value, rules.enum) then
          table.insert(errors, string.format("Field '%s' must be one of %s", field, table.concat(rules.enum, ", ")))
        end
      end
      
      -- Pattern validation (for strings)
      if rules.pattern and type(value) == "string" then
        if not value:match(rules.pattern) then
          table.insert(errors, string.format("Field '%s' does not match pattern %s", field, rules.pattern))
        end
      end
      
      -- Min/max validation (for numbers)
      if rules.min ~= nil and type(value) == "number" and value < rules.min then
        table.insert(errors, string.format("Field '%s' must be at least %s", field, tostring(rules.min)))
      end
      if rules.max ~= nil and type(value) == "number" and value > rules.max then
        table.insert(errors, string.format("Field '%s' must be at most %s", field, tostring(rules.max)))
      end
    else
      -- Unknown field
      table.insert(errors, string.format("Unknown field: %s", field))
    end
  end
  
  return #errors == 0, errors
end

-- Validate a single item against an item schema (used for arrays)
-- item_schema: one of "action", "parameter", "variable", "action_or_blueprint"
-- item: the value to validate
-- returns: true if valid, false and a list of errors otherwise
function SourceSchema:validate_item(item_schema, item)
  local schema_def
  if item_schema == "action" then
    schema_def = self.ACTION_SCHEMA
  elseif item_schema == "parameter" then
    schema_def = self.PARAM_SCHEMA
  elseif item_schema == "variable" then
    schema_def = self.VARIABLE_SCHEMA
  elseif item_schema == "action_or_blueprint" then
    -- This is a union: either an action or a blueprint reference
    -- We'll try both; if one passes, it's valid
    local action_ok, _ = self:validate_item("action", item)
    if action_ok then return true, {} end
    -- For blueprint reference, we expect a string (the blueprint name)
    if type(item) == "string" and item ~= "" then
      return true, {}
    end
    return false, { "Item must be either a valid action object or a non-empty string (blueprint name)" }
  else
    error("Unknown item schema: " .. tostring(item_schema))
  end
  
  return self:validate(schema_def, item)
end

-- Validate a project
function SourceSchema:validate_project(data)
  return self:validate(self.PROJECT_SCHEMA, data)
end

-- Validate an operation
function SourceSchema:validate_operation(data)
  return self:validate(self.OPERATION_SCHEMA, data)
end

-- Validate a blueprint
function SourceSchema:validate_blueprint(data)
  return self:validate(self.BLUEPRINT_SCHEMA, data)
end

return SourceSchema