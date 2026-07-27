-- tests/ui/test_escort_round_trip.lua
-- F15 end to end: a walked path becomes editable Waypoint/Wait nodes in the campaign.
--
-- WHY THIS IS ITS OWN FILE
-- -----------------------
-- Every piece of F15 was individually green before this existed and the feature still did not
-- work, because the pieces were wired to each other's neighbours rather than to each other:
--
--   * the Graph binding's render callback sampled `ctx.player_position` into
--     `state.escort_timeline` ONCE PER FRAME, so a two-minute walk produced thousands of
--     "waypoints" describing the same corridor;
--   * `EscortRecorder` sampled properly, on the tick, at one second -- and its `generate_nodes`
--     had no caller at all;
--   * `GraphState:generate_escort_nodes` inserted its nodes into the LOCAL node list, so the
--     recording existed only in the panel that made it and vanished with the session.
--
-- The requirement is one sentence -- "generated Waypoint/Wait nodes reproduce the path and are
-- editable like any other sequence" -- and every clause of it needs the pieces joined up. So the
-- test walks a path through the shell's own tick context, stops, and then edits one of the nodes
-- that came back, which is the only way "editable like any other sequence" can be asserted rather
-- than assumed.

local IdePanels = require("ui/ide_panels")
local GraphState = require("ui/panels/graph_state")
local T = require("tests/test_util")

local M = {}

local GRAPH_ID = "graph-escort"

--- The path the operator walks: an L, so a collapsed or reordered recording is visible.
local PATH = {
    { x = 100, y = 200, z = 10 },
    { x = 110, y = 200, z = 10 },
    { x = 120, y = 200, z = 10 },
    { x = 120, y = 210, z = 10 },
    { x = 120, y = 220, z = 10 },
    { x = 120, y = 230, z = 10 },
}

--- An editor that keeps what it is given and answers with it, so the round trip is a real one:
--- the nodes the panel shows afterwards are the nodes the editor stored, with the editor's ids.
local function storing_editor()
    local editor = { stored = {}, writes = 0, next_id = 0 }

    function editor.load_campaign(_, name)
        local nodes = {}
        for i, node in ipairs(editor.stored) do nodes[i] = node end
        return {
            schema_version = 1, id = "campaign-1", name = name,
            imports = {}, variables = {}, conditions = {},
            graphs = { { id = GRAPH_ID, name = "main",
                         entry_node = nodes[1] and nodes[1].id or "nil-id",
                         nodes = nodes, edges = {} } },
        }
    end

    function editor.add_nodes(_, _campaign, nodes)
        editor.writes = editor.writes + 1
        for _, node in ipairs(nodes) do
            editor.next_id = editor.next_id + 1
            local intent = {}
            for k, v in pairs(node.intent or {}) do intent[k] = v end
            editor.stored[#editor.stored + 1] = {
                id = string.format("srv-%04d", editor.next_id),
                type = node.type, intent = intent,
            }
        end
        return true
    end

    function editor.update_node(_, _campaign, node_id, node)
        for _, stored in ipairs(editor.stored) do
            if stored.id == node_id then
                stored.intent = node.intent
                return true
            end
        end
        return false, "no such node"
    end

    function editor.list_campaigns() return {} end
    function editor.validate() return {} end
    function editor.compile() return {} end
    function editor.take_error() return nil end
    function editor.forget() end
    function editor.forget_create() end
    return editor
end

--- A Graph panel with a campaign open and a recorder whose clock the test drives.
local function walked_panel(editor)
    local binding = IdePanels.new_graph({ editor_client = editor })
    local spec = binding:spec()
    local state = binding:state()

    -- One second of recorder time per tick: the sample interval is one second, so this walks the
    -- path at exactly one sample per step without the test taking six seconds to run.
    local clock = 0
    binding._recorder._now = function() return clock end

    spec.dispatch({ kind = "open_campaign", name = "escort" }, nil)
    spec.on_tick({})

    spec.dispatch({ kind = "toggle_escort" }, nil)
    for index, position in ipairs(PATH) do
        -- The clock moves BEFORE each sample but the first, so `clock` still reads the moment of
        -- the last sample when the walk ends -- otherwise a probe tick afterwards would look like
        -- another second of walking.
        if index > 1 then clock = clock + 1 end
        -- The SHELL's tick context, which is where `player_position` actually comes from
        -- (`shell.lua::_tick_context`). Reading the object manager here instead would test a
        -- fallback the injector never takes.
        spec.on_tick({ player_position = position })
    end
    return binding, spec, state
end

-- ---------------------------------------------------------------------------

