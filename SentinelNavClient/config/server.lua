-- SentinelNavClient/config/server.lua
-- Server connection defaults bundled with the client.
-- Consumers can override via Navigation:new({ base_url = "..." }) or
-- Navigation:update_config({ base_url = "..." }).

-- Map Sylvannas game version strings to NavServer game identifiers.
-- core.get_game_version() returns e.g. "Tbc", "Midnight", "Vanilla", "Mop".
-- NavServer expects "tbc" or "retail" via ?game= query parameter.
local VERSION_TO_GAME = {
    Tbc      = "tbc",
    Vanilla  = "tbc",
    Midnight = "retail",
    Mop      = "retail",
}

local raw = core.get_game_version()
local detected_game = VERSION_TO_GAME[raw] or "retail"

local ServerConfig = {
    --- Base URL for SentinelNavServer HTTP API
    -- base_url = "http://127.0.0.1:47110",
    base_url = "http://138.201.59.112:47110",
    --- Maximum HTTP request retries before marking as failed
    max_retries = 3,

    --- Health check interval in seconds (0 = disabled)
    health_check_interval = 30,

    --- Game identifier sent with every request (e.g. "tbc", "retail").
    --- Must match a [navmesh.games.<name>] section in NavServer config.
    --- Auto-detected from core.get_game_version().
    game = detected_game,
}

return ServerConfig
