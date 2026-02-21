---@module BGBOT.core.perception.scanner
-- Per-tick object scanning engine.
-- Reads core.object_manager.* and core.game_ui.*, writes to WorldModel.
-- Implements tiered scanning: near (every tick), tactical (every 5), full (every 30).

local constants = require("shared/constants")
local config    = require("shared/config")
local utils     = require("shared/utils")
local filters   = require("core/perception/filters")

local scanner = {}
scanner.__index = scanner

local AURA_DISTANCE_DELTA_REFRESH = 20
local AURA_REFRESH_NEAR = 0.4
local AURA_REFRESH_TACTICAL = 1.0
local AURA_REFRESH_FAR = 3.0
local AURA_REFRESH_COMBAT = 0.5
local AURA_REFRESH_SELF = 0.15
local AURA_REFRESH_FLAG_TRACK = 0.6
local AURA_CACHE_PRUNE_INTERVAL = 8.0
local AURA_CACHE_STALE_GRACE = 12.0

local function map_matches(map_id, id_list)
    for _, id in ipairs(id_list or {}) do
        if map_id == id then
            return true
        end
    end
    return false
end

local function new_scan_debug_stats()
    return {
        visible_total        = 0,
        visible_trackable    = 0,
        visible_player_like  = 0,
        visible_bg_objects   = 0,
        visible_processed    = 0,
        full_total           = 0,
        full_trackable       = 0,
        full_player_like     = 0,
        full_bg_objects      = 0,
        full_processed       = 0,
        last_full_tick       = 0,
        last_full_time       = 0,
    }
end

local function faction_source_rank(source)
    local s = tostring(source or "")
    if string.find(s, "self_", 1, true) == 1 then return 4 end
    if string.find(s, "ally_", 1, true) == 1 then return 3 end
    if string.find(s, "enemy_", 1, true) == 1 then return 3 end
    if string.find(s, "faction_id:", 1, true) == 1 then return 2 end
    if string.find(s, "fallback", 1, true) == 1 then return 1 end
    return 0
end

local function safe_call_method(obj, method_name, ...)
    if not obj then
        return nil, false
    end
    local fn = obj[method_name]
    if type(fn) ~= "function" then
        return nil, false
    end

    local ok, result = pcall(fn, obj, ...)
    if not ok then
        return nil, false
    end
    return result, true
end

local function safe_is_valid(obj)
    local valid, ok = safe_call_method(obj, "is_valid")
    return ok and valid == true
end

local function cache_key_for_obj(obj)
    return tostring(obj)
end

local function aura_scan_interval(opts, cached_has_flag)
    if opts and opts.is_self then
        return AURA_REFRESH_SELF
    end
    if cached_has_flag or (opts and opts.must_track) then
        return AURA_REFRESH_FLAG_TRACK
    end
    if opts and opts.is_in_combat then
        return AURA_REFRESH_COMBAT
    end

    local distance = tonumber(opts and opts.distance) or 0
    if distance <= constants.RING.NEAR_MAX then
        return AURA_REFRESH_NEAR
    end
    if distance <= constants.RING.TACTICAL_MAX then
        return AURA_REFRESH_TACTICAL
    end
    return AURA_REFRESH_FAR
end

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------

function scanner.new(world_model)
    local self = setmetatable({}, scanner)
    self.world_model   = world_model
    self.tick_count     = 0
    self.last_full_scan = 0
    self.last_bg_phase   = 0
    self.last_prep_active = false
    self.unknown_phase_since = 0
    self.unknown_phase_elapsed = 0
    self.faction        = constants.FACTION.UNKNOWN
    self.faction_source = "unknown"
    self.scan_debug_stats = new_scan_debug_stats()
    self.aura_cache = {} -- { [handle_key] = { auras, fetched_at, distance, is_in_combat, has_any_flag, has_horde_flag, has_alliance_flag } }
    self.last_aura_cache_prune = 0
    return self
end

