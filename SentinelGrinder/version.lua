local Version = {
    major = 0,
    minor = 1,
    patch = 0,
    revision = 15,
    author = "Laidbak",
    history = {
        {
            revision = 15,
            date = "2026-02-17",
            summary = "Add Unstuck v2 move recovery pipeline with staged input actions, progress stall detection, and unified move cancellation handling",
        },
        {
            revision = 14,
            date = "2026-02-17",
            summary = "Add route profile manager with map/level auto-selection, profile patrol mode, and closest-waypoint resume with legacy circle fallback",
        },
        {
            revision = 13,
            date = "2026-02-15",
            summary = "Improve warlock spec detection, add patrol mount+dismount flow, and throttle curse/immolate debuff recasts",
        },
        {
            revision = 12,
            date = "2026-02-15",
            summary = "Prioritize selected target, add combat retarget/loot states, and improve hostile enemy search expansion",
        },
        {
            revision = 11,
            date = "2026-02-15",
            summary = "Fix UI open flow without reload, prevent Soul Link self-buff spam, and expand patrol radius when no enemies",
        },
        {
            revision = 10,
            date = "2026-02-15",
            summary = "Add Grind settings tab, hostile mob level filters, and stronger UI mouse-capture release logic",
        },
        {
            revision = 9,
            date = "2026-02-15",
            summary = "Prevent Astro settings mouse lock by auto-closing UI outside main menu and resetting capture state",
        },
        {
            revision = 8,
            date = "2026-02-15",
            summary = "Fix missing vec3 imports causing startup crash in route and blackspot modules",
        },
        {
            revision = 7,
            date = "2026-02-15",
            summary = "Make GrindBuddy initialization resilient when NavLib facade loads late and auto-retry movement binding",
        },
        {
            revision = 6,
            date = "2026-02-15",
            summary = "Import MaxDps TBC profiles, add Astro UI rotation selector, and enable manual/auto profile loading",
        },
        {
            revision = 5,
            date = "2026-02-15",
            summary = "Add TBC basic warlock rotation and persistent blackspot learning for movement timeouts",
        },
        {
            revision = 4,
            date = "2026-02-15",
            summary = "Add target-driven grind loop with scoring, pull flow, and TTL blacklists (NavLib movement only)",
        },
        {
            revision = 3,
            date = "2026-02-15",
            summary = "Integrate NavLib movement loop for GrindBuddy patrol (no local unstuck logic)",
        },
        {
            revision = 2,
            date = "2026-02-15",
            summary = "Stabilize bump_version script behavior",
        },
        {
            revision = 1,
            date = "2026-02-15",
            summary = "Initial GrindBuddy module with integrated per-change versioning system.",
        },
    },
}

function Version.to_string()
    return string.format("%d.%d.%d-r%d", Version.major, Version.minor, Version.patch, Version.revision)
end

function Version.latest_change()
    return Version.history[1]
end

return Version
