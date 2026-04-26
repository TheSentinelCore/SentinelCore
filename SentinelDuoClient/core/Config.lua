-- Config.lua — Static configuration for SentinelDuoClient.
-- Modify values here; do not require() and modify at runtime.

---@class DuoConfig
local Config = {
    coord_server_url      = "http://127.0.0.1:7300",
    poll_interval_ms      = 100,   -- heartbeat every ~100ms (near real-time)
    barrier_poll_interval_ms = 100,
    http_timeout_ms       = 2000,  -- 2s timeout before clearing pending
    debug_overlay         = false,
    session_max_runtime_ms = 14400000,  -- 4 hours
}

return Config