function scanner:get_debug_stats()
    local s = self.scan_debug_stats or {}
    return {
        visible_total       = s.visible_total or 0,
        visible_trackable   = s.visible_trackable or 0,
        visible_player_like = s.visible_player_like or 0,
        visible_wsg_objects = s.visible_bg_objects or 0,   -- legacy alias
        visible_bg_objects  = s.visible_bg_objects or 0,
        visible_processed   = s.visible_processed or 0,
        full_total          = s.full_total or 0,
        full_trackable      = s.full_trackable or 0,
        full_player_like    = s.full_player_like or 0,
        full_wsg_objects    = s.full_bg_objects or 0,      -- legacy alias
        full_bg_objects     = s.full_bg_objects or 0,
        full_processed      = s.full_processed or 0,
        last_full_tick      = s.last_full_tick or 0,
        last_full_time      = s.last_full_time or 0,
        tick_count          = self.tick_count or 0,
        faction             = self.faction or constants.FACTION.UNKNOWN,
        faction_source      = self.faction_source or "unknown",
        unknown_phase_since = self.unknown_phase_since or 0,
        unknown_phase_elapsed = self.unknown_phase_elapsed or 0,
        unknown_phase_timeout = math.max(1, tonumber(config.bg.unknown_to_action_secs) or constants.BG.UNKNOWN_TO_ACTION_SECS or 30),
    }
end

----------------------------------------------------------------------
-- Main tick entry point
----------------------------------------------------------------------

function scanner:tick()
    self.tick_count = self.tick_count + 1

    local local_player = core.object_manager.get_local_player()
    if not safe_is_valid(local_player) then return end

    local now = (core and core.time and core.time()) or 0
    local self_pos = utils.pos_from_object(local_player)

    -- Always update self-state
    self:update_self(local_player, self_pos, now)

    -- Always update BG state
    self:update_bg_state(local_player, now)

    -- Visible-object scan (near + tactical rings)
    self:scan_visible(local_player, self_pos, now)

    -- Full reconciliation scan (every FULL_INTERVAL ticks)
    local full_scan_rate = math.max(1, tonumber(config.perception.full_scan_rate) or constants.SCAN.FULL_INTERVAL)
    if self.tick_count % full_scan_rate == 0 then
        self:scan_full(local_player, self_pos, now)
        self.last_full_scan = now
    end

    -- Update temporal metadata
    self.world_model:update_temporal({
        tick_count          = self.tick_count,
        last_full_scan      = self.last_full_scan,
        last_visible_scan   = now,
    })

    if config.debug.log_perception and self.tick_count % 30 == 0 then
        local counts = self.world_model:get_entity_counts()
        core.log(string.format(
            "[BGBOT][Perception] tick=%d allies=%d enemies=%d total=%d",
            self.tick_count, counts.allies, counts.enemies, counts.total
        ))
    end
end

----------------------------------------------------------------------
-- Self-state update
----------------------------------------------------------------------

function scanner:update_self(player, pos, now)
    self:resolve_faction(player)
    local spec_id = tonumber(select(1, safe_call_method(player, "get_specialization_id"))) or 0
    local in_combat = player:is_in_combat()

    local self_state = {
        handle       = player,
        position     = pos,
        health       = player:get_health(),
        max_health   = player:get_max_health(),
        health_pct   = (player:get_health() / math.max(1, player:get_max_health())) * 100,
        power        = player:get_power(0),      -- 0 = mana (PowerType enum)
        max_power    = player:get_max_power(0),
        power_pct    = (player:get_power(0) / math.max(1, player:get_max_power(0))) * 100,
        class_id     = player:get_class(),
        spec_id      = spec_id,
        group_role   = tonumber(player:get_group_role()) or constants.GROUP_ROLE.NONE,
        is_dead      = player:is_dead(),
        is_ghost     = player:is_ghost(),
        is_in_combat = in_combat,
        is_mounted   = player:is_mounted(),
        is_moving    = player:is_moving(),
        movement_speed = player:get_movement_speed(),
        rotation     = player:get_rotation(),
        buffs        = player:get_buffs(),
        debuffs      = player:get_debuffs(),
        is_casting   = player:is_casting_spell(),
        target       = player:get_target(),
        has_flag     = self:check_has_flag(player, nil, {
            now = now,
            force_refresh = true,
            is_self = true,
            distance = 0,
            is_in_combat = in_combat,
        }),
        faction      = self.faction,
        last_updated = now,
    }

    self.world_model:update_self(self_state)
end

