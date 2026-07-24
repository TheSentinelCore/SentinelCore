-- modules/questing/profile_chain.lua
-- Pure chain-resolution over the compiled profile manifest (chain.json).
--
-- The manifest is derived from RestedXP's `#next` directives: each entry names
-- its successor options in fallback order, each option (and each entry itself)
-- optionally class-guarded. Guards use "/"-separated class lists; class_only
-- admits only those classes, class_not excludes them. Resolution is pure so it
-- is fully offline-testable; loading the manifest from disk lives in the
-- module layer, not here.

local ProfileChain = {}

--- Does a guard pair admit `class_name` (Title-Case, e.g. "Paladin")?
local function eligible(class_only, class_not, class_name)
    if class_only and class_only ~= "" then
        local found = false
        for cls in string.gmatch(class_only, "[^/]+") do
            if cls == class_name then found = true end
        end
        if not found then return false end
    end
    if class_not and class_not ~= "" then
        for cls in string.gmatch(class_not, "[^/]+") do
            if cls == class_name then return false end
        end
    end
    return true
end

ProfileChain._eligible = eligible

--- Resolve the next profile slug after `current_slug` for `class_name`.
--- Options are tried in manifest order; an option is taken only when both the
--- link's guard and the TARGET entry's own guard admit the class, and the
--- target exists in the manifest. Returns nil at the end of the chain.
function ProfileChain.next_slug(manifest, current_slug, class_name)
    local entries = manifest and manifest.entries
    if type(entries) ~= "table" then return nil end
    local entry = entries[current_slug]
    if not entry then return nil end
    for _, opt in ipairs(entry.next or {}) do
        if eligible(opt.class_only, opt.class_not, class_name) then
            local target = entries[opt.slug]
            if target and eligible(target.class_only, target.class_not, class_name) then
                return opt.slug
            end
        end
    end
    return nil
end

--- Walk the whole chain from `start_slug`, bounded against manifest cycles.
--- Returns the ordered slug list (including the start).
function ProfileChain.walk(manifest, start_slug, class_name)
    local seen, order = {}, {}
    local cur = start_slug
    while cur and not seen[cur] do
        seen[cur] = true
        order[#order + 1] = cur
        cur = ProfileChain.next_slug(manifest, cur, class_name)
    end
    return order
end

return ProfileChain
