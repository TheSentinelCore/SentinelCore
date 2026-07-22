-- Sentinel Questing Editor UI
--
-- Three-layer architecture:
--   EditorClient   — HTTP client for the Rust editor API (port 3031)
--   EditorProject  — in-memory project model with operation helpers
--   QuestingEditor — public interface: state machine, frame management, picker
--
-- The Lua UI runs inside Sylvannas and communicates with a Rust HTTP server
-- (sentinel-editor binary) for all persistent operations. Game-data lookups
-- (NPCs, quests, objects) go through the existing QueryClient to port 3030.
--
-- UI primitives (button rendering, frame positioning, list scrolling) are
-- stubbed with `---@stub` markers. Wire them to whatever Sylvannas UI
-- primitives your project provides.

local QueryClient = require("shared/query_client")

-- Safe require with fallback for Sylvannas APIs (which may not be available at load time)
---@param module_name string
---@param fallback any
---@return any
local function require_or(module_name, fallback)
    local ok, mod = pcall(require, module_name)
    if ok and mod ~= nil then
        return mod
    end
    return fallback
end

-- JSON shim: the Sylvannas sandbox has no global JSON. Wrap sentinel's pure-Lua
-- core/JSON in the stringify/parse API this module uses.
local JsonLib = require_or("core/JSON", nil)
local JSON = JsonLib and {
    stringify = function(value) return (JsonLib.encode(value)) end,
    parse = function(str) return (JsonLib.decode(str)) end,
} or nil

-- Sylvannas UI primitives (loaded once, used throughout the rendering code)
---@type color
local Color = require_or("common/color", {
    new = function(r, g, b, a)
        return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 }
    end,
    white = function(a)
        return { r = 255, g = 255, b = 255, a = a or 255 }
    end,
})

---@type vec2
local Vec2 = require_or("common/geometry/vector_2", {
    new = function(x, y)
        return { x = x or 0, y = y or 0 }
    end,
})

---@type enums
local Enums = require_or("common/enums", {
    window_enums = {
        font_id = {
            FONT_SMALL = 0,
            FONT_SEMI_BIG = 0,
        },
        window_resizing_flags = {
            RESIZE_BOTH_AXIS = 0,
        },
        window_cross_visuals = {
            DEFAULT = 0,
        },
        window_behaviour_flags = {
            NO_SCROLLBAR = 0,
        },
    },
})

-- ===========================================================================
-- 1. EditorClient — HTTP wrapper for the Rust editor API
-- ===========================================================================

local EditorClient = {}
EditorClient.__index = EditorClient

function EditorClient:new(host, port)
    local o = setmetatable({}, EditorClient)
    o._host = host or "127.0.0.1"
    o._port = port or 3031
    o._query = QueryClient:new(host, 3030)  -- reused for game-data lookups
    return o
end

function EditorClient:_url(path)
    return string.format("http://%s:%d/editor%s", self._host, self._port, path)
end

--- Generic HTTP helpers (core.http_* from Sylvannas runtime).
---@return table|nil parsed JSON response, or nil on failure
function EditorClient:_get(path)
    local url = self:_url(path)
    if JSON and core and core.http_get then
        local ok, resp = pcall(core.http_get, url)
        if ok and resp then
            local ok2, decoded = pcall(JSON.parse, resp)
            if ok2 and decoded then return decoded end
        end
    end
    return nil
end

function EditorClient:_post(path, body)
    local url = self:_url(path)
    if JSON and core and core.http_post then
        local body_json = JSON.stringify(body or {})
        local ok, resp = pcall(core.http_post, url, body_json)
        if ok and resp then
            local ok2, decoded = pcall(JSON.parse, resp)
            if ok2 and decoded then return decoded end
        end
    end
    return nil
end

function EditorClient:_put(path, body)
    local url = self:_url(path)
    if JSON and core and core.http_put then
        local body_json = JSON.stringify(body or {})
        local ok, resp = pcall(core.http_put, url, body_json)
        if ok and resp then
            local ok2, decoded = pcall(JSON.parse, resp)
            if ok2 and decoded then return decoded end
        end
    end
    return nil
end

function EditorClient:_delete(path)
    local url = self:_url(path)
    if JSON and core and core.http_delete then
        local ok, resp = pcall(core.http_delete, url)
        if ok and resp then
            local ok2, decoded = pcall(JSON.parse, resp)
            if ok2 and decoded then return decoded end
        end
    end
    return nil
end

--- List all projects. Returns array of {name, path, created_at, updated_at, operation_count}.
function EditorClient:list_projects()
    return self:_get("/projects")
end

--- Create a new empty project. Returns the Project object.
---@param name string
function EditorClient:create_project(name)
    return self:_post("/projects", { name = name })
end

--- Load a project by name. Returns the full Project object (JSON with metadata, operations, etc).
---@param name string
function EditorClient:load_project(name)
    return self:_get("/projects/" .. name)
end

--- Save a project. Sends the full Project object.
---@param project table  The full project table
function EditorClient:save_project(project)
    return self:_put("/projects/" .. project.metadata.name, project)
end

--- Delete a project.
---@param name string
function EditorClient:delete_project(name)
    return self:_delete("/projects/" .. name)
end

--- Rename a project.
---@param name string
---@param new_name string
function EditorClient:rename_project(name, new_name)
    return self:_post("/projects/" .. name .. "/rename", { new_name = new_name })
end

--- Duplicate a project.
---@param name string
---@param new_name string
function EditorClient:duplicate_project(name, new_name)
    return self:_post("/projects/" .. name .. "/duplicate", { new_name = new_name })
end

--- Compile a project. Returns {profile_json, operation_count, diagnostics}.
---@param name string
function EditorClient:compile_project(name)
    return self:_post("/projects/" .. name .. "/compile", {})
end

--- Validate a project. Returns array of {severity, code, message, entity?, action?}.
---@param name string
function EditorClient:validate_project(name)
    return self:_post("/projects/" .. name .. "/validate", {})
end

--- Undo the last command. Returns { description }.
---@param name string
function EditorClient:undo(name)
    return self:_post("/projects/" .. name .. "/undo", {})
end

--- Redo the last undone command. Returns { description }.
---@param name string
function EditorClient:redo(name)
    return self:_post("/projects/" .. name .. "/redo", {})
end

--- Get undo/redo history state. Returns { can_undo, can_redo, undo_description, redo_description }.
---@param name string
function EditorClient:get_history(name)
    return self:_get("/projects/" .. name .. "/history")
end

--- Add an operation through the command system.
---@param name string project name
---@param operation table operation object
function EditorClient:add_operation_via_command(name, operation)
    return self:_post("/projects/" .. name .. "/add-operation", { operation = operation })
end

--- Remove an operation through the command system.
---@param name string project name
---@param index number 0-based index
function EditorClient:remove_operation_via_command(name, index)
    return self:_post("/projects/" .. name .. "/remove-operation", { index = index })
end

--- Modify an operation through the command system.
---@param name string project name
---@param index number 0-based index
---@param operation table new operation object
function EditorClient:modify_operation_via_command(name, index, operation)
    return self:_post("/projects/" .. name .. "/modify-operation", { index = index, operation = operation })
end

--- Add an action to an operation through the command system.
---@param name string project name
---@param op_index number 0-based operation index
---@param action table action object
function EditorClient:add_action_via_command(name, op_index, action)
    return self:_post("/projects/" .. name .. "/add-action", { op_index = op_index, action = action })
end

--- Remove an action from an operation through the command system.
---@param name string project name
---@param op_index number 0-based operation index
---@param index number 0-based action index
function EditorClient:remove_action_via_command(name, op_index, index)
    return self:_post("/projects/" .. name .. "/remove-action", { op_index = op_index, index = index })
end

--- Modify an action through the command system.
---@param name string project name
---@param op_index number 0-based operation index
---@param action_index number 0-based action index
---@param action table new action object
function EditorClient:modify_action_via_command(name, op_index, action_index, action)
    return self:_post("/projects/" .. name .. "/modify-action", { op_index = op_index, action_index = action_index, action = action })
end

--- Reload a full project from the server (re-fetch after mutations).
---@param name string
function EditorClient:reload_project(name)
    return self:_get("/projects/" .. name)
end

--- Search NPCs via QueryClient.
---@param query string
function EditorClient:search_npcs(query)
    return self._query:search_npcs(query)
end

--- Search quests via QueryClient.
---@param query string
function EditorClient:search_quests(query)
    return self._query:search_quests(query)
end

--- Search objects via QueryClient.
---@param query string
function EditorClient:search_objects(query)
    return self._query:search_objects(query)
end

function EditorClient:get_npc(entry)
    return self._query:get_npc(entry)
end

function EditorClient:get_quest(quest_id)
    return self._query:get_quest(quest_id)
end

function EditorClient:get_object(entry)
    return self._query:get_object(entry)
end


-- ===========================================================================
-- 2. EditorProject — in-memory project model with helpers
-- ===========================================================================

local EditorProject = {}
EditorProject.__index = EditorProject

--- Wrap a raw project table with helper methods.
---@param raw table  Raw deserialized Project JSON
function EditorProject:new(raw)
    local o = setmetatable({}, EditorProject)
    o._data = raw
    o._dirty = false
    o._original_json = JSON.stringify(raw)  -- for dirty detection
    return o
