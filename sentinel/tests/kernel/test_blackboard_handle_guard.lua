-- tests/kernel/test_blackboard_handle_guard.lua
-- AUDIT 2's REPLACEMENT PRIMARY DEFENCE: no key on the blackboard may hold a live SDK handle,
-- and the guard that enforces it is a MECHANISM, not a naming convention.
--
-- ================================================================================
-- WHY THE PATTERN HAD TO GO
-- ================================================================================
-- `test_blackboard_namespace_audit.lua` detects handles with `'"([%w_%.]-)%.object"'` -- a key
-- ending in `.object`. That is a rule about SPELLING. `combat.target`, `player.target` and
-- `combat.low_health_add` hold live handles today and match nothing, so the audit reported a
-- clean bill of health for keys it had never agreed to look at. Widening the pattern to
-- `.target` as well only moves the boundary; the next key to hold a handle will be called
-- something else again.
--
-- This is the same failure shape as the audit that globbed its own scope and the force-release
-- pin that could only see keys the kernel pressed: RIGHT ABOUT WHAT IT SAW, WRONG ABOUT WHAT
-- IT LOOKED AT. The fix is not a better pattern. It is to stop asking what a key is CALLED and
-- start asking what it CONTAINS.
--
-- ================================================================================
-- THE MECHANISM
-- ================================================================================
-- `kernel/snapshot.lua` already refuses userdata, functions, threads, or any table containing
-- one at any depth (ADR 08 §2.7 -- a game_object pointer can die inside the tick that froze
-- it). `Blackboard:set` now applies the same test. A handle cannot reach the blackboard under
-- ANY name, because the check never reads the name.
--
-- ================================================================================
-- THE LEDGER
-- ================================================================================
-- The blackboard legitimately stores handles TODAY, so rejection ships with a shrink-only
-- exception ledger (`Blackboard.HANDLE_LEDGER`). Its entries are the worklist for retiring the
-- last handle-bearing keys, and it may only shrink: an entry whose writer no longer sets the
-- key fails exactly as loudly as a key that was never listed. A ledger that only catches new
-- violations is a list; the staleness direction is what makes it a ratchet.
--
-- The old `.object` audit stays, demoted from primary defence to backstop: it reads source
-- text and so still catches a handle key in code that this process never executes.

local T = require("tests/test_util")
local Scope = require("tests/kernel/audit_scope")
local Blackboard = require("core/blackboard")

local M = {}

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

--- Real userdata. This is what a Sylvannas `game_object` actually is in the client.
local function userdata_handle()
    return newproxy(false)
end

--- What a handle looks like OFFLINE: a table carrying behaviour. The mocks in this suite
--- build units this way, so the guard must reject it for the same reason it rejects
--- userdata -- it is the thing whose methods get called a tick later.
local function mock_handle()
    return {
        get_max_health = function() return 100 end,
        get_position = function() return { x = 0, y = 0, z = 0 } end,
    }
end

---Assert `bb:set(key, value)` is refused, and return the message so callers can inspect it.
local function refusal(bb, key, value)
    local ok, err = pcall(function() bb:set(key, value) end)
    T.assert_false(ok, "expected set(" .. tostring(key) .. ", <impure>) to be REFUSED")
    return tostring(err)
end

-- ---------------------------------------------------------------------------
-- The guard rejects behaviour, whatever the key is called
-- ---------------------------------------------------------------------------

function M.test_set_refuses_raw_userdata()
    local bb = Blackboard:new()
    local err = refusal(bb, "combat.some_unlisted_key", userdata_handle())
    T.assert_true(err:match("userdata") ~= nil,
        "the refusal must name the offending type, got: " .. err)
end

--- Refusing is half the job. A guard that stops the write but leaves the author guessing gets
--- worked around, so the message must say WHY it is unsound and WHAT to do instead. Removing
--- `userdata` from the behaviour branch still refuses -- it falls through to the generic
--- "unsupported type" arm -- so accept/reject alone cannot tell the two apart. This can.
function M.test_the_refusal_explains_the_rule_and_the_way_out()
    local bb = Blackboard:new()
    for _, value in ipairs({ userdata_handle(), mock_handle() }) do
        local err = refusal(bb, "combat.some_unlisted_key", value)
        T.assert_true(err:match("carries behaviour") ~= nil,
            "must state the rule, got: " .. err)
        T.assert_true(err:match("ADR 08") ~= nil,
            "must cite the contract it enforces, got: " .. err)
        T.assert_true(err:match("HANDLE_LEDGER") ~= nil,
            "must point at the ledger as the phased way out, got: " .. err)
    end
