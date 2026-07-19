-- sentinel/runtime/stage_lowering.lua
-- SENT-6.8, SENT-6.10: Stage 7 — Lowering to RuntimeProfile
-- ADR 008 §10, §15 — Converts optimized authoring structures into an immutable Runtime Execution Profile
-- Implements incremental caching with LRU eviction

local RuntimeTypes = require("runtime/runtime_types")
local Diagnostics = require("runtime/diagnostics")

local LoweringStage = {}
LoweringStage.__index = LoweringStage

-- Cache configuration (SENT-6.10)
LoweringStage.MAX_CACHE_SIZE = 50

-- Diagnostic codes for this stage (C-7xxx)
LoweringStage.ErrorCodes = {
    MissingProfileId = "C-7001",
    MissingOperations = "C-7002",
    InvalidOperation = "C-7003",
    InvalidAction = "C-7004",
    MissingActionId = "C-7005",
    CacheHit = "C-7006",
    Lowered = "C-7007",
}

-- ============================================================================
-- Cache Registry (SENT-6.10)
-- ============================================================================

local ProfileCache = {}
ProfileCache.__index = ProfileCache

function ProfileCache:new()
    return setmetatable({
        _entries = {},
        _order = {},
        _max_size = LoweringStage.MAX_CACHE_SIZE,
    }, ProfileCache)
end

function ProfileCache:get(profile_id)
    if not profile_id then return nil end
    local entry = self._entries[profile_id]
    if entry then
        self:_touch(profile_id)
        return entry.profile
    end
    return nil
end

function ProfileCache:has(profile_id)
    return self._entries[profile_id] ~= nil
end

function ProfileCache:put(profile_id, profile)
    if not profile_id or not profile then return end
    if not self._entries[profile_id] then
        if #self._order >= self._max_size then self:_evict_lru() end
        table.insert(self._order, profile_id)
    end
    self._entries[profile_id] = { profile = profile, cached_at = os.time() }
end

function ProfileCache:_evict_lru()
    if #self._order == 0 then return end
    local lru_id = table.remove(self._order, 1)
    if lru_id then self._entries[lru_id] = nil end
end

function ProfileCache:_touch(profile_id)
    if not profile_id then return end
    for i, id in ipairs(self._order) do
        if id == profile_id then
            table.remove(self._order, i)
            table.insert(self._order, profile_id)
            break
        end
    end
end

function ProfileCache:clear() self._entries = {} self._order = {} end

function ProfileCache:stats() return { size = #self._order, max_size = self._max_size } end

-- Class-level cache retained only for the backward-compatible static
-- helpers (get_cached_profile / has_cached_profile / clear_cache /
-- get_cache_stats). The per-compile cache is instance-scoped (see
-- LoweringStage:new) so independent CompilerBridge sessions in a shared
-- VM do not leak lowered profiles into one another (ADR-008 §15 intent).
LoweringStage._profile_cache = ProfileCache:new()

---Create a new LoweringStage
---@return table
function LoweringStage:new()
    local o = setmetatable({}, LoweringStage)
    o._cache = ProfileCache:new()
    return o
end

---Run Stage 7: Lower optimized profile to RuntimeProfile
---@param optimized_profile table Optimized profile from Stage 6
---@param source_profile_id string Source profile ID for provenance
---@return table result { runtime_profile = RuntimeProfile, diagnostics = { errors = {}, warnings = {} } }
function LoweringStage:run(optimized_profile, source_profile_id)
    local errors = {}
    local warnings = {}

    if not optimized_profile then
        table.insert(errors, Diagnostics.error(
            LoweringStage.ErrorCodes.MissingOperations,
            Diagnostics.Stage.Lowering,
            "Optimized profile is nil"
        ))
        return { runtime_profile = nil, diagnostics = { errors = errors, warnings = warnings } }
    end

    if not source_profile_id then
        table.insert(errors, Diagnostics.error(
            LoweringStage.ErrorCodes.MissingProfileId,
            Diagnostics.Stage.Lowering,
            "Source profile ID is required for caching"
        ))
        return { runtime_profile = nil, diagnostics = { errors = errors, warnings = warnings } }
    end

    if not optimized_profile.operations then
        table.insert(errors, Diagnostics.error(
            LoweringStage.ErrorCodes.MissingOperations,
            Diagnostics.Stage.Lowering,
            "Optimized profile missing operations"
        ))
        return { runtime_profile = nil, diagnostics = { errors = errors, warnings = warnings } }
    end

    -- Key the cache on the optimized-profile CONTENT hash (ADR-008 §15),
    -- not the profile name/id, so identical content reuses the cache
    -- regardless of VM-shared state or name collisions, and an edited
    -- profile (same name) correctly bypasses it.
        local cache_key = RuntimeTypes._compute_content_hash(optimized_profile)

    local cached = self._cache:get(cache_key)
    if cached then
        table.insert(warnings, Diagnostics.info(
            LoweringStage.ErrorCodes.CacheHit,
            Diagnostics.Stage.Lowering,
            "Cache hit for profile: " .. tostring(source_profile_id),
            source_profile_id
        ))
        -- Content is identical, but re-stamp identity on a shallow copy so
        -- the returned RuntimeProfile carries the right profile_id even when
        -- two differently-named profiles share identical content. The cached
        -- entry itself is left untouched for other callers.
        local hit = {}
        for k, v in pairs(cached) do hit[k] = v end
        hit.profile_id = source_profile_id
        hit.source_profile_id = source_profile_id
        if hit.metadata then
            hit.metadata = {}
            for k, v in pairs(cached.metadata or {}) do hit.metadata[k] = v end
            hit.metadata.source_hash = cache_key
        end
        return { runtime_profile = hit, diagnostics = { errors = errors, warnings = warnings }, cached = true }
    end

    local runtime_profile = RuntimeTypes.new_runtime_profile(optimized_profile, source_profile_id)
    local validation = RuntimeTypes.validate_runtime_profile(runtime_profile)
    for _, err in ipairs(validation.errors) do table.insert(errors, err) end
    for _, warn in ipairs(validation.warnings) do table.insert(warnings, warn) end

    if #errors == 0 then
        self._cache:put(cache_key, runtime_profile)
        table.insert(warnings, Diagnostics.info(
            LoweringStage.ErrorCodes.Lowered,
            Diagnostics.Stage.Lowering,
            "Lowered " .. tostring(#runtime_profile.operations) .. " operations to RuntimeProfile",
            runtime_profile.profile_id
        ))
    end

    return { runtime_profile = runtime_profile, diagnostics = { errors = errors, warnings = warnings } }
end

---Transform an action into runtime-ready format with generated_from tracking
---@param action table Source action
---@param source_action_id string|nil Original action ID for provenance
---@return table RuntimeAction
function LoweringStage:_transform_action(action, source_action_id)
    local runtime_action = RuntimeTypes.new_runtime_action(action)
    if source_action_id and not runtime_action.generated_from then
        runtime_action.generated_from = source_action_id
    end
    return runtime_action
end

function LoweringStage.get_cached_profile(profile_id)
    return LoweringStage._profile_cache:get(profile_id)
end

function LoweringStage.has_cached_profile(profile_id)
    return LoweringStage._profile_cache:has(profile_id)
end

function LoweringStage.clear_cache()
    LoweringStage._profile_cache:clear()
end

function LoweringStage.get_cache_stats()
    return LoweringStage._profile_cache:stats()
end

return LoweringStage