end

--- Access the raw project data.
function EditorProject:raw()
    return self._data
end

function EditorProject:name()
    return self._data.metadata.name
end

function EditorProject:is_dirty()
    return self._dirty
end

--- Mark as clean (after save).
function EditorProject:mark_clean()
    self._dirty = false
    self._original_json = JSON.stringify(self._data)
end

-- ---- Operation helpers ------------------------------------------------

function EditorProject:operations()
    return self._data.operations or {}
end

--- Add a new operation at the end.
---@param op table Operation object (must have id, label, actions array)
function EditorProject:add_operation(op)
    if not self._data.operations then
        self._data.operations = {}
    end
    table.insert(self._data.operations, op)
    self._dirty = true
end

--- Insert an operation at a specific index (1-based).
function EditorProject:insert_operation(idx, op)
    if not self._data.operations then
        self._data.operations = {}
    end
    table.insert(self._data.operations, idx, op)
    self._dirty = true
end

--- Remove an operation by index (1-based).
function EditorProject:remove_operation(idx)
    if self._data.operations then
        table.remove(self._data.operations, idx)
        self._dirty = true
    end
end

--- Move an operation from index `from` to index `to`.
function EditorProject:move_operation(from, to)
    if not self._data.operations then return end
    local ops = self._data.operations
    if from < 1 or from > #ops or to < 1 or to > #ops then return end
    local op = table.remove(ops, from)
    table.insert(ops, to, op)
    self._dirty = true
end

---@return number Number of operations
function EditorProject:operation_count()
    return self._data.operations and #self._data.operations or 0
end

-- ---- Action helpers ---------------------------------------------------

--- Add an action to an operation.
---@param op_idx number 1-based operation index
---@param action table ActionPayload object
function EditorProject:add_action(op_idx, action)
    local op = self:_op(op_idx)
    if op then
        if not op.actions then op.actions = {} end
        table.insert(op.actions, action)
        self._dirty = true
    end
end

--- Remove an action from an operation.
function EditorProject:remove_action(op_idx, action_idx)
    local op = self:_op(op_idx)
    if op and op.actions then
        table.remove(op.actions, action_idx)
        self._dirty = true
    end
end

--- Move an action within an operation.
function EditorProject:move_action(op_idx, from, to)
    local op = self:_op(op_idx)
    if op and op.actions then
        local acts = op.actions
        if from >= 1 and from <= #acts and to >= 1 and to <= #acts then
            local act = table.remove(acts, from)
            table.insert(acts, to, act)
            self._dirty = true
        end
    end
end

function EditorProject:_op(idx)
    if self._data.operations and idx >= 1 and idx <= #self._data.operations then
        return self._data.operations[idx]
    end
    return nil
end

-- ---- Condition helpers ------------------------------------------------

--- Set condition on an action.
---@param op_idx number
---@param action_idx number
---@param condition table Condition object (type + params) or nil to remove
function EditorProject:set_action_condition(op_idx, action_idx, condition)
    local op = self:_op(op_idx)
    if op and op.actions and action_idx >= 1 and action_idx <= #op.actions then
        op.actions[action_idx].condition = condition
        self._dirty = true
    end
end

-- ---- Variable helpers -------------------------------------------------

function EditorProject:variables()
    return self._data.variables or {}
end

function EditorProject:add_variable(var)
    if not self._data.variables then self._data.variables = {} end
    table.insert(self._data.variables, var)
    self._dirty = true
end

-- ---- NPC / Quest / Object library helpers -----------------------------

function EditorProject:npc_library()
    return self._data.npc_library or {}
end

function EditorProject:add_npc(npc_ref)
    if not self._data.npc_library then self._data.npc_library = {} end
    -- Deduplicate by entry
    for _, existing in ipairs(self._data.npc_library) do
        if existing.entry == npc_ref.entry then return end
    end
    table.insert(self._data.npc_library, npc_ref)
    self._dirty = true
end

function EditorProject:quest_library()
    return self._data.quest_library or {}
end

function EditorProject:add_quest(quest_ref)
    if not self._data.quest_library then self._data.quest_library = {} end
    for _, existing in ipairs(self._data.quest_library) do
        if existing.id == quest_ref.id then return end
    end
    table.insert(self._data.quest_library, quest_ref)
    self._dirty = true
end

function EditorProject:object_library()
    return self._data.object_library or {}
end

function EditorProject:add_object(obj_ref)
    if not self._data.object_library then self._data.object_library = {} end
    for _, existing in ipairs(self._data.object_library) do
        if existing.entry == obj_ref.entry then return end
    end
    table.insert(self._data.object_library, obj_ref)
    self._dirty = true
end

-- ---- Validation -------------------------------------------------------

function EditorProject:diagnostics()
    return self._data.diagnostics or {}
end

function EditorProject:set_diagnostics(diags)
    self._data.diagnostics = diags
end

-- ---- Settings ---------------------------------------------------------

function EditorProject:settings()
    return self._data.settings or {}
end

function EditorProject:update_settings(changes)
    for k, v in pairs(changes) do
        self._data.settings[k] = v
    end
    self._dirty = true
end


-- ===========================================================================
-- 3. QuestingEditor — public interface
-- ===========================================================================

local QuestingEditor = {}
QuestingEditor.__index = QuestingEditor

--- Create the editor.
---@param opts table Optional: {host="127.0.0.1", editor_port=3031, query_port=3030}
function QuestingEditor:new(opts)
    opts = opts or {}
    local o = setmetatable({}, QuestingEditor)
    o._client = EditorClient:new(opts.host, opts.editor_port or 3031)
    o._window_epoch = 0
    o._project = nil          -- current EditorProject (or nil)
    o._project_list = {}      -- cached project listing
    o._visible = false
    o._active_pane = "list"   -- "list" | "detail" | "picker" | "validation" | "timeline" | "console" | "inspector"
    o._selected_op_idx = nil  -- 1-based index of selected operation
    o._selected_action_idx = nil
    o._picker_mode = nil      -- "npc" | "quest" | "object" | nil
    o._picker_results = {}
    o._picker_query = ""
    o._compile_result = nil
    o._validation_diagnostics = {}
    -- Timeline panel state
    o._timeline_scroll = 0
    -- Console/log panel state
    o._execution_log = {}
    o._console_scroll_offset = 0
    o._console_collapsed = false
    -- Inspector panel state
    o._inspector_target = nil    -- "operation" | "action" | nil
    o._inspector_target_idx = nil
    o._inspector_sub_idx = nil
    -- Keyboard shortcut flags (processed once per frame)
    o._shortcuts_enabled = true
    -- Frame handles (stubs — wire to your Sylvannas UI framework)
    o._frames = {
        root = nil,
        list_pane = nil,
        detail_pane = nil,
        picker_pane = nil,
        validation_pane = nil,
    }
    return o
end

-- ======================================================================
-- 3a. Project CRUD operations
-- ======================================================================

--- Refresh the cached project list from the server.
function QuestingEditor:refresh_project_list()
    local result = self._client:list_projects()
    self._project_list = result or {}
    return self._project_list
end

--- Open a project for editing.
---@param name string
---@return boolean success
function QuestingEditor:open_project(name)
    local raw = self._client:load_project(name)
    if raw then
        self._project = EditorProject:new(raw)
        self._active_pane = "detail"
        self._selected_op_idx = nil
        self._validation_diagnostics = {}
        self._compile_result = nil
        self:_refresh_all_frames()
        self:_refresh_history_state()
        return true
    end
    return false, "Failed to load project"
end

--- Create a new project.
---@param name string
---@return boolean success
function QuestingEditor:create_project(name)
    local result = self._client:create_project(name)
    if result then
        return self:open_project(name)
    end
    return false, "Failed to create project"
end

--- Save the current project.
function QuestingEditor:save_project()
    if not self._project then return false, "No project open" end
    local result = self._client:save_project(self._project:raw())
    if result then
        self._project:mark_clean()
        self:_refresh_all_frames()
        self:_refresh_history_state()
        return true
    end
    return false, "Failed to save project"
end

--- Delete a project by name.
function QuestingEditor:delete_project(name)
    local result = self._client:delete_project(name)
    if result then
        if self._project and self._project:name() == name then
            self._project = nil
        end
        self:refresh_project_list()
        self:_refresh_all_frames()
        return true
    end
    return false, "Failed to delete project"
end

--- Rename the current project.
function QuestingEditor:rename_project(new_name)
    if not self._project then return false, "No project open" end
    local result = self._client:rename_project(self._project:name(), new_name)
    if result then
        -- Reload under new name
        return self:open_project(new_name)
    end
    return false, "Failed to rename project"
end

--- Duplicate a project.
function QuestingEditor:duplicate_project(name, new_name)
    local result = self._client:duplicate_project(name, new_name)
    if result then
        self:refresh_project_list()
        self:_refresh_all_frames()
        return true
    end
    return false, "Failed to duplicate project"
end

-- ======================================================================
-- 3b. Compilation & Validation
-- ======================================================================

