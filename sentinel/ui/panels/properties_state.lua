-- sentinel/ui/panels/properties_state.lua
-- The Properties panel's view-model (NPC Inspector, Vendor Editor, Condition Editor,
-- Inventory Rules, Loot Object Editor).
--
-- The panel is context-sensitive: it displays different editors depending on what the
-- user has selected. All state lives here; `properties.lua` only renders whatever
-- `build()` returns.
--
-- Decision logic (branches, layout arithmetic) lives in `build_plan`, which is in this
-- file — the one module tests CAN reach.

local PropertiesState = {}
PropertiesState.__index = PropertiesState

-- ============================================================================
-- Construction
-- ============================================================================

function PropertiesState.new(opts)
    opts = opts or {}
    return setmetatable({
        -- Current selection context (set by shell or other panels via dispatch)
        context = nil,  -- { panel_id, selection_type, selection_id }

        -- Dynamic data (loaded by on_tick based on context)
        npc_detail = nil,     -- NpcDetail from /npc/{entry}
        vendor_info = nil,    -- VendorInfo from /vendor/{entry}
        object_info = nil,    -- ObjectInfo from /object/{entry}
        npc_spawns = nil,     -- [{ map, x, y, z }]

        -- NPC inspector tab
        npc_tab = "info",     -- "info" | "loot" | "quests" | "spawns"

        -- Vendor editor items  [{ entry, name, price, enabled, mode, threshold }]
        vendor_items = nil,

        -- Condition editor (tree of RuntimeCondition objects)
        condition_tree = nil,

        -- Inventory rules [{ entry, name, action }]
        inventory_rules = nil,
        inventory_default = nil,  -- { sell_grey, ignore_white }

        loading = false,
        error = nil,
        _dirty = true,
    }, PropertiesState)
end

-- ============================================================================
-- Mutators
-- ============================================================================

function PropertiesState:set_context(ctx)
    if ctx == nil then
        self.context = nil
        self.npc_detail = nil
        self.vendor_info = nil
        self.object_info = nil
        self.npc_spawns = nil
        self.vendor_items = nil
        self.condition_tree = nil
        self.inventory_rules = nil
        self.inventory_default = nil
        self.loading = false
        self.error = nil
        self._dirty = true
        return
    end

    if self.context
        and self.context.selection_type == ctx.selection_type
        and self.context.selection_id == ctx.selection_id then
        return  -- same selection, no change
    end

    self.context = ctx
    self.npc_detail = nil
    self.vendor_info = nil
    self.object_info = nil
    self.npc_spawns = nil
    self.vendor_items = nil
    self.condition_tree = nil
    self.inventory_rules = nil
    self.inventory_default = nil
    self.error = nil
    self.npc_tab = "info"
    self.loading = true
    self._dirty = true
end

function PropertiesState:set_npc_tab(tab)
    if self.npc_tab == tab then return end
    self.npc_tab = tab
end

-- ============================================================================
-- Reduce — map an activated control id to a command for the host
-- ============================================================================

function PropertiesState.reduce(action_id)
    if action_id == nil then return nil end

    -- NPC tab switches
    if action_id == "npc_tab_info"   then return { kind = "set_npc_tab", tab = "info" } end
    if action_id == "npc_tab_loot"   then return { kind = "set_npc_tab", tab = "loot" } end
    if action_id == "npc_tab_quests" then return { kind = "set_npc_tab", tab = "quests" } end
    if action_id == "npc_tab_spawns" then return { kind = "set_npc_tab", tab = "spawns" } end

    -- Vendor item toggles
    local prefix, id_str = action_id:match("^(.-):(.+)$")
    if prefix == "vendor_toggle" then
        return { kind = "toggle_vendor_item", entry = tonumber(id_str) }
    end

    -- Condition editor
    if action_id == "add_condition"   then return { kind = "add_condition" } end
    if action_id == "add_and_group"   then return { kind = "add_condition_group", group_type = "all" } end
    if action_id == "add_or_group"    then return { kind = "add_condition_group", group_type = "any" } end
    if action_id == "delete_condition" then return { kind = "delete_condition" } end

    -- Inventory rules
    if action_id == "add_inventory_rule"   then return { kind = "add_inventory_rule" } end
    if action_id == "clear_inventory_rules" then return { kind = "clear_inventory_rules" } end

    return nil
