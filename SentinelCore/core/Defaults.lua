---@class SentinelDefaults
local Defaults = {}

Defaults.runtime = {
    game_version = "Classic Tbc",
    mode = "grind",
    context_resolve_interval = 10.0,
    dependency_health_interval = 5.0,
    update_order = {
        "sensors",
        "dependency_health",
        "mode",
        "services",
        "recovery",
        "telemetry",
    },
}

Defaults.recovery = {
    auto_restart_enabled = true,
    auto_restart_max_attempts = 3,
    auto_restart_backoff_secs = { 2, 5, 10 },
}

Defaults.world_data = {
    base_url = "http://127.0.0.1:47120",
    max_retries = 2,
    retry_backoff_secs = 0.5,
    health_endpoint = "/health",
    api_version_prefix = "/api/v1",
    min_confidence = 0.60,
    expected_game_version = "tbc",
    expected_source = "cmangos",
}

Defaults.targeting = {
    base_radius = 45.0,
    max_radius = 75.0,
    defensive_retarget_radius = 35.0,
    pull_range = 30.0,
    only_engage_opposing_faction_if_attacked = true,
    score_weights = {
        kill_speed = 0.40,
        loot_value = 0.20,
        travel_cost = 0.30,
        risk = 0.10,
    },
}

Defaults.objective = {
    objective_timeout = 120.0,
    progress_emit_interval = 1.0,
}

Defaults.combat = {
    combat_timeout = 30.0,
    pull_timeout = 8.0,
    min_pull_mana_pct = 0.12,
    pull_chase_repath_distance = 3.0,
    pull_chase_repath_cooldown = 0.35,
    pull_chase_move_to_cooldown = 0.75,
    combat_chase_range = 5.5,
    combat_chase_repath_distance = 3.0,
    combat_chase_repath_cooldown = 0.35,
    combat_chase_move_to_cooldown = 0.75,
    combat_face_cooldown = 0.20,
    combat_face_max_distance = 7.0,
    combat_face_realign_distance = 0.75,
    action_throttle = 0.15,
    aoe_enemy_threshold = 3,
}

Defaults.rotation = {
    paladin = {
        retribution = {
            drink_mana_pct = 0.45,
            eat_health_pct = 0.80,
            loh_hp_pct = 0.10,
            divine_shield_hp_pct = 0.20,
            divine_protection_hp_pct = 0.35,
            holy_light_hp_pct = 0.60,
            holy_light_min_mana_pct = 0.22,
            flash_light_hp_pct = 0.45,
            flash_light_very_oom_mana_pct = 0.12,
            heal_low_mana_threshold = 0.22,
            heal_critical_mana_threshold = 0.08,
            health_potion_hp_pct = 0.30,
            mana_potion_mana_pct = 0.15,
            mana_potion_min_hp_pct = 0.35,
            consecration_st_min_mana_pct = 0.35,
            consecration_aoe_min_mana_pct = 0.45,
            exorcism_min_mana_pct = 0.55,
            holy_wrath_aoe_min_mana_pct = 0.30,
        },
    },
    warlock = {
        affliction = {
            drink_mana_pct = 0.40,
            eat_health_pct = 0.65,
            life_tap_min_health_pct = 0.50,
            life_tap_max_mana_pct = 0.60,
            life_tap_ooc_max_mana_pct = 0.85,
            death_coil_hp_pct = 0.25,
            drain_life_hp_pct = 0.45,
            health_funnel_pet_hp_pct = 0.30,
            health_potion_hp_pct = 0.25,
            mana_potion_mana_pct = 0.15,
            mana_potion_min_hp_pct = 0.35,
            wand_mana_pct = 0.08,
        },
    },
}

Defaults.loot = {
    loot_timeout = 8.0,
    interaction_retry_limit = 3,
    interaction_retry_delay = 0.6,
}

Defaults.inventory = {}  -- bag capacity computed dynamically from equipped bags

Defaults.vendor = {
    search_radius = 250.0,
    min_free_slots = 2,
    interaction_timeout = 10.0,
    return_timeout = 25.0,
    return_to_anchor = true,
    candidate_blacklist_secs = 90,
    candidate_cache_max_entries = 500,
    require_sell = true,
    require_repair = false,
}

Defaults.telemetry = {
    flush_interval = 1.0,
}

Defaults.policy = {
    schema_version = "vendor_inventory_policy.v1",
    updated_at_unix = 0,
    vendor_enabled = true,
    min_free_slots = 2,
    sell_quality_max = 1,
    repair_enabled = true,
    sell_gray = true,
    sell_white = false,
    sell_green = false,
    sell_blue = false,
    sell_epic = false,
    never_sell = {},
    always_sell = {},
    keep_stack_min = {},
    special_rules = {},
}

Defaults.runtime_state = {
    schema_version = "runtime_state.v1",
    last_session_id = "",
    last_state = "idle",
    last_error_code = "",
    auto_restart_attempts_used = 0,
    last_known_context = {
        canonical_map_id = 0,
        zone_id = 0,
        area_id = 0,
        x = 0,
        y = 0,
        z = 0,
    },
    last_grind_anchor = {
        x = 0,
        y = 0,
        z = 0,
    },
    updated_at_unix = 0,
}

Defaults.vendor_cache = {
    schema_version = "vendor_runtime_cache.v1",
    entries = {},
    updated_at_unix = 0,
}

Defaults.profiles = {
    schema_version = "runtime_profiles.v1",
    active_profile_id = "default",
    profiles = {},
    updated_at_unix = 0,
}

---@param value any
---@return any
local function deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[deep_copy(k)] = deep_copy(v)
    end
    return out
end

---@param extra? table
---@return table
function Defaults.build_runtime(extra)
    local cfg = {
        runtime = deep_copy(Defaults.runtime),
        recovery = deep_copy(Defaults.recovery),
        world_data = deep_copy(Defaults.world_data),
        targeting = deep_copy(Defaults.targeting),
        objective = deep_copy(Defaults.objective),
        combat = deep_copy(Defaults.combat),
        rotation = deep_copy(Defaults.rotation),
        loot = deep_copy(Defaults.loot),
        inventory = deep_copy(Defaults.inventory),
        vendor = deep_copy(Defaults.vendor),
        telemetry = deep_copy(Defaults.telemetry),
    }

    if type(extra) == "table" then
        for section, section_values in pairs(extra) do
            if type(section_values) == "table" and type(cfg[section]) == "table" then
                for key, value in pairs(section_values) do
                    cfg[section][key] = value
                end
            else
                cfg[section] = section_values
            end
        end
    end

    return cfg
end

---@param obj any
---@return any
function Defaults.copy(obj)
    return deep_copy(obj)
end

return Defaults