--- Compile the current project.
function QuestingEditor:compile_project()
    if not self._project then return false, "No project open" end
    local result = self._client:compile_project(self._project:name())
    if result then
        self._compile_result = result
        if result.diagnostics and #result.diagnostics > 0 then
            self._project:set_diagnostics(result.diagnostics)
        end
        self._active_pane = "validation"
        self:_refresh_validation_pane()
        return true, result
    end
    return false, "Compilation failed"
end

--- Validate the current project.
function QuestingEditor:validate_project()
    if not self._project then return false, "No project open" end
    local diags = self._client:validate_project(self._project:name())
    if diags then
        self._validation_diagnostics = diags
        self._project:set_diagnostics(diags)
        self._active_pane = "validation"
        self:_refresh_validation_pane()
        return true, diags
    end
    return false, "Validation failed"
end

-- ======================================================================
-- 3c. Operation editing
-- ======================================================================

--- Select an operation by index (1-based).
function QuestingEditor:select_operation(idx)
    if not self._project then return end
    if idx >= 1 and idx <= self._project:operation_count() then
        self._selected_op_idx = idx
        self._selected_action_idx = nil
        self:_refresh_detail_pane()
    end
end

--- Add a new (empty) operation.
function QuestingEditor:add_operation()
    if not self._project then return false end
    local op = {
        id = self:_generate_id(),
        label = "New Operation",
        actions = {},
    }
    self._project:add_operation(op)
    self._selected_op_idx = self._project:operation_count()
    self:_refresh_detail_pane()
    return true
end

--- Remove the selected operation.
function QuestingEditor:remove_selected_operation()
    if not self._project or not self._selected_op_idx then return false end
    self._project:remove_operation(self._selected_op_idx)
    self._selected_op_idx = nil
    self:_refresh_detail_pane()
    return true
end

--- Move selected operation up or down.
---@param direction "up"|"down"
function QuestingEditor:move_operation(direction)
    if not self._project or not self._selected_op_idx then return end
    local idx = self._selected_op_idx
    local target = (direction == "up") and (idx - 1) or (idx + 1)
    if target < 1 or target > self._project:operation_count() then return end
    self._project:move_operation(idx, target)
    self._selected_op_idx = target
    self:_refresh_detail_pane()
end

-- ======================================================================
-- 3d. Action editing
-- ======================================================================

--- Add an action to the selected operation.
---@param action_type string e.g. "Travel", "KillTarget", "AcceptQuest", etc.
---@param params table Payload fields
function QuestingEditor:add_action(action_type, params)
    if not self._project or not self._selected_op_idx then return false end
    local action = {
        type = action_type,
        label = action_type,
        payload = params or {},
    }
    self._project:add_action(self._selected_op_idx, action)
    self._selected_action_idx = nil
    self:_refresh_detail_pane()
    return true
end

--- Remove an action from the selected operation.
function QuestingEditor:remove_action(action_idx)
    if not self._project or not self._selected_op_idx then return false end
    self._project:remove_action(self._selected_op_idx, action_idx)
    self._selected_action_idx = nil
    self:_refresh_detail_pane()
    return true
end

-- ======================================================================
-- 3e. Library management
-- ======================================================================

--- Search NPCs via QueryClient and add to library.
function QuestingEditor:search_and_add_npc(query)
    local results = self._client:search_npcs(query)
    if results then
        for _, npc in ipairs(results) do
            if self._project then
                self._project:add_npc({
                    entry = npc.entry,
                    name = npc.name,
                    subtype = npc.subtype,
                })
            end
        end
        self:_refresh_detail_pane()
        return results
    end
    return {}
end

--- Search quests via QueryClient and add to library.
function QuestingEditor:search_and_add_quest(query)
    local results = self._client:search_quests(query)
    if results then
        for _, q in ipairs(results) do
            if self._project then
                self._project:add_quest({
                    id = q.id,
                    title = q.title,
                    level = q.level,
                })
            end
        end
        self:_refresh_detail_pane()
        return results
    end
    return {}
end

--- Search objects and add to library.
function QuestingEditor:search_and_add_object(query)
    local results = self._client:search_objects(query)
    if results then
        for _, obj in ipairs(results) do
            if self._project then
                self._project:add_object({
                    entry = obj.entry,
                    name = obj.name,
                })
            end
        end
        self:_refresh_detail_pane()
        return results
    end
    return {}
end

-- ======================================================================
-- 3f. Picker (NPC/Quest/Object selector)
-- ======================================================================

--- Open the picker for a specific type.
---@param mode "npc" | "quest" | "object"
function QuestingEditor:open_picker(mode)
    self._picker_mode = mode
    self._picker_query = ""
    self._picker_results = {}
    self._active_pane = "picker"
    self:_refresh_picker_pane()
end

--- Search in the picker.
function QuestingEditor:picker_search(query)
    self._picker_query = query
    if not self._picker_mode then
        self._picker_results = {}
        return
    end

    if self._picker_mode == "npc" then
        self._picker_results = self._client:search_npcs(query) or {}
    elseif self._picker_mode == "quest" then
        self._picker_results = self._client:search_quests(query) or {}
    elseif self._picker_mode == "object" then
        self._picker_results = self._client:search_objects(query) or {}
    end
    self:_refresh_picker_pane()
end

--- Select an item from the picker to add to the library.
function QuestingEditor:picker_select(item)
    if not self._project or not self._picker_mode then return end
    if self._picker_mode == "npc" then
        self._project:add_npc({ entry = item.entry, name = item.name, subtype = item.subtype })
    elseif self._picker_mode == "quest" then
        self._project:add_quest({ id = item.id, title = item.title, level = item.level })
    elseif self._picker_mode == "object" then
        self._project:add_object({ entry = item.entry, name = item.name })
    end
    self._active_pane = "detail"
    self:_refresh_detail_pane()
end

--- Close the picker.
function QuestingEditor:close_picker()
    self._active_pane = "detail"
    self._picker_mode = nil
    self._picker_results = {}
    self:_refresh_all_frames()
end

-- ======================================================================
-- 3g. Visibility & lifecycle
-- ======================================================================

function QuestingEditor:show()
    self._visible = true
    self:refresh_project_list()
    self:_register_shortcuts()
    self:_show_all_frames()
end

function QuestingEditor:hide()
    self._visible = false
    self:_hide_all_frames()
end

function QuestingEditor:is_visible()
    return self._visible
end

--- Toggle visibility.
function QuestingEditor:toggle()
    if self._visible then self:hide() else self:show() end
end

--- Cleanup before module shutdown.
function QuestingEditor:destroy()
    self:hide()
    -- Clean up keyboard bindings if supported
    if self._shortcuts_registered and core and core.input and core.input.unbind_keyboard_event then
        core.input.unbind_keyboard_event({ key = "S", ctrl = true })
        core.input.unbind_keyboard_event({ key = "B", ctrl = true })
        core.input.unbind_keyboard_event({ key = "Z", ctrl = true })
        core.input.unbind_keyboard_event({ key = "Y", ctrl = true })
        core.input.unbind_keyboard_event({ key = "F", ctrl = true })
        core.input.unbind_keyboard_event({ key = "D", ctrl = true })
        core.input.unbind_keyboard_event({ key = "DELETE" })
        core.input.unbind_keyboard_event({ key = "F2" })
        core.input.unbind_keyboard_event({ key = "SPACE" })
    end
    self._shortcuts_registered = false
    self._frames = {}
    self._project = nil
    self._project_list = {}
end


-- ===========================================================================
-- 4. Sylvannas UI rendering (immediate-mode, called from window:begin callback)
-- ===========================================================================

-- Each `---@stub` marks a method that needs UI framework integration.
-- The logic for what to render is described so you can wire it to your
-- specific frame/button/list primitives.

function QuestingEditor:_generate_id()
    return string.format("%08x", math.random(0, 0xFFFFFFFF))
end

