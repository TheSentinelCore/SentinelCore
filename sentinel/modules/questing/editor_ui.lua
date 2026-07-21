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

local QueryClient = require("shared.query_client")
local Geometry = require("core.geometry")

-- Sylvannas UI primitives (loaded once, used throughout the rendering code)
---@type color
local Color = require("common/color")
---@type vec2
local Vec2 = require("common/geometry/vector_2")
---@type enums
local Enums = require("common/enums")

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
    if core and core.http_get then
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
    if core and core.http_post then
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
    if core and core.http_put then
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
    if core and core.http_delete then
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
    o._project = nil          -- current EditorProject (or nil)
    o._project_list = {}      -- cached project listing
    o._visible = false
    o._active_pane = "list"   -- "list" | "detail" | "picker" | "validation"
    o._selected_op_idx = nil  -- 1-based index of selected operation
    o._selected_action_idx = nil
    o._picker_mode = nil      -- "npc" | "quest" | "object" | nil
    o._picker_results = {}
    o._picker_query = ""
    o._compile_result = nil
    o._validation_diagnostics = {}
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
    self:_create_all_frames()  -- lazy creation
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
    self._frames = {}
    self._project = nil
    self._project_list = {}
end


-- ===========================================================================
-- 4. Sylvannas UI rendering (immediate-mode, called from window:render callback)
-- ===========================================================================

-- Each `---@stub` marks a method that needs UI framework integration.
-- The logic for what to render is described so you can wire it to your
-- specific frame/button/list primitives.

function QuestingEditor:_generate_id()
    return string.format("%08x", math.random(0, 0xFFFFFFFF))
end

--- Create the Sylvannas window + register the render callback.
--- Must be called outside the render callback per Sylvannas convention.
function QuestingEditor:_create_all_frames()
    if self._frames.root then return end  -- already created, skip

    -- 1. Create the main window object (OUTSIDE render callback -- required by Sylvannas)
    local window = core.menu.window.new("SentinelQuestEditor")
    window:set_initial_size(Vec2.new(820, 620))
    window:set_initial_position(Vec2.new(200, 100))
    self._frames.root = window

    -- 2. Pre-create stable menu elements (also OUTSIDE render callback)
    -- Buttons used in the detail pane header
    self._menu_el = {}
    self._menu_el.btn_save = core.menu.button()
    self._menu_el.btn_compile = core.menu.button()
    self._menu_el.btn_validate = core.menu.button()
    self._menu_el.btn_close_proj = core.menu.button()
    self._menu_el.btn_add_op = core.menu.button()
    self._menu_el.btn_new_proj = core.menu.button()
    -- Action type selector for "Add Action"
    self._menu_el.action_type_combo = core.menu.combobox(1, "editor_action_type")
    -- Picker controls
    self._menu_el.btn_picker_close = core.menu.button()
    self._menu_el.btn_picker_search = core.menu.button()
    -- NPC / Quest / Object library tree nodes
    self._menu_el.tree_npc_lib = core.menu.tree_node()
    self._menu_el.tree_quest_lib = core.menu.tree_node()
    self._menu_el.tree_obj_lib = core.menu.tree_node()
    -- Picker mode selector
    self._menu_el.picker_mode_combo = core.menu.combobox(1, "editor_picker_mode")
    -- Duplicate / Rename / Delete buttons (reused per project item)
    self._menu_el.btn_dup = core.menu.button()
    self._menu_el.btn_rename = core.menu.button()
    self._menu_el.btn_delete = core.menu.button()

    -- 3. Register the window render callback once
    local self_ref = self  -- upvalue for the callback
    core.register_on_render_window_callback(function()
        self_ref:_on_render_window()
    end)
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

--- No-op in immediate mode: the window:render callback draws every frame.
function QuestingEditor:_refresh_all_frames()
    -- In immediate mode, nothing to do -- the render callback picks up state.
end

-- ======================================================================
-- Main render dispatch and drawing helpers
-- ======================================================================

--- Called inside the window:render() callback every frame.
function QuestingEditor:_on_render_window()
    local window = self._frames.root
    if not window then return end

    window:render(
        Enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS,
        true,  -- close cross
        Color.new(0, 0, 0, 0),  -- use theme default background
        Color.new(100, 99, 150, 255),  -- border
        Enums.window_enums.window_cross_visuals.BLUE_THEME,
        0, 0, 0,  -- extra behaviour flags (0 = none)
        function()
            if not self._visible then return end

            -- Dispatch to the right pane based on _active_pane
            if self._active_pane == "list" then
                self:_draw_project_list(window)
            elseif self._active_pane == "detail" then
                self:_draw_detail_pane(window)
            elseif self._active_pane == "validation" then
                self:_draw_validation_pane(window)
            end

            -- Picker is rendered as a popup overlay on top of the current pane
            if self._active_pane == "picker" then
                self:_draw_picker_popup(window)
            end
        end
    )
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

--- Draw the project list pane (\"list\" mode).
function QuestingEditor:_draw_project_list(window)
    -- Title
    window:center_text(\"Sentinel Questing Profiles\")
    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 100))
    window:draw_next_dynamic_widget_on_new_line()

    -- Project list
    if #self._project_list == 0 then
        window:add_text_on_dynamic_pos(Color.new(150, 150, 150, 200), \"  No projects yet. Create one below.\")
        window:draw_next_dynamic_widget_on_new_line()
    else
        for i, proj in ipairs(self._project_list) do
            local ops = proj.operation_count or 0
            local updated = proj.updated_at or \"\"
            -- Truncate datetime for display: \"2026-07-20T...\" -> \"2026-07-20\"
            local date_str = string.sub(updated, 1, 10)
            local label = string.format(\"  %s  (%d ops, %s)\", proj.name, ops, date_str)

            if self:_draw_row(window, label, false) then
                self:open_project(proj.name)
            end

            -- Action buttons on the same line
            window:draw_next_dynamic_widget_on_same_line(420)
            if self._menu_el.btn_dup:render(\"Dup\") then
                self:duplicate_project(proj.name, proj.name .. \" (copy)\")
            end
            window:draw_next_dynamic_widget_on_same_line(470)
            if self._menu_el.btn_rename:render(\"Rnm\") then
                -- Simple rename: appends \"_renamed\" -- user can rename properly via editor
                self:rename_project(proj.name, proj.name .. \"_renamed\")
            end
            window:draw_next_dynamic_widget_on_same_line(530)
            if self._menu_el.btn_delete:render(\"Del\") then
                self:delete_project(proj.name)
            end

            window:draw_next_dynamic_widget_on_new_line()
        end
    end

    window:add_separator(10, 10, 0, 0, Color.new(100, 100, 150, 100))
    window:draw_next_dynamic_widget_on_new_line()

    -- New project
    if self._menu_el.btn_new_proj:render(\"+ New Project\") then
        local name = \"profile_\" .. os.date(\"%Y%m%d_%H%M%S\")
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


-- ===========================================================================
-- 5. Export
-- ===========================================================================

return QuestingEditor
