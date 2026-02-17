local Catalog = require("modules/RotationProfileCatalog")

local RotationManager = {}
RotationManager.__index = RotationManager

local ok_enums, enums = pcall(require, "common/enums")
if not ok_enums then
    enums = nil
end

local WARLOCK_EXTRA_SELF_BUFFS = {
    11735, -- Demon Armor
    132,   -- Detect Invisibility
    19028, -- Soul Link
}

local WARLOCK_SIGNATURES = {
    destruction = { 29722, 17962 },
    affliction = { 30108, 63106 },
    demonology = { 30146, 19028, 18788 },
}

local WARLOCK_SPEC_TO_PROFILE = {
    [1] = "Affliction",
    [2] = "Demonology",
    [3] = "Destruction",
}

local WARLOCK_DEBUFF_RETRY = {
    [1490] = 30.0, -- Curse of Elements
    [603] = 20.0,  -- Curse of Doom
    [348] = 10.0,  -- Immolate
    [172] = 12.0,  -- Corruption
    [63106] = 12.0,
    [30108] = 12.0,
}

local function call_method(obj, name, ...)
    if not obj then
        return nil
    end
    local fn = obj[name]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, obj, ...)
    if not ok then
        return nil
    end
    return result
end

local function is_spell_learned(spell_id)
    return core.spell_book and core.spell_book.is_spell_learned and core.spell_book.is_spell_learned(spell_id) == true
end

local function has_buff(unit, spell_id)
    local buffs = call_method(unit, "get_buffs")
    if not buffs then
        return false
    end
    for _, buff in ipairs(buffs) do
        if buff and buff.buff_id == spell_id then
            return true
        end
    end
    return false
end

local function has_debuff(unit, spell_id)
    local debuffs = call_method(unit, "get_debuffs")
    if not debuffs then
        return false
    end
    for _, debuff in ipairs(debuffs) do
        if debuff and debuff.buff_id == spell_id then
            return true
        end
    end
    return false
end

local function can_cast_target(spell_id, caster, target)
    if not core.spell_book or not core.input or not core.input.cast_target_spell then
        return false
    end
    if not is_spell_learned(spell_id) then
        return false
    end
    if core.spell_book.get_global_cooldown and core.spell_book.get_global_cooldown() > 0 then
        return false
    end
    if core.spell_book.get_spell_cooldown and core.spell_book.get_spell_cooldown(spell_id) > 0 then
        return false
    end
    if core.spell_book.is_usable_spell and core.spell_book.is_usable_spell(spell_id) == false then
        return false
    end
    if core.spell_book.is_spell_in_range and target and caster then
        local in_range = core.spell_book.is_spell_in_range(spell_id, target, caster)
        if in_range == false then
            return false
        end
    end
    return true
end

local function get_target_hp_pct(target)
    local hp = call_method(target, "get_health") or 0
    local hp_max = call_method(target, "get_max_health") or 1
    if hp_max <= 0 then
        return 100
    end
    return (hp / hp_max) * 100
end

local function get_class_key(local_player)
    local class_id = call_method(local_player, "get_class")
    if not class_id then
        return nil
    end

    if enums and enums.class_id then
        for key, value in pairs(enums.class_id) do
            if type(key) == "string" and value == class_id then
                return key
            end
        end
    end

    return nil
end

local function get_specialization_id(local_player)
    local spec_id = nil

    if core.spell_book and core.spell_book.get_specialization_id then
        spec_id = core.spell_book.get_specialization_id()
    end

    if (not spec_id or spec_id <= 0) and local_player then
        spec_id = call_method(local_player, "get_specialization_id")
    end

    if type(spec_id) ~= "number" then
        return nil
    end

    return math.floor(spec_id)
end

local function shallow_copy_table(list)
    local out = {}
    for i, value in ipairs(list) do
        out[i] = value
    end
    return out
end

