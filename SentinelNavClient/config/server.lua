-- SentinelNavClient/config/server.lua
-- Server connection defaults bundled with the client.
-- Consumers can override via Navigation:new({ base_url = "..." }) or
-- Navigation:update_config({ base_url = "..." }).

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
    --- nil = use server's default_game.
    game = nil,
}

return ServerConfig
