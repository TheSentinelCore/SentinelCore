-- tests/kernel/audit_scope.lua
-- The single definition of "what the plugin audits look at", plus the scanning primitives
-- all three of them share.
--
-- WHY THIS FILE EXISTS.
-- The `core.input` count in rotations/ was once reported as ONE. The real number is an order
-- of magnitude higher. The audit was not wrong about what it saw -- it was wrong about what
-- it looked at. An audit's scope is therefore not an implementation detail of one audit; it
-- is a shared fact, defined once, asserted non-empty once, and consumed by all three. Two
-- audits that disagree about their scope produce two different truths, and the more
-- comfortable one gets believed.
--
-- ADR 08 §8.1: promotion is mechanical IF AND ONLY IF no plugin reaches past the public API.
-- These are the trees where that claim has to hold.

local Scope = {}

-- ---------------------------------------------------------------------------
-- THE SCOPE
-- ---------------------------------------------------------------------------

--- Every tree the audits treat as plugin code.
---
--- `namespace` is the blackboard domain the package owns: it may read and write
--- `module.<namespace>.*` and nothing else under `module.`.
---
--- `require_prefix` is the only require target prefix its files may name.
---
--- `migrating` marks a package that is not under the kernel registry YET but is scheduled to
--- be (ADR 08 §12, Phase 4b Deliverable 4). It is audited now so the violation list is the
--- migration worklist rather than a surprise discovered during the migration.
Scope.PACKAGES = {
    {
        name = "mage_frost",
        dir = "sentinel/rotations/mage_frost",
        require_prefix = "rotations/mage_frost",
        namespace = "mage_frost",
        migrating = false,
    },
    {
        name = "combat",
        dir = "sentinel/modules/combat",
        require_prefix = "modules/combat",
        namespace = "combat",
        migrating = true,
    },
}

--- Files ADR 08 §11.4 marks PROMOTE-with-rework: they are slated to move INTO the kernel.
---
--- Kernel code owns no `module.*` namespace, so every `module.…` key such a file touches is
--- rework the promotion depends on -- including keys in what is currently its own namespace,
--- which stops being "its own" the moment it lands in the kernel. This is why those reads are
--- tracked separately from a cross-namespace violation: today they are legal, and after
--- promotion they are not.
Scope.PROMOTION_CANDIDATES = {
    "sentinel/modules/combat/condition_library.lua",
}

--- Roots scanned for packages that exist on disk but are missing from PACKAGES above.
--- Without this, adding a second rotation and forgetting to register it would make it
--- invisible to every audit -- silently, and in the direction that reports success.
Scope.PACKAGE_ROOTS = { "sentinel/rotations" }

-- ---------------------------------------------------------------------------
-- Filesystem
-- ---------------------------------------------------------------------------
--
-- `find` rather than a recursive Lua walk: this is offline test-harness code running under
-- luajit on Linux, not sandboxed in-game code, so a subprocess is available and honest.

local function popen_lines(command)
    local out = {}
    local pipe = io.popen(command)
    if not pipe then return out end
    for line in pipe:lines() do out[#out + 1] = line end
    pipe:close()
    return out
end

---@param dir string
---@return string[] absolute-ish paths to every .lua file under `dir`
function Scope.lua_files(dir)
    return popen_lines('find "' .. dir .. '" -type f -name "*.lua" 2>/dev/null | sort')
end

---@param root string
---@return string[] immediate subdirectories of `root`
function Scope.subdirs(root)
    return popen_lines('find "' .. root .. '" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort')
end

---@param path string
---@return string|nil
function Scope.read_file(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local source = handle:read("*a")
    handle:close()
    return source
end

---@param path string
---@return boolean
function Scope.dir_exists(path)
    return #popen_lines('test -d "' .. path .. '" && echo yes') > 0
end

-- ---------------------------------------------------------------------------
-- Line iteration
-- ---------------------------------------------------------------------------

--- Iterate the source's code lines, skipping whole-line comments.
---
--- Whole-line comments only. A trailing `-- like this` is NOT stripped, because stripping it
--- correctly means knowing whether the `--` sits inside a string literal, and a lint that
--- guesses at that trades a clear false positive for a silent false negative. The former
--- gets fixed; the latter gets trusted.
---@param source string
---@param fn fun(line: string, line_number: integer)
function Scope.each_code_line(source, fn)
    local line_number = 0
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        line_number = line_number + 1
        if not line:match("^%s*%-%-") then
            fn(line, line_number)
        end
    end
end

--- Run `fn(path, line, line_number)` over every code line of every .lua file in a package.
---@param package_dir string
---@param fn fun(path: string, line: string, line_number: integer)
function Scope.each_package_line(package_dir, fn)
    for _, path in ipairs(Scope.lua_files(package_dir)) do
        local source = Scope.read_file(path)
        if source then
            Scope.each_code_line(source, function(line, line_number)
                fn(path, line, line_number)
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Violation reporting
-- ---------------------------------------------------------------------------

---@param violations table[] each with .file, .line, .detail
---@return string
function Scope.describe(violations)
    local out = {}
    for _, v in ipairs(violations) do
        out[#out + 1] = v.file .. ":" .. v.line .. "  " .. (v.detail or "")
    end
    return table.concat(out, "\n  ")
end

--- Stable `file:line` key, used by the ratchet ledgers to identify a known violation.
---@param v table
---@return string
function Scope.key(v)
    return v.file .. ":" .. v.line
end

-- ---------------------------------------------------------------------------
-- The ratchet
-- ---------------------------------------------------------------------------
--
-- The audits find live violations today. Deliverables 1b/2/4 burn them down. Between now and
-- then the suite must stay green on work that is not yet done, while refusing anything NEW --
-- so each audit carries a ledger of known violations, and the ledger may only shrink.
--
-- A ledger entry is an admission, not an exemption. It names a file:line and the deliverable
-- that removes it. When the count reaches zero the ledger goes, and with it the ratchet.

---Compare live violations against a ledger of accepted ones.
---@param violations table[] live findings
---@param ledger table<string, string> `file:line` -> reason it is tolerated
---@return table[] unexpected, string[] stale  -- new violations, and ledger entries now fixed
function Scope.ratchet(violations, ledger)
    local unexpected, seen = {}, {}
    for _, v in ipairs(violations) do
        local k = Scope.key(v)
        seen[k] = true
        if not ledger[k] then unexpected[#unexpected + 1] = v end
    end

    local stale = {}
    for k in pairs(ledger) do
        if not seen[k] then stale[#stale + 1] = k end
    end
    table.sort(stale)
    return unexpected, stale
end

return Scope
