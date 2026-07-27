-- sentinel/ui/panels/validation_status.lua
-- Auto Validation status bar (Phase 5, F19).
--
-- Renders as a thin footer bar below all IDE panels showing structural validation
-- checks for the current campaign. Not a panel — rendered by the shell.
--
-- The validators are heuristic structural checks against the campaign plan:
-- they DON'T run the profile. Each check produces a status: "pass", "warn",
-- "fail", or "pending".

local Theme = require("ui/theme")

-- Approximate character width for layout maths (same constant the panels use); real glyph
-- measurement only exists inside a render callback.
local CHAR_W = 7

local ValidationStatus = {}
ValidationStatus.__index = ValidationStatus

-- ============================================================================
-- Construction
-- ============================================================================

local DEFAULT_CHECKS = {
    { id = "campaign_loaded", label = "Campaign loaded", status = "pending", detail = "" },
    { id = "nodes_valid",     label = "All nodes valid", status = "pending", detail = "" },
    { id = "edges_valid",     label = "Edges connected", status = "pending", detail = "" },
    { id = "conditions_valid", label = "Conditions match", status = "pending", detail = "" },
    { id = "variables_valid", label = "Variables defined", status = "pending", detail = "" },
    { id = "quests_complete", label = "Quest chain complete", status = "pending", detail = "" },
}

function ValidationStatus.new()
    -- Deep-copy the default checks so each instance owns its own state
    local checks = {}
    for _, c in ipairs(DEFAULT_CHECKS) do
        table.insert(checks, {
            id = c.id, label = c.label, status = c.status, detail = c.detail,
        })
    end

    return setmetatable({
        checks = checks,
        diagnostics = nil,   -- editor diagnostics from POST /editor/campaigns/{name}/validate
        active = false,      -- toggle visibility
        summary = "",        -- e.g. "4/6 checks pass"
        expanded_check = nil, -- id of check showing detail dropdown
        expanded_diagnostic = nil, -- index of expanded diagnostic
        _dirty = true,
    }, ValidationStatus)
end

-- ============================================================================
-- Toggle
-- ============================================================================

---Toggle the validation bar visibility.
---@return boolean new visibility
function ValidationStatus:toggle()
    self.active = not self.active
    if not self.active then
        self.expanded_check = nil
    end
    self._dirty = true
    return self.active
end

-- ============================================================================
-- Validators
-- ============================================================================

