local spell_helper = require("common/utility/spell_helper")
local spell_queue = require("common/modules/spell_queue")
local unit_helper = require("common/utility/unit_helper")

local ok_enums, enums = pcall(require, "common/enums")

local CombatManager = {}
CombatManager.__index = CombatManager

local CLASS_IDS = {
    warrior = 1,
    paladin = 2,
    hunter = 3,
    rogue = 4,
    priest = 5,
    shaman = 7,
    mage = 8,
    warlock = 9,
    druid = 11,
}

if ok_enums and enums and enums.class_id then
    CLASS_IDS.warrior = enums.class_id.WARRIOR or CLASS_IDS.warrior
    CLASS_IDS.paladin = enums.class_id.PALADIN or CLASS_IDS.paladin
    CLASS_IDS.hunter = enums.class_id.HUNTER or CLASS_IDS.hunter
    CLASS_IDS.rogue = enums.class_id.ROGUE or CLASS_IDS.rogue
    CLASS_IDS.priest = enums.class_id.PRIEST or CLASS_IDS.priest
    CLASS_IDS.shaman = enums.class_id.SHAMAN or CLASS_IDS.shaman
    CLASS_IDS.mage = enums.class_id.MAGE or CLASS_IDS.mage
    CLASS_IDS.warlock = enums.class_id.WARLOCK or CLASS_IDS.warlock
    CLASS_IDS.druid = enums.class_id.DRUID or CLASS_IDS.druid
end

local ROTATION_KEYS = {
    "warrior",
    "paladin",
    "hunter",
    "rogue",
    "priest",
    "shaman",
    "mage",
    "warlock",
    "druid",
}

local ROTATION_LABELS = {
    warrior = "Warrior (Empty)",
    paladin = "Paladin (Empty)",
    hunter = "Hunter (Empty)",
    rogue = "Rogue (Empty)",
    priest = "Priest (Empty)",
    shaman = "Shaman (Empty)",
    mage = "Mage (Empty)",
    warlock = "Warlock (Demo)",
    druid = "Druid (Empty)",
}

local SPELLS = {
    shadow_bolt = 686,
    corruption = 172,
    immolate = 348,
    curse_of_agony = 980,
    life_tap = 1454,
    drain_life = 689,
    demonic_armor = 11735,
    detect_invisibility = 132,
    soul_link = 19028,
}

local function has_spell(spell_id)
    return spell_helper:has_spell_equipped(spell_id)
end

local function can_cast(spell_id, caster, target)
    return spell_helper:is_spell_castable(spell_id, caster, target, false, false)
end

local function find_target(local_player, range)
    local current_target = local_player:get_target()
    if current_target
        and current_target:is_valid()
        and not current_target:is_dead()
        and local_player:is_enemy_with(current_target)
        and local_player:get_position():dist_to(current_target:get_position()) <= range then
        return current_target
    end

    local player_pos = local_player:get_position()
    local enemies = unit_helper:get_enemy_list_around(player_pos, range, true, false, true, false)
    if not enemies or #enemies == 0 then
        return nil
    end

    local best = nil
    local best_dist = range + 1
    for _, enemy in ipairs(enemies) do
        if enemy and enemy:is_valid() and not enemy:is_dead() then
            local dist = player_pos:dist_to(enemy:get_position())
            if dist < best_dist then
                best = enemy
                best_dist = dist
            end
        end
    end

    return best
end

local function has_debuff(target, spell_id)
    local debuffs = target:get_debuffs()
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

local function has_buff(unit, spell_id)
    local buffs = unit:get_buffs()
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

function CombatManager:new()
    local o = setmetatable({}, CombatManager)

    o._enabled = true
    o._range = 35.0
    o._tick_interval = 0.20
    o._last_tick = 0
    o._selected_rotation_class = "warlock"

    return o
end

function CombatManager:set_enabled(enabled)
    self._enabled = enabled == true
end

function CombatManager:get_enabled()
    return self._enabled
end

function CombatManager:get_rotation_options()
    local options = {}
    for _, key in ipairs(ROTATION_KEYS) do
        table.insert(options, ROTATION_LABELS[key] or key)
    end
    return options
end

