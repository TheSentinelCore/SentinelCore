local Controller = require("core/intent/controller")
local config = require("shared/config")

local function with_mock_core(run)
    local previous_core = _G.core
    local now = 0

    _G.core = {
        time = function()
            return now
        end,
        log = function()
        end,
    }

    local ok, err = pcall(run, function(next_time)
        now = next_time
    end)

    _G.core = previous_core
    if not ok then
        error(err, 0)
    end
end

local function with_intent_logging_disabled(run)
    local previous = config.debug.log_intent
    config.debug.log_intent = false
    local ok, err = pcall(run)
    config.debug.log_intent = previous
    if not ok then
        error(err, 0)
    end
end

local function make_intent(id, opts)
    local options = opts or {}
    local intent = {
        id = id,
        exit_count = 0,
    }

    function intent:exit()
        self.exit_count = self.exit_count + 1
    end

    if type(options.is_interruptible) == "function" then
        intent.is_interruptible = options.is_interruptible
    end
    if type(options.can_bypass_gates) == "function" then
        intent.can_bypass_gates = options.can_bypass_gates
    end

    return intent
end

return function(test)
    test.case("intent_controller enforces min_commit before switching", function()
        with_intent_logging_disabled(function()
            with_mock_core(function(set_time)
                local carry = make_intent("carry_flag")
                local fight = make_intent("fight")
                local intent_controller = Controller.new(carry)

                set_time(2.0)
                local active = intent_controller:process({
                    intent_id = "fight",
                    score = 95,
                    intent_instance = fight,
                })

                test.assert_eq(active.id, "carry_flag")
                test.assert_eq(intent_controller:get_current_id(), "carry_flag")
            end)
        end)
    end)

    test.case("intent_controller switches once min_commit window has elapsed", function()
        with_intent_logging_disabled(function()
            with_mock_core(function(set_time)
                local carry = make_intent("carry_flag")
                local fight = make_intent("fight")
                local intent_controller = Controller.new(carry)

                set_time(9.0)
                local active = intent_controller:process({
                    intent_id = "fight",
                    score = 95,
                    intent_instance = fight,
                })

                test.assert_eq(active.id, "fight")
                test.assert_eq(intent_controller:get_current_id(), "fight")
                test.assert_eq(carry.exit_count, 1)
            end)
        end)
    end)

    test.case("intent_controller enforces switch_margin threshold", function()
        with_intent_logging_disabled(function()
            with_mock_core(function(set_time)
                local roam = make_intent("roam")
                local fight = make_intent("fight")
                local intent_controller = Controller.new(roam)

                -- Prime current score for roam.
                set_time(10.0)
                intent_controller:process({
                    intent_id = "roam",
                    score = 100,
                    intent_instance = roam,
                })

                -- 10% gain is below default 15% switch margin.
                set_time(10.1)
                local held = intent_controller:process({
                    intent_id = "fight",
                    score = 110,
                    intent_instance = fight,
                })
                test.assert_eq(held.id, "roam")
                test.assert_eq(intent_controller:get_current_id(), "roam")

                -- 16% gain passes the margin gate.
                set_time(10.2)
                local switched = intent_controller:process({
                    intent_id = "fight",
                    score = 116,
                    intent_instance = fight,
                })
                test.assert_eq(switched.id, "fight")
                test.assert_eq(intent_controller:get_current_id(), "fight")
            end)
        end)
    end)

    test.case("intent_controller enforces cooldown before second switch", function()
        with_intent_logging_disabled(function()
            with_mock_core(function(set_time)
                local roam = make_intent("roam")
                local fight = make_intent("fight")
                local intent_controller = Controller.new(roam)

                set_time(10.0)
                intent_controller:process({
                    intent_id = "fight",
                    score = 150,
                    intent_instance = fight,
                })
                test.assert_eq(intent_controller:get_current_id(), "fight")

                -- Cooldown gate should block this switch.
                set_time(11.0)
                local held = intent_controller:process({
                    intent_id = "roam",
                    score = 220,
                    intent_instance = roam,
                })
                test.assert_eq(held.id, "fight")

                -- Cooldown and min-commit elapsed: switch is now allowed.
                set_time(16.0)
                local switched = intent_controller:process({
                    intent_id = "roam",
                    score = 220,
                    intent_instance = roam,
                })
                test.assert_eq(switched.id, "roam")
            end)
        end)
    end)

    test.case("intent_controller allows candidate bypass method to skip gates", function()
        with_intent_logging_disabled(function()
            with_mock_core(function(set_time)
                local roam = make_intent("roam")
                local fight = make_intent("fight")
                local retreat = make_intent("retreat", {
                    can_bypass_gates = function()
                        return true
                    end,
                })
                local intent_controller = Controller.new(roam)

                set_time(10.0)
                intent_controller:process({
                    intent_id = "fight",
                    score = 150,
                    intent_instance = fight,
                })
                test.assert_eq(intent_controller:get_current_id(), "fight")

                -- Cooldown is active here; bypass-capable retreat should still switch.
                set_time(10.2)
                local switched = intent_controller:process({
                    intent_id = "retreat",
                    score = 60,
                    intent_instance = retreat,
                })
                test.assert_eq(switched.id, "retreat")
            end)
        end)
    end)

    test.case("intent_controller allows current intent interruptible contract", function()
        with_intent_logging_disabled(function()
            with_mock_core(function(set_time)
                local carry = make_intent("carry_flag", {
                    is_interruptible = function(_, next_intent_id)
                        return next_intent_id == "escort_carrier"
                    end,
                })
                local escort = make_intent("escort_carrier")
                local intent_controller = Controller.new(carry)

                -- Below carry_flag min_commit (8s), but carry intent can allow interruption.
                set_time(2.0)
                local switched = intent_controller:process({
                    intent_id = "escort_carrier",
                    score = 50,
                    intent_instance = escort,
                })
                test.assert_eq(switched.id, "escort_carrier")
            end)
        end)
    end)
end
