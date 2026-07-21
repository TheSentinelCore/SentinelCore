---shared/spell_queue.lua
---Spell queue resolver — abstracts the IZI spell_queue global and the
---common/modules/spell_queue fallback behind a single resolve() call.
---
---SentinelCore modules should require this module instead of inlining
---resolve_spell_queue() themselves.

local _ref = nil
local _resolved = false

local M = {}

---Resolve the spell queue reference.
---Checks the global `spell_queue` first (IZI injection), then falls back to
---`require("common/modules/spell_queue")`. Result is cached.
---@return table|nil
function M.resolve()
    if spell_queue then
        _ref = spell_queue
        _resolved = true
        return _ref
    end
    if not _resolved then
        local ok, mod = pcall(require, "common/modules/spell_queue")
        if ok and mod then
            _ref = mod
        end
        _resolved = true
    end
    return _ref
end

---Call a spell queue method using method-call convention (queue:method(...)).
---@param method_name string
---@param ... any
---@return boolean ok
---@return any result
function M.call(method_name, ...)
    local queue = M.resolve()
    if not queue or type(queue[method_name]) ~= "function" then
        return false, nil
    end
    return pcall(queue[method_name], queue, ...)
end

---Get the full queue snapshot, or nil if unavailable.
---@return table|nil
function M.snapshot()
    local queue = M.resolve()
    if not queue or type(queue.get_queue_snapshot) ~= "function" then
        return nil
    end
    local ok, snapshot = pcall(queue.get_queue_snapshot, queue)
    if ok and type(snapshot) == "table" then
        return snapshot
    end
    return nil
end

return M