----------------------------------------------------------------------
-- BG state update
----------------------------------------------------------------------

function scanner:update_bg_state(local_player, now)
    local map_id = core.get_map_id()
    local ui_map_id = core.game_ui.get_current_map_id()
    local phase = tonumber(core.game_ui.get_battlefield_state()) or 0
    local phase_source = (phase > 0) and "api" or "unknown"
    local run_time = tonumber(core.game_ui.get_battlefield_run_time()) or 0
    local status_indicates_prep = false
    local prep_active, prep_aura_id, prep_aura_name = self:detect_preparation_aura(local_player)
    local has_local_flag = self:check_has_flag(local_player, nil, {
        force_refresh = true,
        is_self = true,
        distance = 0,
        must_track = true,
    })

    -- Multi-BG detection: iterate ordered BG_MAP_REGISTRY, first match wins.
    local detected_bg_type = "unknown"
    for _, entry in ipairs(constants.BG_MAP_REGISTRY or {}) do
        if map_matches(map_id, entry.map_ids) then
            detected_bg_type = entry.bg_type
            break
        end
    end
    local in_bg_map = detected_bg_type ~= "unknown"

    -- Phase inference: only when inside a detected BG map.
    if in_bg_map then
        -- Fallback: infer phase when battlefield_state is unavailable/0.
        if phase <= 0 then
            for i = 0, 10 do
                local status = tostring(core.game_ui.get_battlefield_status(i) or "")
                status = status:lower():match("^%s*(.-)%s*$")
                if status == "active" then
                    phase = constants.BG_PHASE.ACTION
                    phase_source = "status_active"
                    break
                elseif status == "queued" or status == "confirm" then
                    status_indicates_prep = true
                end
            end

            if phase <= 0 and status_indicates_prep then
                phase = constants.BG_PHASE.PREP
                phase_source = "status_prep"
            end
        end

        -- Hard override: active Preparation aura always means pre-match phase.
        if prep_active then
            phase = constants.BG_PHASE.PREP
            phase_source = "prep_aura"
        end

        -- WSG-specific: If we have a flag aura, force ACTION even if prep aura detection is stale.
        if detected_bg_type == "wsg" and has_local_flag then
            phase = constants.BG_PHASE.ACTION
            phase_source = "self_has_flag"
            prep_active = false
            prep_aura_id = 0
            prep_aura_name = ""
        end
    else
        phase = 0
        phase_source = "outside_bg_map"
        prep_active = false
        prep_aura_id = 0
        prep_aura_name = ""
    end

    local bg = {
        phase    = phase,
        phase_source = phase_source,
        run_time = run_time,
        winner   = core.game_ui.get_battlefield_winner(),
        map_id   = map_id,     -- aligned with docs (Q-001, DEC-012)
        ui_map_id = ui_map_id, -- auxiliary runtime check
        has_preparation = prep_active,
        preparation_aura_id = prep_aura_id or 0,
        preparation_aura_name = prep_aura_name or "",
        bg_type  = detected_bg_type,

        -- WSG extensions (updated by flag inference, unused for non-WSG BGs)
        our_flag_state      = "unknown",
        their_flag_state    = "unknown",
        our_flag_carrier    = nil,
        their_flag_carrier  = nil,
        our_score           = nil,   -- INFERRED / no confirmed API (DEC-013)
        their_score         = nil,
    }

    -- Final phase fallback for environments where battlefield APIs are partial.
    if (bg.phase == nil or bg.phase == 0) and bg.bg_type ~= "unknown" and not prep_active then
        if (bg.run_time or 0) > 0 then
            bg.phase = constants.BG_PHASE.ACTION
            bg.phase_source = "runtime"
        end
    end

    -- WSG-only: If we clearly have a flag aura, the match is active.
    if (bg.phase == nil or bg.phase == 0) and bg.bg_type == "wsg" and has_local_flag then
        bg.phase = constants.BG_PHASE.ACTION
        bg.phase_source = "self_has_flag"
    end

    -- Private-server fallback: some servers return phase=0 once match starts.
    -- If we were previously in PREP, interpret 0 as ACTION.
    if (bg.phase == nil or bg.phase == 0) and bg.bg_type ~= "unknown" then
        if self.last_bg_phase == constants.BG_PHASE.PREP then
            bg.phase = constants.BG_PHASE.ACTION
            bg.phase_source = "prep_to_zero"
        -- Sticky fallback: once action has begun, keep ACTION even if API flickers to 0.
        elseif self.last_bg_phase == constants.BG_PHASE.ACTION then
            bg.phase = constants.BG_PHASE.ACTION
            bg.phase_source = "sticky_action"
        end
    end

    -- Timeout fallback: if phase stays unknown in a known BG with no prep aura,
    -- assume ACTION after a configurable grace period.
    if bg.bg_type ~= "unknown" and not prep_active and (bg.phase == nil or bg.phase == 0) then
        if self.unknown_phase_since == 0 then
            self.unknown_phase_since = now
        end

        local timeout_secs = math.max(1, tonumber(config.bg.unknown_to_action_secs) or constants.BG.UNKNOWN_TO_ACTION_SECS or 30)
        self.unknown_phase_elapsed = math.max(0, now - self.unknown_phase_since)
        if self.unknown_phase_elapsed >= timeout_secs then
            bg.phase = constants.BG_PHASE.ACTION
            bg.phase_source = "unknown_timeout"
        end
    else
        self.unknown_phase_since = 0
        self.unknown_phase_elapsed = 0
    end

    self.world_model:update_bg_state(bg)
    self.last_bg_phase = tonumber(bg.phase) or 0
    self.last_prep_active = prep_active