--- Create the Sylvannas window + menu elements.
--- MUST be called from a non-render callback (Sylvannas forbids creating
--- windows/menu elements inside render callbacks). Driven by main.lua's
--- update callback via ensure_frames_created().
--- Atomic: state is only published to self after full success, so a failure
--- leaves no half-initialized window behind and the retry reports the real
--- failing line.
function QuestingEditor:_create_all_frames()
    if self._frames.root then return end  -- already created, skip

    -- 1. Create the main window object
    self._window_epoch = self._window_epoch + 1
    local window_id = string.format("SentinelQuestEditor##%d", self._window_epoch)
    local window = core.menu.window(window_id)
    window:set_initial_size(Vec2.new(820, 620))
    window:set_initial_position(Vec2.new(200, 100))

    -- 2. Pre-create stable menu elements
    -- NOTE: core.menu.button REQUIRES a unique string id on Core 2.x (no-arg throws:
    -- "bad argument #1 to 'button' (string expected, got no value)").
    local el = {}
    el.btn_save = core.menu.button("sentinel_qe_btn_save")
    el.btn_compile = core.menu.button("sentinel_qe_btn_compile")
    el.btn_validate = core.menu.button("sentinel_qe_btn_validate")
    el.btn_close_proj = core.menu.button("sentinel_qe_btn_close_proj")
    el.btn_add_op = core.menu.button("sentinel_qe_btn_add_op")
    el.btn_new_proj = core.menu.button("sentinel_qe_btn_new_proj")
    -- Action type selector for "Add Action"
    el.action_type_combo = core.menu.combobox(1, "editor_action_type")
    -- Picker controls
    el.btn_picker_close = core.menu.button("sentinel_qe_btn_picker_close")
    el.btn_picker_search = core.menu.button("sentinel_qe_btn_picker_search")
    -- NPC / Quest / Object library tree nodes
    el.tree_npc_lib = core.menu.tree_node()
    el.tree_quest_lib = core.menu.tree_node()
    el.tree_obj_lib = core.menu.tree_node()
    -- Picker mode selector
    el.picker_mode_combo = core.menu.combobox(1, "editor_picker_mode")
    -- Duplicate / Rename / Delete buttons (reused per project item)
    el.btn_dup = core.menu.button("sentinel_qe_btn_dup")
    el.btn_rename = core.menu.button("sentinel_qe_btn_rename")
    el.btn_delete = core.menu.button("sentinel_qe_btn_delete")

    -- Tab bar buttons (panel selector) — must cover every tab _draw_tab_bar iterates
    for _, name in ipairs({ "list", "detail", "timeline", "console", "picker", "validation" }) do
        el["tab_" .. name] = core.menu.button("sentinel_qe_tab_" .. name)
    end

    -- Keyboard shortcut action buttons (invisible, triggered by input bindings)
    el.shortcut_save = core.menu.button("sentinel_qe_shortcut_save")
    el.shortcut_compile = core.menu.button("sentinel_qe_shortcut_compile")
    el.shortcut_duplicate = core.menu.button("sentinel_qe_shortcut_duplicate")
    el.shortcut_delete = core.menu.button("sentinel_qe_shortcut_delete")

    -- Inspector panel elements
    el.btn_inspect_op = core.menu.button("sentinel_qe_btn_inspect_op")
    el.btn_inspect_action = core.menu.button("sentinel_qe_btn_inspect_action")

    -- 3. Publish only after everything succeeded
    self._menu_el = el
    self._frames.root = window
end

--- Ensure the window + menu elements exist. Called every tick from main.lua's
--- update callback (a non-render context, per Sylvannas requirements).
--- No-op until the editor is shown for the first time.
function QuestingEditor:ensure_frames_created()
    if not self._visible then return end
    if self._frames.root then return end
    self:_create_all_frames()
end

function QuestingEditor:_show_all_frames()
    local w = self._frames.root
    if w then
        w:set_visibility(true)
    end
end

function QuestingEditor:_hide_all_frames()
    local w = self._frames.root
    if w then
        w:set_visibility(false)
    end
end

--- No-op in immediate mode: the window:begin callback draws every frame.
function QuestingEditor:_refresh_all_frames()
    -- In immediate mode, nothing to do -- the render callback picks up state.
end

-- ======================================================================
-- Main render dispatch and drawing helpers
-- ======================================================================

--- Register keyboard shortcuts via Sylvannas input bindings.
--- Called once when the editor is shown. Binds are cleaned up in :destroy().
function QuestingEditor:_register_shortcuts()
    if not (core and core.input and core.input.bind_keyboard_event) then
        return  -- Runtime doesn't support input bindings
    end

    -- Avoid double registration
    if self._shortcuts_registered then return end

    local self_ref = self

    local function bind(key, ctrl, shift, callback, label)
        core.input.bind_keyboard_event({
            key = key,
            ctrl = ctrl or false,
            shift = shift or false,
            callback = function()
                if self_ref._visible and self_ref._shortcuts_enabled then
                    return callback(self_ref)
                end
                return false
            end,
            description = label or key,
        })
    end

    -- Ctrl+S — Save current project
    bind("S", true, false, function(s)
        if s._project then s:save_project() end
        return true
    end, "Save project")

    -- Ctrl+B — Compile/validate current project
    bind("B", true, false, function(s)
        if s._project then s:compile_project() end
        return true
    end, "Compile project")

    -- Ctrl+Z — Undo
    bind("Z", true, false, function(s)
        if not s._project then return false end
        local result = s._client:undo(s._project:name())
        if result and result.description then
            s:_log_event("undo", "Undo: " .. result.description)
            s:_reload_current_project()
            s:_refresh_history_state()
        else
            s:_log_event("warning", "Nothing to undo")
        end
        return true
    end, "Undo")

    -- Ctrl+Y — Redo
    bind("Y", true, false, function(s)
        if not s._project then return false end
        local result = s._client:redo(s._project:name())
        if result and result.description then
            s:_log_event("redo", "Redo: " .. result.description)
            s:_reload_current_project()
            s:_refresh_history_state()
        else
            s:_log_event("warning", "Nothing to redo")
        end
        return true
    end, "Redo")

    -- Ctrl+F — Focus search in picker panel
    bind("F", true, false, function(s)
        if s._project then
            s:open_picker("npc")  -- Default to NPC picker on Ctrl+F
        end
        return true
    end, "Focus picker search")

    -- Ctrl+D — Duplicate selected operation/action
    bind("D", true, false, function(s)
        return s:_shortcut_duplicate()
    end, "Duplicate selected")

    -- Delete — Delete selected operation/action
    bind("DELETE", false, false, function(s)
        return s:_shortcut_delete()
    end, "Delete selected")

    -- F2 — Rename selected (placeholder)
    bind("F2", false, false, function(s)
        if not s._project then return false end
        if s._execution_log then
            table.insert(s._execution_log, {
                timestamp = (core and core.time and core.time()) or 0,
                event = "rename_placeholder",
                message = "Rename UI not yet implemented (selected: op " .. tostring(s._selected_op_idx)
                    .. ", action " .. tostring(s._selected_action_idx) .. ")",
            })
        end
        return true
    end, "Rename selected (placeholder)")

    -- Space — Toggle enable/disable selected operation
    bind("SPACE", false, false, function(s)
        return s:_shortcut_toggle_enable()
    end, "Toggle operation enabled")

    self._shortcuts_registered = true
end

--- Handle keyboard shortcuts via rendered button triggers (fallback for
--- environments without core.input.bind_keyboard_event).
function QuestingEditor:_handle_shortcuts()
    -- If the runtime supports native bindings, skip frame-based handling
    if self._shortcuts_registered then return end
    -- If runtime has core.input.is_key_pressed, poll it here (stub)
end

--- Duplicate the selected operation or action (Ctrl+D).
function QuestingEditor:_shortcut_duplicate()
    if not self._project then return false end
    if self._selected_op_idx then
        local ops = self._project:operations()
        local op = ops[self._selected_op_idx]
        if op then
            local dup = JSON and JSON.parse(JSON.stringify(op)) or self:_deep_copy(op)
            dup.id = self:_generate_id()
            dup.label = (dup.label or "Operation") .. " (copy)"
            self._project:insert_operation(self._selected_op_idx + 1, dup)
            self._selected_op_idx = self._selected_op_idx + 1
            self:_refresh_detail_pane()
            return true
        end
    end
    return false
end

--- Delete the selected operation or action (Delete key).
function QuestingEditor:_shortcut_delete()
    if not self._project then return false end
    if self._selected_action_idx and self._selected_op_idx then
        self:remove_action(self._selected_action_idx)
        return true
    elseif self._selected_op_idx then
        self:remove_selected_operation()
        return true
    end
    return false
end

--- Toggle enable/disable on the selected operation (Space).
function QuestingEditor:_shortcut_toggle_enable()
    if not self._project or not self._selected_op_idx then return false end
    local ops = self._project:operations()
    local op = ops[self._selected_op_idx]
    if op then
        if op.enabled == nil then
            op.enabled = false
        else
            op.enabled = not op.enabled
        end
        self._project._dirty = true
        self:_refresh_detail_pane()
        -- Log the toggle
        if self._execution_log then
            table.insert(self._execution_log, {
                timestamp = (core and core.time and core.time()) or 0,
                event = "toggle_enabled",
                message = "Operation " .. self._selected_op_idx .. " enabled=" .. tostring(op.enabled),
            })
        end
        return true
    end
    return false
end

--- Log an event to the execution console.
function QuestingEditor:_log_event(event, message)
    if self._execution_log then
        table.insert(self._execution_log, {
            timestamp = (core and core.time and core.time()) or 0,
            event = event,
            message = message or "",
        })
    end
end

--- Reload the current project data from the server (re-fetch after undo/redo/mutations).
function QuestingEditor:_reload_current_project()
    if not self._project then return end
    local raw = self._client:reload_project(self._project:name())
    if raw then
        self._project = EditorProject:new(raw)
    end
end

--- Refresh the undo/redo history state after a mutation.
function QuestingEditor:_refresh_history_state()
    if not self._project then return end
    self._client:get_history(self._project:name())
    -- Results are used implicitly by the undo/redo shortcuts.
    -- We cache if needed for menu display.
end

--- Deep-copy a table (fallback when JSON is unavailable).
function QuestingEditor:_deep_copy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[self:_deep_copy(k)] = self:_deep_copy(v)
    end
    return copy
end

