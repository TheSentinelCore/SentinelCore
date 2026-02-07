
-- Syntax / IntelliSense helper for: universal_kicks external filters (plugin-internal)
-- Usage pattern (plugin must be running):
--   local prefix = "core_"
--   local kicks_exist, ext = pcall(require, "root/" .. prefix .. "universal_kicks/external_filters")
--   if kicks_exist and ext then
--       -- use `ext` functions below
--   end
-- Reason: the file is internal to the plugin; `pcall` avoids errors if not present.

---@class external_filter_info
---@field type string        -- "block" | "allow"
---@field name string|nil    -- filter name (for block hits)
---@field label string|nil   -- human-readable label from opts.label
---@field why string|nil     -- reason from your filter or policy text
---@field policy string|nil  -- "block_return_false" | "at_least_one_allow_must_pass"
---@field frames number|nil  -- opts.frames (diagnostic echo)
---@field time number|nil    -- opts.time   (diagnostic echo)
---@field count number|nil   -- opts.count  (diagnostic echo)

---@class kick_external_filters
---@field public register fun(self: kick_external_filters, name: string, func: fun(local_player: game_object, solution_table: table, spell_to_kick_table: table, kick_target: game_object, prediction_data: table): boolean, string|nil, opts: table|nil): nil
---@field public unregister fun(self: kick_external_filters, name: string): nil
---@field public clear fun(self: kick_external_filters): nil
---@field public list fun(self: kick_external_filters): table              -- snapshot of active filters (for debug UIs)
---@field public touch fun(self: kick_external_filters, name: string, opts_patch: table): boolean
---@field public apply fun(self: kick_external_filters, local_player: game_object, solution_table: table, spell_to_kick_table: table, kick_target: game_object, prediction_data: table): boolean, external_filter_info|nil
-- Notes:
-- • type="block": your func returns FALSE to block the kick.
-- • type="allow": when ANY allow filter exists, at least one must return TRUE or the kick is blocked.
-- • opts supports: { type="block"|"allow", frames?:number, time?:number, count?:number, label?:string }

--========================
-- Examples (copy-paste)
--========================

-- Example 1: safe require (plugin must be running)
-- local prefix = "core_"
-- local kicks_exist, ext = pcall(require, "root/" .. prefix .. "universal_kicks/external_filters")
-- if not kicks_exist or not ext then
--     -- plugin not present; nothing to do
--     return
-- end

-- Example 2: block while stealthed (works only during stealth)
-- ext.register("block_while_stealth",
--     function(local_player, solution_table, spell_to_kick_table, kick_target, prediction_data)
--         local data = buff_manager:get_buff_data(local_player, enums.buff_db.STEALTH, 50)
--         local is_stealthed = data and data.is_active == true
--         if is_stealthed then
--             return false, "stealth_active"  -- block while stealthed
--         end
--         return true                         -- allow otherwise
--     end,
--     { type = "block", label = "No Kick While Stealth" }
-- )

-- Example 3: allow only boss target for 2 seconds (then auto-expire)
-- local boss_ptr = core.units.boss1
-- ext.register("allow_boss_for_2s",
--     function(_, _, _, kick_target)
--         return kick_target == boss_ptr
--     end,
--     { type = "allow", time = 2, label = "Boss Only 2s" }
-- )
-- -- while active, kicks are permitted ONLY when target == boss_ptr
-- -- if that’s too restrictive later, remember to ext.unregister("allow_boss_for_2s")

-- Example 4: block a specific enemy cast id
-- ext.register("block_cast_12345",
--     function(_, _, cast)
--         local allow = (cast.id ~= 12345)
--         return allow, allow and nil or "cast_12345"
--     end,
--     { type = "block", label = "Skip 12345" }
-- )

-- Example 5: block using frames/count/time expirations
-- ext.register("block_once",
--     function() return false, "once" end,
--     { type = "block", frames = 1, label = "One Pass" }
-- )
-- ext.register("block_next_5_checks",
--     function() return false, "next_5" end,
--     { type = "block", count = 5, label = "Next 5 Checks" }
-- )
-- ext.register("mute_for_3s",
--     function() return false, "window_3s" end,
--     { type = "block", time = 3, label = "Mute 3s" }
-- )

-- Example 6: inspect reasons in your decision path
-- local blocked, info = ext.apply(local_player, solution, cast, target, pred)
-- if blocked then
--     local msg = "[Universal Kicks] blocked | reason=" .. tostring(info and info.why or "-")
--         .. (info and info.name and (" | filter=" .. info.name) or "")
--         .. (info and info.label and (" | label=" .. info.label) or "")
--         .. (info and info.policy and (" | policy=" .. info.policy) or "")
--     core.log(msg)
--     return
-- end

-- Example 7: remove or extend existing filters
-- ext.unregister("block_while_stealth")
-- ext.touch("allow_boss_for_2s", { time = 4 })  -- extend window if still active

-- Tips:
-- • If you register ANY allow filter, kicks are permitted ONLY when at least one allow returns true.
-- • Prefer time or count expirations for temporary rules so you don’t have to manually unregister.
-- • For debug UIs, use ext.list() and show secs_left / calls / frames_used.

---@type kick_external_filters
local tbl
return tbl