local function unique_append(dst, values)
    local seen = {}
    for _, v in ipairs(dst) do
        seen[v] = true
    end
    for _, v in ipairs(values) do
        if not seen[v] then
            seen[v] = true
            dst[#dst + 1] = v
        end
    end
end

function RotationManager:new(config)
    local instance = setmetatable({}, RotationManager)
    instance._config = {
        tick_interval = (config and config.tick_interval) or 0.20,
        self_buff_retry_delay = (config and config.self_buff_retry_delay) or 4.0,
    }
    instance._last_tick = 0
    instance._last_pet_attack = 0
    instance._pet_attack_interval = 1.5
    instance._profiles = Catalog.get_all()
    instance._profiles_by_id = {}
    instance._profile_descriptors = {}
    instance._active_profile_id = nil
    instance._active_profile = nil
    instance._auto_select = true
    instance._last_detected_spec_id = nil
    instance._self_buff_retry = {}
    instance._target_debuff_retry = {}

    for idx, profile in ipairs(instance._profiles) do
        instance._profiles_by_id[profile.id] = profile
        instance._profile_descriptors[#instance._profile_descriptors + 1] = {
            index = idx,
            id = profile.id,
            label = string.format("%s - %s (TBC)", profile.class_key, profile.spec),
            class_key = profile.class_key,
            spec = profile.spec,
        }
    end

    return instance
end

function RotationManager:get_all_profile_descriptors()
    return self._profile_descriptors
end

function RotationManager:get_active_profile_id()
    return self._active_profile_id
end

function RotationManager:get_active_profile_label()
    local profile = self._active_profile
    if not profile then
        return "none"
    end
    return string.format("%s - %s", profile.class_key, profile.spec)
end

function RotationManager:is_auto_select_enabled()
    return self._auto_select == true
end

function RotationManager:set_auto_select(enabled)
    self._auto_select = enabled == true
end

function RotationManager:set_profile_by_id(profile_id)
    local profile = self._profiles_by_id[profile_id]
    if not profile then
        return false
    end
    self._active_profile_id = profile.id
    self._active_profile = profile
    return true
end

function RotationManager:set_profile_by_index(index)
    local profile = self._profiles[index]
    if not profile then
        return false
    end
    self._active_profile_id = profile.id
    self._active_profile = profile
    return true
end

function RotationManager:get_profile_index_by_id(profile_id)
    if not profile_id then
        return nil
    end
    for idx, profile in ipairs(self._profiles) do
        if profile.id == profile_id then
            return idx
        end
    end
    return nil
end

function RotationManager:_find_profile_by_spec(class_key, spec_name)
    if not class_key or not spec_name then
        return nil
    end
    local wanted = string.lower(spec_name)
    for _, profile in ipairs(self._profiles) do
        if profile.class_key == class_key and string.lower(profile.spec or "") == wanted then
            return profile
        end
    end
    return nil
end

function RotationManager:_pick_warlock_profile(local_player)
    local spec_id = get_specialization_id(local_player)
    if spec_id then
        local spec_name = WARLOCK_SPEC_TO_PROFILE[spec_id]
        if spec_name then
            local profile = self:_find_profile_by_spec("WARLOCK", spec_name)
            if profile then
                return profile
            end
        end
    end

    for _, spell_id in ipairs(WARLOCK_SIGNATURES.destruction) do
        if is_spell_learned(spell_id) then
            return self:_find_profile_by_spec("WARLOCK", "Destruction")
        end
    end
    for _, spell_id in ipairs(WARLOCK_SIGNATURES.affliction) do
        if is_spell_learned(spell_id) then
            return self:_find_profile_by_spec("WARLOCK", "Affliction")
        end
    end
    for _, spell_id in ipairs(WARLOCK_SIGNATURES.demonology) do
        if is_spell_learned(spell_id) then
            return self:_find_profile_by_spec("WARLOCK", "Demonology")
        end
    end

    local best_profile = nil
    local best_score = -1
    for _, profile in ipairs(self._profiles) do
        if profile.class_key == "WARLOCK" then
            local score = 0
            for _, sid in ipairs(profile.priority or {}) do
                if is_spell_learned(sid) then
                    score = score + 1
                end
            end
            if score > best_score then
                best_score = score
                best_profile = profile
            end
        end
    end

    return best_profile
end

function RotationManager:detect_default_profile(local_player)
    local class_key = get_class_key(local_player)
    if not class_key then
        return nil
    end

    if class_key == "WARLOCK" then
        self._last_detected_spec_id = get_specialization_id(local_player)
        local warlock_profile = self:_pick_warlock_profile(local_player)
        if warlock_profile then
            self._active_profile_id = warlock_profile.id
            self._active_profile = warlock_profile
            return warlock_profile.id
        end
    else
        self._last_detected_spec_id = nil
    end

    for _, profile in ipairs(self._profiles) do
        if profile.class_key == class_key then
            self._active_profile_id = profile.id
            self._active_profile = profile
            return profile.id
        end
    end

    return nil
end

function RotationManager:_cast(spell_id, target)
    if core.input and core.input.cast_target_spell then
        core.input.cast_target_spell(spell_id, target)
        return true
    end
    return false
end

function RotationManager:_build_self_buff_list(profile)
    local buffs = shallow_copy_table(profile.self_buffs or {})
    if profile.class_key == "WARLOCK" then
        unique_append(buffs, WARLOCK_EXTRA_SELF_BUFFS)
    end
    return buffs
end

function RotationManager:_tick_pet_attack(profile, target)
    if not target then
        return
    end
    if not core.input or not core.input.pet_attack then
        return
    end
    if profile.class_key ~= "WARLOCK" and profile.class_key ~= "HUNTER" then
        return
    end

    local now = core.time()
    if (now - self._last_pet_attack) >= self._pet_attack_interval then
        core.input.pet_attack(target)
        self._last_pet_attack = now
    end
end

function RotationManager:_cast_self_buffs(local_player, profile)
    if profile.class_key ~= "WARLOCK" then
        return false
    end

    local target = call_method(local_player, "get_target")
    if target and call_method(target, "is_valid") == true and call_method(target, "is_dead") == false then
        return false
    end

    local now = core.time()
    local buffs = self:_build_self_buff_list(profile)
    for _, spell_id in ipairs(buffs) do
        if has_buff(local_player, spell_id) then
            self._self_buff_retry[spell_id] = nil
        else
            local next_try = self._self_buff_retry[spell_id] or 0
            if now >= next_try then
                if spell_id == 19028 then
                    local pet = call_method(local_player, "get_pet")
                    if not pet or call_method(pet, "is_valid") ~= true or call_method(pet, "is_dead") == true then
                        self._self_buff_retry[spell_id] = now + 8.0
                    elseif can_cast_target(spell_id, local_player, local_player) then
                        self._self_buff_retry[spell_id] = now + self._config.self_buff_retry_delay
                        return self:_cast(spell_id, local_player)
                    else
                        self._self_buff_retry[spell_id] = now + self._config.self_buff_retry_delay
                    end
                elseif can_cast_target(spell_id, local_player, local_player) then
                    self._self_buff_retry[spell_id] = now + self._config.self_buff_retry_delay
                    return self:_cast(spell_id, local_player)
                else
                    self._self_buff_retry[spell_id] = now + self._config.self_buff_retry_delay
                end
            end
        end
    end
    return false
end

function RotationManager:_cast_execute(local_player, target, profile)
    if not profile.execute or #profile.execute == 0 then
        return false
    end

    local hp_pct = get_target_hp_pct(target)
    for _, rule in ipairs(profile.execute) do
        if hp_pct <= rule.target_hp_lte and can_cast_target(rule.spell_id, local_player, target) then
            return self:_cast(rule.spell_id, target)
        end
    end

    return false
end

function RotationManager:_get_target_key(target)
    local guid = call_method(target, "get_guid")
    if guid then
        return tostring(guid)
    end
    return tostring(target)
end

function RotationManager:_get_debuff_retry_delay(profile, spell_id)
    if profile.class_key == "WARLOCK" then
        return WARLOCK_DEBUFF_RETRY[spell_id] or 8.0
    end
    return 5.0
end

function RotationManager:_cast_target_debuffs(local_player, target, profile)
    local now = core.time()
    local target_key = self:_get_target_key(target)
    if not target_key then
        return false
    end

    local per_target = self._target_debuff_retry[target_key]
    if not per_target then
        per_target = {}
        self._target_debuff_retry[target_key] = per_target
    end

    for _, spell_id in ipairs(profile.target_debuffs or {}) do
        local next_try = per_target[spell_id] or 0
        if now >= next_try then
            if has_debuff(target, spell_id) then
                per_target[spell_id] = nil
            elseif can_cast_target(spell_id, local_player, target) then
                per_target[spell_id] = now + self:_get_debuff_retry_delay(profile, spell_id)
                return self:_cast(spell_id, target)
            else
                per_target[spell_id] = now + 2.0
            end
        end
    end
    return false
end

function RotationManager:_cast_priority(local_player, target, profile)
    for _, spell_id in ipairs(profile.priority or {}) do
        if can_cast_target(spell_id, local_player, target) then
            return self:_cast(spell_id, target)
        end
    end
    return false
end

function RotationManager:tick(local_player, target)
    local now = core.time()
    if (now - self._last_tick) < self._config.tick_interval then
        return false
    end
    self._last_tick = now

    if call_method(local_player, "is_casting_spell") == true or call_method(local_player, "is_channelling_spell") == true then
        return false
    end

    if self._auto_select then
        local class_key = get_class_key(local_player)
        local should_redetect = (not self._active_profile) or (class_key and self._active_profile.class_key ~= class_key)
        if class_key == "WARLOCK" then
            local current_spec_id = get_specialization_id(local_player)
            if current_spec_id and current_spec_id ~= self._last_detected_spec_id then
                should_redetect = true
            end
        end

        if should_redetect then
            self:detect_default_profile(local_player)
        end
    end

    local profile = self._active_profile
    if not profile then
        return false
    end

    if self:_cast_self_buffs(local_player, profile) then
        return true
    end

    if not target or call_method(target, "is_dead") == true then
        return false
    end

    self:_tick_pet_attack(profile, target)

    if self:_cast_execute(local_player, target, profile) then
        return true
    end

    if self:_cast_target_debuffs(local_player, target, profile) then
        return true
    end

    if self:_cast_priority(local_player, target, profile) then
        return true
    end

    return false
end

return RotationManager
