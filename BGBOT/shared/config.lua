---@module BGBOT.shared.config
-- Runtime configuration with defaults.
-- Menu integration (core.menu.*) will be wired in M3.

local constants = require("shared/constants")

local config = {}

----------------------------------------------------------------------
-- Master toggle
----------------------------------------------------------------------
config.enabled = true

----------------------------------------------------------------------
-- Debug / Logging
----------------------------------------------------------------------
config.debug = {
    log_perception  = false,
    log_world_model = false,
    log_intent      = true,
    log_combat      = false,
    log_nav         = false,
    log_humanize    = false,
}

----------------------------------------------------------------------
-- Perception Overrides
----------------------------------------------------------------------
config.perception = {
    near_range     = constants.RING.NEAR_MAX,
    tactical_range = constants.RING.TACTICAL_MAX,
    full_scan_rate = constants.SCAN.FULL_INTERVAL,
}

----------------------------------------------------------------------
-- Intent Controller Overrides
----------------------------------------------------------------------
config.intent = {
    switch_margin   = constants.INTENT.SWITCH_MARGIN,
    switch_cooldown = constants.INTENT.SWITCH_COOLDOWN,
}

----------------------------------------------------------------------
-- Role / Playstyle
----------------------------------------------------------------------
config.role = {
    -- 0=auto, 1=dps, 2=healer, 3=tankish
    mode = constants.ROLE.AUTO,
}

----------------------------------------------------------------------
-- Combat Overrides
----------------------------------------------------------------------
config.combat = {
    min_target_score  = constants.COMBAT.TARGET_SCORE_MIN,
    chase_range       = constants.COMBAT.DEFAULT_CHASE_RANGE,
    retreat_hp_pct    = constants.COMBAT.RETREAT_HEALTH_PCT,
}

----------------------------------------------------------------------
-- Humanization Overrides
----------------------------------------------------------------------
config.humanization = {
    enabled = true,
    reaction_base_multiplier = 1.0,
    hesitation_chance = 0.08,
    nav_jitter_yards = 3.0,
    fatigue_enabled = true,
    fatigue_max_factor = 1.4,
    cast_delay_enabled = false,
    max_idle_seconds = constants.HUMAN.MAX_IDLE_SECS,
}

----------------------------------------------------------------------
-- Structured Telemetry
----------------------------------------------------------------------
config.telemetry = {
    enabled = false,
    dir = "BGBOT/data/telemetry",
    file_name = "events.ndjson",
    summary_file_name = "match_summaries.ndjson",
}

----------------------------------------------------------------------
-- Nav Overrides
----------------------------------------------------------------------
config.nav = {
    max_inflight = constants.NAV.MAX_INFLIGHT,
    repath_cd    = constants.NAV.REPATH_CD,
    stale_path   = constants.NAV.STALE_PATH,
    objective_blacklist_threshold = 3,
    objective_blacklist_window = 20,
    objective_blacklist_cooldown = 30,
}

----------------------------------------------------------------------
-- WSG Tactical Behavior
----------------------------------------------------------------------
config.wsg = {
    enable_buff_pickups      = true,
    buff_detour_max          = constants.WSG.BUFF_DETOUR_MAX,
    buff_enemy_advantage_max = constants.WSG.BUFF_ENEMY_ADVANTAGE_MAX,
    outnumbered_margin       = constants.WSG.OUTNUMBERED_MARGIN,
}

----------------------------------------------------------------------
-- Battleground Phase Behavior
----------------------------------------------------------------------
config.bg = {
    -- If false, phase<=0 is treated as non-action (safe/default).
    -- Enable only if your server never reports battlefield phase APIs.
    allow_unknown_phase_action = false,
    -- Hard override for private servers that never expose phase correctly.
    -- When true, BGBOT treats unknown as ACTION whenever prep aura is absent.
    force_action_phase = false,
    -- Automatic fallback delay before forcing ACTION when phase remains unknown.
    unknown_to_action_secs = constants.BG.UNKNOWN_TO_ACTION_SECS,
}

return config
