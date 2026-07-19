local Events = {
    ENGAGE_REQUESTED = "combat:engage_requested",
    ENGAGED = "combat:engaged",
    DISENGAGE_REQUESTED = "combat:disengage_requested",
    DISENGAGED = "combat:disengaged",
    STATE_CHANGED = "combat:state_changed",
    TARGET_ACQUIRED = "combat:target_acquired",
    TARGET_CHANGED = "combat:target_changed",
    TARGET_LOST = "combat:target_lost",
    OUTNUMBERED = "combat:outnumbered",
    HEALTH_THRESHOLD = "combat:health_threshold",
    ACTION_SELECTED = "rotation:action_selected",
    ACTION_QUEUED = "rotation:action_queued",
    ACTION_BLOCKED = "rotation:action_blocked",
    PROFILE_LOADED = "rotation:profile_loaded",
    SEAL_CHANGED = "rotation:seal_changed",
    TWIST_WINDOW_OPEN = "rotation:twist_window_open",
    TWIST_WINDOW_MISSED = "rotation:twist_window_missed",
    VENGEANCE_CHANGED = "rotation:vengeance_changed",

    -- Player state transition events (fired by SensorHub on state changes)
    PLAYER_COMBAT_CHANGED = "player:combat_changed",
    PLAYER_DEATH_CHANGED = "player:death_changed",
    PLAYER_MOUNT_CHANGED = "player:mount_changed",
    PLAYER_CAST_STARTED = "player:cast_started",
    PLAYER_CAST_ENDED = "player:cast_ended",
    PLAYER_CHANNEL_STARTED = "player:channel_started",
    PLAYER_CHANNEL_ENDED = "player:channel_ended",
    PLAYER_HEALTH_THRESHOLD = "player:health_threshold",
    PLAYER_AUTO_ATTACK_CHANGED = "player:auto_attack_changed",
    PLAYER_BUFF_GAINED = "player:buff_gained",
    PLAYER_BUFF_LOST = "player:buff_lost",

    -- Unit-level events (fired by IZI SDK aura callbacks in SensorHub)
    UNIT_DEBUFF_APPLIED = "unit:debuff_applied",
    UNIT_BUFF_APPLIED = "unit:buff_applied",
    UNIT_SPELL_CASTING = "unit:spell_casting",
    UNIT_SPELL_CANCELLED = "unit:spell_cancelled",

    -- Game-level events (fired by CallbackBridge via core.register_on_game_event_callback)
    GAME_ENTERED_COMBAT = "game:entered_combat",
    GAME_EXITED_COMBAT = "game:exited_combat",
}

return Events
