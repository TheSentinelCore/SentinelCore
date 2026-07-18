local PvPTargetSelector = {}
PvPTargetSelector.__index = PvPTargetSelector

local function safe_require(mod)
    local ok, m = pcall(require, mod)
    if ok then
        return m
    end
    return nil
end

local function num(v)
    return tonumber(v) or 0
end

local function normalize_guid(v)
    if v == nil then
        return nil
    end
    local s = tostring(v)
    if s == "" then
        return nil
    end
    return s
end

local function invoke_unit_method(unit, method, ...)
    local unit_type = type(unit)
    if unit_type ~= "table" and unit_type ~= "userdata" then
        return false, nil
    end
    local ok_get, fn = pcall(function()
        return unit[method]
    end)
    if not ok_get then
        return false, nil
    end
    if type(fn) ~= "function" then
        return false, nil
    end
    local ok, value = pcall(fn, unit, ...)
    if ok then
        return true, value
    end
    return false, nil
end

local function get_unit_guid(unit)
    local ok, guid = invoke_unit_method(unit, "get_guid")
    if not ok then
        return nil
    end
    return normalize_guid(guid)
end

local function same_unit_by_guid(a, b)
    local ga = get_unit_guid(a)
    local gb = get_unit_guid(b)
    if not ga or not gb then
        return false
    end
    return ga == gb
end

local function is_probably_player_object(obj)
    if not obj then
        return false
    end

    local okp, is_player = invoke_unit_method(obj, "is_player")
    if okp then
        return is_player == true
    end

    local ok_unit, is_unit = invoke_unit_method(obj, "is_unit")
    if ok_unit and is_unit ~= true then
        return false
    end

    local ok_npc, npc_id = invoke_unit_method(obj, "get_npc_id")
    if ok_npc and num(npc_id) > 0 then
        return false
    end

    local ok_class, class_id = invoke_unit_method(obj, "get_class")
    if ok_class then
        local cid = num(class_id)
        if cid >= 1 and cid <= 11 then
            return true
        end
    end

    return false
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return 99999
    end
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function now_ms()
    if core and core.game_time and type(core.game_time) == "function" then
        local ok, v = pcall(core.game_time)
        if ok and tonumber(v) then
            return tonumber(v)
        end
    end
    return 0
end

local CLOTH_CLASS_IDS = {
    [5] = true,
    [8] = true,
    [9] = true,
}

function PvPTargetSelector.new(event_bus, blackboard)
    local self = setmetatable({}, PvPTargetSelector)
    self._event_bus = event_bus
    self._blackboard = blackboard
    self.unit_helper = safe_require("common/utility/unit_helper")
    self.izi = safe_require("common/izi_sdk")
    self.spell_helper = safe_require("common/utility/spell_helper")
    self.pvp_helper = safe_require("common/utility/pvp_helper")
    self.buff_manager = safe_require("common/modules/buff_manager")

    self.last_target = nil
    self.last_target_guid = nil
    self.last_switch_ms = 0
    self.last_score = 0
    self.last_ranked = {}
    self._last_diag_ms = 0

    return self
end

local function is_hostile_player(player, unit)
    if not player or not unit then
        return false
    end

    if not is_probably_player_object(unit) then
        return false
    end

    local okd, dead = invoke_unit_method(unit, "is_dead")
    if okd and dead == true then
        return false
    end

    local okh, hostile = invoke_unit_method(unit, "is_enemy_with", player)
    if okh and hostile == true then
        return true
    end

    okh, hostile = invoke_unit_method(player, "is_enemy_with", unit)
    if okh and hostile == true then
        return true
    end

    local okc, can_attack = invoke_unit_method(player, "can_attack", unit)
    if okc and can_attack == true then
        return true
    end

    okc, can_attack = invoke_unit_method(unit, "can_attack", player)
    if okc and can_attack == true then
        return true
    end

    local okf, friendly = invoke_unit_method(player, "is_friend_with", unit)
    if okf and friendly == true then
        return false
    end
    okf, friendly = invoke_unit_method(unit, "is_friend_with", player)
    if okf and friendly == true then
        return false
    end

    local ok_pf, pf = invoke_unit_method(player, "get_faction_id")
    local ok_uf, uf = invoke_unit_method(unit, "get_faction_id")
    if ok_pf and ok_uf and num(pf) > 0 and num(uf) > 0 and num(pf) ~= num(uf) then
        return true
    end

    return false
end

local function get_class_id(unit)
    if unit then
        local ok, v = invoke_unit_method(unit, "get_class")
        if ok then
            return num(v)
        end
    end
    return 0
