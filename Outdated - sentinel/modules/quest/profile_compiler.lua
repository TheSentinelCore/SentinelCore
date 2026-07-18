-- sentinel/modules/quest/profile_compiler.lua
-- Profile Compiler: YAML parsing, validation, bytecode compilation, CompiledProfile emission

local JSON = require("lib/JSON")

local ProfileCompiler = {}
ProfileCompiler.__index = ProfileCompiler

-- ============================================================
-- YAML Parser (minimal subset for profile DSL)
-- ============================================================

-- Export for testing
function ProfileCompiler.parseYAML(yaml_str)
    local lines = {}
    for line in yaml_str:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end
    
    local root = {}
    -- Stack entries: {indent, node, key_in_parent, is_sequence, sequence_array}
    local stack = {{indent = -1, node = root, key_in_parent = nil, is_sequence = false, sequence_array = nil}}
    local line_num = 0
    
    local function current_indent(line)
        local _, count = line:find("^%s*")
        return count or 0
    end
    
    local function parse_value(str)
        str = str:match("^%s*(.-)%s*$")
        if str == "true" then return true end
        if str == "false" then return false end
        if str == "null" or str == "~" then return nil end
        if str:match("^%d+$") then return tonumber(str) end
        if str:match("^%d+%.%d+$") then return tonumber(str) end
        if str:match('^".*"$') then return str:sub(2, -2) end
        if str:match("^'.*'$") then return str:sub(2, -2) end
        return str
    end
    
    local function parse_inline_mapping(str)
        local result = {}
        str = str:match("^%s*{?(.-)}?%s*$")
        for pair in str:gmatch("([^,]+)") do
            local k, v = pair:match("^%s*([^:]+):%s*(.+)%s*$")
            if k and v then
                result[k:match("^%s*(.-)%s*$")] = parse_value(v)
            end
        end
        return result
    end
    
    local function split_args_quoted(str)
        -- Split on commas while respecting quoted strings
        -- Handles: 'item1, "item2, with comma", item3'
        local result = {}
        local current = ""
        local in_quotes = nil
        local i = 1
        
        while i <= #str do
            local char = str:sub(i, i)
            local next_char = str:sub(i + 1, i + 1)
            
            if in_quotes then
                current = current .. char
                if char == in_quotes and next_char ~= in_quotes then
                    in_quotes = nil
                elseif char == "\\" and next_char == in_quotes then
                    -- Escape sequence
                    current = current .. next_char
                    i = i + 1
                end
            elseif char == "'" or char == '"' then
                in_quotes = char
                current = current .. char
            elseif char == "," then
                table.insert(result, current)
                current = ""
            else
                current = current .. char
            end
            i = i + 1
        end
        table.insert(result, current)
        
        -- Clean up each item
        for idx, item in ipairs(result) do
            result[idx] = item:match("^%s*(.-)%s*$") or ""
        end
        
        return result
    end

    local function parse_inline_sequence(str)
        if not str or str == "" then return {} end
        local result = {}
        str = str:match("^%s*%[(.-)%]%s*$")
        if not str then return {} end
        for item in str:gmatch("([^,]+)") do
            table.insert(result, parse_value(item))
        end
        return result
    end
    
    local line_num = 0
    
    for i, line in ipairs(lines) do
        line_num = i
        if line:match("^%s*$") or line:match("^%s*#") then
            goto continue
        end
        
        local indent = current_indent(line)
        local content = line:sub(indent + 1)
        
        -- Pop stack to correct indent level
        while #stack > 0 and stack[#stack].indent >= indent do
            table.remove(stack)
        end
        
        if #stack == 0 then
            error("YAML parse error at line " .. line_num .. ": indent error")
        end
        
        local parent = stack[#stack]
        
        -- Check for sequence item (- item)
        local seq_item = content:match("^-%s*(.*)$")
        if seq_item then
            local key, value = seq_item:match("^([^:]+):%s*(.*)$")
            if key then
                -- Sequence item that starts a mapping: - key: value
                key = key:match("^%s*(.-)%s*$")
                value = value:match("^%s*(.-)%s*$")
                
                local node
                if value == "" or value == "{" or value == "[" then
                    if i < #lines then
                        local next_indent = current_indent(lines[i + 1])
                        if next_indent > indent then
                            if value == "[" or value:match("^%s*%[") then
                                node = {}
                            else
                                node = {}
                            end
                        else
                            node = parse_value(value)
                        end
                    else
                        node = {}
                    end
                else
                    node = parse_value(value)
                end
                
                -- Create a new mapping for this sequence item
                local seq_item_mapping = {[key] = node}
                
                -- Find the sequence array (parent should be it, or find in stack)
                local seq_array = parent.node
                if not parent.is_sequence then
                    -- Search stack for sequence array
                    for si = #stack, 1, -1 do
                        if stack[si].is_sequence then
                            seq_array = stack[si].node
                            break
                        end
                    end
                end
                
                -- Add to sequence array
                table.insert(seq_array, seq_item_mapping)
                
                -- Push the SEQUENCE ITEM MAPPING onto stack (not the array)
                table.insert(stack, {indent = indent, node = seq_item_mapping, key_in_parent = nil, is_sequence = true, sequence_array = seq_array})
            else
                -- Simple sequence item
                local item = parse_value(seq_item)
                if type(parent.node) == "table" then
                    table.insert(parent.node, item)
                end
            end
        else
            -- Regular key: value
            local key, value = content:match("^([^:]+):%s*(.*)$")
            if key then
                key = key:match("^%s*(.-)%s*$")
                value = value:match("^%s*(.-)%s*$")
                
                local node
                if value == "" or value == "{" or value == "[" then
                    if i < #lines then
                        local next_indent = current_indent(lines[i + 1])
                        if next_indent > indent then
                            -- Check if next non-empty line starts with - (sequence)
                            local is_seq = false
                            for j = i + 1, #lines do
                                local l = lines[j]
                                if not (l:match("^%s*$") or l:match("^%s*#")) then
                                    local ind = current_indent(l)
                                    local cont = l:sub(ind + 1)
                                    if cont:match("^-%s") then
                                        is_seq = true
                                    end
                                    break
                                end
                            end
                            if is_seq then
                                node = {}
                            elseif value == "[" or value:match("^%s*%[") then
                                node = {}
                            else
                                node = {}
                            end
                        else
                            node = parse_value(value)
                        end
                    else
                        node = parse_value(value)
                    end
                else
                    if value:match("^%s*{") then
                        node = parse_inline_mapping(value)
                    elseif value:match("^%s*%[") then
                        node = parse_inline_sequence(value)
                    else
                        node = parse_value(value)
                    end
                end
                
                if type(parent.node) == "table" then
                    parent.node[key] = node
                end
                
                if type(node) == "table" and (value == "" or value == "{" or value == "[") then
                    local is_seq = false
                    if value == "" and i < #lines then
                        -- Check if next non-empty line starts with -
                        for j = i + 1, #lines do
                            local l = lines[j]
                            if not (l:match("^%s*$") or l:match("^%s*#")) then
                                local ind = current_indent(l)
                                local cont = l:sub(ind + 1)
                                if cont:match("^-%s") then
                                    is_seq = true
                                end
                                break
                            end
                        end
                    end
                    table.insert(stack, {indent = indent, node = node, key_in_parent = key, is_sequence = is_seq, sequence_array = node})
                end
            else
                -- Check if it's a key:value inside the last sequence item
                if parent.is_sequence and parent.sequence_array and #parent.sequence_array > 0 then
                    local last_item = parent.sequence_array[#parent.sequence_array]
                    if type(last_item) == "table" then
                        local mkey, mvalue = content:match("^([^:]+):%s*(.*)$")
                        if mkey then
                            mkey = mkey:match("^%s*(.-)%s*$")
                            mvalue = mvalue:match("^%s*(.-)%s*$")
                            last_item[mkey] = parse_value(mvalue)
                        else
                            error("YAML parse error at line " .. line_num .. ": " .. content)
                        end
                    else
                        error("YAML parse error at line " .. line_num .. ": " .. content)
                    end
                else
                    error("YAML parse error at line " .. line_num .. ": " .. content)
                end
            end
        end
        
        ::continue::
    end
    
    return root
end

-- ============================================================
-- Schema Validation
-- ============================================================

local SCHEMA = {
    required = {"schemaVersion", "profile"},
    profile = {
        required = {"id", "name", "author", "expansion", "faction", "race", "class", "levelRange"},
        levelRange = {required = {"min", "max"}}
    },
    states = {required = true},
    variables = {optional = true},
    actions = {optional = true}
}

local VALID_STATE_TYPES = {"atomic", "compound", "parallel", "final", "exclusive"}
local VALID_REGION_TYPES = {"parallel", "exclusive"}
local KNOWN_EVENTS = {
    "QuestAccepted", "QuestCompleted", "QuestTurnedIn", "QuestFailed",
    "ObjectiveProgress", "InventoryChanged", "DurabilityChanged",
    "PlayerDied", "PlayerResurrected", "CombatStart", "CombatEnd",
    "LootReady", "LevelUp", "SkillUp", "ReputationChanged",
    "ZoneChanged", "HearthstoneReady", "FlightPathDiscovered",
    "RareSeen", "EliteSeen", "PlayerNearby", "Stuck",
    "NavigationArrived", "NavigationFailed", "NavigationReplanned",
    "VendorDone", "RepairDone", "TrainDone", "ProfileStart", "ProfileEvent"
}

function ProfileCompiler:_contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

function ProfileCompiler:_validate_schema(ast, diagnostics)
    for _, key in ipairs(SCHEMA.required) do
        if not ast[key] then
            table.insert(diagnostics.errors, {
                path = key,
                message = "Missing required field: " .. key
            })
        end
    end
    
    if not ast.profile then return end
    
    for _, key in ipairs(SCHEMA.profile.required) do
        if not ast.profile[key] then
            table.insert(diagnostics.errors, {
                path = "profile." .. key,
                message = "Missing required profile field: " .. key
            })
        end
    end
    
    if ast.profile.levelRange then
        for _, key in ipairs(SCHEMA.profile.levelRange.required) do
            if not ast.profile.levelRange[key] then
                table.insert(diagnostics.errors, {
                    path = "profile.levelRange." .. key,
                    message = "Missing levelRange field: " .. key
                })
            end
        end
    end
    
    if ast.states then
        self:_validate_states(ast.states, "", diagnostics)
    end
    
    if ast.variables then
        self:_validate_variables(ast.variables, diagnostics)
    end
end

function ProfileCompiler:_validate_states(states, prefix, diagnostics)
    for state_name, state in pairs(states) do
        local full_name = prefix == "" and state_name or (prefix .. "." .. state_name)
        
        if not state.type then
            table.insert(diagnostics.errors, {
                path = full_name .. ".type",
                message = "State missing required 'type' field"
            })
        elseif not self:_contains(VALID_STATE_TYPES, state.type) then
            table.insert(diagnostics.errors, {
                path = full_name .. ".type",
                message = "Invalid state type: " .. tostring(state.type) .. ". Valid: " .. table.concat(VALID_STATE_TYPES, ", ")
            })
        end
        
        if state.type == "compound" or state.type == "exclusive" or state.type == "parallel" then
            if not state.initial then
                table.insert(diagnostics.errors, {
                    path = full_name .. ".initial",
                    message = "Compound/exclusive/parallel state requires 'initial' field"
                })
            end
        end
        
        if state.type == "parallel" then
            if not state.regions then
                table.insert(diagnostics.errors, {
                    path = full_name .. ".regions",
                    message = "Parallel state requires 'regions' field"
                })
            else
                for region_name, region in pairs(state.regions) do
                    if not region.type or not self:_contains(VALID_REGION_TYPES, region.type) then
                        table.insert(diagnostics.errors, {
                            path = full_name .. ".regions." .. region_name .. ".type",
                            message = "Invalid region type: " .. tostring(region.type) .. ". Valid: parallel, exclusive"
                        })
                    end
                    if region.states then
                        self:_validate_states(region.states, full_name .. ".regions." .. region_name, diagnostics)
                    end
                end
            end
        end
        
        if state.states then
            self:_validate_states(state.states, full_name, diagnostics)
        end
        
        if state.transitions then
            for i, trans in ipairs(state.transitions) do
                if not trans.event then
                    table.insert(diagnostics.errors, {
                        path = full_name .. ".transitions[" .. i .. "].event",
                        message = "Transition missing 'event' field"
                    })
                elseif not self:_contains(KNOWN_EVENTS, trans.event) and not trans.event:match("^ProfileEvent:") then
                    table.insert(diagnostics.warnings, {
                        path = full_name .. ".transitions[" .. i .. "].event",
                        message = "Unknown event: " .. trans.event .. " (may be custom ProfileEvent:)"
                    })
                end
                if not trans.target then
                    table.insert(diagnostics.errors, {
                        path = full_name .. ".transitions[" .. i .. "].target",
                        message = "Transition missing 'target' field"
                    })
                end
            end
        end
        
        for _, hook in ipairs({"onEnter", "onExit"}) do
            if state[hook] then
                for i, action in ipairs(state[hook]) do
                    if type(action) ~= "string" then
                        table.insert(diagnostics.errors, {
                            path = full_name .. "." .. hook .. "[" .. i .. "]",
                            message = "Action must be a string"
                        })
                    end
                end
            end
        end
    end
end

function ProfileCompiler:_validate_variables(variables, diagnostics)
    for var_name, var_def in pairs(variables) do
        if not var_def.type then
            table.insert(diagnostics.errors, {
                path = "variables." .. var_name .. ".type",
                message = "Variable missing 'type' field"
            })
        elseif not self:_contains({"number", "string", "boolean"}, var_def.type) then
            table.insert(diagnostics.errors, {
                path = "variables." .. var_name .. ".type",
                message = "Invalid variable type: " .. tostring(var_def.type)
            })
        end
        if var_def.bind and type(var_def.bind) ~= "string" then
            table.insert(diagnostics.errors, {
                path = "variables." .. var_name .. ".bind",
                message = "Variable bind must be a string (blackboard path)"
            })
        end
    end
end

-- ============================================================
-- Semantic Validation (Quest/NPC/Policy references)
-- ============================================================

function ProfileCompiler:_validate_references(ast, diagnostics)
    if not self.quest_registry then
        table.insert(diagnostics.warnings, {
            path = "general",
            message = "QuestRegistry not available - skipping semantic validation"
        })
        return
    end
    
    local quest_ids = {}
    local npc_ids = {}
    local policy_names = {}
    local action_names = {}
    
    self:_collect_references(ast.states, "", quest_ids, npc_ids, policy_names, action_names)
    
    for quest_id, locations in pairs(quest_ids) do
        local quest = self.quest_registry:getQuest(quest_id)
        if not quest then
            for _, loc in ipairs(locations) do
                table.insert(diagnostics.errors, {
                    path = loc,
                    message = "Quest ID " .. quest_id .. " not found in database"
                })
            end
        end
    end
    
    for npc_id, locations in pairs(npc_ids) do
        if npc_id > 999999 then
            for _, loc in ipairs(locations) do
                table.insert(diagnostics.warnings, {
                    path = loc,
                    message = "NPC ID " .. npc_id .. " seems unusually high"
                })
            end
        end
    end
    
    for policy_name, locations in pairs(policy_names) do
        local policy = self.policy_loader and self.policy_loader:load(policy_name)
        if not policy then
            for _, loc in ipairs(locations) do
                table.insert(diagnostics.errors, {
                    path = loc,
                    message = "Routing policy '" .. policy_name .. "' not found"
                })
            end
        end
    end
    
    for action_name, locations in pairs(action_names) do
        if not self.core_actions[action_name] then
            for _, loc in ipairs(locations) do
                table.insert(diagnostics.errors, {
                    path = loc,
                    message = "Unknown core action: " .. action_name
                })
            end
        end
    end
end

function ProfileCompiler:_collect_references(states, prefix, quest_ids, npc_ids, policy_names, action_names)
    for state_name, state in pairs(states) do
        local full_name = prefix == "" and state_name or (prefix .. "." .. state_name)
        
        if state.meta and state.meta.questIds then
            for _, qid in ipairs(state.meta.questIds) do
                quest_ids[qid] = quest_ids[qid] or {}
                table.insert(quest_ids[qid], full_name .. ".meta.questIds")
            end
        end
        
        if state.transitions then
            for i, trans in ipairs(state.transitions) do
                if trans.guard and trans.guard:match("questId") then
                end
                if trans.actions then
                    for _, action in ipairs(trans.actions) do
                        self:_extract_refs_from_action(action, full_name .. ".transitions[" .. i .. "].actions",
                            quest_ids, npc_ids, policy_names, action_names)
                    end
                end
            end
        end
        
        for _, hook in ipairs({"onEnter", "onExit"}) do
            if state[hook] then
                for i, action in ipairs(state[hook]) do
                    self:_extract_refs_from_action(action, full_name .. "." .. hook .. "[" .. i .. "]",
                        quest_ids, npc_ids, policy_names, action_names)
                end
            end
        end
        
        if state.states then
            self:_collect_references(state.states, full_name, quest_ids, npc_ids, policy_names, action_names)
        end
        
        if state.regions then
            for region_name, region in pairs(state.regions) do
                if region.states then
                    self:_collect_references(region.states, full_name .. ".regions." .. region_name,
                        quest_ids, npc_ids, policy_names, action_names)
                end
            end
        end
    end
end

function ProfileCompiler:_extract_refs_from_action(action_str, location, quest_ids, npc_ids, policy_names, action_names)
    for qid in action_str:gmatch("questId%s*==%s*(%d+)") do
        local id = tonumber(qid)
        quest_ids[id] = quest_ids[id] or {}
        table.insert(quest_ids[id], location)
    end
    for qid in action_str:gmatch("questId%s*=%s*(%d+)") do
        local id = tonumber(qid)
        quest_ids[id] = quest_ids[id] or {}
        table.insert(quest_ids[id], location)
    end
    
    for policy in action_str:gmatch("followPolicy%('([^']+)'%)") do
        policy_names[policy] = policy_names[policy] or {}
        table.insert(policy_names[policy], location)
    end
    for policy in action_str:gmatch('followPolicy%("([^"]+)"%)') do
        policy_names[policy] = policy_names[policy] or {}
        table.insert(policy_names[policy], location)
    end
    
    for action in action_str:gmatch("coreActions%.([%w_%.]+)") do
        action_names[action] = action_names[action] or {}
        table.insert(action_names[action], location)
    end
end

-- ============================================================
-- Guard/Action Compilation
-- ============================================================

-- Sandbox environment for guard/action evaluation
-- Restricts access to safe globals only
local GUARD_SANDBOX = {
    -- Safe math functions
    math = {
        min = math.min,
        max = math.max,
        abs = math.abs,
        floor = math.floor,
        ceil = math.ceil,
        sqrt = math.sqrt,
        pow = math.pow,
    },
    -- Safe string functions
    string = {
        match = string.match,
        find = string.find,
        sub = string.sub,
        gmatch = string.gmatch,
        upper = string.upper,
        lower = string.lower,
        len = string.len,
        format = string.format,
    },
    -- Safe utilities
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    -- Nil globals (explicitly denied)
    os = nil,
    io = nil,
    debug = nil,
    getfenv = nil,
    setfenv = nil,
    loadfile = nil,
    dofile = nil,
    require = nil,
    package = nil,
    collectgarbage = nil,
}

-- Create sandboxed function with restricted globals
local function sandbox_function(fn)
    if not fn then return nil end
    if setfenv then
        setfenv(fn, GUARD_SANDBOX)
    end
    return fn
end

function ProfileCompiler:_compile_guards(compiled)
    for state_id, state in pairs(compiled.states) do
        if state.transitions then
            for event_name, transitions in pairs(state.transitions) do
                for _, trans in ipairs(transitions) do
                    if trans.guard and type(trans.guard) == "string" then
                        local fn, err = loadstring("return function(event, bb, profile, state) return " .. trans.guard .. " end")
                        if not fn then
                            table.insert(compiled.diagnostics.errors, {
                                path = state_id .. ".transitions." .. event_name .. ".guard",
                                message = "Guard compile error: " .. err
                            })
                        else
                            -- Apply sandbox before evaluating
                            trans.guard_fn = sandbox_function(fn())
                        end
                    end
                end
            end
        end
    end
end

function ProfileCompiler:_compile_actions(compiled)
    -- Profile-local actions
    if compiled.profileActions then
        for name, action_str in pairs(compiled.profileActions) do
            local fn, err = loadstring(action_str)
            if not fn then
                table.insert(compiled.diagnostics.errors, {
                    path = "actions." .. name,
                    message = "Action compile error: " .. err
                })
            else
                compiled.profileActions[name] = fn
            end
        end
    end
    
    -- State hook actions and transition actions
    for state_id, state in pairs(compiled.states) do
        for _, hook in ipairs({"onEnter", "onExit"}) do
            if state[hook] then
                local compiled_hooks = {}
                for _, action_str in ipairs(state[hook]) do
                    local core_action = action_str:match("^coreActions%.([%w_%.]+)%s*%((.*)%)%s*$")
                    if core_action and self.core_actions[core_action] then
                        -- Parse arguments with quoted string support
                        local args_str = action_str:match("^coreActions%.[%w_%.]+%s*%((.*)%)%s*$") or ""
                        local args = {}
                        if args_str ~= "" then
                            for _, arg in ipairs(split_args_quoted(args_str)) do
                                if arg:match("^%d+$") then
                                    table.insert(args, tonumber(arg))
                                elseif arg == "true" then
                                    table.insert(args, true)
                                elseif arg == "false" then
                                    table.insert(args, false)
                                elseif arg:match('^".*"$') or arg:match("^'.*'$") then
                                    table.insert(args, arg:sub(2, -2))
                                else
                                    table.insert(args, arg)
                                end
                            end
                        end
                        table.insert(compiled_hooks, {type = "core", name = core_action, args = args})
                    else
                        local fn, err = loadstring("return function(ctx) " .. action_str .. " end")
                        if not fn then
                            table.insert(compiled.diagnostics.errors, {
                                path = state_id .. "." .. hook,
                                message = "Action compile error: " .. err
                            })
                        else
                            -- Apply sandbox to inline actions
                            table.insert(compiled_hooks, {type = "inline", fn = sandbox_function(fn)})
                        end
                    end
                end
                state[hook] = compiled_hooks
            end
        end
        
        if state.transitions then
            for event_name, transitions in pairs(state.transitions) do
                for _, trans in ipairs(transitions) do
                    if trans.actions then
                        local compiled_actions = {}
                        for _, action_str in ipairs(trans.actions) do
                            local core_action = action_str:match("^coreActions%.([%w_%.]+)%s*%((.*)%)%s*$")
                            if core_action and self.core_actions[core_action] then
                                -- Parse arguments with quoted string support
                                local args_str = action_str:match("^coreActions%.[%w_%.]+%s*%((.*)%)%s*$") or ""
                                local args = {}
                                if args_str ~= "" then
                                    for _, arg in ipairs(split_args_quoted(args_str)) do
                                        if arg:match("^%d+$") then
                                            table.insert(args, tonumber(arg))
                                        elseif arg == "true" then
                                            table.insert(args, true)
                                        elseif arg == "false" then
                                            table.insert(args, false)
                                        elseif arg:match('^".*"$') or arg:match("^'.*'$") then
                                            table.insert(args, arg:sub(2, -2))
                                        else
                                            table.insert(args, arg)
                                        end
                                    end
                                end
                                table.insert(compiled_actions, {type = "core", name = core_action, args = args})
                            else
                                local fn, err = loadstring("return function(ctx) " .. action_str .. " end")
                                if not fn then
                                    table.insert(compiled.diagnostics.errors, {
                                        path = state_id .. ".transitions." .. event_name .. ".actions",
                                        message = "Action compile error: " .. err
                                    })
                                else
                                    -- Apply sandbox to inline actions
                                    table.insert(compiled_actions, {type = "inline", fn = sandbox_function(fn)})
                                end
                            end
                        end
                        trans.actions = compiled_actions
                    end
                end
            end
        end
    end
end

-- ============================================================
-- State Flattening & Transition Table Building
-- ============================================================

function ProfileCompiler:_flatten_states(ast)
    local flat = {}
    local regions = {}
    
    local function process_states(states, parent_path, parent_region)
        for state_name, state in pairs(states) do
            local full_path = parent_path == "" and state_name or (parent_path .. "." .. state_name)
            local state_copy = {
                id = full_path,
                name = state_name,
                type = state.type,
                parent = parent_path,
                region = parent_region,
                meta = state.meta,
                onEnter = state.onEnter or {},
                onExit = state.onExit or {},
                transitions = {}
            }
            
            if state.transitions then
                for _, trans in ipairs(state.transitions) do
                    if not state_copy.transitions[trans.event] then
                        state_copy.transitions[trans.event] = {}
                    end
                    table.insert(state_copy.transitions[trans.event], {
                        guard = trans.guard,
                        target = trans.target,
                        actions = trans.actions or {}
                    })
                end
            end
            
            flat[full_path] = state_copy
            
            if state.states then
                process_states(state.states, full_path, parent_region)
            end
            
            if state.regions then
                for region_name, region in pairs(state.regions) do
                    local region_path = full_path .. ".regions." .. region_name
                    if region.states then
                        process_states(region.states, region_path, region_name)
                    end
                end
            end
        end
    end
    
    -- Process top-level regions (Questing, Survival, Logistics)
    for region_name, region in pairs(ast.states) do
        -- Add region to regions table
        if region.type == "exclusive" or region.type == "parallel" then
            regions[region_name] = {
                type = region.type,
                initial = region.initial,
                regions = region.regions
            }
        end
        if region.states then
            process_states(region.states, "", region_name)
        end
    end
    
    return flat, regions
end

-- ============================================================
-- Routing Policy Loading
-- ============================================================

function ProfileCompiler:_load_routing_policies(ast, compiled)
    local policies = {}
    local policy_names = {}
    
    -- Collect all referenced policy names from compiled actions
    for state_id, state in pairs(compiled.states) do
        for _, hook in ipairs({"onEnter", "onExit"}) do
            for _, action in ipairs(state[hook] or {}) do
                if action.type == "core" and action.name == "nav.followPolicy" then
                    policy_names[action.args[1]] = true
                end
            end
        end
        if state.transitions then
            for _, transitions in pairs(state.transitions) do
                for _, trans in ipairs(transitions) do
                    if trans.actions then
                        for _, action in ipairs(trans.actions) do
                            if action.type == "core" and action.name == "nav.followPolicy" then
                                policy_names[action.args[1]] = true
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Load each policy
    for name in pairs(policy_names) do
        local policy = self.policy_loader and self.policy_loader:load(name)
        if policy then
            policies[name] = policy
        end
    end
    
    return policies
end

-- ============================================================
-- Main Compile API
-- ============================================================

function ProfileCompiler.new(quest_registry, policy_loader, core_actions)
    return setmetatable({
        quest_registry = quest_registry,
        policy_loader = policy_loader,
        core_actions = core_actions or {}
    }, ProfileCompiler)
end

function ProfileCompiler:compile(yaml_string)
    local diagnostics = {errors = {}, warnings = {}}
    
    -- Stage 1: Parse YAML
    local ast
    local ok, err = pcall(function()
        ast = ProfileCompiler.parseYAML(yaml_string)
    end)
    if not ok then
        table.insert(diagnostics.errors, {
            path = "parse",
            message = "YAML parse error: " .. tostring(err)
        })
        return {ok = false, diagnostics = diagnostics}
    end
    
    -- Stage 2: Schema validation
    self:_validate_schema(ast, diagnostics)
    
    -- Stage 3: Semantic validation
    self:_validate_references(ast, diagnostics)
    
    if #diagnostics.errors > 0 then
        return {ok = false, diagnostics = diagnostics}
    end
    
    -- Stage 4: Flatten states
    local flat_states, regions = self:_flatten_states(ast)
    
    -- Stage 5: Build compiled profile
    local compiled = {
        profile = {
            id = ast.profile.id,
            name = ast.profile.name,
            author = ast.profile.author,
            expansion = ast.profile.expansion,
            faction = ast.profile.faction,
            race = ast.profile.race,
            class = ast.profile.class,
            levelRange = ast.profile.levelRange,
        },
        variables = ast.variables or {},
        states = flat_states,
        regions = regions,
        coreActions = self.core_actions,
        profileActions = ast.actions or {},
        routingPolicies = {},
        diagnostics = diagnostics
    }
    
    -- Stage 6: Compile guards
    self:_compile_guards(compiled)
    
    -- Stage 7: Compile actions
    self:_compile_actions(compiled)
    
    -- Stage 8: Load routing policies
    compiled.routingPolicies = self:_load_routing_policies(ast, compiled)
    
    -- Final error check
    if #compiled.diagnostics.errors > 0 then
        return {ok = false, diagnostics = compiled.diagnostics}
    end
    
    return {ok = true, compiled = compiled, diagnostics = diagnostics}
end

-- ============================================================
-- CompiledProfile Serialization (for hot-reload)
-- ============================================================

function ProfileCompiler.serialize(compiled)
    local serializable = {
        profile = compiled.profile,
        variables = compiled.variables,
        states = {},
        regions = compiled.regions,
        coreActions = compiled.coreActions,
        profileActions = compiled.profileActions,
        routingPolicies = compiled.routingPolicies,
        schemaVersion = "2.0"
    }
    
    for state_id, state in pairs(compiled.states) do
        serializable.states[state_id] = {
            id = state.id,
            name = state.name,
            type = state.type,
            parent = state.parent,
            region = state.region,
            meta = state.meta,
            onEnter = state.onEnter,
            onExit = state.onExit,
            transitions = state.transitions
        }
    end
    
    return JSON.encode(serializable)
end

function ProfileCompiler.deserialize(json_string)
    return JSON.decode(json_string)
end

return ProfileCompiler