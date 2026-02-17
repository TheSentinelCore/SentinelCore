-- config/server.lua
-- Shared server configuration consumed by SentinelNavClient and other projects.
-- Single source of truth for SentinelNavServer connection details.

local ServerConfig = {
    --- Base URL for SentinelNavServer HTTP API
    base_url = "http://127.0.0.1:47110",

    --- Maximum HTTP request retries before marking as failed
    max_retries = 3,

    --- Health check interval in seconds (0 = disabled)
    health_check_interval = 30,
}

return ServerConfig