--- Draw the panel tab bar at the top of the window.
function QuestingEditor:_draw_tab_bar(window)
    local tabs = { "list", "detail", "timeline", "console", "picker" }
    local tab_labels = {
        list = "List",
        detail = "Detail",
        timeline = "Timeline",
        console = "Console",
        picker = "Picker",
    }

    -- Only show detail/timeline/console/picker tabs when a project is loaded
    local start_idx = self._project and 1 or 1
    local end_idx = self._project and #tabs or 1

    for i = start_idx, end_idx do
        local name = tabs[i]
        local label = tab_labels[name]
        local active = (self._active_pane == name)

        window:draw_next_dynamic_widget_on_same_line((i - 1) * 90 + 10)

        -- Active tab highlight
        if active then
            local offset = window:get_current_context_dynamic_drawing_offset()
            if offset then
                window:render_rect_filled(
                    Vec2.new(offset.x - 2, offset.y - 2),
                    Vec2.new(offset.x + 86, offset.y + 22),
                    Color.new(60, 60, 140, 100),
                    2.0
                )
            end
        end

        local btn = self._menu_el and self._menu_el["tab_" .. name]
        if btn and btn:render(label) then
            self._active_pane = name
            -- If switching to picker with no project, stay on list
            if name == "picker" and not self._project then
                self._active_pane = "list"
            end
            -- Open picker if switching to picker tab
            if name == "picker" and self._project then
                self:open_picker("npc")
            end
        end
    end

    window:draw_next_dynamic_widget_on_new_line()
    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 80))
    window:draw_next_dynamic_widget_on_new_line()
end

--- Called every frame from the load-time render-window callback in main.lua.
--- Frames are created ahead of time in tick context (see main.lua update
--- callback): Sylvannas menu elements must never be created inside a render
--- callback.
function QuestingEditor:_on_render_window()
    if not self._visible then return end
    local window = self._frames.root
    if not window then return end  -- frames are created in tick context (ensure_frames_created)

    -- Process keyboard shortcuts for this frame
    self:_handle_shortcuts()

    window:begin(
        Enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS,
        true,  -- close cross
        Color.new(0, 0, 0, 0),  -- use theme default background
        Color.new(100, 99, 150, 255),  -- border
        Enums.window_enums.window_cross_visuals.BLUE_THEME,
        Enums.window_enums.window_behaviour_flags.NO_SCROLLBAR,
        function()
            -- Tab bar for panel selection
            self:_draw_tab_bar(window)

            -- Dispatch to the right pane based on _active_pane
            if self._active_pane == "list" then
                self:_draw_project_list(window)
            elseif self._active_pane == "detail" then
                self:_draw_detail_pane(window)
            elseif self._active_pane == "validation" then
                self:_draw_validation_pane(window)
            elseif self._active_pane == "timeline" then
                self:_draw_timeline_pane(window)
            elseif self._active_pane == "console" then
                self:_draw_console_pane(window)
            elseif self._active_pane == "inspector" then
                self:_draw_inspector_pane(window)
            end

            -- Picker is rendered as a popup overlay on top of the current pane
            if self._active_pane == "picker" then
                self:_draw_picker_popup(window)
            end
        end
    )

    -- Sync close-cross: if the user closed the window via the cross, reflect it
    -- in Lua state so the next menu-button click re-opens instead of no-oping.
    if window.is_being_shown and not window:is_being_shown() then
        self._visible = false
    end
end

--- Draw a clickable text row. Returns true if clicked.
---@param window userdata  The Sylvannas window
---@param label string  The text to display
---@param selected boolean  Whether this row is currently selected
---@return boolean clicked
function QuestingEditor:_draw_row(window, label, selected)
    local offset = window:get_current_context_dynamic_drawing_offset()
    if not offset then return false end

    local x = offset.x
    local y = offset.y
    local row_w = 780
    local row_h = 24

    -- Background highlight for selected item
    if selected then
        window:render_rect_filled(
            Vec2.new(x, y),
            Vec2.new(x + row_w + row_w, y + row_h),
            Color.new(60, 60, 120, 80),
            2.0
        )
    end

    -- Hover highlight
    local hovered = window:is_mouse_hovering_rect(
        Vec2.new(x, y),
        Vec2.new(x + row_w, y + row_h)
    )
    if hovered and not selected then
        window:render_rect_filled(
            Vec2.new(x, y),
            Vec2.new(x + row_w, y + row_h),
            Color.new(80, 80, 100, 40),
            2.0
        )
    end

    -- Click detection
    local clicked = window:is_rect_clicked(
        Vec2.new(x, y),
        Vec2.new(x + row_w, y + row_h)
    )

    -- Draw the text (this advances the dynamic position)
    window:add_text_on_dynamic_pos(Color.new(220, 220, 220, 255), label)

    return clicked
end

--- Draw a small action icon button. Returns true if clicked.
--- Icon is drawn as text with a colored background rect.
function QuestingEditor:_draw_icon_btn(window, icon, color, size)
    size = size or 20
    local offset = window:get_current_context_dynamic_drawing_offset()
    if not offset then return false end
    local x, y = offset.x, offset.y

    window:render_rect_filled(
        Vec2.new(x, y),
        Vec2.new(x + size, y + size),
        color or Color.new(100, 100, 120, 100),
        3.0
    )
    local clicked = window:is_rect_clicked(
        Vec2.new(x, y),
        Vec2.new(x + size, y + size)
    )
    window:add_text_on_dynamic_pos(Color.new(255, 255, 255, 255), icon)

    return clicked
end

-- ---- Project list pane ------------------------------------------------

--- Draw the project list pane ("list" mode).
function QuestingEditor:_draw_project_list(window)
    -- Title
    window:center_text("Sentinel Questing Profiles")
    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 100))
    window:draw_next_dynamic_widget_on_new_line()

    -- Project list
    if #self._project_list == 0 then
        window:add_text_on_dynamic_pos(Color.new(150, 150, 150, 200), "  No projects yet. Create one below.")
        window:draw_next_dynamic_widget_on_new_line()
    else
        for i, proj in ipairs(self._project_list) do
            local ops = proj.operation_count or 0
            local updated = proj.updated_at or ""
            -- Truncate datetime for display: "2026-07-20T..." -> "2026-07-20"
            local date_str = string.sub(updated, 1, 10)
            local label = string.format("  %s  (%d ops, %s)", proj.name, ops, date_str)

            if self:_draw_row(window, label, false) then
                self:open_project(proj.name)
            end

            -- Action buttons on the same line
            window:draw_next_dynamic_widget_on_same_line(420)
            if self._menu_el.btn_dup:render("Dup") then
                self:duplicate_project(proj.name, proj.name .. " (copy)")
            end
            window:draw_next_dynamic_widget_on_same_line(470)
            if self._menu_el.btn_rename:render("Rnm") then
                -- Simple rename: appends "_renamed" -- user can rename properly via editor
                self:rename_project(proj.name, proj.name .. "_renamed")
            end
            window:draw_next_dynamic_widget_on_same_line(530)
            if self._menu_el.btn_delete:render("Del") then
                self:delete_project(proj.name)
            end

            window:draw_next_dynamic_widget_on_new_line()
        end
    end

    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 100))
    window:draw_next_dynamic_widget_on_new_line()

    -- New project
    if self._menu_el.btn_new_proj:render("+ New Project") then
        -- Sylvannas sandbox has no `os` library -- use the internal id generator
        local name = "profile_" .. self:_generate_id()
        self:create_project(name)
    end
end

-- ---- Detail pane (operation list + action editor) --------------------