end

----------------------------------------------------------------------
-- Visible-object scan
----------------------------------------------------------------------

function scanner:scan_visible(local_player, self_pos, now)
    local objects = core.object_manager.get_visible_objects()
    if not objects then return end

    local stats = self.scan_debug_stats
    stats.visible_total = 0
    stats.visible_trackable = 0
    stats.visible_player_like = 0
    stats.visible_bg_objects = 0
    stats.visible_processed = 0

    local processed = 0
    for _, obj in pairs(objects) do
        stats.visible_total = stats.visible_total + 1

        if obj ~= local_player and safe_is_valid(obj) then
            local is_player_like = filters.is_player_like(obj)
            local is_bg_object = false
            local is_basic = select(1, safe_call_method(obj, "is_basic_object")) == true
            if is_basic then
                local npc_id = select(1, safe_call_method(obj, "get_npc_id"))
                is_bg_object = npc_id and (constants.BG_OBJECT_IDS[npc_id] ~= nil or constants.WSG_OBJECT_IDS[npc_id] ~= nil)
            end

            if is_player_like then
                stats.visible_player_like = stats.visible_player_like + 1
            end
            if is_bg_object then
                stats.visible_bg_objects = stats.visible_bg_objects + 1
            end
            if is_player_like or is_bg_object then
                stats.visible_trackable = stats.visible_trackable + 1
            end
        end

        if processed >= constants.SCAN.MAX_ENTITY_PER_TICK then break end

        if obj ~= local_player and filters.is_trackable(obj) then
            local obj_pos  = utils.pos_from_object(obj)
            local distance = utils.distance_3d(self_pos, obj_pos)
            local ring     = filters.assign_ring(distance)

            -- Near ring: update every tick
            -- Tactical ring: update every TACTICAL_INTERVAL ticks
            local should_update = (ring == "near")
                or (ring == "tactical" and self.tick_count % constants.SCAN.TACTICAL_INTERVAL == 0)

            if should_update then
                local ok = pcall(function()
                    self:build_entity_record(obj, local_player, obj_pos, distance, ring, now)
                end)
                if ok then
                    processed = processed + 1
                end
            end
        end
    end

    stats.visible_processed = processed
end