end

local function is_cloth(unit)
    return CLOTH_CLASS_IDS[get_class_id(unit)] == true
end

local function health_pct(unit)
    if not unit then
        return 100
    end
    local okh, h = invoke_unit_method(unit, "get_health")
    local okm, m = invoke_unit_method(unit, "get_max_health")
    if okh and okm and num(m) > 0 then
        return (num(h) / num(m)) * 100
    end
    return 100
end

function PvPTargetSelector:_is_healer(unit)
    if not unit then
        return false
    end

    local ok, role = invoke_unit_method(unit, "get_group_role")
    if ok and num(role) == 1 then
        return true
    end

    if self.unit_helper and type(self.unit_helper.is_healer) == "function" then
        local ok, v = pcall(self.unit_helper.is_healer, self.unit_helper, unit)
        if ok and v == true then
            return true
        end
    end

    return false
end

local DEFAULT_FLAG_CARRIER_AURAS = { 23333, 23335, 34976 }  -- WSG Horde/Alliance flag, EOTS Netherstorm Flag

function PvPTargetSelector:_has_flag_carrier_aura(unit, settings)
    if not self.buff_manager or type(self.buff_manager.get_buff_data) ~= "function" then
        return false
    end

    -- Check built-in defaults first
    local ok, data = pcall(self.buff_manager.get_buff_data, self.buff_manager, unit, DEFAULT_FLAG_CARRIER_AURAS)
    if ok and type(data) == "table" and data.is_active == true then
        return true
    end

    -- Then check custom aura IDs from settings
    local custom_ids = settings.flag_carrier_aura_ids or {}
    if type(custom_ids) == "table" and #custom_ids > 0 then
        ok, data = pcall(self.buff_manager.get_buff_data, self.buff_manager, unit, custom_ids)
        if ok and type(data) == "table" and data.is_active == true then
            return true
        end
    end

    return false
end

function PvPTargetSelector:_is_hard_immune(unit)
    -- Check via pvp_helper
    if self.pvp_helper and type(self.pvp_helper.is_damage_immune) == "function" then
        local ok, immune = pcall(self.pvp_helper.is_damage_immune, self.pvp_helper, unit)
        if ok and immune == true then
            return true
        end
    end
    -- Check via izi_sdk game_object method (Divine Shield, Ice Block, etc.)
    local ok_imm, is_immune = invoke_unit_method(unit, "is_damage_immune")
    if ok_imm and is_immune == true then
        return true
    end
    return false
end

function PvPTargetSelector:_cc_remaining_s(unit)
    -- Check loss-of-control info for remaining CC duration
    local ok, info = invoke_unit_method(unit, "get_loss_of_control_info")
    if ok and type(info) == "table" and info.valid == true then
        -- Use core.time() (seconds since injection) to match SDK expire_time epoch
        local now = 0
        if core and core.time and type(core.time) == "function" then
            local ok_t, v = pcall(core.time)
            if ok_t and tonumber(v) then now = tonumber(v) end
        end
        local end_time = num(info.end_time)
        if end_time > now then
            return end_time - now
        end
    end
    return 0
end

function PvPTargetSelector:_damage_reduction_penalty(unit)
    if not self.pvp_helper then
        return 0
    end

    -- Immunity is now handled as a hard-skip in select(); don't double-penalize
    if type(self.pvp_helper.has_damage_reduction) == "function" then
        local ok, has_dr, pct = pcall(self.pvp_helper.has_damage_reduction, self.pvp_helper, unit, 20)
        if ok and has_dr == true then
            return 6 + (num(pct) * 0.05)
        end
    end

    return 0
end

function PvPTargetSelector:_dr_penalty(unit)
    if not self.pvp_helper then
        return 0
    end

    if type(self.pvp_helper.get_cc_reduction_percentage) == "function" then
        local ok, pct = pcall(self.pvp_helper.get_cc_reduction_percentage, self.pvp_helper, unit)
        if ok and tonumber(pct) then
            return math.max(0, math.min(8, num(pct) * 0.08))
        end
    end

    return 0
end

function PvPTargetSelector:_los_penalty(player, unit, settings)
    local probe_spell_id = num(settings.los_probe_spell_id)
    if probe_spell_id <= 0 then
        return 0
    end

    if self.spell_helper and type(self.spell_helper.is_spell_in_line_of_sight) == "function" then
        local ok, los = pcall(self.spell_helper.is_spell_in_line_of_sight, self.spell_helper, probe_spell_id, player, unit)
        if ok and los ~= true then
            return num(settings.los_penalty) > 0 and num(settings.los_penalty) or 12
        end
    end

    return 0
