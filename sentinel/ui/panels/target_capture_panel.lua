-- sentinel/ui/panels/target_capture_panel.lua
-- Panel for capturing NPC data from current target

local SentinelUI = require("shared/ui/sentinel_ui")
local QueryClient = require("runtime/query_client")

local TargetCapturePanel = {}
TargetCapturePanel.__index = TargetCapturePanel

function TargetCapturePanel:new(blackboard, event_bus)
    local o = setmetatable({}, TargetCapturePanel)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._ui = nil
    o._query_client = QueryClient.new()
    o._current_target = nil
    o._npc_data = nil
    o._is_fetching = false
    return o
end

function TargetCapturePanel:init()
    self._ui = SentinelUI.new({
        id = "target_capture_panel",
        title = "Target Capture",
        default_x = 200,
        default_y = 200,
        default_w = 400,
        default_h = 500,
        theme = "sentinel",
    })

    -- Main tab
    self._ui:add_tab({ id = "main", label = "Main" }, function(t)
        t:slider_list({
            label = "Target Info",
            elements = {
                { element = self._ui.menu.label("Target: None", "target_capture_target_label"), label = "" },
                { element = self._ui.menu.label("Type: Unknown", "target_capture_type_label"), label = "" },
            }
        })
        -- Store labels for later update
        self._target_label = self._ui.menu.get_label("target_capture_target_label")
        self._type_label = self._ui.menu.get_label("target_capture_type_label")

        t:button({
            label = "Capture NPC",
            callback = function()
                self:_capture_current_target()
            end,
            id = "target_capture_capture_button"
        })

        t:label({
            label = "Status: Ready",
            id = "target_capture_status_label"
        })
        self._status_label = self._ui.menu.get_label("target_capture_status_label")

        t:custom_render({
            label = "NPC Data",
            render_fn = function(ui, y)
                return self:_render_npc_data(ui, y)
            end
        })
    end)

    return true
end

function TargetCapturePanel:_capture_current_target()
    -- Get current target from blackboard
    local target = self._blackboard:get("player.target")
    if not target then
        self:_set_status("No target selected")
        return
    end

    -- Check if target is an NPC (we need to determine type)
    -- For now, we assume any unit that is not a player is an NPC
    -- We might need to check via object manager or blackboard flags
    local is_player = self._blackboard:get("player.target_is_player", false)
    if is_player then
        self:_set_status("Target is a player, cannot capture NPC data")
        return
    end

    self:_set_status("Fetching NPC data...")
    self._is_fetching = true

    -- Get the NPC entry ID, with fallback to direct target object query.
    local entry = self._blackboard:get("player.target_entry")
    if not entry and target and type(target.get_npc_id) == "function" then
        local ok, npc_id = pcall(target.get_npc_id, target)
        if ok and npc_id then
            entry = npc_id
        end
    end
    if not entry and target and type(target.get_entry) == "function" then
        local ok, e = pcall(target.get_entry, target)
        if ok and e then
            entry = e
        end
    end
    if not entry then
        self:_set_status("Could not get NPC entry from target")
        self._is_fetching = false
        return
    end

    self._query_client:get_npc(entry, function(data, err)
        self._is_fetching = false
        if err then
            self:_set_status("Error: " .. err)
            return
        end
        self._npc_data = data
        self:_set_status("NPC data captured")
        self:_update_target_info(target)
    end)
end

function TargetCapturePanel:_set_status(text)
    if self._status_label then
        self._status_label:set_text(text)
    end
end

function TargetCapturePanel:_update_target_info(target)
    if self._target_label then
        local name = "Unknown"
        if type(target.get_name) == "function" then
            local ok, n = pcall(target.get_name, target)
            if ok and n then name = n end
        end
        self._target_label:set_text("Target: " .. name)
    end
    if self._type_label then
        local is_player = self._blackboard:get("player.target_is_player", false)
        local type_str = is_player and "Player" or "NPC"
        -- Check additional type hints from the target object
        if target and not is_player then
            if type(target.is_quest_unit) == "function" then
                local ok, is_qg = pcall(target.is_quest_unit, target)
                if ok and is_qg then
                    type_str = "Quest Giver"
                end
            end
            if type(target.is_vendor) == "function" then
                local ok, is_v = pcall(target.is_vendor, target)
                if ok and is_v then
                    type_str = "Vendor"
                end
            end
        end
        self._type_label:set_text("Type: " .. type_str)
    end
end

function TargetCapturePanel:_render_npc_data(ui, y)
    local window = ui.window
    local colors = ui.colors

    if not self._npc_data then
        window:render_text(0, { x = 16, y = y }, colors.text_secondary, "No NPC data captured")
        return y + 20
    end

    -- Render NPC data in a formatted way
    local function render_field(label, value)
        if value == nil then value = "N/A" end
        if type(value) == "table" then
            value = table.concat(value, ", ")
        end
        local text = label .. ": " .. tostring(value)
        local text_size = window:get_text_size(text)
        window:render_text(0, { x = 16, y = y }, colors.text_primary, text)
        return y + text_size.y + 4
    end

    y = render_field("Name", self._npc_data.name)
    y = render_field("Entry", self._npc_data.entry)
    y = render_field("Level", self._npc_data.level)
    y = render_field("Creature Type", self._npc_data.creature_type)
    y = render_field("Faction", self._npc_data.faction)
    y = render_field("Health", self._npc_data.health)
    y = render_field("Mana", self._npc_data.mana)
    y = render_field("Armor", self._npc_data.armor)
    y = render_field("Damage", self._npc_data.damage)
    y = render_field("Attack Speed", self._npc_data.attack_speed)
    y = render_field("Range", self._npc_data.range)
    y = render_field("AI Name", self._npc_data.ai_name)
    y = render_field("Bounding Radius", self._npc_data.bounding_radius)
    y = render_field("Combat Reach", self._npc_data.combat_reach)
    y = render_field("Flags", self._npc_data.flags)
    y = render_field("Flags Extra", self._npc_data.flags_extra)
    y = render_field("Verified Build", self._npc_data.verified_build)

    return y + 10
end

function TargetCapturePanel:tick(delta)
    if self._ui and self._ui.tick then
        self._ui:tick(delta)
    end
end

function TargetCapturePanel:update()
    if self._ui and self._ui.update then
        self._ui:update()
    end
end

function TargetCapturePanel:render()
    if self._ui and self._ui.render then
        self._ui:render()
    end
end

function TargetCapturePanel:render_window()
    if self._ui and self._ui.render_window then
        self._ui:render_window()
    end
end

function TargetCapturePanel:render_menu()
    if self._ui and self._ui.render_menu then
        self._ui:render_menu()
    end
end

function TargetCapturePanel:shutdown()
    self._ui = nil
    self._query_client = nil
    self._current_target = nil
    self._npc_data = nil
end

return TargetCapturePanel