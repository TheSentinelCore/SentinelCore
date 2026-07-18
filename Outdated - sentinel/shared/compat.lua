local Compat = {}

function Compat.safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(obj[method], obj, ...)
    if not ok then
        return nil
    end
    return value
end

function Compat.safe_call0(fn, owner)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn)
    if ok then
        return value
    end
    if owner ~= nil then
        ok, value = pcall(fn, owner)
        if ok then
            return value
        end
    end
    return nil
end

function Compat.safe_call2(fn, owner, arg)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, arg)
    if ok then
        return value
    end
    if owner ~= nil then
        ok, value = pcall(fn, owner, arg)
        if ok then
            return value
        end
    end
    return nil
end

function Compat.same_guid(a, b)
    if not a or not b then return false end
    local ok_a, guid_a = pcall(a.get_guid, a)
    local ok_b, guid_b = pcall(b.get_guid, b)
    if not ok_a or not ok_b then return false end
    return tostring(guid_a) == tostring(guid_b)
end

function Compat.dist(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Compat.dist_sq(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return dx * dx + dy * dy + dz * dz
end

function Compat.dist_in_range(a, b, range)
    if not a or not b or not range then return false end
    return Compat.dist_sq(a, b) <= range * range
end

function Compat.num(value)
    return tonumber(value) or 0
end

function Compat.is_trueish(value)
    if value == true or value == 1 then
        return true
    end
    local lowered = tostring(value or ""):lower()
    return lowered == "true" or lowered == "1"
end

return Compat
