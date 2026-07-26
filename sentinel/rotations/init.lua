-- rotations/init.lua
-- The rotations layer's OWN inventory: every rotation package this bundle ships, loaded so each
-- one's bootstrap can self-register onto `__SentinelPending` (ADR 08 §2.4/§14).
--
-- This list lives HERE — not in main.lua, not in the kernel — because the only party that may
-- know a bundle's contents is the bundle layer itself. The host requires this file once; the
-- kernel and the app never name a rotation and select purely by manifest KIND after the drain.
--
-- THE END STATE (ADR 08 §14): each rotation is its own Project Sylvanas plugin —
-- `scripts/<plugin>/header.lua` gating load (the SDK gates by class natively) and `main.lua`
-- pushing the manifest onto `__SentinelPending`. A rotation shipped that way appears in no list
-- anywhere in sentinel, including this one; when the last bundled rotation moves out, this file
-- and its single require in main.lua are deleted. Until the move is verified against a live
-- injector (shared `_G`/`package.loaded` across plugins and the global F6 reload make it a
-- live-session change, not an offline one), this inventory is the loading point.
require("rotations/mage_frost/bootstrap")
require("rotations/paladin_retribution/bootstrap")
require("rotations/warlock_affliction/bootstrap")