function scanner:detect_preparation_aura(player)
    if not safe_is_valid(player) then
        return false, 0, ""
    end

    local function matches_prep(aura)
        local id = tonumber(aura.buff_id) or 0
        local name = tostring(aura.buff_name or "")
        local lname = string.lower(name)

        for _, prep_id in ipairs(constants.BG_PREP_AURA_IDS or {}) do
            if id == prep_id then
                return true, id, name
            end
        end

        for _, needle in ipairs(constants.BG_PREP_AURA_NAME_MATCH or {}) do
            if needle ~= "" and string.find(lname, needle, 1, true) then
                return true, id, name
            end
        end

        return false, 0, ""
    end

    local now = (core and core.time and core.time()) or 0
    local aura_lists = {
        select(1, self:get_auras_cached(player, now, {
            force_refresh = true,
            is_self = true,
            distance = 0,
            is_in_combat = false,
        })),
        select(1, safe_call_method(player, "get_buffs")),
    }

    for _, list in ipairs(aura_lists) do
        if list then
            for _, aura in pairs(list) do
                local ok, id, name = matches_prep(aura)
                if ok then
                    return true, id, name
                end
            end
        end
    end

    return false, 0, ""
end

function scanner:get_aura_cache_entry(obj)
    if not obj then
        return nil
    end
    return self.aura_cache[cache_key_for_obj(obj)]
end

function scanner:should_refresh_auras(cache_entry, now, opts)
    if opts and opts.force_refresh then
        return true
    end
    if not cache_entry then
        return true
    end

    local interval = aura_scan_interval(opts, cache_entry.has_any_flag == true)
    local elapsed = now - (cache_entry.fetched_at or 0)
    if elapsed >= interval then
        return true
    end

    local distance = tonumber(opts and opts.distance)
    if distance and cache_entry.distance then
        if math.abs(distance - cache_entry.distance) >= AURA_DISTANCE_DELTA_REFRESH then
            return true
        end
    end

    local in_combat = opts and opts.is_in_combat
    if in_combat ~= nil and cache_entry.is_in_combat ~= nil and in_combat ~= cache_entry.is_in_combat then
        if elapsed >= AURA_REFRESH_NEAR then
            return true
        end
    end

    return false
end

function scanner:get_auras_cached(obj, now, opts)
    if not safe_is_valid(obj) then
        return nil, false
    end

    opts = opts or {}
    local key = cache_key_for_obj(obj)
    local cache_entry = self.aura_cache[key]
    if not self:should_refresh_auras(cache_entry, now, opts) then
        return cache_entry.auras, true
    end

    local auras, ok = safe_call_method(obj, "get_auras")
    if not ok or not auras then
        if cache_entry and cache_entry.auras then
            return cache_entry.auras, true
        end
        return nil, false
    end

    local has_horde = false
    local has_alliance = false
    for _, aura in pairs(auras) do
        local id = aura.buff_id or 0
        if id == constants.FLAG_AURAS.HORDE_FLAG then
            has_horde = true
        elseif id == constants.FLAG_AURAS.ALLIANCE_FLAG then
            has_alliance = true
        end
    end

    self.aura_cache[key] = {
        auras = auras,
        fetched_at = now,
        distance = tonumber(opts.distance),
        is_in_combat = opts.is_in_combat,
        has_horde_flag = has_horde,
        has_alliance_flag = has_alliance,
        has_any_flag = has_horde or has_alliance,
    }

    return auras, true
end

function scanner:prune_aura_cache(now)
    if (now - (self.last_aura_cache_prune or 0)) < AURA_CACHE_PRUNE_INTERVAL then
        return
    end

    self.last_aura_cache_prune = now
    for key, entry in pairs(self.aura_cache) do
        local fetched_at = entry and entry.fetched_at or 0
        if (now - fetched_at) > (AURA_CACHE_STALE_GRACE + AURA_REFRESH_FAR) then
            self.aura_cache[key] = nil
        end
    end
end

----------------------------------------------------------------------
-- Full reconciliation scan
----------------------------------------------------------------------

