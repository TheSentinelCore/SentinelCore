-- SentinelNavClient/config/server.lua
-- Server connection defaults bundled with the client.
-- Consumers can override via Navigation:new({ base_url = "..." }) or
-- Navigation:update_config({ base_url = "..." }).

local ServerConfig = {
    --- Base URL for SentinelNavServer HTTP API
    base_url = "http://78.31.71.163:47110",

    --- Maximum HTTP request retries before marking as failed
    max_retries = 3,

    --- Health check interval in seconds (0 = disabled)
    health_check_interval = 30,
}

return ServerConfig
