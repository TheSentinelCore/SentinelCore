local Schema = {}

Schema.SCHEMA_VERSION = "1.0"

function Schema.defaults()
    return {
        version = Schema.SCHEMA_VERSION,
        metadata = {
            name = "New Profile",
            author = "",
            description = "",
            tags = {},
            created_at = 0,
            updated_at = 0,
        },
        requirements = {
            map_id = -1,
            min_level = 1,
            max_level = 80,
            class_restrictions = {},
        },
        target_defaults = {
            level_min = 1,
            level_max = 80,
            creature_types = {},
            npc_blacklist = {},
            npc_whitelist = {},
        },
        hotspots = {},
        blackspots = {},
        vendors = {},
        rest_spots = {},
        loop = true,
        dry_spell_secs = 15,
        travel_engage = true,
        overrides = {},
    }
end

function Schema.merge_target_filters(defaults, overrides)
    defaults = defaults or {}
    local merged = {
        level_min = defaults.level_min,
        level_max = defaults.level_max,
        creature_types = {},
        npc_blacklist = {},
        npc_whitelist = {},
    }
    local src_ct = defaults.creature_types or {}
    for i = 1, #src_ct do merged.creature_types[i] = src_ct[i] end
    local src_bl = defaults.npc_blacklist or {}
    for i = 1, #src_bl do merged.npc_blacklist[i] = src_bl[i] end
    local src_wl = defaults.npc_whitelist or {}
    for i = 1, #src_wl do merged.npc_whitelist[i] = src_wl[i] end

    if type(overrides) ~= "table" then
        return merged
    end

    if overrides.level_min ~= nil then merged.level_min = overrides.level_min end
    if overrides.level_max ~= nil then merged.level_max = overrides.level_max end
    if overrides.creature_types then
        merged.creature_types = {}
        for i = 1, #overrides.creature_types do
            merged.creature_types[i] = overrides.creature_types[i]
        end
    end
    if overrides.npc_blacklist then
        merged.npc_blacklist = {}
        for i = 1, #overrides.npc_blacklist do
            merged.npc_blacklist[i] = overrides.npc_blacklist[i]
        end
    end
    if overrides.npc_whitelist then
        merged.npc_whitelist = {}
        for i = 1, #overrides.npc_whitelist do
            merged.npc_whitelist[i] = overrides.npc_whitelist[i]
        end
    end

    return merged
end

return Schema