function scanner:scan_full(local_player, self_pos, now)
    local objects = core.object_manager.get_all_objects()
    if not objects then return end
    self:prune_aura_cache(now)

    local stats = self.scan_debug_stats
    stats.full_total = 0
    stats.full_trackable = 0
    stats.full_player_like = 0
    stats.full_bg_objects = 0
    stats.full_processed = 0

    local processed = 0
    for _, obj in pairs(objects) do
        stats.full_total = stats.full_total + 1

        if obj ~= local_player and safe_is_valid(obj) then
            local is_player_like = filters.is_player_like(obj)
            local is_bg_object = false
            local is_basic = select(1, safe_call_method(obj, "is_basic_object")) == true
            if is_basic then
                local npc_id = select(1, safe_call_method(obj, "get_npc_id"))
                is_bg_object = npc_id and (constants.BG_OBJECT_IDS[npc_id] ~= nil or constants.WSG_OBJECT_IDS[npc_id] ~= nil)
            end

            if is_player_like then
                stats.full_player_like = stats.full_player_like + 1
            end
            if is_bg_object then
                stats.full_bg_objects = stats.full_bg_objects + 1
            end
            if is_player_like or is_bg_object then
                stats.full_trackable = stats.full_trackable + 1
            end
        end

        if processed >= constants.SCAN.MAX_ENTITY_FULL then break end

        if obj ~= local_player and filters.is_trackable(obj) then
            local obj_pos  = utils.pos_from_object(obj)
            local distance = utils.distance_3d(self_pos, obj_pos)
            local ring     = filters.assign_ring(distance)

            local ok = pcall(function()
                self:build_entity_record(obj, local_player, obj_pos, distance, ring, now)
            end)
            if ok then
                processed = processed + 1
            end
        end
    end

    stats.full_processed = processed
    stats.last_full_tick = self.tick_count
    stats.last_full_time = now

    -- Run flag inference after full scan (WSG only)
    local bg_state = self.world_model:get_bg_state()
    if bg_state and bg_state.bg_type == "wsg" then
        self:infer_flag_state(local_player, now)
    end
end

----------------------------------------------------------------------
-- Build entity record & push to world model
----------------------------------------------------------------------

function scanner:build_entity_record(obj, local_player, pos, distance, ring, now)
    if obj:is_basic_object() then
        local npc_id = obj:get_npc_id()
        -- Check unified BG_OBJECT_IDS first, then legacy WSG_OBJECT_IDS
        local meta = constants.BG_OBJECT_IDS[npc_id] or constants.WSG_OBJECT_IDS[npc_id]
        local name = obj:get_name()
        if (not name or name == "") and meta then
            name = meta.name
        end

        local object_kind = meta and meta.kind or "basic_object"
        local is_flag = object_kind == "flag"
        local is_buff = meta and string.find(object_kind, "buff_", 1, true) == 1 or false
        local is_banner = meta and (string.find(object_kind, "banner_", 1, true) == 1) or false
        local is_cap_point = object_kind == "cap_point"

        local record = {
            handle           = obj,
            name             = name or ("object_" .. tostring(npc_id or 0)),
            npc_id           = npc_id,
            object_kind      = object_kind,
            is_flag_object   = is_flag,
            is_buff_object   = is_buff,
            is_banner_object = is_banner,
            is_cap_point     = is_cap_point,
            bg_affinity      = meta and meta.bg or nil,
            position         = pos,
            health_pct       = 100,
            power_pct        = 0,
            class_id         = 0,
            spec_id          = 0,
            group_role       = constants.GROUP_ROLE.NONE,
            is_player        = false,
            is_enemy         = false,
            is_ally          = false,
            is_dead          = false,
            is_in_combat     = false,
            is_mounted       = false,
            is_moving        = false,
            movement_speed   = 0,
            target_handle    = nil,
            has_flag         = false,
            is_casting       = false,
            buffs            = {},
            debuffs          = {},
            distance         = distance,
            last_seen        = now,
            confidence       = 1.0,
            ring             = ring,
        }

        self.world_model:update_entity(obj, record)
        return
    end

    local is_player_like = filters.is_player_like(obj)
    local is_enemy_with_local = obj:is_enemy_with(local_player)
    local spec_id = tonumber(select(1, safe_call_method(obj, "get_specialization_id"))) or 0
    local is_in_combat = obj:is_in_combat()

    local record = {
        handle           = obj,
        name             = obj:get_name(),
        npc_id           = obj:get_npc_id(),
        position         = pos,
        health_pct       = (obj:get_health() / math.max(1, obj:get_max_health())) * 100,
        power_pct        = (obj:get_power(0) / math.max(1, obj:get_max_power(0))) * 100,
        class_id         = obj:get_class(),
        spec_id          = spec_id,
        group_role       = tonumber(obj:get_group_role()) or constants.GROUP_ROLE.NONE,
        is_player        = is_player_like,
        is_enemy         = is_enemy_with_local,
        is_ally          = not is_enemy_with_local,
        is_dead          = obj:is_dead(),
        is_in_combat     = is_in_combat,
        is_mounted       = obj:is_mounted(),
        is_moving        = obj:is_moving(),
        movement_speed   = obj:get_movement_speed(),
        target_handle    = obj:get_target(),
        has_flag         = self:check_has_flag(obj, nil, {
            now = now,
            distance = distance,
            ring = ring,
            is_in_combat = is_in_combat,
        }),
        is_casting       = obj:is_casting_spell(),
        buffs            = obj:get_buffs(),
        debuffs          = obj:get_debuffs(),
        distance         = distance,
        last_seen        = now,
        confidence       = 1.0,
        ring             = ring,
    }

    self.world_model:update_entity(obj, record)
