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

Defaults.death = {
    death_release_delay_secs = 2.5,
    death_release_retry_secs = 2.0,
    death_move_to_cooldown = 0.9,
    death_move_reissue_distance = 1.0,
    death_resurrect_distance = 10.0,
    death_resurrect_retry_secs = 0.75,
    corpse_max_path_cost = 800,
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
    pull_risk_budget = 1.20,
    pull_risk_deaths_per_hour_low = 0.20,
    pull_risk_deaths_per_hour_high = 1.50,
    pull_risk_budget_min_scale = 0.45,
    pull_risk_budget_max_scale = 1.00,
    pull_risk_budget_min_absolute = 0.20,
    pull_add_scan_radius = 10.0,
    pull_add_risk_weight = 0.20,
    memory_failure_risk_penalty = 0.12,
    path_cost_cache_ttl = 8.0,
    path_cost_request_interval = 1.5,
    path_cost_prune_interval = 2.0,
    path_cost_cache_max_entries = 256,
    path_unreachable_ttl = 20.0,
    path_unreachable_risk_penalty = 1.0,
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

Defaults.exploration = {
    enabled = true,
    enabled_modes = { "grind" },
    cell_size = 18.0,
    cell_memory_ttl = 360.0,
    cell_memory_max_entries = 512,
    recent_cells = 8,
    sighting_gain = 1.0,
    sighting_cap = 8.0,
    pursuit_extra_radius = 30.0,
    pursuit_min_gap = 2.0,
    pursuit_distance_weight = 0.15,
    pursuit_stale_timeout = 1.5,
    frontier_min_radius = 20.0,
    frontier_max_radius = 65.0,
    frontier_ring_count = 3,
    frontier_rays = 20,
    novelty_horizon = 120.0,
    seen_horizon = 90.0,
    weight_novelty = 0.55,
    weight_sighting = 0.30,
    weight_travel = 0.20,
    weight_recent = 0.35,
    weight_failure = 0.60,
    destination_switch_distance = 2.5,
    destination_switch_cooldown = 0.75,
    destination_switch_min_gain = 0.05,
    move_to_cooldown = 0.30,
    soft_repath_cooldown = 0.25,
    soft_repath_distance = 1.5,
    arrive_distance = 6.5,
    cell_failure_cooldown = 8.0,
    max_failures_before_reset = 2,
}

Defaults.combat = {
    combat_timeout = 30.0,
    pull_timeout = 8.0,
    min_pull_mana_pct = 0.12,
    min_pull_health_pct = 0.30,
    recovery_deaths_per_hour_low = 0.20,
    recovery_deaths_per_hour_high = 1.50,
    recovery_mana_bonus_max = 0.20,
    recovery_health_bonus_max = 0.10,
    recovery_idle_relax_start_pct = 0.18,
    recovery_idle_relax_full_pct = 0.35,
    recovery_idle_mana_relief_max = 0.06,
    recovery_idle_health_relief_max = 0.04,
    recovery_mana_floor_pct = 0.00,
    recovery_mana_ceiling_pct = 0.65,
    recovery_health_floor_pct = 0.00,
    recovery_health_ceiling_pct = 0.95,
    pull_engage_range_padding = 0.35,
    pull_in_range_stability_window = 0.20,
    pull_in_range_stability_band = 1.25,
    pull_chase_repath_distance = 2.2,
    pull_chase_repath_cooldown = 0.35,
    pull_chase_move_to_cooldown = 0.50,
    pull_chase_refresh_cooldown = 2.25,
    pull_auto_attack_commit_range = 4.5,
    pull_auto_attack_trigger_range = 5.5,
    combat_chase_range = 5.5,
    combat_chase_repath_distance = 2.2,
    combat_chase_repath_cooldown = 0.35,
    combat_chase_move_to_cooldown = 0.50,
    combat_chase_refresh_cooldown = 2.00,
    chase_destination_lateral_gate = 0.0,
    chase_destination_vertical_gate = 0.0,
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
            rest_until_full = true,
            rest_resume_health_pct = 1.00,
            rest_resume_mana_pct = 1.00,
            loh_hp_pct = 0.10,
            divine_shield_hp_pct = 0.20,
            divine_protection_hp_pct = 0.35,
            holy_light_hp_pct = 0.65,
            holy_light_min_mana_pct = 0.15,
            flash_light_hp_pct = 0.65,
            heal_low_mana_threshold = 0.22,
            heal_critical_mana_threshold = 0.08,
            health_potion_hp_pct = 0.30,
            mana_potion_mana_pct = 0.15,
            mana_potion_min_hp_pct = 0.35,
            consecration_st_min_mana_pct = 0.35,
            consecration_aoe_min_mana_pct = 0.45,
            exorcism_min_mana_pct = 0.55,
            holy_wrath_aoe_min_mana_pct = 0.30,
            mana_sustain_enter_pct = 0.48,
            mana_sustain_exit_pct = 0.60,
            mana_recovery_enter_pct = 0.24,
            mana_recovery_exit_pct = 0.34,
            holy_light_execute_hold_hp_pct = 0.45,
            execute_ttd_horizon_sec = 8.0,
            flash_light_execute_hold_ttd_sec = 4.0,
            holy_light_execute_hold_ttd_sec = 6.0,
            hammer_of_wrath_min_ttd_sec = 0.80,
            consecration_aoe_min_ttd_sec = 4.50,
            hoj_defensive_hp_pct = 0.52,
            hoj_defensive_min_ttd_sec = 2.0,
            repentance_defensive_hp_pct = 0.34,
            repentance_defensive_min_ttd_sec = 4.5,
            repentance_defensive_min_distance = 6.0,
            ttd_alpha = 0.35,
            ttd_min_sample_secs = 0.20,
            ttd_memory_ttl_secs = 20.0,
            ttd_max_seconds = 120.0,
        },
    },
    warlock = {
        affliction = {
            drink_mana_pct = 0.15,
            eat_health_pct = 0.45,
            rest_until_full = true,
            rest_resume_health_pct = 0.80,
            rest_resume_mana_pct = 0.55,
            life_tap_min_health_pct = 0.50,
            life_tap_max_mana_pct = 0.85,
            life_tap_ooc_max_mana_pct = 0.90,
            death_coil_hp_pct = 0.35,
            drain_life_hp_pct = 0.55,
            health_funnel_pet_hp_pct = 0.30,
            health_potion_hp_pct = 0.25,
            mana_potion_mana_pct = 0.15,
            mana_potion_min_hp_pct = 0.35,
            wand_mana_pct = 0.05,
            mana_sustain_enter_pct = 0.35,
            mana_sustain_exit_pct = 0.50,
            mana_recovery_enter_pct = 0.12,
            mana_recovery_exit_pct = 0.22,
            ttd_alpha = 0.35,
            ttd_min_sample_secs = 0.20,
            ttd_memory_ttl_secs = 20.0,
            ttd_max_seconds = 120.0,
            execute_target_health_pct = 0.25,
            execute_ttd_horizon_sec = 8.0,
            corruption_min_ttd_sec = 6.0,
            curse_of_agony_min_ttd_sec = 6.0,
            immolate_min_ttd_sec = 5.0,
            siphon_life_min_ttd_sec = 8.0,
            unstable_affliction_min_ttd_sec = 6.0,
            dot_refresh_window_sec = 4.5,
        },
    },
}