function CombatManager:set_rotation_class(class_key)
    for _, key in ipairs(ROTATION_KEYS) do
        if key == class_key then
            self._selected_rotation_class = class_key
            return true
        end
    end
    return false
end

function CombatManager:get_rotation_class()
    return self._selected_rotation_class
end

function CombatManager:_queue(spell_id, target, label)
    spell_queue:queue_spell_target(spell_id, target, 1, label)
end

function CombatManager:_try_warlock_self_buffs(local_player)
    local buff_priority = {
        { id = SPELLS.demonic_armor, label = "Demonic Armor" },
        { id = SPELLS.detect_invisibility, label = "Detect Invisibility" },
        { id = SPELLS.soul_link, label = "Soul Link" },
    }

    for _, buff in ipairs(buff_priority) do
        if has_spell(buff.id)
            and not has_buff(local_player, buff.id)
            and can_cast(buff.id, local_player, local_player)
        then
            self:_queue(buff.id, local_player, buff.label)
            return true
        end
    end

    return false
end

function CombatManager:_run_warlock_rotation(local_player)
    if self:_try_warlock_self_buffs(local_player) then
        return true
    end

    local target = find_target(local_player, self._range)
    if not target then
        return false
    end

    core.input.set_target(target)

    local my_health = local_player:get_health()
    local my_max_health = math.max(1, local_player:get_max_health())
    local health_pct = my_health / my_max_health

    local my_mana = local_player:get_power(0)
    local my_max_mana = math.max(1, local_player:get_max_power(0))
    local mana_pct = my_mana / my_max_mana

    local level = local_player:get_level()

    if has_spell(SPELLS.life_tap)
        and mana_pct < 0.18
        and health_pct > 0.45
        and can_cast(SPELLS.life_tap, local_player, local_player) then
        self:_queue(SPELLS.life_tap, local_player, "Life Tap")
        return true
    end

    if has_spell(SPELLS.corruption)
        and not has_debuff(target, SPELLS.corruption)
        and can_cast(SPELLS.corruption, local_player, target) then
        self:_queue(SPELLS.corruption, target, "Corruption")
        return true
    end

    if level >= 10
        and has_spell(SPELLS.immolate)
        and not has_debuff(target, SPELLS.immolate)
        and can_cast(SPELLS.immolate, local_player, target) then
        self:_queue(SPELLS.immolate, target, "Immolate")
        return true
    end

    if level >= 8
        and has_spell(SPELLS.curse_of_agony)
        and not has_debuff(target, SPELLS.curse_of_agony)
        and can_cast(SPELLS.curse_of_agony, local_player, target) then
        self:_queue(SPELLS.curse_of_agony, target, "Curse of Agony")
        return true
    end

    if health_pct < 0.35
        and has_spell(SPELLS.drain_life)
        and can_cast(SPELLS.drain_life, local_player, target) then
        self:_queue(SPELLS.drain_life, target, "Drain Life")
        return true
    end

    if has_spell(SPELLS.shadow_bolt)
        and can_cast(SPELLS.shadow_bolt, local_player, target) then
        self:_queue(SPELLS.shadow_bolt, target, "Shadow Bolt")
        return true
    end

    if has_spell(SPELLS.drain_life)
        and can_cast(SPELLS.drain_life, local_player, target) then
        self:_queue(SPELLS.drain_life, target, "Drain Life")
        return true
    end

    return false
end

function CombatManager:_run_empty_rotation(_local_player)
    return false
end

function CombatManager:_class_key_from_id(class_id)
    for key, value in pairs(CLASS_IDS) do
        if value == class_id then
            return key
        end
    end
    return nil
end

function CombatManager:update(local_player)
    if not self._enabled then
        return
    end

    if not local_player or not local_player:is_valid() or local_player:is_dead() then
        return
    end

    if local_player:is_casting_spell() or local_player:is_channelling_spell() then
        return
    end

    local selected = self._selected_rotation_class
    local player_class = self:_class_key_from_id(local_player:get_class())
    if not selected or not player_class or selected ~= player_class then
        return
    end

    local now = core.time()
    if now - self._last_tick < self._tick_interval then
        return
    end
    self._last_tick = now

    if selected == "warlock" then
        self:_run_warlock_rotation(local_player)
        return
    end

    self:_run_empty_rotation(local_player)
end

return CombatManager