end

----------------------------------------------------------------------
-- Faction helpers
----------------------------------------------------------------------

function scanner:set_faction(faction, source, force)
    if faction == nil or faction == constants.FACTION.UNKNOWN then return end
    local next_source = tostring(source or "unknown")
    local current_source = tostring(self.faction_source or "unknown")
    local next_rank = faction_source_rank(next_source)
    local current_rank = faction_source_rank(current_source)

    if not force and self.faction ~= constants.FACTION.UNKNOWN and faction ~= self.faction and next_rank <= current_rank then
        return
    end

    if self.faction == faction and current_rank >= next_rank then
        return
    end

    self.faction = faction
    self.faction_source = next_source

    if config.debug.log_perception then
        core.log(string.format(
            "[BGBOT][Perception] Faction resolved: %s (%s)",
            faction == constants.FACTION.HORDE and "horde" or "alliance",
            next_source
        ))
    end
end

function scanner:resolve_faction(player)
    if not safe_is_valid(player) then return end

    -- Highest-confidence source: local carried-flag aura.
    if self:check_has_flag(player, constants.FLAG_AURAS.HORDE_FLAG, {
        force_refresh = true,
        is_self = true,
        distance = 0,
        must_track = true,
    }) then
        self:set_faction(constants.FACTION.ALLIANCE, "self_horde_flag_aura", true)
        return
    end
    if self:check_has_flag(player, constants.FLAG_AURAS.ALLIANCE_FLAG, {
        force_refresh = true,
        is_self = true,
        distance = 0,
        must_track = true,
    }) then
        self:set_faction(constants.FACTION.HORDE, "self_alliance_flag_aura", true)
        return
    end

    local faction_id = tonumber(select(1, safe_call_method(player, "get_faction_id"))) or 0
    local mapped = constants.FACTION_BY_ID[faction_id]
    if mapped then
        self:set_faction(mapped, "faction_id:" .. tostring(faction_id))
        return
    end
end

function scanner:infer_faction_from_flag(ent, aura_id)
    if not ent then return end

    if aura_id == constants.FLAG_AURAS.HORDE_FLAG then
        -- Alliance players carry Horde flag aura.
        if ent.is_ally then
            self:set_faction(constants.FACTION.ALLIANCE, "ally_horde_flag_aura")
        elseif ent.is_enemy then
            self:set_faction(constants.FACTION.HORDE, "enemy_horde_flag_aura")
        end
    elseif aura_id == constants.FLAG_AURAS.ALLIANCE_FLAG then
        -- Horde players carry Alliance flag aura.
        if ent.is_ally then
            self:set_faction(constants.FACTION.HORDE, "ally_alliance_flag_aura")
        elseif ent.is_enemy then
            self:set_faction(constants.FACTION.ALLIANCE, "enemy_alliance_flag_aura")
        end
    end
end

function scanner:get_team_flag_auras()
    -- Return: our_flag_aura, enemy_flag_aura
    if self.faction == constants.FACTION.HORDE then
        return constants.FLAG_AURAS.HORDE_FLAG, constants.FLAG_AURAS.ALLIANCE_FLAG
    elseif self.faction == constants.FACTION.ALLIANCE then
        return constants.FLAG_AURAS.ALLIANCE_FLAG, constants.FLAG_AURAS.HORDE_FLAG
    end
    return nil, nil
end

----------------------------------------------------------------------
-- Flag aura checks (A-001)
----------------------------------------------------------------------

