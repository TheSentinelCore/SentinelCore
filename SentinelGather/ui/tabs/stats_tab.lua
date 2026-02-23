--[[
    Statistics Tab - AstroUI card-based statistics display
    Uses metric_grid for session stats, progress_bar_list for path progress,
    and row_list (info) for current target.
]]

local color = require("common/color")

local StatsTab = {}

---Register the stats tab with the UI
---@param ui any AstroUI instance
function StatsTab.register(ui)
    ui:add_tab({ id = "stats", label = "Stats" }, function(t)
        -- Session statistics (2-column metric grid)
        t:metric_grid({
            label = "Session",
            elements = {
                {
                    label = "Duration",
                    value_fn = function()
                        local SentinelGather = require("init")
                        local stats = SentinelGather:get_statistics()
                        return stats and stats.duration_formatted or "0:00"
                    end,
                },
                {
                    label = "Nodes",
                    value_fn = function()
                        local SentinelGather = require("init")
                        local stats = SentinelGather:get_statistics()
                        return tostring(stats and stats.nodes_gathered or 0)
                    end,
                },
                {
                    label = "Nodes/hr",
                    value_fn = function()
                        local SentinelGather = require("init")
                        local stats = SentinelGather:get_statistics()
                        return string.format("%.1f", stats and stats.nodes_per_hour or 0)
                    end,
                },
                {
                    label = "Items",
                    value_fn = function()
                        local SentinelGather = require("init")
                        local stats = SentinelGather:get_statistics()
                        return tostring(stats and stats.total_items or 0)
                    end,
                },
                {
                    label = "Deaths",
                    value_fn = function()
                        local SentinelGather = require("init")
                        local stats = SentinelGather:get_statistics()
                        local deaths = stats and stats.deaths or 0
                        return tostring(deaths)
                    end,
                    color_fn = function(v) return tonumber(v) and tonumber(v) > 0 and "status_red" or nil end,
                },
            },
        })

        -- Path progress (progress bar)
        t:progress_bar_list({
            label = "Path Progress",
            elements = {
                {
                    label = "Waypoints",
                    value_fn = function()
                        local client = _G.SentinelNavClient and _G.SentinelNavClient.client
                        if client and client:get_current_path() then
                            local path_count = #client:get_current_path()
                            local path_idx = client:get_path_index()
                            if path_count > 0 then
                                return path_idx / path_count
                            end
                        end
                        return 0
                    end,
                    format_fn = function(_v)
                        local client = _G.SentinelNavClient and _G.SentinelNavClient.client
                        if client and client:get_current_path() then
                            local path_count = #client:get_current_path()
                            local path_idx = client:get_path_index()
                            return string.format("%d / %d", path_idx, path_count)
                        end
                        return "No path"
                    end,
                    color = color.new(10, 132, 255, 255),  -- Apple blue
                },
            },
        })

        -- Current target info
        t:row_list({
            label = "Target",
            elements = {
                {
                    type = "info",
                    label = "Destination",
                    value_fn = function()
                        local client = _G.SentinelNavClient and _G.SentinelNavClient.client
                        if client and client:get_destination() then
                            local dest = client:get_destination()
                            return string.format("(%.0f, %.0f, %.0f)", dest.x, dest.y, dest.z)
                        end
                        return "None"
                    end,
                },
            },
        })
    end)
end

return StatsTab