end

function M.test_set_refuses_a_function()
    local bb = Blackboard:new()
    refusal(bb, "combat.some_unlisted_key", function() end)
end

function M.test_set_refuses_a_thread()
    local bb = Blackboard:new()
    refusal(bb, "combat.some_unlisted_key", coroutine.create(function() end))
end

--- THE DEFECT THIS TRACK EXISTS FOR. None of these keys ends in `.object`, so the pattern
--- audit never looked at them -- while they held live handles the whole time.
---
--- They are ledgered now, so the guard lets them through DELIBERATELY. That makes the
--- interesting assertion not "are they refused" but "is the ledger entry the ONLY reason they
--- are not". So each entry is lifted for the length of one set: if the key were still refused
--- with its exception removed, the exception is load-bearing; if it were accepted anyway, the
--- guard has a hole and the ledger is decoration.
function M.test_the_ledger_entry_is_the_only_thing_permitting_a_handle_the_pattern_missed()
    for _, key in ipairs({ "combat.target", "player.target", "combat.low_health_add" }) do
        T.assert_true(key:match("%.object$") == nil,
            "fixture error: " .. key .. " must NOT match the old `.object` pattern")
        T.assert_not_nil(Blackboard.HANDLE_LEDGER[key],
            key .. " is expected to be a ledgered handle key")

        local entry = Blackboard.HANDLE_LEDGER[key]
        Blackboard.HANDLE_LEDGER[key] = nil
        local ok, err = pcall(function() Blackboard:new():set(key, mock_handle()) end)
        Blackboard.HANDLE_LEDGER[key] = entry

        T.assert_false(ok, key .. " must be refused once its ledger entry is lifted -- if it "
            .. "is accepted anyway, the ledger is not what is permitting it")
        T.assert_true(tostring(err):match("carries behaviour") ~= nil, tostring(err))
    end
end

--- Name-independence, stated directly: the guard never reads the key, so a handle is refused
--- at a key that resembles nothing the old pattern knew about.
function M.test_refusal_does_not_depend_on_what_the_key_is_called()
    local bb = Blackboard:new()
    for _, key in ipairs({
        "combat.tgt", "player.foo", "rotation.whatever", "nav.thing", "bg.x", "system.y",
        "operation.z", "module.combat.something_new",
    }) do
        T.assert_true(Blackboard.HANDLE_LEDGER[key] == nil, "fixture error: " .. key)
        refusal(bb, key, mock_handle())
    end
end

--- Depth is the whole point: a handle wrapped in one table is still a handle.
function M.test_set_refuses_a_handle_nested_inside_a_table()
    local bb = Blackboard:new()
    refusal(bb, "combat.some_unlisted_key", { units = { { unit = mock_handle() } } })
end

function M.test_set_refuses_a_list_of_handles()
    local bb = Blackboard:new()
    refusal(bb, "combat.some_unlisted_key", { mock_handle(), mock_handle() })
end

--- THE EVASION THE FIELD WALK CANNOT CATCH. `pairs` reads the RAW table, so a handle served
--- through `__index` has no fields to find -- the scan sees an empty table and waves it
--- through. Measured before closing it: every metatable-carrying value on the blackboard today
--- sits under an already-ledgered key, so refusing metatables costs nothing.
function M.test_set_refuses_a_table_carrying_a_metatable()
    local bb = Blackboard:new()
    local cases = {
        ["__index serving a handle"] = setmetatable({}, { __index = mock_handle() }),
        ["__index serving methods"] = setmetatable({ guid = 1 },
            { __index = { get_hp = function() return 1 end } }),
        ["__call"] = setmetatable({}, { __call = function() end }),
        ["protected metatable"] = setmetatable({}, { __metatable = "locked" }),
    }
    for label, value in pairs(cases) do
        local err = refusal(bb, "combat.some_unlisted_key", value)
        T.assert_true(err:match("metatable") ~= nil, label .. ": " .. err)
    end
