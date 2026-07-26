-- rotations/mage_frost/bootstrap.lua
-- Self-registration, ADR 08 §2.4. This package announces itself by pushing its manifest onto
-- `__SentinelPending`; the kernel drains that queue at publish and for the first ~60 ticks.
-- The kernel does not know this package exists — that is the point. A rotation shipped as its
-- own Project Sylvanas plugin runs this same idiom from its own entry point and needs no line
-- anywhere in sentinel; the only reason sentinel's host (main.lua) requires THIS file is that
-- this rotation currently ships inside the sentinel bundle.
--
-- `push()` is exposed for hosts that stand up more than one kernel per process (tests): a
-- require is cached, so the load-time push happens once, and a second registry needs a second
-- push. Pushing twice at the same registry is harmless — `discover` refuses duplicate_id.
local manifest = require("rotations/mage_frost/manifest")

local Bootstrap = {}

function Bootstrap.push()
    _G.__SentinelPending = _G.__SentinelPending or {}
    table.insert(_G.__SentinelPending, manifest)
    return manifest
end

Bootstrap.push()

return Bootstrap