function M.test_the_walk_is_sampled_once_per_interval_not_once_per_tick()
    local editor = storing_editor()
    local binding, spec, state = walked_panel(editor)

    T.assert_equal(binding:recorder().samples, #PATH,
        "one sample per second of walking, not one per frame -- frame-rate sampling turned a "
        .. "two-minute escort into thousands of waypoints describing the same corridor")
    T.assert_equal(#state.escort_timeline, #PATH,
        "and the indicator counts the recorder's samples, not a second timeline beside them")

    -- Ticking again without moving the clock adds nothing.
    spec.on_tick({ player_position = PATH[#PATH] })
    T.assert_equal(binding:recorder().samples, #PATH, "the interval gates the next sample")
end

function M.test_stopping_writes_the_path_into_the_campaign()
    local editor = storing_editor()
    local _, spec, state = walked_panel(editor)

    local ok, reason = spec.dispatch({ kind = "generate_escort_nodes" }, nil)
    T.assert_true(ok, "the recording must land: " .. tostring(reason))
    T.assert_equal(editor.writes, 1,
        "through the EDITOR -- generated into the local node list they would be a recording the "
        .. "operator can look at and nothing else")
    T.assert_false(state.escort_mode, "and recording has stopped")

    spec.on_tick({})   -- the graph comes back from the editor

    local travels, waits = {}, 0
    for _, node in ipairs(state.nodes) do
        if node.type == "questing.Travel" then travels[#travels + 1] = node end
        if node.type == "questing.Wait" then waits = waits + 1 end
    end
    T.assert_equal(#travels, #PATH, "one Travel node per recorded position")
    T.assert_equal(waits, 1, "and a Wait for pacing every fifth sample")

    for i, node in ipairs(travels) do
        T.assert_equal(node.intent.x, PATH[i].x, "waypoint " .. i .. " reproduces the path in x")
        T.assert_equal(node.intent.y, PATH[i].y, "and in y")
        T.assert_equal(node.intent.z, PATH[i].z, "and in z")
    end
end

function M.test_the_generated_nodes_are_editable_like_any_other_sequence()
    -- The clause that cannot be assumed. Nodes are editable only if they came back with the
    -- EDITOR's ids; a locally generated node has an id that addresses nothing on the server, so
    -- the first edit of it would 400 and read as "the editor is broken".
    local editor = storing_editor()
    local _, spec, state = walked_panel(editor)
    spec.dispatch({ kind = "generate_escort_nodes" }, nil)
    spec.on_tick({})

    local first = state.nodes[1]
    T.assert_not_nil(first, "there is a node to edit")
    T.assert_true(tostring(first.id):find("srv-", 1, true) == 1,
        "and it carries the editor's id, not the one the recorder made up: got "
        .. tostring(first.id))

    local opened = spec.dispatch({ kind = "edit_intent", node_id = first.id,
                                   field = "tolerance" }, nil)
    T.assert_true(opened, "Edit opens on a recorded node exactly as on a hand-authored one")
    T.assert_equal(state.edit_input.value, "5", "seeded with the recorded tolerance")

    state.edit_input.buffer = "12"
    spec.dispatch(GraphState.reduce("edit_value_submit"), nil)
    spec.on_tick({})   -- the graph comes back with the edit in it

    T.assert_equal(state.nodes[1].intent.tolerance, 12,
        "and the edit round-trips through the editor like any other node's would")
    T.assert_equal(state.nodes[1].intent.x, PATH[1].x,
        "without disturbing the position the recording captured")
end

function M.test_a_recording_that_captured_nothing_says_so_and_writes_nothing()
    -- The player was out of world, or the object manager never answered. That is a fact to report,
    -- not an empty sequence to write into someone's campaign.
    local editor = storing_editor()
    local binding = IdePanels.new_graph({ editor_client = editor })
    local spec, state = binding:spec(), binding:state()
    spec.dispatch({ kind = "open_campaign", name = "escort" }, nil)
    spec.on_tick({})

    -- No position from the shell AND none from the object manager. The second half matters: the
    -- binding falls back to reading the object manager itself, and with a mocked player in the
    -- process that fallback answers -- which is the fallback working, not this case.
    local saved = core.object_manager
    core.object_manager = nil
    spec.dispatch({ kind = "toggle_escort" }, nil)
    spec.on_tick({ player_position = nil })
    core.object_manager = saved

    spec.dispatch({ kind = "generate_escort_nodes" }, nil)

    T.assert_equal(editor.writes, 0, "nothing was recorded, so nothing is written")
    T.assert_true(tostring(state.error):find("nothing was recorded", 1, true) ~= nil,
        "and the panel says why: " .. tostring(state.error))
end

function M.test_a_binding_ticked_without_a_shell_still_records_from_the_object_manager()
    -- The fallback the case above has to switch off. A binding ticked with no context at all --
    -- which is what every unit test and any host that ticks it directly does -- must still be able
    -- to record, or F15 would work only through the shell.
    local editor = storing_editor()
    local binding = IdePanels.new_graph({ editor_client = editor })
    local spec = binding:spec()
    local clock = 0
    binding._recorder._now = function() return clock end

    local saved = core.object_manager
    core.object_manager = {
        get_local_player = function()
            return { get_position = function() return { x = 1, y = 2, z = 3 } end }
        end,
    }
    spec.dispatch({ kind = "toggle_escort" }, nil)
    spec.on_tick()
    core.object_manager = saved

    T.assert_equal(binding:recorder().samples, 1, "the tick read the position for itself")
    T.assert_equal(binding:recorder().timeline[1].position.x, 1, "and it is the player's")
end

function M.test_a_refused_write_loses_no_nodes_to_a_phantom_success()
    local editor = storing_editor()
    local _, spec, state = walked_panel(editor)
    function editor.add_nodes() return false, "campaign is locked" end

    spec.dispatch({ kind = "generate_escort_nodes" }, nil)
    spec.on_tick({})
    T.assert_true(tostring(state.error):find("campaign is locked", 1, true) ~= nil,
        tostring(state.error))
    T.assert_equal(#state.nodes, 0,
        "and no waypoint appears -- a path drawn from a write that was refused is the phantom "
        .. "authoring this whole change exists to remove")
end

return M
