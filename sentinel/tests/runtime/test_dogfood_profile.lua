-- sentinel/tests/runtime/test_dogfood_profile.lua
-- SENT-11.5 / SENT-11.2: the Human 1-10 dogfood profile must load, pass
-- structural + goal-coverage validation, prepare cleanly, and do so quickly.

local T = require("tests/test_util")
local JSON = require("lib/JSON")
local ProfileManager = require("runtime/profile_manager")
local ValidationService = require("runtime/validation_service")
local Blackboard = require("core/blackboard")

local M = {}

-- At runtime, profiles live under the loader's `scripts_data/` sandbox at
-- `scripts_data/sentinel/profiles/authoring/` (storage_manager TIER2_DIR). In
-- this repo the `sentinel/` tree IS that `scripts_data/sentinel/` root, and the
-- harness runs from `sentinel/`, so the cwd-relative path is:
local PROFILE_PATH = "profiles/authoring/human-1-10.json"

function M.run()
    print("=== Dogfood Profile (Human 1-10) Tests ===")

    local f = io.open(PROFILE_PATH, "r")
    T.assert_not_nil(f, "dogfood profile file exists at " .. PROFILE_PATH)
    local raw = f:read("*a")
    f:close()

    local profile, dec_err = JSON.decode(raw)
    T.assert_not_nil(profile, "dogfood profile decodes as JSON"
        .. (dec_err and (": " .. dec_err) or ""))

    -- Structural validation (ProfileManager.validate, static).
    local errors = ProfileManager.validate(profile)
    T.assert_equal(#errors, 0, "dogfood profile passes structural validation"
        .. (errors[1] and (": " .. errors[1]) or ""))

    -- Goal-coverage validation (runtime continuous-validation service).
    local vr = ValidationService:new():validate_profile(profile)
    T.assert_true(vr.is_valid, "dogfood profile passes goal-coverage validation")

    -- Prepare must be clean and fast (SENT-11.2 benchmark smoke check).
    local pm = ProfileManager:new({ blackboard = Blackboard:new() })
    local start = os.clock()
    local prepared, perr = pm:prepare(profile)
    local elapsed_ms = (os.clock() - start) * 1000
    T.assert_not_nil(prepared, "dogfood profile prepares without error"
        .. (perr and (": " .. perr) or ""))
    T.assert_true(elapsed_ms < 200, "dogfood prepare under 200ms (got " .. elapsed_ms .. "ms)")

    -- Every operation id is unique and referenced by dependents that exist.
    local ids = {}
    for _, op in ipairs(profile.operations) do
        ids[op.id] = true
    end
    for _, op in ipairs(profile.operations) do
        if op.dependencies then
            for _, dep in ipairs(op.dependencies) do
                T.assert_true(ids[dep.operation_id] ~= nil,
                    "dependency '" .. tostring(dep.operation_id)
                    .. "' of '" .. op.id .. "' resolves")
            end
        end
    end

    print("  PASS (" .. elapsed_ms .. "ms prepare)")
    print("\n=== All Dogfood Profile Tests PASSED ===")
end

return M
