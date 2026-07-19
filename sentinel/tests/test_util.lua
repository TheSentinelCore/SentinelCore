local TestUtil = {}

function TestUtil.assert_true(value, message)
    if not value then
        error(message or "expected true")
    end
end

function TestUtil.assert_false(value, message)
    if value then
        error(message or "expected false")
    end
end

function TestUtil.assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

function TestUtil.assert_not_nil(value, message)
    if value == nil then
        error(message or "expected non-nil value")
    end
end

function TestUtil.run(name, fn)
    local ok, err = pcall(fn)
    return {
        name = name,
        ok = ok,
        err = err,
    }
end

function TestUtil.assert_nil(value, message)
    if value ~= nil then
        error((message or "expected nil") .. ": got " .. tostring(value))
    end
end

function TestUtil.table_contains(t, value)
    for _, v in ipairs(t) do
        if v == value then
            return true
        end
    end
    return false
end

function TestUtil.assert_near(actual, expected, tolerance, message)
    tolerance = tolerance or 0.001
    local diff = math.abs(actual - expected)
    if diff > tolerance then
        error((message or "assert_near failed") .. ": expected ~" .. tostring(expected) .. ", got " .. tostring(actual) .. " (diff=" .. tostring(diff) .. ")")
    end
end

return TestUtil