function scanner:check_has_flag(obj, flag_aura_id, opts)
    if not safe_is_valid(obj) then return false end
    local scan_opts = opts or {}
    local now = scan_opts.now or ((core and core.time and core.time()) or 0)
    local auras, ok = self:get_auras_cached(obj, now, scan_opts)
    if not ok or not auras then return false end

    local cache_entry = self:get_aura_cache_entry(obj)
    if cache_entry then
        if flag_aura_id == nil then
            return cache_entry.has_any_flag == true
        elseif flag_aura_id == constants.FLAG_AURAS.HORDE_FLAG then
            return cache_entry.has_horde_flag == true
        elseif flag_aura_id == constants.FLAG_AURAS.ALLIANCE_FLAG then
            return cache_entry.has_alliance_flag == true
        end
    end

    for _, aura in pairs(auras) do
        local id = aura.buff_id or 0
        if flag_aura_id ~= nil then
            if id == flag_aura_id then
                return true
            end
        elseif id == constants.FLAG_AURAS.HORDE_FLAG
            or id == constants.FLAG_AURAS.ALLIANCE_FLAG then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------
-- Flag state inference (runs after full scans)
----------------------------------------------------------------------

function scanner:infer_flag_state(local_player, now)
    local bg = self.world_model:get_bg_state()
    if not bg or bg.bg_type ~= "wsg" then return end

    self:resolve_faction(local_player)

    local self_state = self.world_model:get_self()
    local self_pos = self_state and self_state.position or nil
    local our_carrier    = nil
    local their_carrier  = nil
    local our_flag_aura, enemy_flag_aura = self:get_team_flag_auras()

    local entities = self.world_model:get_all_entities()
    for _, ent in pairs(entities) do
        if ent and ent.handle and ent.is_player and not ent.is_dead and safe_is_valid(ent.handle) then
            local distance = tonumber(ent.distance)
            if (not distance or distance >= 999999) and self_pos and ent.position then
                distance = utils.distance_3d(self_pos, ent.position)
            end

            local should_probe = (ent.has_flag == true)
            if not should_probe and distance and distance <= constants.RING.NEAR_MAX then
                should_probe = true
            end

            if should_probe then
                self:get_auras_cached(ent.handle, now, {
                    distance = distance,
                    ring = ent.ring,
                    is_in_combat = ent.is_in_combat,
                    must_track = ent.has_flag == true,
                })

                local cache_entry = self:get_aura_cache_entry(ent.handle)
                if cache_entry and cache_entry.has_any_flag then
                    local function apply_flag(id)
                        self:infer_faction_from_flag(ent, id)
                        our_flag_aura, enemy_flag_aura = self:get_team_flag_auras()

                        if ent.is_ally and enemy_flag_aura and id == enemy_flag_aura then
                            our_carrier = ent.handle
                        elseif ent.is_enemy and our_flag_aura and id == our_flag_aura then
                            their_carrier = ent.handle
                        end
                    end

                    if cache_entry.has_horde_flag then
                        apply_flag(constants.FLAG_AURAS.HORDE_FLAG)
                    end
                    if cache_entry.has_alliance_flag then
                        apply_flag(constants.FLAG_AURAS.ALLIANCE_FLAG)
                    end
                end
            end
        end
    end

    -- Check self (can carry enemy flag only)
    if self_state and self_state.handle and safe_is_valid(self_state.handle) then
        if self.faction == constants.FACTION.UNKNOWN then
            self:resolve_faction(self_state.handle)
            our_flag_aura, enemy_flag_aura = self:get_team_flag_auras()
        end

        if enemy_flag_aura and self:check_has_flag(self_state.handle, enemy_flag_aura, {
            now = now,
            force_refresh = true,
            is_self = true,
            distance = 0,
            is_in_combat = self_state.is_in_combat,
            must_track = true,
        }) then
            our_carrier = self_state.handle
        end
    end

    -- Push inferred flag state
    self.world_model:update_flag_inference({
        our_flag_carrier   = our_carrier,
        their_flag_carrier = their_carrier,
        our_flag_state     = their_carrier and "carried" or "unknown",
        their_flag_state   = our_carrier and "carried" or "unknown",
    })
end

return scanner
