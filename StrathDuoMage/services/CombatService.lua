local CombatService = {}
CombatService.__index = CombatService

local function safe_method(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(obj[method], obj, ...)
    if ok then
        return value
    end
    return nil
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return math.huge
    end
    local dx = (tonumber(a.x) or 0) - (tonumber(b.x) or 0)
    local dy = (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
    local dz = (tonumber(a.z) or 0) - (tonumber(b.z) or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---@class CombatService
function CombatService:new(bb, cfg, movement, logger)
    local o = setmetatable({}, CombatService)
    o._bb = bb
    o._cfg = cfg or {}
    o._movement = movement
    o._log = logger
    o._spell_cache = {}
    o._spell_cache_at = 0
    return o
end

function CombatService:_refresh_spells(now)
    if (now - self._spell_cache_at) < 5.0 then
        return
    end
    self._spell_cache_at = now

    local combat_cfg = self._cfg.combat or {}
    local keys = {
        "frostbolt_rank_ids",
        "blizzard_rank_ids",
        "cone_of_cold_rank_ids",
        "frost_nova_rank_ids",
        "arcane_explosion_rank_ids",
        "ice_barrier_rank_ids",
        "blink_rank_ids",
    }

    for i = 1, #keys do
        local key = keys[i]
        local ids = combat_cfg[key]
        local resolved = nil

        if type(ids) == "table" then
            for j = 1, #ids do
                local id = tonumber(ids[j])
                if id and id > 0 then
                    local learned = nil
                    if core and core.spell_book and core.spell_book.is_spell_learned then
                        local ok_learned, value = pcall(core.spell_book.is_spell_learned, id)
                        if ok_learned then
                            learned = value == true
                        end
                    end
                    if learned == nil and core and core.spell_book and core.spell_book.has_spell then
                        local ok_has, value = pcall(core.spell_book.has_spell, id)
                        if ok_has then
                            learned = value == true
                        end
                    end
                    if learned == true then
                        resolved = id
                        break
                    end
                end
            end
            if not resolved and tonumber(ids[1]) then
                resolved = tonumber(ids[1])
            end
        end

        self._spell_cache[key] = resolved
    end
end

function CombatService:_spell(key)
    return tonumber(self._spell_cache[key]) or nil
end

function CombatService:_is_spell_usable(spell_id)
    local sid = tonumber(spell_id) or 0
    if sid <= 0 then
        return false
    end

    if core and core.spell_book and core.spell_book.is_usable_spell then
        local ok, usable = pcall(core.spell_book.is_usable_spell, sid)
        if ok then
            return usable == true
        end
    end

    return true
end

function CombatService:_cast_target(spell_id, target)
    if not self:_is_spell_usable(spell_id) then
        return false
    end
    if not core or not core.input then
        return false
    end

    if type(core.input.set_target) == "function" and target then
        pcall(core.input.set_target, target)
    end
    if type(core.input.look_at) == "function" and target and target.get_position then
        local ok_pos, pos = pcall(target.get_position, target)
        if ok_pos and pos then
            pcall(core.input.look_at, pos)
        end
    end

    if type(core.input.cast_target_spell) == "function" then
        local ok = pcall(core.input.cast_target_spell, spell_id, target)
        return ok == true
    end
    return false
end

function CombatService:_cast_self(spell_id)
    if not self:_is_spell_usable(spell_id) then
        return false
    end
    if not core or not core.input then
        return false
    end

    if type(core.input.cast_self_spell) == "function" then
        local ok = pcall(core.input.cast_self_spell, spell_id)
        if ok then
            return true
        end
    end

    local player = self._bb:get("player.object")
    if type(core.input.cast_target_spell) == "function" and player then
        local ok = pcall(core.input.cast_target_spell, spell_id, player)
        return ok == true
    end

    return false
end

function CombatService:_cast_position(spell_id, pos)
    if not self:_is_spell_usable(spell_id) then
        return false
    end
    if not core or not core.input or type(core.input.cast_position_spell) ~= "function" then
        return false
    end

    local ok = pcall(core.input.cast_position_spell, spell_id, pos)
    return ok == true
end

function CombatService:_kite_away(player_pos, target_pos)
    if type(player_pos) ~= "table" or type(target_pos) ~= "table" then
        return false
    end

    local ideal = tonumber(self._cfg.combat and self._cfg.combat.kite_ideal_range) or 23.0
    local dx = (tonumber(player_pos.x) or 0) - (tonumber(target_pos.x) or 0)
    local dy = (tonumber(player_pos.y) or 0) - (tonumber(target_pos.y) or 0)
    local dz = (tonumber(player_pos.z) or 0) - (tonumber(target_pos.z) or 0)
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.001 then
        dx, dy, dz, len = 1, 0, 0, 1
    end

    local dest = {
        x = (tonumber(target_pos.x) or 0) + (dx / len) * ideal,
        y = (tonumber(target_pos.y) or 0) + (dy / len) * ideal,
        z = (tonumber(target_pos.z) or 0) + (dz / len) * ideal,
    }

    if self._movement then
        return self._movement:move_to(dest)
    end
    return false
end

---@param now number
---@return boolean
function CombatService:tick(now)
    self:_refresh_spells(now)

    local player = self._bb:get("player.object")
    local target = self._bb:get("combat.target")
    if not player or not target then
        return false
    end

    if safe_method(target, "is_valid") ~= true or safe_method(target, "is_dead") == true then
        return false
    end

    local player_pos = self._bb:get("player.position")
    local target_pos = safe_method(target, "get_position")
    local dist = distance(player_pos, target_pos)

    local target_guid = tostring(safe_method(target, "get_guid") or "")
    self._bb:set("combat.target_guid", target_guid)
    self._bb:set("combat.target_distance", dist)

    local hp_pct = tonumber(self._bb:get("player.health_pct", 1.0)) or 1.0
    local mana_pct = tonumber(self._bb:get("player.mana_pct", 1.0)) or 1.0
    local enemy_count = tonumber(self._bb:get("combat.enemy_count", 1)) or 1
    local route_collecting = self._bb:get("route.collecting", false) == true
    local route_collect_complete = self._bb:get("route.collect_complete", false) == true
    local collect_mode = route_collecting and not route_collect_complete

    local is_casting = self._bb:get("player.is_casting", false) == true
    if is_casting then
        return false
    end

    local nova_threshold = tonumber(self._cfg.combat and self._cfg.combat.emergency_nova_health_pct) or 0.50
    local kite_min = tonumber(self._cfg.combat and self._cfg.combat.kite_min_range) or 12.0

    if hp_pct <= nova_threshold and dist <= 10.0 then
        local nova = self:_spell("frost_nova_rank_ids")
        if nova and self:_cast_self(nova) then
            return true
        end

        local blink = self:_spell("blink_rank_ids")
        if blink and self:_cast_self(blink) then
            return true
        end
    end

    local barrier = self:_spell("ice_barrier_rank_ids")
    if barrier and hp_pct < 0.85 and self:_cast_self(barrier) then
        return true
    end

    local aoe_threshold = tonumber(self._cfg.targeting and self._cfg.targeting.aoe_enemy_threshold) or 3
    if not collect_mode and enemy_count >= aoe_threshold then
        local coc = self:_spell("cone_of_cold_rank_ids")
        if coc and dist <= 10.0 and self:_cast_target(coc, target) then
            return true
        end

        local blizzard = self:_spell("blizzard_rank_ids")
        local blizzard_anchor = self._bb:get("combat.blizzard_anchor")
        local cast_pos = blizzard_anchor or target_pos
        local cast_dist = distance(player_pos, cast_pos)
        if blizzard and cast_dist <= 30.0 and mana_pct >= 0.20 and cast_pos and self:_cast_position(blizzard, cast_pos) then
            self._bb:set("combat.last_blizzard_anchor", cast_pos)
            return true
        end

        local arcane_explosion = self:_spell("arcane_explosion_rank_ids")
        if arcane_explosion and dist <= 5.5 and mana_pct >= 0.15 and self:_cast_self(arcane_explosion) then
            return true
        end
    end

    if dist < kite_min then
        if self:_kite_away(player_pos, target_pos) then
            return true
        end
    end

    local frostbolt = self:_spell("frostbolt_rank_ids")
    if frostbolt and dist <= 30.0 and self:_cast_target(frostbolt, target) then
        return true
    end

    return false
end

---@param target any
---@param now number
---@return boolean
function CombatService:pull_target(target, now)
    if not target then
        return false
    end
    self:_refresh_spells(now)

    local player_pos = self._bb:get("player.position")
    local target_pos = safe_method(target, "get_position")
    local dist = distance(player_pos, target_pos)
    local pull_range = tonumber(self._cfg.targeting and self._cfg.targeting.pull_range) or 30.0

    if dist > pull_range then
        if self._movement then
            self._movement:move_to(target_pos)
        end
        return false
    end

    local frostbolt = self:_spell("frostbolt_rank_ids")
    if frostbolt and self:_cast_target(frostbolt, target) then
        return true
    end

    return false
end

return CombatService
