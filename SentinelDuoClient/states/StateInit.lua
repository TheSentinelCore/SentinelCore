-- StateInit.lua — Initial state: begin coord polling, detect key, wait for client ID.

local helpers = require("lib/helpers")

local StateInit = { name = "INIT" }

function StateInit:create(ctx)
    local bb           = ctx.bb
    local coord_client = ctx.coord_client

    local enter_time_ms = 0

    return {
        enter = function(_bb)
            enter_time_ms = helpers.game_time_ms()
            helpers.log("[INIT] enter — beginning coord polling")
        end,

        update = function(_bb)
            local gt = helpers.game_time_ms()

            -- Check for Key to the City (item 12382) in bags / keyring.
            -- Each slot has slot.object (game_object); use obj:get_item_id().
            local has_key = false
            for _, bag_id in ipairs({ -2, 0, 1, 2, 3, 4 }) do
                local ok, items = pcall(core.inventory.get_items_in_bag, bag_id)
                if ok and type(items) == "table" then
                    for _, slot in ipairs(items) do
                        local obj = slot and slot.object
                        if obj then
                            local ok_id, item_id = pcall(obj.get_item_id, obj)
                            if ok_id and item_id == 12382 then
                                has_key = true
                                break
                            end
                        end
                    end
                end
                if has_key then break end
            end
            bb:set("duo.has_instance_key", has_key)

            -- Transition once coord server has assigned a client ID
            local my_id = bb:get("duo.my_client_id", nil)
            if my_id and my_id ~= "" then
                return "COORD_CONNECT"
            end

            -- Warn after 5 seconds with no response
            if gt - enter_time_ms > 5000 then
                helpers.log_err("[INIT] no coord response after 5s — check SentinelDuoCoordServer")
                enter_time_ms = gt  -- reset to avoid spam
            end
        end,

        exit = function(_bb)
            local role = bb:get("duo.my_client_id", "?")
            helpers.log("[INIT] exit — role=" .. role)
        end,
    }
end

return StateInit