end

function PvPTargetSelector:_collect_enemies(player, settings)
    local enemies = {}
    if not player then
        return enemies
    end

    local scan_radius = num(settings and settings.pvp_engage_scan_radius)
    if scan_radius <= 0 then
        scan_radius = 55
    end

    local player_pos = nil
    local ok_pos, pos = invoke_unit_method(player, "get_position")
    if ok_pos and type(pos) == "table" then
        player_pos = pos
    end

    if self.unit_helper and player_pos and type(self.unit_helper.get_enemy_list_around) == "function" then
        local ok, list = pcall(self.unit_helper.get_enemy_list_around, self.unit_helper, player_pos, scan_radius, true, false, true, false)
        if ok and type(list) == "table" then
            for i = 1, #list do
                local u = list[i]
                if is_hostile_player(player, u) then
                    enemies[#enemies + 1] = u
                end
            end
        end
    end

    if #enemies == 0 and self.izi and type(self.izi.enemies_if) == "function" then
        local ok, list = pcall(self.izi.enemies_if, scan_radius, function(u)
            return is_hostile_player(player, u)
        end)
        if ok and type(list) == "table" then
            for i = 1, #list do
                local u = list[i]
                if is_hostile_player(player, u) then
                    enemies[#enemies + 1] = u
                end
            end
        end
    end

    if #enemies == 0 and core and core.object_manager and type(core.object_manager.get_visible_objects) == "function" then
        local ok, list = pcall(core.object_manager.get_visible_objects)
        if ok and type(list) == "table" then
            for i = 1, #list do
                local u = list[i]
                if is_hostile_player(player, u) then
                    local within_radius = true
                    if player_pos then
                        local okp, upos = invoke_unit_method(u, "get_position")
                        if okp and type(upos) == "table" then
                            within_radius = distance(player_pos, upos) <= scan_radius
                        end
                    end
                    if within_radius then
                        enemies[#enemies + 1] = u
                    end
                end
            end
        end
    end

    return enemies
end

function PvPTargetSelector:external_score(unit)
    local ranked = self.last_ranked or {}
    local unit_guid = get_unit_guid(unit)
    if not unit_guid then
        return 0
    end
    for i = 1, #ranked do
        local rg = get_unit_guid(ranked[i].unit)
        if rg and rg == unit_guid then
            return ranked[i].score
        end
    end
    return 0
end

function PvPTargetSelector:select(player, settings)
    settings = settings or {}

    local enemies = self:_collect_enemies(player, settings)
    local scan_radius = num(settings.pvp_engage_scan_radius)
    if scan_radius <= 0 then scan_radius = 55 end
    local now = now_ms()
    local player_guid = get_unit_guid(player)

    if #enemies == 0 then
        self.last_ranked = {}
        if self._event_bus and (now - self._last_diag_ms) > 1000 then
            self._last_diag_ms = now
            self._event_bus:publish("combat.selector_diag", {
                candidate_count = 0,
                radius = scan_radius,
                best_score = 0,
            })
        end
        return nil, {}
    end

    local player_pos = nil
    if player then
        local ok_pos, pos = invoke_unit_method(player, "get_position")
        if ok_pos and type(pos) == "table" then
            player_pos = pos
        end
    end

    local healer_weight = tonumber(settings.healer_weight) or 10
    local flag_carrier_weight = tonumber(settings.flag_carrier_weight) or 9
    local low_hp_weight = tonumber(settings.low_hp_weight) or 8
    local cloth_weight = tonumber(settings.cloth_weight) or 4
    local attacking_me_weight = tonumber(settings.attacking_me_weight) or 6
    local nearest_weight = tonumber(settings.nearest_weight) or 3
    local switch_cost = tonumber(settings.switch_cost) or 4

    -- Assist train: count how many allies are targeting each enemy
    local ally_target_counts = {}
    if settings.assist_train_enabled ~= false and self.unit_helper
        and type(self.unit_helper.get_ally_list_around) == "function" and player_pos then
        local ok, allies = pcall(self.unit_helper.get_ally_list_around,
            self.unit_helper, player_pos, num(settings.assist_scan_radius_yd or 40),
            true, false, false)
        if ok and type(allies) == "table" then
            for _, ally in ipairs(allies) do
                local ok_t, ally_target = invoke_unit_method(ally, "get_target")
                if ok_t and ally_target then
                    local ally_target_guid = get_unit_guid(ally_target)
                    for _, enemy in ipairs(enemies) do
                        local enemy_guid = get_unit_guid(enemy)
                        local matched = ally_target_guid and enemy_guid and enemy_guid == ally_target_guid
                        if matched then
                            ally_target_counts[enemy] = (ally_target_counts[enemy] or 0) + 1
                        end
                    end
                end
            end
        end
    end

    local ranked = {}

    for i = 1, #enemies do
        local unit = enemies[i]
        local unit_guid = get_unit_guid(unit)

        -- Hard-skip fully immune targets (Divine Shield, Ice Block, etc.)
        if not self:_is_hard_immune(unit) then

        local score = 0

        -- Heavy penalty for long-duration CC (sheep, fear, sap >2s remaining)
        local cc_remain = self:_cc_remaining_s(unit)
        if cc_remain > 2.0 then
            score = score - 15
        end

        if self:_is_healer(unit) then
            score = score + healer_weight
        end

        if self:_has_flag_carrier_aura(unit, settings) then
            score = score + flag_carrier_weight
        end

        local hp = health_pct(unit)
        score = score + ((100 - hp) / 100) * low_hp_weight

        if is_cloth(unit) then
            score = score + cloth_weight
        end

        local ok_t, t = invoke_unit_method(unit, "get_target")
        if ok_t and t then
            local t_guid = get_unit_guid(t)
            if player_guid and t_guid and t_guid == player_guid then
                score = score + attacking_me_weight
            end
        end

        local d = 99999
        if player_pos then
            local okp, pos = invoke_unit_method(unit, "get_position")
            if okp and type(pos) == "table" then
                d = distance(player_pos, pos)
                score = score + (1 / math.max(1, d)) * nearest_weight
            end
        end

        score = score - self:_los_penalty(player, unit, settings)
        score = score - self:_damage_reduction_penalty(unit)
        score = score - self:_dr_penalty(unit)

        local same_as_last = unit_guid and self.last_target_guid and unit_guid == self.last_target_guid
        if self.last_target_guid and (not same_as_last) and (now - self.last_switch_ms) < (num(settings.switch_hesitation_ms) > 0 and num(settings.switch_hesitation_ms) or 1200) then
            score = score - switch_cost
        end

        -- Interrupt awareness: boost interruptible casters
        if settings.interrupt_awareness ~= false then
            local is_casting = false
            local ok_c, c_val = invoke_unit_method(unit, "is_casting_spell")
            if ok_c and c_val == true then is_casting = true end
            if not is_casting then
                local ok_ch, ch_val = invoke_unit_method(unit, "is_channelling_spell")
                if ok_ch and ch_val == true then is_casting = true end
            end
            if is_casting then
                local ok_i, i_val = invoke_unit_method(unit, "is_active_spell_interruptable")
                if ok_i and i_val == true then
                    score = score + num(settings.interruptible_caster_weight or 6)
                    if self:_is_healer(unit) then
                        score = score + num(settings.interruptible_healer_weight or 8)
                    end
                end
            end
        end

        -- Assist train bonus
        local ally_focus = ally_target_counts[unit] or 0
        if ally_focus >= num(settings.assist_train_min_allies or 2) then
            score = score + num(settings.assist_train_weight or 7)
            if self:_is_healer(unit) then
                score = score + num(settings.assist_train_healer_bonus or 5)
            end
        end

        ranked[#ranked + 1] = {
            unit = unit,
            score = score,
            hp = hp,
            distance = d,
        }

        end -- not hard_immune
    end

    table.sort(ranked, function(a, b)
        if a.score == b.score then
            return a.distance < b.distance
        end
        return a.score > b.score
    end)

    self.last_ranked = ranked

    local best = ranked[1]
    if not best then
        return nil, ranked
    end

    local best_guid = get_unit_guid(best.unit)
    local changed_target = not (best_guid and self.last_target_guid and best_guid == self.last_target_guid)
    if changed_target then
        self.last_target = best.unit
        self.last_target_guid = best_guid
        self.last_switch_ms = now
        if self._event_bus then
            self._event_bus:publish("combat.target_switched", { score = best.score, hp = best.hp, distance = best.distance })
        end
    else
        self.last_target = best.unit
    end

    self.last_score = best.score

    if self._event_bus and (now - self._last_diag_ms) > 1000 then
        self._last_diag_ms = now
        self._event_bus:publish("combat.selector_diag", {
            candidate_count = #ranked,
            radius = scan_radius,
            best_score = best.score,
        })
    end

    return best.unit, ranked
end

return PvPTargetSelector
