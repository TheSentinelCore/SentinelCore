
--[[
Example:
---@type wigs_tracker
local bars = require("common/utility/wigs_tracker")
bars: -> IntelliSense
Warning: Access with ":" not "."
]]

---@alias bar_data_table bar_data[]
---@alias bar_p_data_table bar_p_data[]

---@class bar_data
---@field public key number         -- The identifier (id) of the bar.
---@field public text string        -- The label or message associated with the bar.
---@field public duration number    -- The original duration of the bar (in seconds).
---@field public created_at number  -- The time (in milliseconds) when the bar was created.
---@field public expire_time number -- The time (in milliseconds) when the bar will expire.
---@field public remaining number   -- The remaining time (in milliseconds) (expire_time - current time) ONLY IN BAR_DATA.

---@class bar_p_data -- MISSING REMAINING
---@field public key number         -- The identifier (id) of the bar.
---@field public text string        -- The label or message associated with the bar.
---@field public duration number    -- The original duration of the bar (in seconds).
---@field public created_at number  -- The time (in milliseconds) when the bar was created.
---@field public expire_time number -- The time (in milliseconds) when the bar will expire.

---@class wigs_tracker
---@field public lookup_by_text fun(self: wigs_tracker, search_text: string): bar_data_table
---@field public lookup_by_key fun(self: wigs_tracker, key: number): bar_data_table
---@field public get_all fun(self: wigs_tracker): bar_p_data_table

---@type wigs_tracker
local tbl
return tbl