Defaults.loot = {
    loot_timeout = 8.0,
    interaction_retry_limit = 3,
    interaction_retry_delay = 0.6,
    loot_interact_range = 5.0,
    loot_approach_max_distance = 45.0,
    loot_approach_timeout = 2.5,
    loot_approach_reissue_cooldown = 0.75,
    zero_loot_confirm_delay = 0.2,
}

Defaults.inventory = {}  -- bag capacity computed dynamically from equipped bags

Defaults.vendor = {
    search_radius = 2000.0,
    candidate_fetch_limit = 10,
    min_free_slots = 2,
    interaction_timeout = 10.0,
    return_timeout = 25.0,
    return_to_anchor = true,
    candidate_blacklist_secs = 90,
    candidate_cache_max_entries = 500,
    require_sell = true,
    require_repair = false,
    -- Sell loop timing
    vendor_interact_delay = 0.75,
    vendor_sell_delay = 0.30,
    vendor_sell_timeout = 30.0,
    -- Repair
    repair_threshold = 0.25,
}

Defaults.telemetry = {
    flush_interval = 1.0,
    idle_full_resource_threshold = 0.98,
}

Defaults.logging = {
    global_level = "INFO",
    console_logger_enabled = true,
    max_history = 200,
}

Defaults.mount = {
    enabled = true,
    min_travel_distance = 30.0,   -- only mount if > 30m to destination
    min_level = 40,
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
    max_session_minutes = 240,
}

Defaults.zone_overrides = {}

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
    dry_spell_secs = 15,
    travel_engage = true,
    loop = true,
    hotspot_arrival_radius_mult = 1.0,
    vendor_durability_threshold = 0.25,
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
        death = deep_copy(Defaults.death),
        world_data = deep_copy(Defaults.world_data),
        targeting = deep_copy(Defaults.targeting),
        objective = deep_copy(Defaults.objective),
        exploration = deep_copy(Defaults.exploration),
        combat = deep_copy(Defaults.combat),
        rotation = deep_copy(Defaults.rotation),
        loot = deep_copy(Defaults.loot),
        inventory = deep_copy(Defaults.inventory),
        vendor = deep_copy(Defaults.vendor),
        telemetry = deep_copy(Defaults.telemetry),
        logging = deep_copy(Defaults.logging),
        mount = deep_copy(Defaults.mount),
        zone_overrides = deep_copy(Defaults.zone_overrides),
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
