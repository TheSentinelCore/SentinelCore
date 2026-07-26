-- rotations/paladin_retribution/sentinel_api.lua
-- The plugin's handle on `_G.Sentinel`.
--
-- ADR 08 §2.3/§2.4: a plugin cannot `require` the kernel -- there is no documented load order and no
-- guarantee the kernel initialised first. `_G` is the only handshake, and the kernel publishes its
-- surface behind a live-getter metatable precisely so a reference taken early still resolves later.
--
-- This file exists so the plugin never captures a value at LOAD time. Every read goes through
-- `__index` at USE time, which means:
--
--   local API = require("rotations/paladin_retribution/sentinel_api")
--   ... later, inside a tick ...
--   API.catalogs.aura.has_any(unit, ids)
--
-- resolves correctly whether this file loaded before or after the kernel published. Writing
-- `local Aura = _G.Sentinel.catalogs.aura` at the top of a module would capture nil forever if the
-- plugin happened to load first -- the exact bug §2.4's live getter exists to prevent, reintroduced
-- one layer up.
--
-- It requires NOTHING. That is deliberate: this is the only file in the package that touches `_G`,
-- and it is three lines of logic, so the whole plugin's coupling to the kernel is auditable here.
--
-- ================================================================================
-- WHY THIS IS A COPY OF `rotations/mage_frost/sentinel_api.lua` AND NOT A SHARED FILE
-- ================================================================================
-- The two files are byte-identical below the header, and sharing them is not merely worse style --
-- it is forbidden by `tests/kernel/test_plugin_require_audit.lua`, which fails any `require` whose
-- target does not begin with the requiring package's own prefix. A `rotations/shared/sentinel_api`
-- would be a cross-package require from every rotation that used it, and the only legal home for
-- shared code is the kernel surface -- which cannot host this file, because its entire job is
-- NOT being on the surface. Three seven-line copies is the design.

return setmetatable({}, {
    __index = function(_, key)
        local surface = _G.Sentinel
        if surface == nil then return nil end
        return surface[key]
    end,
})