end

-- ============================================================================
-- Build — produce the flat view the render layer draws
-- ============================================================================

function PropertiesState:build()
    if not self.context then
        return { context_type = nil, loading = false, error = nil }
    end

    local ctype = self.context.selection_type
    local view = {
        context_type = ctype,
        selection_id = self.context.selection_id,
        loading = self.loading,
        error = self.error,
    }

    if ctype == "npc" then
        view.npc_view = {
            detail = self.npc_detail,
            tab = self.npc_tab,
            spawns = self.npc_spawns,
        }
    elseif ctype == "vendor" then
        view.vendor_view = {
            info = self.vendor_info,
            items = self.vendor_items,
        }
    elseif ctype == "object" then
        view.object_view = {
            detail = self.object_info,
        }
    elseif ctype == "condition" then
        view.condition_view = {
            tree = self.condition_tree,
        }
    elseif ctype == "inventory" then
        view.inventory_view = {
            rules = self.inventory_rules,
            default = self.inventory_default,
        }
    end

    return view
end

-- ============================================================================
-- Build plan — produce the draw items for one frame
-- ============================================================================
-- Every if/elseif/while the render layer cannot have lives here, where tests
-- can reach it. This is the same pattern ExplorerState.build_plan follows.

local CHAR_W = 7
local PAD = 12
local CONTROL_H = 28
local SECTION_H = 20
local ROW_H = 18
local SMALL_H = 14

local Theme = require("ui/theme")

local function fit(text, width)
    text = tostring(text or "")
    local max_chars = math.floor((width or 0) / CHAR_W)
    if max_chars < 1 then return "" end
    if #text <= max_chars then return text end
    if max_chars <= 3 then return text:sub(1, max_chars) end
    return text:sub(1, max_chars - 3) .. "..."
end

