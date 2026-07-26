-- shared/plain_position.lua
-- Copy a position-shaped table into a plain {x, y, z} the blackboard's purity guard can prove
-- safe. MEASURED LIVE (first two in-game runs, 2026-07-26): the injector returns positions as
-- vec3 CLASS instances — plain x/y/z number fields under a ~35-method vector metatable — and
-- the guard rightly refuses any metatabled table, one write site per boot: `player.position`
-- on run one, `player.corpse_position` on run two. Offline mocks return plain tables, which is
-- why no test ever fired. One helper, so the NEXT position-shaped SDK read starts safe instead
-- of being run three's error line.
local PlainPosition = {}

---@param value any a vec3-ish table, or anything else
---@return table|nil `{ x, y, z }` with plain numbers, or nil when there is no usable x/y —
---never the original table, never a metatable
function PlainPosition.copy(value)
    if type(value) ~= "table" then return nil end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not (x and y) then return nil end
    return { x = x, y = y, z = z }
end

return PlainPosition
