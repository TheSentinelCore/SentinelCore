-- kernel/semver.lua
-- The version gate's arithmetic. ADR 08 §8.2: a manifest declares `api = "^1.0"`, checked
-- against `Sentinel.API_VERSION`.
--
-- Its own module because a silently wrong range check ADMITS INCOMPATIBLE PLUGINS -- the exact
-- failure the gate exists to prevent -- and a wrong gate is worse than no gate, because it also
-- stops anyone from looking.
--
-- THE NAMED TRAP: string comparison. Lexically "1.10" < "1.9", so any comparison that does not
-- parse to integers silently rejects everything past .9. Nothing here compares version strings.
--
-- WHAT IS DELIBERATELY NOT SUPPORTED. Only `^X.Y.Z` and exact `X.Y.Z` are implemented. Tilde
-- ranges, comparators, wildcards, unions and pre-release identifiers are REFUSED BY NAME rather
-- than approximated: a `~1.2` quietly read as `^1.2` would widen the gate with nobody noticing,
-- which is the same class of bug as the string comparison above.

local Semver = {}

---Parse a version. Partial versions zero-fill, since manifests are hand-written and will omit
---the patch.
---@param str string
---@return table|nil { major, minor, patch }, string|nil reason
function Semver.parse(str)
    if type(str) ~= "string" or str == "" then
        return nil, "invalid_version"
    end

    -- Anchored, digits and dots only: rejects "1.x", "1..2", "1.2.3.4", "-1.0.0", trailing dots.
    local major, minor, patch = str:match("^(%d+)%.(%d+)%.(%d+)$")
    if major == nil then
        major, minor = str:match("^(%d+)%.(%d+)$")
        patch = "0"
    end
    if major == nil then
        major = str:match("^(%d+)$")
        minor, patch = "0", "0"
    end
    if major == nil then
        -- Pre-release and build metadata are refused rather than half-ordered: their comparison
        -- rules are intricate and nothing here needs them.
        --
        -- Checked only AFTER the numeric core fails to match, and only when a valid core
        -- PRECEDES the marker. Checking for "-" up front reported "-1.0.0" as a pre-release when
        -- it is simply malformed -- a leading "-" is not a marker, and the diagnostic has to
        -- point at the right defect.
        if str:match("^%d+%.%d+%.%d+[-+]") or str:match("^%d+%.%d+[-+]") or str:match("^%d+[-+]") then
            return nil, "prerelease_not_supported"
        end
        return nil, "invalid_version"
    end

    return {
        major = tonumber(major),
        minor = tonumber(minor),
        patch = tonumber(patch),
    }
end

---Compare two versions numerically.
---@return number|nil -1, 0 or 1, or nil on a parse failure
---@return string|nil reason
function Semver.compare(a, b)
    local va, ra = Semver.parse(a)
    if va == nil then return nil, ra end
    local vb, rb = Semver.parse(b)
    if vb == nil then return nil, rb end

    for _, field in ipairs({ "major", "minor", "patch" }) do
        if va[field] ~= vb[field] then
            return va[field] > vb[field] and 1 or -1
        end
    end
    return 0
end

---The exclusive upper bound implied by a caret floor.
---
---THE PRE-1.0 RULE, stated rather than hand-waved. Below 1.0.0 there is no stable public API, so
---semver hands the breaking-change role down a level:
---
---  ^1.2.3  ->  >=1.2.3  <2.0.0      major is stable, minor/patch are additive
---  ^0.9.0  ->  >=0.9.0  <0.10.0     no stable major, so a MINOR bump is breaking
---  ^0.0.3  ->  >=0.0.3  <0.0.4      no stable major or minor, so only the exact patch fits
---
---The wrong reading of the middle case -- treating ^0.9 as "<1.0.0" -- would admit 0.10 into a
---plugin written against 0.9, and pre-1.0 is precisely when that break is most likely.
local function caret_upper_bound(floor)
    if floor.major > 0 then
        return { major = floor.major + 1, minor = 0, patch = 0 }
    end
    if floor.minor > 0 then
        return { major = 0, minor = floor.minor + 1, patch = 0 }
    end
    return { major = 0, minor = 0, patch = floor.patch + 1 }
end

local function lt(a, b)
    if a.major ~= b.major then return a.major < b.major end
    if a.minor ~= b.minor then return a.minor < b.minor end
    return a.patch < b.patch
end

---Does `version` satisfy `range`?
---@param version string e.g. "1.0.0" (Sentinel.API_VERSION)
---@param range string e.g. "^1.0" (a manifest's `api` field)
---@return boolean satisfied, string|nil reason when false
function Semver.satisfies(version, range)
    if type(range) ~= "string" or range == "" then
        return false, "invalid_range"
    end

    local operator, body = range:match("^([%^~><=*|]*)%s*(.*)$")
    if operator == nil then
        return false, "invalid_range"
    end

    -- Anything with an operator we have not implemented is refused, not approximated.
    if operator ~= "" and operator ~= "^" then
        return false, "unsupported_range"
    end
    -- Unions, wildcards and multi-comparator ranges reach here with an empty operator.
    if body:find("[%s|*x><=]") then
        return false, "unsupported_range"
    end

    local floor, floor_reason = Semver.parse(body)
    if floor == nil then
        -- "^banana" is a malformed range; distinguish that from a malformed VERSION so the
        -- diagnostic points at the manifest field that is actually wrong.
        return false, floor_reason == "prerelease_not_supported" and floor_reason or "invalid_range"
    end

    local actual, actual_reason = Semver.parse(version)
    if actual == nil then
        return false, actual_reason
    end

    if operator == "" then
        -- Exact match, zero-filled on both sides.
        local same = actual.major == floor.major
            and actual.minor == floor.minor
            and actual.patch == floor.patch
        if same then return true end
        return false, "version_mismatch"
    end

    if lt(actual, floor) then
        return false, "below_range_floor"
    end
    if not lt(actual, caret_upper_bound(floor)) then
        return false, "above_range_ceiling"
    end
    return true
end

return Semver