function PropertiesState.build_plan(view, bounds)
    local items = {}
    local text_x = bounds.x + PAD
    local content_w = math.max(0, bounds.w - PAD * 2)
    local y = bounds.y + PAD

    local function push(item) items[#items + 1] = item end

    local function text_item(font, token, str, ox, oy)
        push({
            kind = "text", x = text_x + (ox or 0), y = y + (oy or 0),
            font = Theme.font[font], token = token,
            alpha = Theme.interaction.resting.text, text = str,
        })
    end

    local function header(title, extra_y)
        push({
            kind = "section_header",
            bounds = { x = text_x, y = y, w = content_w, h = SECTION_H },
            title = title,
        })
        y = y + SECTION_H + (extra_y or Theme.space.xs)
    end

    -- -----------------------------------------------------------------------
    -- No context
    -- -----------------------------------------------------------------------
    if view.context_type == nil then
        push({
            kind = "empty_state",
            bounds = { x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h },
            title = "No Selection",
            message = "Select an NPC, vendor, object or node to inspect",
        })
        return { items = items }
    end

    if view.loading then
        text_item("body", "text_muted", "Loading...")
        return { items = items }
    end

    if view.error then
        text_item("body", "danger", "Error: " .. tostring(view.error))
        return { items = items }
    end

    -- -----------------------------------------------------------------------
    -- NPC Inspector
    -- -----------------------------------------------------------------------
    if view.context_type == "npc" then
        local nv = view.npc_view
        if not nv or not nv.detail then
            text_item("body", "text_muted", "Select an NPC to inspect")
            return { items = items }
        end

        local d = nv.detail
        text_item("title", "text_primary", fit(d.name or "NPC", content_w))
        y = y + Theme.line_height.title + Theme.space.xs

        local info = "Entry: " .. tostring(d.entry or "?")
        if d.level then info = info .. "  Level: " .. tostring(d.level) end
        text_item("body", "text_secondary", fit(info, content_w))
        y = y + Theme.line_height.body + Theme.space.xs

        if d.faction then
            text_item("caption", "text_muted", fit("Faction: " .. tostring(d.faction), content_w))
            y = y + SMALL_H
        end
        y = y + Theme.space.sm

        -- Tab bar
        local tabs = {
            { id = "npc_tab_info",   label = "Info",   sel = nv.tab == "info" },
            { id = "npc_tab_loot",   label = "Loot",   sel = nv.tab == "loot" },
            { id = "npc_tab_quests", label = "Quests", sel = nv.tab == "quests" },
            { id = "npc_tab_spawns", label = "Spawns", sel = nv.tab == "spawns" },
        }
        local tx = text_x
        for _, t in ipairs(tabs) do
            local w = #t.label * CHAR_W + Theme.space.lg
            push({ kind = "chip", id = t.id,
                bounds = { x = tx, y = y, w = w, h = CONTROL_H },
                label = t.label, selected = t.sel })
            tx = tx + w + Theme.space.sm
        end
        y = y + CONTROL_H + Theme.space.md

        -- ---- Info tab ----
        if nv.tab == "info" then
            if d.roles and #d.roles > 0 then
                header("Roles")
                text_item("body", "text_secondary", fit(table.concat(d.roles, ", "), content_w), Theme.space.sm)
                y = y + ROW_H + Theme.space.sm
            end
            if d.classification then
                header("Classification")
                text_item("body", "text_secondary", fit(d.classification, content_w), Theme.space.sm)
                y = y + ROW_H
            end

        -- ---- Spawns tab ----
        elseif nv.tab == "spawns" then
            local spawns = nv.spawns or d.positions or {}
            if #spawns > 0 then
                header("Spawns (" .. tostring(#spawns) .. ")")
                for _, sp in ipairs(spawns) do
                    local p = sp.position or sp
                    local s = string.format("  Map %s ( %.0f, %.0f, %.0f )",
                        tostring(p.map or 0), p.x or 0, p.y or 0, p.z or 0)
                    text_item("body", "text_secondary", fit(s, content_w))
                    y = y + ROW_H
                end
            else
                text_item("body", "text_muted", "No spawn data available")
                y = y + ROW_H
            end

        -- ---- Quests tab ----
        elseif nv.tab == "quests" then
            local quests = d.quests or {}
            if #quests > 0 then
                header("Quests")
                for _, q in ipairs(quests) do
                    local qn = q.title or tostring(q.id or "?")
                    text_item("body", "text_primary", fit("  " .. qn, content_w))
                    y = y + ROW_H
                end
            else
                text_item("body", "text_muted", "No quest data available")
                y = y + ROW_H
            end

        -- ---- Loot tab ----
        elseif nv.tab == "loot" then
            local loot = d.loot or {}
            if #loot > 0 then
                header("Loot Table")
                for _, entry in ipairs(loot) do
                    local chance = entry.chance and string.format("%.1f%%", entry.chance) or ""
                    local label = string.format("  [%s] %s %s",
                        tostring(entry.item or ""), entry.name or "", chance)
                    text_item("body", "text_secondary", fit(label, content_w))
                    y = y + ROW_H
                end
            else
                text_item("body", "text_muted", "No loot data available")
                y = y + ROW_H
            end
        end

        return { items = items }
    end

    -- -----------------------------------------------------------------------
    -- Vendor Editor
    -- -----------------------------------------------------------------------
    if view.context_type == "vendor" then
        local vv = view.vendor_view
        if not vv or not vv.info then
            text_item("body", "text_muted", "Select a vendor to inspect")
            return { items = items }
        end

        local info = vv.info
        text_item("title", "text_primary", fit(info.name or "Vendor", content_w))
        y = y + Theme.line_height.title + Theme.space.xs
        text_item("body", "text_secondary", fit(
            string.format("Entry: %s    Repairs: %s", tostring(info.entry or "?"),
                info.repairs and "Yes" or "No"), content_w))
        y = y + Theme.line_height.body + Theme.space.md

        local sell_items = info.sells or {}
        if #sell_items > 0 then
            header("Inventory (" .. tostring(#sell_items) .. ")")
            for _, item in ipairs(sell_items) do
                local mode_label = ""
                if item.mode == "buy" then
                    mode_label = "Buy " .. tostring(item.threshold or 0)
                elseif item.mode == "sell" then
                    mode_label = "Sell"
                else
                    mode_label = "Ignore"
                end
                local label = string.format("  [%s] %s    %s",
                    tostring(item.entry or ""), fit(item.name or "", 20), mode_label)
                text_item("body", "text_secondary", fit(label, content_w))
                y = y + ROW_H
            end
        else
            text_item("body", "text_muted", "No inventory data available")
            y = y + ROW_H
        end

        return { items = items }
    end

    -- -----------------------------------------------------------------------
    -- Loot Object Editor
    -- -----------------------------------------------------------------------
    if view.context_type == "object" then
        local ov = view.object_view
        if not ov or not ov.detail then
            text_item("body", "text_muted", "Select an object to inspect")
            return { items = items }
        end

        local obj = ov.detail
        text_item("title", "text_primary", fit(obj.name or "Object", content_w))
        y = y + Theme.line_height.title + Theme.space.xs
        text_item("body", "text_secondary", fit(
            string.format("Entry: %s    Type: %s", tostring(obj.entry or "?"), obj.kind or "?"), content_w))
        y = y + Theme.line_height.body + Theme.space.md

        if obj.position then
            local p = obj.position
            text_item("body", "text_secondary", fit(
                string.format("Map %s ( %.0f, %.0f, %.0f )",
                    tostring(p.map or 0), p.x or 0, p.y or 0, p.z or 0), content_w))
            y = y + ROW_H
        end

        if obj.respawn then
            text_item("caption", "text_muted", fit("Respawn: " .. tostring(obj.respawn) .. "s", content_w))
            y = y + SMALL_H
        end
        if obj.skill then
            text_item("caption", "text_muted", fit("Skill: " .. tostring(obj.skill), content_w))
            y = y + SMALL_H
        end

        return { items = items }
    end

    -- -----------------------------------------------------------------------
    -- Condition Editor
    -- -----------------------------------------------------------------------
    if view.context_type == "condition" then
        local cv = view.condition_view
        header("Condition: " .. (cv and cv.tree and (cv.tree.type or "?") or "None"), Theme.space.md)

        if cv and cv.tree then
            local function render_cond(cond, depth)
                if not cond then return end
                local indent_str = string.rep("  ", depth)
                local label_prefix = (depth > 0) and "  " .. indent_str or ""
                local t = cond.type

                if t == "all" or t == "any" then
                    local heading = (t == "all") and "ALL of:" or "ANY of:"
                    text_item("body", "text_primary", fit(label_prefix .. heading, content_w))
                    y = y + ROW_H
                    for _, c in ipairs(cond.conditions or {}) do render_cond(c, depth + 1) end
                elseif t == "not" then
                    text_item("body", "text_primary", fit(label_prefix .. "NOT:", content_w))
                    y = y + ROW_H
                    if cond.condition then render_cond(cond.condition, depth + 1) end
                elseif t == "quest_accepted" then
                    text_item("body", "text_secondary", fit(label_prefix .. "QuestAccepted (" .. tostring(cond.quest_id or "?") .. ")", content_w))
                    y = y + ROW_H
                elseif t == "quest_completed" then
                    text_item("body", "text_secondary", fit(label_prefix .. "QuestCompleted (" .. tostring(cond.quest_id or "?") .. ")", content_w))
                    y = y + ROW_H
                elseif t == "quest_rewarded" then
                    text_item("body", "text_secondary", fit(label_prefix .. "QuestRewarded (" .. tostring(cond.quest_id or "?") .. ")", content_w))
                    y = y + ROW_H
                elseif t == "has_item" then
                    text_item("body", "text_secondary", fit(label_prefix .. "HasItem (" .. tostring(cond.item_id or "?") .. ") x" .. tostring(cond.count or 1), content_w))
                    y = y + ROW_H
                elseif t == "level_at_least" then
                    text_item("body", "text_secondary", fit(label_prefix .. "LevelAtLeast " .. tostring(cond.level or "?"), content_w))
                    y = y + ROW_H
                elseif t == "level_below" then
                    text_item("body", "text_secondary", fit(label_prefix .. "LevelBelow " .. tostring(cond.level or "?"), content_w))
                    y = y + ROW_H
                elseif t == "class_is" then
                    text_item("body", "text_secondary", fit(label_prefix .. "ClassIs " .. tostring(cond.class or "?"), content_w))
                    y = y + ROW_H
                elseif t == "race_is" then
                    text_item("body", "text_secondary", fit(label_prefix .. "RaceIs " .. tostring(cond.race or "?"), content_w))
                    y = y + ROW_H
                elseif t == "faction_is" then
                    text_item("body", "text_secondary", fit(label_prefix .. "FactionIs " .. tostring(cond.faction or "?"), content_w))
                    y = y + ROW_H
                elseif t == "always_true" then
                    text_item("body", "text_secondary", fit(label_prefix .. "AlwaysTrue", content_w))
                    y = y + ROW_H
                else
                    text_item("body", "text_secondary", fit(label_prefix .. tostring(t or "?") .. " (" .. tostring(cond.quest_id or cond.item_id or cond.level or "?") .. ")", content_w))
                    y = y + ROW_H
                end
            end
            render_cond(cv.tree, 0)
        else
            text_item("body", "text_muted", "No condition defined")
            y = y + ROW_H
        end

        y = y + Theme.space.md
        local half = (content_w - Theme.space.sm) * 0.5
        push({ kind = "button", id = "add_condition",
            bounds = { x = text_x, y = y, w = half, h = CONTROL_H }, label = "Add Condition", variant = "secondary" })
        push({ kind = "button", id = "add_and_group",
            bounds = { x = text_x + half + Theme.space.sm, y = y, w = half, h = CONTROL_H }, label = "Add Group (AND)", variant = "ghost" })
        y = y + CONTROL_H + Theme.space.sm
        push({ kind = "button", id = "add_or_group",
            bounds = { x = text_x, y = y, w = half, h = CONTROL_H }, label = "Add Group (OR)", variant = "ghost" })
        push({ kind = "button", id = "delete_condition",
            bounds = { x = text_x + half + Theme.space.sm, y = y, w = half, h = CONTROL_H }, label = "Delete", variant = "danger" })

        return { items = items }
    end

    -- -----------------------------------------------------------------------
    -- Inventory Rules
    -- -----------------------------------------------------------------------
    if view.context_type == "inventory" then
        local iv = view.inventory_view
        header("Inventory Rules", Theme.space.md)

        local rules = (iv and iv.rules) or {}
        if #rules > 0 then
            for _, rule in ipairs(rules) do
                local a = ""
                if rule.action == "sell" then a = "Sell"
                elseif rule.action == "keep" then a = "Keep"
                elseif rule.action == "mail" then a = "Mail to Alt"
                else a = tostring(rule.action) end
                text_item("body", "text_secondary", fit(
                    string.format("  [%s] %s    %s", tostring(rule.entry or ""), fit(rule.name or "", 18), a), content_w))
                y = y + ROW_H
            end
        else
            text_item("body", "text_muted", "No item rules defined")
            y = y + ROW_H
        end

        y = y + Theme.space.sm
        header("Default Behaviour", Theme.space.xs)

        local def = (iv and iv.default) or {}
        local sell_str = (def.sell_grey ~= false) and "Sell grey" or "Keep grey"
        local white_str = def.ignore_white and "Ignore white+" or "Keep white+"
        text_item("body", "text_secondary", fit(sell_str .. "    " .. white_str, content_w))
        y = y + ROW_H + Theme.space.md

        local half = (content_w - Theme.space.sm) * 0.5
        push({ kind = "button", id = "add_inventory_rule",
            bounds = { x = text_x, y = y, w = half, h = CONTROL_H }, label = "Add Rule", variant = "primary" })
        push({ kind = "button", id = "clear_inventory_rules",
            bounds = { x = text_x + half + Theme.space.sm, y = y, w = half, h = CONTROL_H }, label = "Clear All", variant = "danger" })

        return { items = items }
    end

    -- Fallback for unknown types
    text_item("body", "text_muted", fit("Unknown selection type: " .. tostring(view.context_type), content_w))
    return { items = items }
end

return PropertiesState