--- Draw the detail pane for the currently loaded project.
function QuestingEditor:_draw_detail_pane(window)
    if not self._project then
        window:center_text("No project selected")
        return
    end

    local proj = self._project

    -- ---- 1. Project header -------------------------------------------

    local status = proj:is_dirty() and "Dirty" or "Saved"
    local header_text = string.format("Project: %s  [%s]", proj:name(), status)
    window:center_text(header_text)

    -- Toolbar buttons (same line)
    window:draw_next_dynamic_widget_on_same_line(10)
    if self._menu_el.btn_save:render("Save") then
        self:save_project()
    end
    window:draw_next_dynamic_widget_on_same_line(80)
    if self._menu_el.btn_compile:render("Compile") then
        self:compile_project()
    end
    window:draw_next_dynamic_widget_on_same_line(190)
    if self._menu_el.btn_validate:render("Validate") then
        self:validate_project()
    end
    window:draw_next_dynamic_widget_on_same_line(310)
    if self._menu_el.btn_close_proj:render("Close") then
        self._project = nil
        self._active_pane = "list"
        self:refresh_project_list()
    end

    window:draw_next_dynamic_widget_on_new_line()
    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 100))
    window:draw_next_dynamic_widget_on_new_line()

    -- ---- 2. Operation list -------------------------------------------

    window:add_text_on_dynamic_pos(Color.new(180, 180, 220, 255), "Operations:")
    window:draw_next_dynamic_widget_on_new_line()

    local ops = proj:operations()
    if #ops == 0 then
        window:add_text_on_dynamic_pos(Color.new(150, 150, 150, 200), "  (no operations yet)")
        window:draw_next_dynamic_widget_on_new_line()
    else
        for i, op in ipairs(ops) do
            local label = string.format("  %d. %s  (%d actions)", i, op.label or "", #(op.actions or {}))
            local selected = (self._selected_op_idx == i)

            if self:_draw_row(window, label, selected) then
                self:select_operation(i)
            end

            -- Re-order + delete buttons on same line
            window:draw_next_dynamic_widget_on_same_line(600)
            if self:_draw_icon_btn(window, "^", Color.new(80, 160, 80, 150), 18) then
                self:move_operation("up")
            end
            window:draw_next_dynamic_widget_on_same_line(625)
            if self:_draw_icon_btn(window, "v", Color.new(80, 160, 80, 150), 18) then
                self:move_operation("down")
            end
            window:draw_next_dynamic_widget_on_same_line(650)
            if self:_draw_icon_btn(window, "X", Color.new(200, 60, 60, 180), 18) then
                self:remove_selected_operation()
            end

            window:draw_next_dynamic_widget_on_new_line()
        end
    end

    -- Add operation button
    if self._menu_el.btn_add_op:render("+ Add Operation") then
        self:add_operation()
    end

    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 60))
    window:draw_next_dynamic_widget_on_new_line()

    -- ---- 3. Selected operation detail --------------------------------

    if self._selected_op_idx and ops[self._selected_op_idx] then
        local op = ops[self._selected_op_idx]
        window:add_text_on_dynamic_pos(Color.new(220, 220, 180, 255),
            string.format('Operation: "%s"', op.label or ""))
        window:draw_next_dynamic_widget_on_new_line()

        -- Actions within the operation
        local acts = op.actions or {}
        if #acts == 0 then
            window:add_text_on_dynamic_pos(Color.new(150, 150, 150, 200), "  (no actions)")
            window:draw_next_dynamic_widget_on_new_line()
        else
            for j, act in ipairs(acts) do
                local payload_str = self:_summarize_payload(act)
                local label = string.format("  %d. %s %s", j, act.type or "?", payload_str)
                local act_selected = (self._selected_action_idx == j)

                if self:_draw_row(window, label, act_selected) then
                    self._selected_action_idx = j
                end

                -- Delete action button
                window:draw_next_dynamic_widget_on_same_line(650)
                if self:_draw_icon_btn(window, "X", Color.new(200, 60, 60, 180), 18) then
                    self:remove_action(j)
                end

                window:draw_next_dynamic_widget_on_new_line()
            end
        end

        -- Add Action controls
        local ACTION_TYPES = {
            "Travel", "KillTarget", "AcceptQuest", "TurnInQuest",
            "InteractNpc", "LootObject", "UseItem", "Vendor",
            "Repair", "Wait", "Comment", "SetVariable",
        }
        window:draw_next_dynamic_widget_on_same_line(10)
        self._menu_el.action_type_combo:render("Add:", ACTION_TYPES)
        window:draw_next_dynamic_widget_on_same_line(300)
        if self._menu_el.btn_add_op:render("Add Action") then
            local type_idx = self._menu_el.action_type_combo:get()
            local type_name = ACTION_TYPES[type_idx] or "Travel"
            self:add_action(type_name, {})
        end
    end

    window:draw_next_dynamic_widget_on_new_line()
    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 60))
    window:draw_next_dynamic_widget_on_new_line()

    -- ---- 4. Library sections (collapsible tree nodes) ----------------

    -- NPC Library
    self._menu_el.tree_npc_lib:render("NPC Library", function()
        local npcs = proj:npc_library()
        if #npcs == 0 then
            window:add_text_on_dynamic_pos(Color.new(150, 150, 150, 200), "  (empty)")
            window:draw_next_dynamic_widget_on_new_line()
        else
            for _, npc in ipairs(npcs) do
                local txt = string.format("  %s (entry %d)", npc.name or "?", npc.entry or 0)
                window:add_text_on_dynamic_pos(Color.new(200, 200, 200, 255), txt)
                window:draw_next_dynamic_widget_on_new_line()
            end
        end
        if self._menu_el.btn_picker_search:render("+ From Picker") then
            self:open_picker("npc")
        end
    end)

    -- Quest Library
    self._menu_el.tree_quest_lib:render("Quest Library", function()
        local quests = proj:quest_library()
        if #quests == 0 then
            window:add_text_on_dynamic_pos(Color.new(150, 150, 150, 200), "  (empty)")
            window:draw_next_dynamic_widget_on_new_line()
        else
            for _, q in ipairs(quests) do
                local txt = string.format("  %s (id %d)", q.title or "?", q.id or 0)
                window:add_text_on_dynamic_pos(Color.new(200, 200, 200, 255), txt)
                window:draw_next_dynamic_widget_on_new_line()
            end
        end
        if self._menu_el.btn_picker_search:render("+ From Picker") then
            self:open_picker("quest")
        end
    end)

    -- Object Library
    self._menu_el.tree_obj_lib:render("Object Library", function()
        local objs = proj:object_library()
        if #objs == 0 then
            window:add_text_on_dynamic_pos(Color.new(150, 150, 150, 200), "  (empty)")
            window:draw_next_dynamic_widget_on_new_line()
        else
            for _, obj in ipairs(objs) do
                local txt = string.format("  %s (entry %d)", obj.name or "?", obj.entry or 0)
                window:add_text_on_dynamic_pos(Color.new(200, 200, 200, 255), txt)
                window:draw_next_dynamic_widget_on_new_line()
            end
        end
        if self._menu_el.btn_picker_search:render("+ From Picker") then
            self:open_picker("object")
        end
    end)
end

--- Summarize an action payload for display.
function QuestingEditor:_summarize_payload(action)
    if not action or not action.payload then return "" end
    local p = action.payload
    if p.target_entry then
        return string.format("-> entry %d", p.target_entry)
    elseif p.coord_x then
        return string.format("-> (%.1f, %.1f)", p.coord_x, p.coord_y or 0)
    elseif p.quest_id then
        return string.format("-> quest %d", p.quest_id)
    elseif p.npc_entry then
        return string.format("-> npc %d", p.npc_entry)
    elseif p.text then
        return string.format(": %s", string.sub(p.text, 1, 40))
    end
    return ""
end

--- No-op in immediate mode.
function QuestingEditor:_refresh_detail_pane()
    -- State changes will be reflected on the next frame's render pass.
end

-- ---- Picker pane -----------------------------------------------------

--- Draw the picker as a popup overlay on the current pane.
function QuestingEditor:_draw_picker_popup(window)
    if not self._picker_mode then return end

    local mode_names = { npc = "NPC", quest = "Quest", object = "Object" }
    local mode_label = mode_names[self._picker_mode] or "Item"
    local popup_size = Vec2.new(500, 350)
    local popup_pos = Vec2.new(150, 80)

    -- Popup background + border
    local popup_active = window:begin_popup(
        Color.new(20, 20, 30, 240),
        Color.new(100, 99, 150, 200),
        popup_size,
        popup_pos,
        false,   -- is_close_on_release
        false,   -- is_triggering_from_button
        function()
            -- Title
            window:center_text(string.format("Search %s", mode_label))
            window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 80))
            window:draw_next_dynamic_widget_on_new_line()

            -- Quick search buttons
            local SEARCH_PRESETS = {
                npc = {"humanoid", "raptor", "vendor", "questgiver"},
                quest = {"the", "a", "quest"},
                object = {"chest", "herb", "ore", "plant"},
            }
            local presets = SEARCH_PRESETS[self._picker_mode] or {"search"}

            window:add_text_on_dynamic_pos(Color.new(180, 180, 220, 200), "Quick search:")
            window:draw_next_dynamic_widget_on_new_line()

            for _, term in ipairs(presets) do
                window:draw_next_dynamic_widget_on_same_line(10)
                if self._menu_el.btn_picker_search:render(term) then
                    self:picker_search(term)
                end
            end

            window:draw_next_dynamic_widget_on_new_line()
            window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 60))
            window:draw_next_dynamic_widget_on_new_line()

            -- Results list
            if #self._picker_results == 0 then
                window:add_text_on_dynamic_pos(Color.new(150, 150, 150, 200),
                    "  No results. Use quick search buttons above.")
                window:draw_next_dynamic_widget_on_new_line()
            else
                for _, item in ipairs(self._picker_results) do
                    local item_label
                    if self._picker_mode == "npc" then
                        item_label = string.format("  %s (entry %d)", item.name or "?", item.entry or 0)
                    elseif self._picker_mode == "quest" then
                        item_label = string.format("  %s (id %d)", item.title or "?", item.id or 0)
                    else
                        item_label = string.format("  %s (entry %d)", item.name or "?", item.entry or 0)
                    end

                    if self:_draw_row(window, item_label, false) then
                        self:picker_select(item)
                    end

                    window:draw_next_dynamic_widget_on_new_line()
                end
            end

            window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 60))
            window:draw_next_dynamic_widget_on_new_line()

            -- Close
            if self._menu_el.btn_picker_close:render("Close") then
                self:close_picker()
            end
        end
    )

    -- If popup was closed by clicking outside, reset our state
    if not popup_active then
        self:close_picker()
    end
end

--- No-op in immediate mode.
function QuestingEditor:_refresh_picker_pane()
    -- State changes will be reflected on the next frame's render pass.
end

