---@class NodeScanner
---@field private _event_bus EventBus
---@field private _state_machine StateMachine
---@field private _profile_manager ProfileManager|nil
---@field private _log Logger|nil
---@field private _detected_nodes table<number, table>
---@field private _blacklisted_nodes table<number, number>
local NodeScanner = {}
NodeScanner.__index = NodeScanner

-- Import dependencies (relative paths since we're in SentinelGather folder)
local Helpers = require("lib/Helpers")
local Constants = require("core/Constants")
local Nodes = require("data/Nodes")
local JSON = require("lib/JSON")

-- Import vec3 for ceiling detection
local vec3 = require("common/geometry/vector_3")

-- Import enums for collision flags
local enums = require("common/enums")

-- Get collision flag safely - some versions may have different structure
local COLLISION_FLAG = nil
if enums and enums.collision_flags then
    COLLISION_FLAG = enums.collision_flags.Collision or enums.collision_flags.LineOfSight
end

---Check if position has a ceiling (cave/building/indoor)
---Uses trace_line to detect collision above the position
---@param pos vec3|table Position to check
---@param ceiling_height number? Height to check for ceiling (default 50)
---@return boolean has_ceiling True if there's a ceiling above
local function has_ceiling(pos, ceiling_height)
    -- If we can't get collision flags, skip ceiling detection
    if not COLLISION_FLAG then
        return false
    end

    ceiling_height = ceiling_height or 50
    local above = vec3.new(pos.x, pos.y, pos.z + ceiling_height)

    -- trace_line returns true if CLEAR (no collision), false if blocked
    local success, is_clear = pcall(function()
        return core.graphics.trace_line(pos, above, COLLISION_FLAG)
    end)

    if not success then
        return false  -- Skip ceiling check if trace_line fails
    end

    return not is_clear
end

local EVENTS = Constants.EVENTS
local STATES = Constants.STATES
local DEFAULT_SETTINGS = Constants.DEFAULT_SETTINGS
local PROFESSION_SPELL_IDS = Constants.PROFESSION_SPELL_IDS

-- Import Settings for user preferences
local Settings
local function get_settings()
    if not Settings then
        local success, result = pcall(require, "core/Settings")
        if success then
            Settings = result
        end
    end
    return Settings
end

-- Import logger if available
local Logger
local function get_logger()
    if not Logger then
        local success, result = pcall(require, "lib/Logger")
        if success then
            Logger = result
        end
    end
    if Logger then
        return Logger:new("NodeScanner")
    end
    return nil
end

---Create a new NodeScanner instance
---@param event_bus EventBus
---@param state_machine StateMachine
---@param profile_manager ProfileManager|nil Optional ProfileManager for blackspot checks
---@param config? table Optional configuration
---@return NodeScanner
function NodeScanner:new(event_bus, state_machine, profile_manager, config)
    local instance = setmetatable({}, NodeScanner)

    instance._event_bus = event_bus
    instance._state_machine = state_machine
    instance._profile_manager = profile_manager
    instance._log = get_logger()

    -- Configuration
    config = config or {}
    instance._search_radius = config.search_radius or DEFAULT_SETTINGS.gathering.node_search_radius
    instance._scan_interval = config.scan_interval or 0.5  -- seconds between scans
    instance._blacklist_duration = config.blacklist_duration or DEFAULT_SETTINGS.gathering.node_blacklist_duration or 300

    -- State
    instance._detected_nodes = {}  -- guid -> node_data
    instance._blacklisted_nodes = {}  -- guid -> expiry_time
    instance._last_scan_time = 0
    instance._enabled = true

    -- Filters (can be updated from profile)
    instance._gather_herbs = true
    instance._gather_ores = true
    instance._node_whitelist = {}  -- Empty = allow all
    instance._node_blacklist = {}  -- Names to skip

    -- Profile-level filters (what the profile allows)
    instance._profile_allows_herbs = true
    instance._profile_allows_ores = true

    -- Skill tracking
    instance._has_herbalism = false
    instance._has_mining = false
    instance._skills_checked = false

    -- Subscribe to events
    instance:_subscribe_events()

    -- Check player skills on creation
    instance:_check_player_skills()

    -- Load persisted blacklist from disk
    instance:_load_blacklist()

    return instance
end

---Check if player has gathering professions
function NodeScanner:_check_player_skills()
    -- Check herbalism
    if PROFESSION_SPELL_IDS and PROFESSION_SPELL_IDS.HERBALISM then
        self._has_herbalism = core.spell_book.is_spell_learned(PROFESSION_SPELL_IDS.HERBALISM)
    end

    -- Check mining
    if PROFESSION_SPELL_IDS and PROFESSION_SPELL_IDS.MINING then
        self._has_mining = core.spell_book.is_spell_learned(PROFESSION_SPELL_IDS.MINING)
    end

    self._skills_checked = true

    if self._log then
        self._log:info("Skills checked - Herbalism: %s, Mining: %s",
            tostring(self._has_herbalism), tostring(self._has_mining))
    end

    -- Apply skill-based filtering from settings
    self:_apply_skill_settings()
end

---Apply settings and skill-based filtering
---Combines: profile filters + user settings + skill checks
function NodeScanner:_apply_skill_settings()
    local settings = get_settings()
    if not settings then return end

    -- Get user preferences
    local user_wants_herbs = settings.get("gathering.gather_herbs", true)
    local user_wants_ores = settings.get("gathering.gather_ores", true)
    local check_skills = settings.get("gathering.check_skills", true)

    -- Start with profile allowance (what the profile route supports)
    local can_gather_herbs = self._profile_allows_herbs and user_wants_herbs
    local can_gather_ores = self._profile_allows_ores and user_wants_ores

    -- Apply skill check if enabled
    if check_skills then
        can_gather_herbs = can_gather_herbs and self._has_herbalism
        can_gather_ores = can_gather_ores and self._has_mining
    end

    self._gather_herbs = can_gather_herbs
    self._gather_ores = can_gather_ores

    if self._log then
        self._log:info("Gather types - Herbs: %s (profile=%s, user=%s, skill=%s), Ores: %s (profile=%s, user=%s, skill=%s)",
            tostring(self._gather_herbs), tostring(self._profile_allows_herbs), tostring(user_wants_herbs), tostring(self._has_herbalism),
            tostring(self._gather_ores), tostring(self._profile_allows_ores), tostring(user_wants_ores), tostring(self._has_mining))
    end
end

---Check if player has herbalism skill
---@return boolean
function NodeScanner:has_herbalism()
    return self._has_herbalism
end

---Check if player has mining skill
---@return boolean
function NodeScanner:has_mining()
    return self._has_mining
end

---Refresh skill check (call if player learns new profession)
function NodeScanner:refresh_skills()
    self:_check_player_skills()
end

---Subscribe to relevant events
function NodeScanner:_subscribe_events()
    -- Profile loaded - update filters
    self._event_bus:subscribe(EVENTS.PROFILE_LOADED, function(data)
        self:_update_filters_from_profile(data.profile)
    end, 50, false, "NodeScanner")

    -- Gather failed - blacklist node temporarily
    self._event_bus:subscribe(EVENTS.GATHER_FAILED, function(data)
        if data.node_guid then
            self:blacklist_node(data.node_guid, data.reason)
        end
    end, 50, false, "NodeScanner")

    -- Bot stop - clear state
    self._event_bus:subscribe(EVENTS.BOT_STOP, function()
        self:clear_detected()
    end, 50, false, "NodeScanner")
end

---Update filters from profile settings
---@param profile table Profile data
function NodeScanner:_update_filters_from_profile(profile)
    if not profile then return end

    -- Gather types from profile (what the route supports)
    local filters = profile.filters or {}
    local gather_types = filters.gather_types or { "herb", "ore" }

    -- Set profile-level allowances
    self._profile_allows_herbs = false
    self._profile_allows_ores = false

    for _, gtype in ipairs(gather_types) do
        if gtype == "herb" then
            self._profile_allows_herbs = true
        elseif gtype == "ore" then
            self._profile_allows_ores = true
        end
    end

    -- Node whitelist/blacklist
    self._node_whitelist = filters.node_whitelist or {}
    self._node_blacklist = filters.node_blacklist or {}

    -- Search radius from profile settings
    local settings = profile.settings or {}
    if settings.node_search_radius then
        self._search_radius = settings.node_search_radius
    end

    if self._log then
        self._log:info("Profile filters - allows herbs=%s, allows ores=%s, radius=%.0f",
            tostring(self._profile_allows_herbs), tostring(self._profile_allows_ores), self._search_radius)
    end

    -- Re-apply skill and user settings after profile update
    self:_apply_skill_settings()
end

---Scan for gatherable nodes
---@return table[] detected_nodes Array of detected node data
function NodeScanner:scan()
    if not self._enabled then
        return {}
    end

    local now = core.time()

    -- Rate limit scanning
    if now - self._last_scan_time < self._scan_interval then
        return self:get_detected_nodes()
    end
    self._last_scan_time = now

    -- Clean expired blacklist entries
    self:_clean_blacklist()

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return {}
    end

    local player_pos = player:get_position()
    local objects = core.object_manager.get_all_objects()

    if not objects then
        return {}
    end

    local newly_detected = {}
    local still_visible = {}

    for _, obj in ipairs(objects) do
        if obj and obj:is_valid() then
            local node_data = self:_evaluate_object(obj, player_pos)

            if node_data then
                local guid = node_data.guid
                still_visible[guid] = true

                -- Check if this is a new detection
                if not self._detected_nodes[guid] then
                    self._detected_nodes[guid] = node_data
                    table.insert(newly_detected, node_data)

                    if self._log then
                        self._log:info("Detected %s '%s' at %.1f yards",
                            node_data.node_type, node_data.name, node_data.distance)
                    end

                    -- Publish detection event
                    self._event_bus:publish(EVENTS.NODE_DETECTED, {
                        node = node_data,
                        timestamp = now
                    })
                else
                    -- Update existing node data (distance may have changed)
                    self._detected_nodes[guid].distance = node_data.distance
                    self._detected_nodes[guid].position = node_data.position
                end
            end
        end
    end

    -- Check for nodes that are no longer visible
    local lost_nodes = {}
    for guid, node_data in pairs(self._detected_nodes) do
        if not still_visible[guid] then
            table.insert(lost_nodes, node_data)
        end
    end

    -- Remove lost nodes and publish events
    for _, node_data in ipairs(lost_nodes) do
        self._detected_nodes[node_data.guid] = nil

        if self._log then
            self._log:debug("Lost node '%s'", node_data.name)
        end

        self._event_bus:publish(EVENTS.NODE_LOST, {
            node = node_data,
            timestamp = now
        })
    end

    return self:get_detected_nodes()
end

---Evaluate if an object is a gatherable node
---@param obj game_object The object to evaluate
---@param player_pos vec3 Player position for distance calculation
---@return table|nil node_data Node data if gatherable, nil otherwise
function NodeScanner:_evaluate_object(obj, player_pos)
    -- Double-check validity (object can despawn at any time)
    if not obj:is_valid() then
        return nil
    end

    -- Must be interactable
    if not obj:can_be_looted() and not obj:can_be_used() then
        return nil
    end

    local name = obj:get_name()
    if not name or name == "" then
        return nil
    end

    -- Check if it's a gatherable node
    local is_node, node_type = Nodes.is_node(name)
    if not is_node then
        return nil
    end

    -- Check gather type filters
    if node_type == "herb" and not self._gather_herbs then
        return nil
    end
    if node_type == "ore" and not self._gather_ores then
        return nil
    end

    -- Check whitelist (if not empty, name must be in whitelist)
    if #self._node_whitelist > 0 then
        local in_whitelist = false
        local lower_name = name:lower()
        for _, pattern in ipairs(self._node_whitelist) do
            if lower_name:find(pattern:lower(), 1, true) then
                in_whitelist = true
                break
            end
        end
        if not in_whitelist then
            return nil
        end
    end

    -- Check blacklist
    if #self._node_blacklist > 0 then
        local lower_name = name:lower()
        for _, pattern in ipairs(self._node_blacklist) do
            if lower_name:find(pattern:lower(), 1, true) then
                return nil
            end
        end
    end

    -- Get position and check distance
    local pos = obj:get_position()
    if not pos then
        return nil
    end

    local distance = Helpers.distance_3d(player_pos, pos)
    if distance > self._search_radius then
        return nil
    end

    -- Skip nodes that are underground/indoors (cave detection)
    if has_ceiling(pos) then
        if self._log then
            self._log:debug("Skipping node %s - underground/indoors", name)
        end
        return nil
    end

    -- Skip nodes in blackspot areas
    if self._profile_manager and self._profile_manager.is_in_blackspot then
        local is_blackspot = self._profile_manager:is_in_blackspot(pos)
        if is_blackspot then
            if self._log then
                self._log:debug("Skipping node %s - in blackspot", name)
            end
            return nil
        end
    end

    -- Get object GUID
    local guid = obj:get_guid()
    if not guid then
        return nil
    end

    -- Check if blacklisted
    if self._blacklisted_nodes[guid] then
        return nil
    end

    -- Build node data
    return {
        guid = guid,
        object = obj,
        name = name,
        node_type = node_type,
        position = {
            x = pos.x,
            y = pos.y,
            z = pos.z
        },
        distance = distance,
        detected_at = core.time()
    }
end

---Get all currently detected nodes
---@return table[] Array of node data sorted by distance
function NodeScanner:get_detected_nodes()
    local nodes = {}

    for _, node_data in pairs(self._detected_nodes) do
        -- Verify node is still valid
        if node_data.object and node_data.object:is_valid() then
            table.insert(nodes, node_data)
        end
    end

    -- Sort by distance (nearest first)
    table.sort(nodes, function(a, b)
        return a.distance < b.distance
    end)

    return nodes
end

---Get the nearest gatherable node
---@return table|nil node_data Nearest node or nil
function NodeScanner:get_nearest_node()
    local nodes = self:get_detected_nodes()

    if #nodes > 0 then
        return nodes[1]
    end

    return nil
end

---Get a node with some randomization for anti-detection
---@return table|nil node_data Selected node or nil
function NodeScanner:get_node_with_variance()
    local nodes = self:get_detected_nodes()

    if #nodes == 0 then
        return nil
    end

    if #nodes == 1 then
        return nodes[1]
    end

    -- 70% chance to pick nearest, 30% chance to pick from top 3
    if math.random() < 0.7 then
        return nodes[1]
    else
        local max_index = math.min(3, #nodes)
        local index = math.random(1, max_index)
        return nodes[index]
    end
end

---Get node count
---@return number
function NodeScanner:get_node_count()
    local count = 0
    for _ in pairs(self._detected_nodes) do
        count = count + 1
    end
    return count
end

---Blacklist a node temporarily
---@param guid number|string Node GUID
---@param reason? string Reason for blacklisting
function NodeScanner:blacklist_node(guid, reason)
    local expiry = core.time() + self._blacklist_duration

    self._blacklisted_nodes[guid] = expiry

    -- Remove from detected if present
    local node_data = self._detected_nodes[guid]
    self._detected_nodes[guid] = nil

    if self._log then
        self._log:warn("Blacklisted node %s for %ds: %s",
            tostring(guid), self._blacklist_duration, reason or "unknown")
    end

    -- Publish blacklist event
    self._event_bus:publish(EVENTS.NODE_BLACKLISTED, {
        guid = guid,
        node = node_data,
        reason = reason,
        expiry = expiry,
        timestamp = core.time()
    })

    -- Persist to disk
    self:_save_blacklist()
end

---Check if a node is blacklisted
---@param guid number|string Node GUID
---@return boolean
function NodeScanner:is_blacklisted(guid)
    local expiry = self._blacklisted_nodes[guid]
    if not expiry then
        return false
    end

    if core.time() >= expiry then
        self._blacklisted_nodes[guid] = nil
        return false
    end

    return true
end

---Clean expired blacklist entries
function NodeScanner:_clean_blacklist()
    local now = core.time()
    local to_remove = {}

    for guid, expiry in pairs(self._blacklisted_nodes) do
        if now >= expiry then
            table.insert(to_remove, guid)
        end
    end

    for _, guid in ipairs(to_remove) do
        self._blacklisted_nodes[guid] = nil
    end
end

---Clear all detected nodes
function NodeScanner:clear_detected()
    self._detected_nodes = {}
end

---Clear blacklist
function NodeScanner:clear_blacklist()
    self._blacklisted_nodes = {}
end

local BLACKLIST_FILE = "gatherbuddy/blacklist.json"

---Save blacklist to disk
function NodeScanner:_save_blacklist()
    local entries = {}
    local now = core.time()
    for guid, expiry in pairs(self._blacklisted_nodes) do
        if expiry > now then
            entries[#entries + 1] = {
                guid = guid,
                expires_at = expiry
            }
        end
    end
    local json_str = JSON.encode({ nodes = entries })
    core.write_data_file(BLACKLIST_FILE, json_str)
end

---Load blacklist from disk
function NodeScanner:_load_blacklist()
    local json_str = core.read_data_file(BLACKLIST_FILE)
    if not json_str or json_str == "" then return end

    local ok, data = pcall(JSON.decode, json_str)
    if not ok or not data or not data.nodes then return end

    local now = core.time()
    for _, entry in ipairs(data.nodes) do
        if entry.guid and entry.expires_at and entry.expires_at > now then
            self._blacklisted_nodes[entry.guid] = entry.expires_at
        end
    end

    if self._log then
        self._log:debug("Loaded %d blacklisted nodes from disk", self:get_blacklist_count())
    end
end

---Enable/disable scanning
---@param enabled boolean
function NodeScanner:set_enabled(enabled)
    self._enabled = enabled
end

---Check if scanning is enabled
---@return boolean
function NodeScanner:is_enabled()
    return self._enabled
end

---Set search radius
---@param radius number Search radius in yards
function NodeScanner:set_search_radius(radius)
    self._search_radius = Helpers.clamp(radius, 10, 200)
end

---Get search radius
---@return number
function NodeScanner:get_search_radius()
    return self._search_radius
end

---Set gather types
---@param gather_herbs boolean
---@param gather_ores boolean
function NodeScanner:set_gather_types(gather_herbs, gather_ores)
    self._gather_herbs = gather_herbs
    self._gather_ores = gather_ores
end

---Get blacklist count
---@return number
function NodeScanner:get_blacklist_count()
    local count = 0
    for _ in pairs(self._blacklisted_nodes) do
        count = count + 1
    end
    return count
end

---Clean up module
function NodeScanner:destroy()
    self:clear_detected()
    self:clear_blacklist()
    self._event_bus:unsubscribe_owner("NodeScanner")
end

---Run unit tests
---@return table<string, boolean> Test results
function NodeScanner:_test()
    local results = {}

    -- Create mock dependencies
    local mock_bus = {
        events = {},
        subscriptions = {},
        publish = function(self, event, data)
            table.insert(self.events, { event = event, data = data })
        end,
        subscribe = function(self, event, callback, priority, once, owner)
            table.insert(self.subscriptions, { event = event, owner = owner })
            return #self.subscriptions
        end,
        unsubscribe_owner = function() end
    }

    local mock_state = {
        get_state = function() return STATES.SCANNING end
    }

    -- Test 1: Create scanner (pass nil for profile_manager)
    local scanner = NodeScanner:new(mock_bus, mock_state, nil)
    results.create = (scanner ~= nil)

    -- Test 2: Initial state
    results.initial_enabled = scanner:is_enabled()
    results.initial_radius = (scanner:get_search_radius() == DEFAULT_SETTINGS.gathering.node_search_radius)
    results.initial_no_nodes = (scanner:get_node_count() == 0)

    -- Test 3: Set enabled
    scanner:set_enabled(false)
    results.set_enabled = (scanner:is_enabled() == false)
    scanner:set_enabled(true)

    -- Test 4: Set radius
    scanner:set_search_radius(100)
    results.set_radius = (scanner:get_search_radius() == 100)

    -- Test 5: Clamp radius
    scanner:set_search_radius(500)
    results.clamp_radius = (scanner:get_search_radius() == 200)

    -- Test 6: Blacklist node
    scanner:blacklist_node(12345, "test reason")
    results.blacklist_add = scanner:is_blacklisted(12345)
    results.blacklist_count = (scanner:get_blacklist_count() == 1)

    -- Test 7: Clear blacklist
    scanner:clear_blacklist()
    results.clear_blacklist = (scanner:get_blacklist_count() == 0)
    results.not_blacklisted = not scanner:is_blacklisted(12345)

    -- Test 8: Set gather types
    scanner:set_gather_types(true, false)
    results.gather_types = (scanner._gather_herbs == true and scanner._gather_ores == false)

    -- Test 9: Update filters from profile
    local test_profile = {
        filters = {
            gather_types = { "ore" },
            node_whitelist = { "Copper" },
            node_blacklist = { "Rich" }
        },
        settings = {
            node_search_radius = 75
        }
    }
    scanner:_update_filters_from_profile(test_profile)
    results.profile_herbs = (scanner._gather_herbs == false)
    results.profile_ores = (scanner._gather_ores == true)
    results.profile_radius = (scanner._search_radius == 75)
    results.profile_whitelist = (#scanner._node_whitelist == 1)
    results.profile_blacklist = (#scanner._node_blacklist == 1)

    -- Test 10: Get nearest with no nodes
    results.nearest_empty = (scanner:get_nearest_node() == nil)

    -- Test 11: Events subscribed
    results.events_subscribed = (#mock_bus.subscriptions >= 2)

    return results
end

return NodeScanner