end

--- ...including one buried in an otherwise plain structure.
function M.test_set_refuses_a_metatable_nested_deep_in_plain_data()
    local bb = Blackboard:new()
    refusal(bb, "combat.some_unlisted_key",
        { a = { b = { c = setmetatable({}, { __index = mock_handle() }) } } })
end

-- ---------------------------------------------------------------------------
-- The guard does not reject data
-- ---------------------------------------------------------------------------

function M.test_set_still_accepts_scalars_and_plain_tables()
    local bb = Blackboard:new()
    bb:set("player.health_pct", 0.5)
    bb:set("player.name", "Sentinel")
    bb:set("combat.in_combat", true)
    bb:set("player.position", { x = 1, y = 2, z = 3 })
    bb:set("combat.threat", { { guid = "a", pct = 1 }, { guid = "b", pct = 0.5 } })

    T.assert_equal(bb:get("player.health_pct"), 0.5)
    T.assert_equal(bb:get("player.position").z, 3)
    T.assert_equal(bb:get("combat.threat")[2].pct, 0.5)
end

--- The blackboard is LIVE, mutable, read-through state -- unlike the snapshot it must NOT
--- deep-copy on write, or every `bb:get(k).field = v` in the codebase would silently write to
--- a copy. The guard inspects; it does not take ownership.
function M.test_set_does_not_copy_accepted_tables()
    local bb = Blackboard:new()
    local live = { pending = 0 }
    bb:set("combat.some_unlisted_key", live)
    T.assert_true(bb:get("combat.some_unlisted_key") == live,
        "blackboard:set must store the SAME table, not a deep copy")
end

--- Clearing must stay possible; `nil` carries no behaviour.
function M.test_set_accepts_nil()
    local bb = Blackboard:new()
    bb:set("combat.some_unlisted_key", nil)
    T.assert_false(bb:has("combat.some_unlisted_key"))
end

--- A cycle in plain data is not a handle. The snapshot refuses it because it deep-copies;
--- the blackboard does not copy, so it has no reason to.
function M.test_set_accepts_a_cyclic_plain_table()
    local bb = Blackboard:new()
    local a = { n = 1 }
    a.self = a
    bb:set("combat.some_unlisted_key", a)
    T.assert_true(bb:get("combat.some_unlisted_key") == a)
end

--- Key validation must still run, and must run BEFORE the purity scan -- a bad root is a
--- bad root whatever the value is.
function M.test_key_validation_still_applies()
    local bb = Blackboard:new()
    local ok, err = pcall(function() bb:set("bogus_root.thing", 1) end)
    T.assert_false(ok, "an unknown root must still be refused")
    T.assert_true(tostring(err):match("root_not_allowed") ~= nil, tostring(err))
end

-- ---------------------------------------------------------------------------
-- The ledger is an allow-list, and it is exact
-- ---------------------------------------------------------------------------

function M.test_the_ledger_exists_and_is_not_vacuous()
    T.assert_not_nil(Blackboard.HANDLE_LEDGER, "Blackboard.HANDLE_LEDGER must exist")
    local n = 0
    for _ in pairs(Blackboard.HANDLE_LEDGER) do n = n + 1 end
    T.assert_true(n > 0,
        "an empty ledger means every handle key is retired -- delete the ledger and this test")
end

--- Every listed key really is excused, so the ledger is load-bearing rather than decorative.
function M.test_every_ledger_key_may_still_hold_a_handle()
    for key in pairs(Blackboard.HANDLE_LEDGER) do
        local bb = Blackboard:new()
        local ok, err = pcall(function() bb:set(key, mock_handle()) end)
        T.assert_true(ok, "ledgered key " .. key .. " must be permitted a handle: "
            .. tostring(err))
        T.assert_not_nil(bb:get(key), key .. " must actually be stored")
    end
end

--- ...and the excuse is per-key, not a global off switch. A sibling of a ledgered key under
--- the same namespace is still refused.
function M.test_the_ledger_excuses_only_the_exact_key()
    for key in pairs(Blackboard.HANDLE_LEDGER) do
        local bb = Blackboard:new()
        refusal(bb, key .. "_not_ledgered", mock_handle())
    end