---Run a single structural check by id.
---@param check_id string
---@param campaign_plan table|nil { nodes?, edges?, conditions?, variables? }
---@return string status "pass"|"warn"|"fail"|"pending"
---@return string detail human-readable detail
function ValidationStatus:_run_check(check_id, campaign_plan)
    if not campaign_plan then return "pending", "" end

    local nodes = campaign_plan.nodes or {}
    local edges = campaign_plan.edges or {}

    if check_id == "campaign_loaded" then
        if campaign_plan.name and campaign_plan.name ~= "" then
            return "pass", "Campaign: " .. tostring(campaign_plan.name)
        end
        return "fail", "No campaign data loaded"

    elseif check_id == "nodes_valid" then
        if #nodes == 0 then return "warn", "No nodes defined" end
        local invalid = 0
        for _, node in ipairs(nodes) do
            if not node.type then invalid = invalid + 1 end
        end
        if invalid == 0 then
            return "pass", string.format("%d nodes — all valid", #nodes)
        end
        return "fail", string.format("%d node(s) missing type field", invalid)

    elseif check_id == "edges_valid" then
        if #edges == 0 then return "warn", "No edges defined" end
        -- Build node id index
        local node_ids = {}
        for _, node in ipairs(nodes) do
            node_ids[node.id] = true
        end
        local dangling = 0
        for _, edge in ipairs(edges) do
            if not node_ids[edge.from] or not node_ids[edge.to] then
                dangling = dangling + 1
            end
        end
        if dangling == 0 then
            return "pass", string.format("%d edges — all connected", #edges)
        end
        return "fail", string.format("%d edge(s) reference missing nodes", dangling)

    elseif check_id == "conditions_valid" then
        local conditions = campaign_plan.conditions or {}
        if #conditions == 0 then return "warn", "No conditions to check" end
        -- Check referenced condition GUIDs exist
        local cond_index = {}
        for _, cond in ipairs(conditions) do
            cond_index[cond.guid or cond.id] = true
        end
        local missing = 0
        for _, edge in ipairs(edges) do
            if edge.guard and not cond_index[edge.guard] then
                missing = missing + 1
            end
        end
        if missing == 0 then
            return "pass", string.format("%d condition(s) — all resolve", #conditions)
        end
        return "fail", string.format("%d edge(s) reference unknown conditions", missing)

    elseif check_id == "variables_valid" then
        local variables = campaign_plan.variables or {}
        local var_index = {}
        for _, v in ipairs(variables) do
            var_index[v.name or ""] = true
        end
        -- Check variable references in node intents
        local unresolved = 0
        for _, node in ipairs(nodes) do
            if node.intent then
                for k, v in pairs(node.intent) do
                    if type(v) == "string" and v:match("^{%s*$") then
                        -- Var reference like {var_name}
                        local var_name = v:match("^{%s*(.-)%s*}$")
                        if var_name and not var_index[var_name] then
                            unresolved = unresolved + 1
                        end
                    end
                end
            end
        end
        if unresolved == 0 then
            return "pass", string.format("%d variable(s) defined", #variables)
        end
        return "fail", string.format("%d unresolved variable reference(s)", unresolved)

    elseif check_id == "quests_complete" then
        if #nodes == 0 then return "warn", "No nodes to check" end
        -- Check that the quest chain terminates in TurnIn nodes
        local has_turnin = false
        local has_accept = false
        for _, node in ipairs(nodes) do
            if node.type == "questing.TurnIn" then has_turnin = true end
            if node.type == "questing.AcceptQuest" then has_accept = true end
        end
        if not has_accept then return "warn", "No AcceptQuest nodes found" end
        if not has_turnin then return "warn", "No TurnIn nodes found — chain may not terminate" end
        return "pass", "Quest chain terminates in TurnIn nodes"
    end

    return "pending", ""
end

---Run all structural checks against a campaign plan.
---@param campaign_plan table|nil
function ValidationStatus:run_all(campaign_plan)
    for _, check in ipairs(self.checks) do
        local status, detail = self:_run_check(check.id, campaign_plan)
        check.status = status
        check.detail = detail
    end
    self:update_summary()
    self._dirty = true
end

---Run a single check by id.
---@param check_id string
---@param campaign_plan table|nil
function ValidationStatus:run_check(check_id, campaign_plan)
    for _, check in ipairs(self.checks) do
        if check.id == check_id then
            check.status, check.detail = self:_run_check(check_id, campaign_plan)
            self:update_summary()
            self._dirty = true
            return check.status
        end
    end
end

---Toggle expanded detail for a check.
function ValidationStatus:toggle_expand(check_id)
    if self.expanded_check == check_id then
        self.expanded_check = nil
    else
        self.expanded_check = check_id
    end
    self._dirty = true
end

---Update the summary string from current check statuses.
function ValidationStatus:update_summary()
    local pass = 0
    local total = #self.checks
    for _, check in ipairs(self.checks) do
        if check.status == "pass" then pass = pass + 1 end
    end
    self.summary = string.format("%d/%d checks pass", pass, total)
    if pass == total then
        self.summary = self.summary .. " ✓"
    end
end

---Reset all checks to pending.
function ValidationStatus:reset()
    for _, check in ipairs(self.checks) do
        check.status = "pending"
        check.detail = ""
    end
    self.summary = ""
    self.expanded_check = nil
    self.diagnostics = nil
    self.expanded_diagnostic = nil
    self._dirty = true
end

---Consume the editor's diagnostics.
---
---`GraphState.diagnostics` is the output of `POST /editor/campaigns/{name}/validate`. The bar
---displays them as the authoritative validation result and keeps its own structural checks as a
---fallback when the editor has not been asked yet.
---@param diagnostics table|nil
function ValidationStatus:set_diagnostics(diagnostics)
    local out = {}
    for _, d in ipairs(type(diagnostics) == "table" and diagnostics or {}) do
        out[#out + 1] = {
            severity = tostring(d.severity or "error"),
            code = tostring(d.code or "UNKNOWN"),
            message = tostring(d.message or ""),
            node_id = d.node_id and tostring(d.node_id) or nil,
        }
    end
    self.diagnostics = out
    self.expanded_diagnostic = nil
    self._dirty = true
end

---Toggle expanded detail for a diagnostic.
function ValidationStatus:toggle_expand_diagnostic(index)
    if self.expanded_diagnostic == index then
        self.expanded_diagnostic = nil
    else
        self.expanded_diagnostic = index
    end
    self._dirty = true
end

-- ============================================================================
-- Build — produce the view
-- ============================================================================

function ValidationStatus:build()
    local check_list = {}
    for _, check in ipairs(self.checks) do
        table.insert(check_list, {
            id = check.id,
            label = check.label,
            status = check.status,
            detail = check.detail,
            expanded = (self.expanded_check == check.id),
        })
    end

    local diag_list = {}
    for _, d in ipairs(self.diagnostics or {}) do
        table.insert(diag_list, d)
    end

    return {
        active = self.active,
        checks = check_list,
        diagnostics = diag_list,
        diagnostic_summary = #diag_list > 0
            and string.format("%d editor diagnostic(s)", #diag_list)
            or nil,
        summary = self.summary,
        expanded_check = self.expanded_check,
        expanded_diagnostic = self.expanded_diagnostic,
    }
end

-- ============================================================================
-- Build plan — produce the draw items for the footer bar
-- ============================================================================

---@param view table from build()
---@param bounds table { x, y, w, h }  — the footer bar area
---@return table { items }
function ValidationStatus.build_plan(view, bounds)
    local items = {}
    if not view.active then return { items = items } end

    local text_x = bounds.x + 12
    local content_w = math.max(0, bounds.w - 24)
    local y = bounds.y

    -- Background bar
    table.insert(items, {
        kind = "validation_bar",
        bounds = { x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h },
    })

    -- Summary text
    if view.summary and view.summary ~= "" then
        table.insert(items, {
            kind = "text", x = text_x, y = y + (bounds.h - 16) * 0.5,
            font = Theme.font.body, token = "text_primary",
            alpha = Theme.interaction.resting.text,
            text = view.summary,
        })
    end

    -- Check icons
    local cx = text_x + 180
    for _, check in ipairs(view.checks) do
        local glyph
        local token
        if check.status == "pass" then
            glyph = "✓"
            token = "success"
        elseif check.status == "warn" then
            glyph = "!"
            token = "warning"
        elseif check.status == "fail" then
            glyph = "✗"
            token = "danger"
        else
            glyph = "○"
            token = "text_muted"
        end

        -- Clickable status pill, measured per label (20px for the glyph column, label, right
        -- padding): a fixed 120px forced the renderer to truncate every label to 14 chars.
        local pill_w = 20 + #tostring(check.label or "") * CHAR_W + Theme.space.md
        table.insert(items, {
            kind = "validation_check",
            id = "validation_expand:" .. check.id,
            bounds = { x = cx, y = y, w = pill_w, h = bounds.h },
            glyph = glyph,
            label = check.label,
            token = token,
            detail = check.detail,
            expanded = check.expanded,
        })

        cx = cx + pill_w + Theme.space.xs
    end

    -- Show detail for expanded check
    if view.expanded_check then
        for _, check in ipairs(view.checks) do
            if check.id == view.expanded_check and check.detail ~= "" then
                table.insert(items, {
                    kind = "validation_detail",
                    x = text_x,
                    y = y + bounds.h,
                    text = check.detail,
                })
            end
        end
    end

    -- Editor diagnostics from POST /editor/campaigns/{name}/validate
    if view.diagnostic_summary then
        cx = cx + Theme.space.sm
        table.insert(items, {
            kind = "text", x = cx, y = y + (bounds.h - 16) * 0.5,
            font = Theme.font.body, token = "text_muted",
            alpha = Theme.interaction.resting.text,
            text = view.diagnostic_summary,
        })
        cx = cx + #view.diagnostic_summary * CHAR_W + Theme.space.md

        for idx, diag in ipairs(view.diagnostics or {}) do
            local token = (diag.severity == "error" or diag.severity == "fail") and "danger"
                          or (diag.severity == "warning" or diag.severity == "warn") and "warning"
                          or "info"
            local glyph = token == "danger" and "✗" or token == "warning" and "!" or "i"
            local label = diag.code
            local pill_w = 20 + #label * CHAR_W + Theme.space.md
            table.insert(items, {
                kind = "validation_diagnostic",
                id = "diagnostic_expand:" .. tostring(idx),
                bounds = { x = cx, y = y, w = pill_w, h = bounds.h },
                glyph = glyph,
                label = label,
                token = token,
                detail = diag.message,
                node_id = diag.node_id,
                expanded = (view.expanded_diagnostic == idx),
            })
            cx = cx + pill_w + Theme.space.xs
        end

        if view.expanded_diagnostic then
            local diag = view.diagnostics[view.expanded_diagnostic]
            if diag and diag.message ~= "" then
                table.insert(items, {
                    kind = "validation_detail",
                    x = text_x,
                    y = y + bounds.h,
                    text = diag.message,
                })
            end
        end
    end

    return { items = items }
end

-- ============================================================================
-- Render — draw the validation status bar from plan items
-- ============================================================================
-- Renders the footer bar using a handler dispatch table, matching the pattern
-- used by all panel render layers. Returns the id of any activated check, or nil.

local function require_or(module_name, fallback)
    local ok, mod = pcall(require, module_name)
    return (ok and mod ~= nil and mod) or fallback
end

local Vec2 = require_or("common/geometry/vector_2", {
    new = function(x, y) return { x = x or 0, y = y or 0 } end,
})

local function v2(x, y) return Vec2.new(x, y) end

local function centred_y(bounds, line_height)
    return bounds.y + (bounds.h - line_height) * 0.5
end

local HANDLERS = {
    validation_bar = function(window, item, _fired_ref)
        window:render_rect_filled(
            v2(item.bounds.x, item.bounds.y),
            v2(item.bounds.x + item.bounds.w, item.bounds.y + item.bounds.h),
            Theme.color.surface_raised(255), Theme.radius.none)
        window:render_rect_filled(
            v2(item.bounds.x, item.bounds.y),
            v2(item.bounds.x + item.bounds.w, item.bounds.y + 1),
            Theme.color.border(255), Theme.radius.none)
        return nil
    end,

    text = function(window, item)
        window:render_text(item.font, v2(item.x, item.y),
            Theme.color[item.token](item.alpha or 255), item.text)
        return nil
    end,

    validation_check = function(window, item)
        local mn = v2(item.bounds.x, item.bounds.y)
        local mx = v2(item.bounds.x + item.bounds.w, item.bounds.y + item.bounds.h)
        local hovered = window:is_mouse_hovering_rect(mn, mx)
        local clicked = hovered and window:is_rect_clicked(mn, mx)

        if hovered then
            window:render_rect_filled(mn, mx, Theme.color.accent_soft(120), Theme.radius.sm)
        end

        window:render_text(Theme.font.body,
            v2(item.bounds.x + 4, centred_y(item.bounds, 16)),
            Theme.color[item.token](255), item.glyph)

        -- The pill was measured for this label in build_plan, so it is drawn whole.
        local label = tostring(item.label or "")
        window:render_text(Theme.font.caption,
            v2(item.bounds.x + 20, centred_y(item.bounds, 13)),
            Theme.color[hovered and "text_primary" or "text_secondary"](255), label)

        if clicked then return item.id end
        return nil
    end,

    validation_detail = function(window, item)
        window:render_text(Theme.font.caption,
            v2(item.x, item.y + 2),
            Theme.color.text_muted(255), item.text)
        return nil
    end,

    validation_diagnostic = function(window, item)
        local mn = v2(item.bounds.x, item.bounds.y)
        local mx = v2(item.bounds.x + item.bounds.w, item.bounds.y + item.bounds.h)
        local hovered = window:is_mouse_hovering_rect(mn, mx)
        local clicked = hovered and window:is_rect_clicked(mn, mx)

        if hovered then
            window:render_rect_filled(mn, mx, Theme.color.accent_soft(120), Theme.radius.sm)
        end

        window:render_text(Theme.font.body,
            v2(item.bounds.x + 4, centred_y(item.bounds, 16)),
            Theme.color[item.token](255), item.glyph)

        local label = tostring(item.label or "")
        window:render_text(Theme.font.caption,
            v2(item.bounds.x + 20, centred_y(item.bounds, 13)),
            Theme.color[hovered and "text_primary" or "text_secondary"](255), label)

        if clicked then return item.id end
        return nil
    end,
}

---Render the validation status bar. Returns the activated action id, or nil.
---@return string|nil activated_id
function ValidationStatus.render(window, plan)
    local items = plan.items
    local fired = nil

    for i = 1, #items do
        local item = items[i]
        local handler = HANDLERS[item.kind]
        if handler then
            local activated = handler(window, item)
            fired = fired or activated
        end
    end

    return fired
end

return ValidationStatus