-- ---- Validation pane -------------------------------------------------

--- Draw validation diagnostics.
function QuestingEditor:_draw_validation_pane(window)
    window:center_text("Validation & Compilation")
    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 100))
    window:draw_next_dynamic_widget_on_new_line()

    -- Compilation result summary
    if self._compile_result then
        local ops_count = self._compile_result.operation_count or 0
        local diag_count = #(self._compile_result.diagnostics or {})
        local summary = string.format("Compiled %d operations (%d diagnostics)", ops_count, diag_count)
        window:add_text_on_dynamic_pos(Color.new(150, 220, 150, 255), summary)
        window:draw_next_dynamic_widget_on_new_line()
    end

    -- Diagnostics
    local diags = self._validation_diagnostics
    if #diags == 0 then
        window:add_text_on_dynamic_pos(Color.new(150, 150, 150, 200), "  No issues found.")
        window:draw_next_dynamic_widget_on_new_line()
    else
        -- Severity colors
        local severity_colors = {
            error   = Color.new(220, 60, 60, 255),
            warning = Color.new(220, 200, 60, 255),
            info    = Color.new(150, 150, 180, 255),
        }

        for _, d in ipairs(diags) do
            local sev = (d.severity or "info"):lower()
            local color = severity_colors[sev] or severity_colors.info
            local icon = (sev == "error") and "[!]" or (sev == "warning") and "[W]" or "[i]"
            local code = d.code or ""
            local msg = d.message or ""
            local location = ""
            if d.entity then
                location = location .. d.entity
            end
            if d.action then
                location = location .. "/" .. d.action
            end

            local text = string.format("  %s %s - %s", icon, code, msg)
            if location ~= "" then
                text = text .. string.format(" (on %s)", location)
            end

            window:add_text_on_dynamic_pos(color, text)
            window:draw_next_dynamic_widget_on_new_line()
        end
    end

    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 60))
    window:draw_next_dynamic_widget_on_new_line()

    -- Back to detail
    if self._menu_el.btn_close_proj:render("Back") then
        self._active_pane = "detail"
    end
end

--- No-op in immediate mode.
function QuestingEditor:_refresh_validation_pane()
    -- State changes will be reflected on the next frame's render pass.
end

-- ---- Timeline pane ----------------------------------------------------

--- Draw the timeline (operation order view) panel.
function QuestingEditor:_draw_timeline_pane(window)
    if not self._project then
        window:center_text("No project loaded")
        return
    end

    window:center_text("Operation Timeline")
    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 100))
    window:draw_next_dynamic_widget_on_new_line()

    local ops = self._project:operations()
    if #ops == 0 then
        window:add_text_on_dynamic_pos(Color.new(150, 150, 150, 200), "  (no operations yet — add one in Detail tab)")
        window:draw_next_dynamic_widget_on_new_line()
        return
    end

    local line_x = 60
    local node_r = 8

    for i, op in ipairs(ops) do
        local offset = window:get_current_context_dynamic_drawing_offset()
        if not offset then break end
        local y = offset.y

        -- Draw connection line from previous node
        if i > 1 then
            local prev_y = y - 38 - 2 * node_r
            window:render_line(
                Vec2.new(line_x, prev_y + node_r + 2),
                Vec2.new(line_x, y - node_r - 2),
                Color.new(100, 100, 150, 120),
                2.0
            )
            -- Draw arrow head
            window:render_line(
                Vec2.new(line_x, y - node_r - 2),
                Vec2.new(line_x - 4, y - node_r - 8),
                Color.new(100, 100, 150, 120),
                1.5
            )
            window:render_line(
                Vec2.new(line_x, y - node_r - 2),
                Vec2.new(line_x + 4, y - node_r - 8),
                Color.new(100, 100, 150, 120),
                1.5
            )
        end

        -- Node circle (colored based on status)
        local node_color = Color.new(80, 160, 80, 200)  -- default green
        if op.enabled == false then
            node_color = Color.new(120, 120, 120, 150)  -- disabled gray
        elseif op.enabled == true then
            node_color = Color.new(80, 200, 80, 255)  -- enabled bright green
        end

        -- Draw node circle
        if window.render_circle_filled then
            window:render_circle_filled(Vec2.new(line_x, y), node_r, node_color, 24)
        else
            window:render_rect_filled(
                Vec2.new(line_x - node_r, y - node_r),
                Vec2.new(line_x + node_r, y + node_r),
                node_color, node_r
            )
        end

        -- Node border for selected
        if self._selected_op_idx == i then
            window:render_rect_filled(
                Vec2.new(line_x - node_r - 2, y - node_r - 2),
                Vec2.new(line_x + node_r + 2, y + node_r + 2),
                Color.new(220, 220, 80, 150),
                2.0
            )
            -- Re-draw the inner circle on top
            if window.render_circle_filled then
                window:render_circle_filled(Vec2.new(line_x, y), node_r, node_color, 24)
            else
                window:render_rect_filled(
                    Vec2.new(line_x - node_r, y - node_r),
                    Vec2.new(line_x + node_r, y + node_r),
                    node_color, node_r
                )
            end
        end

        -- Status indicator text
        local status_str = ""
        if op.enabled == false then
            status_str = "[DISABLED]"
        elseif op.enabled == true then
            status_str = "[ON]"
        else
            status_str = "[AUTO]"
        end

        -- Operation title
        local num_actions = #(op.actions or {})
        local detail_str = num_actions == 1 and ("type: " .. (op.actions[1].type or "?")) or (num_actions .. " actions")
        local label = string.format("  %d. %s", i, op.label or "?")
        if num_actions >= 1 then
            label = label .. "  (" .. detail_str .. ")"
        end
        label = label .. "  " .. status_str

        -- Clickable row for the operation info
        if self:_draw_row(window, "    " .. label, self._selected_op_idx == i) then
            self:select_operation(i)
        end

        window:draw_next_dynamic_widget_on_new_line()

        -- Bottom spacer for next node
        window:add_text_on_dynamic_pos(Color.new(0, 0, 0, 0), " ")  -- invisible spacer
        window:draw_next_dynamic_widget_on_new_line()
    end

    -- Keyboard navigation hint
    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 60))
    window:draw_next_dynamic_widget_on_new_line()
    window:add_text_on_dynamic_pos(Color.new(120, 120, 150, 180),
        "  Use Up/Down arrows to navigate, Enter to select, Del to delete")
    window:draw_next_dynamic_widget_on_new_line()

    -- Back to detail button
    if self._menu_el.btn_close_proj:render("Back to Detail") then
        self._active_pane = "detail"
    end
end

-- ---- Console/Log pane -------------------------------------------------

--- Draw the console/log panel.
function QuestingEditor:_draw_console_pane(window)
    if not self._project then
        window:center_text("No project loaded")
        return
    end

    -- Header with collapse toggle
    window:draw_next_dynamic_widget_on_same_line(10)
    if self._menu_el.btn_inspect_op:render(self._console_collapsed and "[+] Console" or "[-] Console") then
        self._console_collapsed = not self._console_collapsed
    end
    window:draw_next_dynamic_widget_on_same_line(200)
    if self._menu_el.btn_inspect_action:render("Clear Log") then
        self:_clear_console_log()
    end
    window:draw_next_dynamic_widget_on_same_line(300)
    local log_count = #self._execution_log
    window:add_text_on_dynamic_pos(Color.new(150, 150, 200, 200), "Entries: " .. log_count)
    window:draw_next_dynamic_widget_on_new_line()

    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 60))
    window:draw_next_dynamic_widget_on_new_line()

    if self._console_collapsed then
        window:add_text_on_dynamic_pos(Color.new(120, 120, 150, 150), "  (collapsed)")
        window:draw_next_dynamic_widget_on_new_line()
        if self._menu_el.btn_close_proj:render("Back") then
            self._active_pane = "detail"
        end
        return
    end

    if log_count == 0 then
        window:add_text_on_dynamic_pos(Color.new(150, 150, 150, 200), "  (no log entries yet)")
        window:draw_next_dynamic_widget_on_new_line()
        window:add_text_on_dynamic_pos(Color.new(120, 120, 150, 150),
            "  Log entries appear here as runtime operations execute.")
        window:draw_next_dynamic_widget_on_new_line()
        window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 60))
        window:draw_next_dynamic_widget_on_new_line()
        if self._menu_el.btn_close_proj:render("Back") then
            self._active_pane = "detail"
        end
        return
    end

    -- Draw log entries (most recent first)
    local start = math.max(1, log_count - 100 + 1) -- Show last 100 by default
    for i = #self._execution_log, start, -1 do
        local entry = self._execution_log[i]
        local timestamp = entry.timestamp or 0
        local event_type = entry.event or "?"
        local message = entry.message or ""

        -- Format timestamp as [HH:MM:SS]
        local hours = math.floor(timestamp / 3600) % 24
        local minutes = math.floor(timestamp / 60) % 60
        local seconds = math.floor(timestamp) % 60
        local ts_str = string.format("[%02d:%02d:%02d]", hours, minutes, seconds)

        -- Event type color
        local event_color = Color.new(150, 150, 200, 255)
        if event_type == "error" or event_type:find("fail") then
            event_color = Color.new(220, 60, 60, 255)
        elseif event_type == "warning" then
            event_color = Color.new(220, 200, 60, 255)
        elseif event_type:find("success") or event_type:find("complete") then
            event_color = Color.new(80, 200, 80, 255)
        elseif event_type:find("skip") or event_type:find("placeholder") then
            event_color = Color.new(180, 160, 120, 200)
        end

        -- Format: [HH:MM:SS]  event_type — message
        local display_text = string.format("  %s %s — %s", ts_str, event_type, message)
        local max_chars = 120
        if #display_text > max_chars then
            display_text = string.sub(display_text, 1, max_chars - 3) + "..."
        end

        window:add_text_on_dynamic_pos(event_color, display_text)
        window:draw_next_dynamic_widget_on_new_line()

        -- Show operatio/n context if available
        if entry.operation and entry.operation ~= 0 then
            window:draw_next_dynamic_widget_on_same_line(60)
            window:add_text_on_dynamic_pos(Color.new(100, 100, 130, 160),
                "  op:" .. tostring(entry.operation) .. " state:" .. tostring(entry.state or "?"))
            window:draw_next_dynamic_widget_on_new_line()
        end
    end

    -- Scroll-to-bottom hint
    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 40))
    window:draw_next_dynamic_widget_on_new_line()
    window:add_text_on_dynamic_pos(Color.new(120, 120, 150, 150), "  (auto-scrolled to bottom)")
    window:draw_next_dynamic_widget_on_new_line()

    if self._menu_el.btn_close_proj:render("Back") then
        self._active_pane = "detail"
    end