end

-- ---------------------------------------------------------------------------
-- Conformance with kernel/snapshot.lua
-- ---------------------------------------------------------------------------
--
-- The guard is NOT shared code with `snapshot.lua:copy_value`, because `core/` may not
-- require `kernel/` -- the dependency runs one way only. Two copies of a taxonomy drift, and
-- drift here means the two gatekeepers disagree about what a handle is, with the more
-- permissive one deciding. So the taxonomy is shared as a PIN instead of as a function: both
-- must classify the same values the same way.

--- Values both gatekeepers must agree on, and the verdict they must agree on.
local CONFORMANCE = {
    { name = "number", value = 1, accept = true },
    { name = "string", value = "x", accept = true },
    { name = "boolean", value = false, accept = true },
    { name = "flat table", value = { a = 1, b = "two" }, accept = true },
    { name = "nested plain table", value = { a = { b = { c = 3 } } }, accept = true },
    { name = "array of plain tables", value = { { x = 1 }, { x = 2 } }, accept = true },
    { name = "function", value = function() end, accept = false },
    { name = "userdata", value = newproxy(false), accept = false },
    { name = "thread", value = coroutine.create(function() end), accept = false },
    { name = "handle", value = mock_handle(), accept = false },
    { name = "nested handle", value = { a = { b = mock_handle() } }, accept = false },
    { name = "array of handles", value = { mock_handle() }, accept = false },
}

function M.test_the_guard_and_the_snapshot_agree_on_what_carries_behaviour()
    local Snapshot = require("kernel/snapshot")

    local disagreements = {}
    for _, case in ipairs(CONFORMANCE) do
        local bb_ok = pcall(function() Blackboard:new():set("combat.conformance", case.value) end)
        local snap_ok = pcall(function() Snapshot.builder():put("combat.conformance", case.value) end)

        if bb_ok ~= case.accept then
            disagreements[#disagreements + 1] = string.format(
                "blackboard %s %s (expected %s)", bb_ok and "accepted" or "refused",
                case.name, case.accept and "accept" or "refuse")
        end
        if snap_ok ~= case.accept then
            disagreements[#disagreements + 1] = string.format(
                "snapshot %s %s (expected %s)", snap_ok and "accepted" or "refused",
                case.name, case.accept and "accept" or "refuse")
        end
    end

    T.assert_equal(#disagreements, 0,
        "blackboard:set and snapshot:put have drifted apart:\n  "
        .. table.concat(disagreements, "\n  "))
end

--- The DELIBERATE divergences, pinned so they stay deliberate. If one flips, the separation
--- above stopped being a considered tradeoff and became an accident.
function M.test_the_deliberate_divergences_from_the_snapshot()
    local Snapshot = require("kernel/snapshot")

    -- 1. The snapshot copies; the blackboard must not, because it is live read-through state.
    local live = { n = 1 }
    local bb = Blackboard:new()
    bb:set("combat.divergence", live)
    T.assert_true(bb:get("combat.divergence") == live, "blackboard must store the original")
    T.assert_false(Snapshot.builder():put("combat.divergence", live):get("combat.divergence") == live,
        "snapshot must store a copy")

    -- 2. The snapshot refuses cycles (it walks them twice); the blackboard tolerates them
    --    (it never copies), because a cycle in plain data is not a handle.
    local cyclic = { n = 1 }
    cyclic.self = cyclic
    Blackboard:new():set("combat.divergence", cyclic)
    T.assert_false(pcall(function() Snapshot.builder():put("combat.divergence", cyclic) end),
        "snapshot must still refuse a cycle")

    -- 3. Metatables. The blackboard REFUSES them; the snapshot accepts them -- and is safe
    --    anyway, but by accident rather than by check: its deep copy rebuilds the table from
    --    raw fields, so the metatable (and with it the `__index` handle) is dropped on the way
    --    in. The blackboard does not copy, so an accepted proxy would be stored LIVE. Divergence
    --    1 is therefore the direct cause of divergence 3, and it is why the metatable check
    --    belongs here and is not needed there.
    local proxy = setmetatable({}, { __index = mock_handle() })
    T.assert_false(pcall(function() Blackboard:new():set("combat.divergence", proxy) end),
        "blackboard must refuse a metatable it cannot see through")

    local captured = Snapshot.builder():put("combat.divergence", proxy):freeze()
    T.assert_nil(captured:get("combat.divergence").get_max_health,
        "the snapshot's copy must have dropped the metatable -- if it ever stops copying, it "
        .. "needs this same metatable check")
