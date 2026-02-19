local Events = {
    -- HSM State Events
    STATE_CHANGED        = "nav.state_changed",
    ARRIVED              = "nav.arrived",
    FAILED               = "nav.failed",

    -- BT Execution Events
    STUCK_DETECTED       = "nav.stuck_detected",
    STUCK_RECOVERED      = "nav.stuck_recovered",
    DEVIATION_DETECTED   = "nav.deviation_detected",
    REPATH_STARTED       = "nav.repath_started",
    REPATH_COMPLETED     = "nav.repath_completed",
    OBSTACLE_DETECTED    = "nav.obstacle_detected",

    -- Path Events
    PATH_REQUESTED       = "nav.path_requested",
    PATH_RECEIVED        = "nav.path_received",
    WAYPOINT_REACHED     = "nav.waypoint_reached",
    LEG_COMPLETED        = "nav.leg_completed",

    -- Server Events
    SERVER_CONNECTED     = "nav.server_connected",
    SERVER_DISCONNECTED  = "nav.server_disconnected",
    SERVER_ERROR         = "nav.server_error",

    -- Blackboard change prefix
    BB_PREFIX            = "bb.",
}

return Events