end

--- Clear the execution log.
function QuestingEditor:_clear_console_log()
    self._execution_log = {}
end

--- Import external log entries (called by runtime context or editor client).
function QuestingEditor:import_log_entries(entries)
    if not entries or type(entries) ~= "table" then return end
    for _, entry in ipairs(entries) do
        table.insert(self._execution_log, entry)
    end
end

--- Import log from RuntimeProfile.
function QuestingEditor:load_runtime_log(profile)
    if not profile or not profile.get_log then return end
    self._execution_log = profile.get_log() or {}
end

-- ---- Inspector pane ----------------------------------------------------

--- Draw the inspector (detailed properties) panel.
function QuestingEditor:_draw_inspector_pane(window)
    if not self._project then
        window:center_text("No project loaded")
        return
    end

    window:center_text("Inspector")
    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 100))
    window:draw_next_dynamic_widget_on_new_line()

    -- Mode selector: inspect operation vs. action
    window:draw_next_dynamic_widget_on_same_line(10)
    if self._menu_el.btn_inspect_op:render("Operation") then
        self._inspector_target = "operation"
        self._inspector_target_idx = self._selected_op_idx
        self._inspector_sub_idx = nil
    end
    window:draw_next_dynamic_widget_on_same_line(120)
    if self._menu_el.btn_inspect_action:render("Action") then
        self._inspector_target = "action"
        self._inspector_target_idx = self._selected_op_idx
        self._inspector_sub_idx = self._selected_action_idx
    end

    -- Auto-update selection
    if not self._inspector_target then
        if self._selected_action_idx then
            self._inspector_target = "action"
            self._inspector_target_idx = self._selected_op_idx
            self._inspector_sub_idx = self._selected_action_idx
        elseif self._selected_op_idx then
            self._inspector_target = "operation"
            self._inspector_target_idx = self._selected_op_idx
        end
    end

    -- Rebase indices on current selection
    if self._inspector_target == "operation" then
        self._inspector_target_idx = self._selected_op_idx
    elseif self._inspector_target == "action" then
        self._inspector_target_idx = self._selected_op_idx
        self._inspector_sub_idx = self._selected_action_idx
    end

    window:draw_next_dynamic_widget_on_new_line()
    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 60))
    window:draw_next_dynamic_widget_on_new_line()

    local ops = self._project:operations()

    if self._inspector_target == "operation" and self._inspector_target_idx then
        local op = ops[self._inspector_target_idx]
        if not op then
            window:add_text_on_dynamic_pos(Color.new(180, 100, 100, 255), "  (operation not found)")
            window:draw_next_dynamic_widget_on_new_line()
        else
            self:_draw_inspector_table(window, op, "Operation")
        end
    elseif self._inspector_target == "action" and self._inspector_target_idx and self._inspector_sub_idx then
        local op = ops[self._inspector_target_idx]
        if op and op.actions then
            local action = op.actions[self._inspector_sub_idx]
            if not action then
                window:add_text_on_dynamic_pos(Color.new(180, 100, 100, 255), "  (action not found)")
                window:draw_next_dynamic_widget_on_new_line()
            else
                self:_draw_inspector_table(window, action, "Action")
            end
        else
            window:add_text_on_dynamic_pos(Color.new(180, 100, 100, 255), "  (no actions in operation)")
            window:draw_next_dynamic_widget_on_new_line()
        end
    else
        window:add_text_on_dynamic_pos(Color.new(150, 150, 150, 200), "  Select a target to inspect")
        window:draw_next_dynamic_widget_on_new_line()
        window:add_text_on_dynamic_pos(Color.new(120, 120, 150, 150),
            "  Click Operation or Action above, or select an item from the Detail tab first.")
        window:draw_next_dynamic_widget_on_new_line()
    end

    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 60))
    window:draw_next_dynamic_widget_on_new_line()

    -- Back to detail
    if self._menu_el.btn_close_proj:render("Back to Detail") then
        self._active_pane = "detail"
    end
end

--- Draw a structured property table for a given target table.
---@param window userdata
---@param target table The object to inspect (operation or action)
---@param title string Label shown at the top
function QuestingEditor:_draw_inspector_table(window, target, title)
    -- Title
    window:add_text_on_dynamic_pos(Color.new(220, 220, 180, 255), string.format("  [%s]", title))
    window:draw_next_dynamic_widget_on_new_line()

    -- Walk all fields in a deterministic order
    local ordered_keys = {
        "id", "label", "type", "enabled", -- primary fields
        "aspect", "next_condition", "condition_id", -- operation fields
        "condition", "payload", "tolerance", -- action/condition fields
    }

    -- First, render known fields in order
    local rendered = {}
    for _, key in ipairs(ordered_keys) do
        if target[key] ~= nil then
            self:_draw_inspector_field(window, key, target[key])
            rendered[key] = true
        end
    end

    -- Then render any remaining fields
    for key, value in pairs(target) do
        if not rendered[key] then
            self:_draw_inspector_field(window, key, value)
        end
    end
end

--- Draw a single field: key = type value.
function QuestingEditor:_draw_inspector_field(window, key, value)
    local vtype = type(value)
    local value_str = ""

    if vtype == "nil" then
        value_str = "nil"
    elseif vtype == "number" then
        value_str = tostring(value)
    elseif vtype == "boolean" then
        value_str = value and "true" or "false"
    elseif vtype == "string" then
        value_str = '"' .. value .. '"'
    elseif vtype == "table" then
        value_str = self:_serialize_inline(value)
    else
        value_str = tostring(value)
    end

    -- Truncate long values
    if #value_str > 100 then
        value_str = string.sub(value_str, 1, 100) .. "..."
    end

    -- Format:   key: type = value
    local display = string.format("  %s: %s = %s", key, vtype, value_str)
    local color = Color.new(180, 200, 220, 255)

    window:add_text_on_dynamic_pos(color, display)
    window:draw_next_dynamic_widget_on_new_line()
end

--- Serialize a small table into an inline representation for the inspector.
function QuestingEditor:_serialize_inline(t)
    if type(t) ~= "table" then return tostring(t) end

    -- Check if empty
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    if count == 0 then
        return "{}"
    end

    -- Check if array-like
    local is_array = true
    for k in pairs(t) do
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
            is_array = false
        end
    end

    if is_array then
        local parts = {}
        for i = 1, math.min(#t, 3) do
            parts[i] = self:serialize_value(t[i])
        end
        local text = "{ "
        for i, p in ipairs(parts) do
            if i > 1 then text = text .. ", " end
            text = text .. p
        end
        if #t > 3 then
            text = text .. ", ... } " .. #t
        else
            text = text .. " }"
        end
        return text
    end

    -- Mixed table: show up to 3 key-value pairs
    local parts = {}
    local i = 0
    for k, v in pairs(t) do
        if i >= 3 then break end
        i = i + 1
        parts[i] = tostring(k) .. ":" .. self:serialize_value(v)
    end
    local text = "{ "
    for i, p in ipairs(parts) do
        if i > 1 then text = text .. ", " end
        text = text .. p
    end
    if count > 3 then
        text = text .. ", +" .. (count - 3)
    end
    text = text .. " }"
    return text
end

--- Serialize a single value for the inspector display.
function QuestingEditor:serialize_value(v)
    if v == nil then return "nil" end
    if type(v) == "string" then return '"' .. v .. '"' end
    if type(v) == "number" then return tostring(v) end
    if type(v) == "boolean" then return v and "true" or "false" end
    if type(v) == "table" then return "table(" .. #v .. ")" end
    return tostring(v)
end


-- ===========================================================================
-- 5. Export
-- ===========================================================================

return QuestingEditor