end

-- ---------------------------------------------------------------------------
-- THE RATCHET: the ledger may only shrink
-- ---------------------------------------------------------------------------

--- The ledger lives in `core/blackboard.lua`, so that file MENTIONS every ledgered key by
--- construction. An entry naming it as a writer would therefore be its own evidence, and the
--- ratchet would never fire for it. A mutation that added a stale entry with this file as its
--- writer survived until the evidence was narrowed from "mentions" to "sets".
local LEDGER_FILE = "sentinel/core/blackboard.lua"

---Live evidence that a ledgered key is still WRITTEN -- not merely named -- by a declared
---writer. `bb:get("k")`, a comment, or the ledger entry itself must not count: a key that is
---only ever read is a key whose handle write is gone, which is exactly the retirement this
---ratchet exists to notice.
---@param key string
---@param entry table
---@return boolean found, string|nil why_not
local function writer_still_sets(key, entry)
    local set_of_key = 'set%(%s*"' .. key:gsub("%.", "%%.") .. '"'
    for _, path in ipairs(entry.writers) do
        local source = Scope.read_file(path)
        if not source then
            return false, "declared writer " .. path .. " does not exist"
        end
        local found = false
        Scope.each_code_line(source, function(line)
            if line:match(set_of_key) then found = true end
        end)
        if found then return true, nil end
    end
    return false, "no declared writer still sets " .. key
end

--- Each entry must declare who writes it and what reads it. An unattributed exception is
--- an exception nobody can retire.
function M.test_every_ledger_entry_names_its_writer_and_its_readers()
    for key, entry in pairs(Blackboard.HANDLE_LEDGER) do
        T.assert_not_nil(entry.writers, key .. " must declare `writers`")
        T.assert_true(#entry.writers > 0, key .. " must declare at least one writer")
        T.assert_not_nil(entry.readers, key .. " must declare `readers`")
        T.assert_not_nil(entry.retire, key .. " must declare `retire` -- what would remove it")
        T.assert_true(entry.kind == "sdk_handle" or entry.kind == "collaborator",
            key .. " must declare kind as sdk_handle or collaborator, got "
            .. tostring(entry.kind))
        for _, path in ipairs(entry.writers) do
            T.assert_false(path == LEDGER_FILE, key .. " may not name the ledger's own file as "
                .. "its writer -- that file names every ledgered key, so the entry would be "
                .. "its own evidence and the ratchet could never fire for it")
        end
    end
end

--- THE SHRINK-ONLY DIRECTION. A key that no longer stores a handle must fail exactly as
--- loudly as a key that stores one without being listed. Without this, the ledger is a list
--- of permissions that outlives its reasons.
function M.test_the_ledger_is_shrink_only()
    local stale = {}
    for key, entry in pairs(Blackboard.HANDLE_LEDGER) do
        local found, why = writer_still_sets(key, entry)
        if not found then
            stale[#stale + 1] = key .. ": " .. why .. " -- RETIRED, delete the ledger entry"
        end
    end
    table.sort(stale)
    T.assert_equal(#stale, 0, "HANDLE_LEDGER has stale entries:\n  "
        .. table.concat(stale, "\n  "))
end

--- The ratchet's own mechanism, exercised against a key that certainly is not written
--- anywhere -- proving `test_the_ledger_is_shrink_only` would actually fire, rather than
--- being green because the detector never detects.
function M.test_the_shrink_only_check_fires_on_a_retired_key()
    local found, why = writer_still_sets("combat.a_key_no_writer_sets", {
        writers = { "sentinel/core/blackboard.lua" },
    })
    T.assert_false(found, "a key nobody writes must read as stale")
    T.assert_true(why:match("no declared writer") ~= nil, tostring(why))

    local missing = select(2, writer_still_sets("player.object", {
        writers = { "sentinel/does/not/exist.lua" },
    }))
    T.assert_true(missing:match("does not exist") ~= nil, tostring(missing))
end

return M
