-- tests/kernel/test_plugin_require_audit.lua
-- THE Phase 4 exit criterion, enforced mechanically rather than by inspection.
--
-- ADR 08 §8.1: "Promotion later is mechanical IF AND ONLY IF no plugin ever reaches past the public
-- API. That discipline is the thing to enforce now."
--
-- §3.3 says the same from the other side: the kernel ships zero behaviour not expressible through
-- the public API, because "if the kernel can privilege itself, the public API silently rots". A
-- rotation that reaches into `modules/combat/...` proves nothing about the API's adequacy -- it just
-- proves the old module still works, which was never in question.
--
-- THE RULE: a plugin may require files inside its OWN package and nothing else. Everything it needs
-- from the kernel arrives through `_G.Sentinel`. Intra-package requires are allowed because a
-- 2,000-line rotation is not one file; cross-package requires are not, because that is the exact
-- move that would make this phase worthless.
--
-- If a plugin needs something the public API lacks, the fix is to ADD IT TO THE API and log the gap
-- in 08a_API_GAPS.md -- never to import the internal module.

local T = require("tests/test_util")

local M = {}

local PLUGIN_ROOT = "sentinel/rotations"

-- ---------------------------------------------------------------------------
-- The audit itself
-- ---------------------------------------------------------------------------

local function read_file(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local source = handle:read("*a")
    handle:close()
    return source
end

local function list_lua_files(dir)
    local files = {}
    -- `find` rather than a recursive Lua walk: this is offline test-harness code running under
    -- luajit on Linux, not sandboxed in-game code, so a subprocess is available and honest.
    local pipe = io.popen('find "' .. dir .. '" -type f -name "*.lua" 2>/dev/null | sort')
    if not pipe then return files end
    for line in pipe:lines() do
        files[#files + 1] = line
    end
    pipe:close()
    return files
end

--- Extract every `require("...")` target from a source string, with its line number.
local function requires_in(source)
    local found = {}
    local line_number = 0
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        line_number = line_number + 1
        -- Skip whole-line comments so prose about `require("modules/...")` is not a violation.
        if not line:match("^%s*%-%-") then
            for target in line:gmatch('require%s*%(?%s*"([^"]+)"') do
                found[#found + 1] = { target = target, line = line_number }
            end
        end
    end
    return found
end

---Audit one plugin package.
---@param package_dir string e.g. "sentinel/rotations/mage_frost"
---@param package_prefix string the require prefix its own files use, e.g. "rotations/mage_frost"
---@return table violations { {file, line, target} }
local function audit(package_dir, package_prefix)
    local violations = {}
    for _, path in ipairs(list_lua_files(package_dir)) do
        local source = read_file(path)
        if source then
            for _, r in ipairs(requires_in(source)) do
                if r.target:sub(1, #package_prefix) ~= package_prefix then
                    violations[#violations + 1] =
                        { file = path, line = r.line, target = r.target }
                end
            end
        end
    end
    return violations
end

M._audit = audit

local function describe(violations)
    local out = {}
    for _, v in ipairs(violations) do
        out[#out + 1] = v.file .. ":" .. v.line .. ' require("' .. v.target .. '")'
    end
    return table.concat(out, "\n  ")
end

-- ---------------------------------------------------------------------------
-- The audit must not be vacuous
-- ---------------------------------------------------------------------------

--- An audit with nothing to audit passes for free, which is indistinguishable from an audit that
--- works. This is the guard against the whole file becoming decorative.
function M.test_there_is_at_least_one_plugin_package_to_audit()
    local dirs = {}
    local pipe = io.popen('find "' .. PLUGIN_ROOT .. '" -mindepth 1 -maxdepth 1 -type d 2>/dev/null')
    if pipe then
        for line in pipe:lines() do dirs[#dirs + 1] = line end
        pipe:close()
    end
    T.assert_true(#dirs > 0,
        "no plugin packages found under " .. PLUGIN_ROOT .. " -- the require audit would be vacuous")
end

--- Proves the audit actually catches the thing it exists to catch. Without this, a bug in the
--- pattern match would make every plugin "clean" forever.
function M.test_the_audit_detects_a_reach_past_the_api()
    local dir = "/tmp/sentinel_require_audit_probe"
    os.execute('rm -rf "' .. dir .. '" && mkdir -p "' .. dir .. '"')
    local handle = io.open(dir .. "/offender.lua", "w")
    handle:write([[
-- a doc comment mentioning require("modules/combat/spell_catalog") must NOT count
local Own = require("rotations/probe/helper")
local Reached = require("modules/combat/spell_catalog")
return { Own, Reached }
]])
    handle:close()

    local violations = audit(dir, "rotations/probe")
    os.execute('rm -rf "' .. dir .. '"')

    T.assert_equal(#violations, 1, "exactly the cross-package require must be flagged")
    T.assert_equal(violations[1].target, "modules/combat/spell_catalog")
    T.assert_equal(violations[1].line, 3, "and the comment on line 2 must be ignored")
end

-- ---------------------------------------------------------------------------
-- THE EXIT CRITERION
-- ---------------------------------------------------------------------------

--- ADR §12's Phase 4 exit criterion: the ported rotation uses only the public API.
function M.test_every_plugin_requires_nothing_outside_its_own_package()
    local dirs = {}
    local pipe = io.popen('find "' .. PLUGIN_ROOT .. '" -mindepth 1 -maxdepth 1 -type d 2>/dev/null')
    if pipe then
        for line in pipe:lines() do dirs[#dirs + 1] = line end
        pipe:close()
    end

    for _, dir in ipairs(dirs) do
        local name = dir:match("([^/]+)$")
        local violations = audit(dir, "rotations/" .. name)
        T.assert_equal(#violations, 0,
            "plugin '" .. name .. "' reached past the public API:\n  " .. describe(violations)
            .. "\nAdd what it needs to the API and log the gap in 08a_API_GAPS.md; do not import "
            .. "the internal module.")
    end
end

return M
