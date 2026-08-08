local t = require("spec.runner")
local engine = require("spec.mock_engine")

local FollowTargets = dofile("./scripts/mods/Servo Mortis/modules/follow_targets.lua")

-- Four units: two humans, one bot, one dead human.
local function ctx(overrides)
	local humans  = { alpha = true, bravo = true, delta = true }
	local alive   = { alpha = true, bravo = true, charlie = true }
	local downed  = { bravo = true }

	local c = {
		player_units = { "alpha", "bravo", "charlie", "delta" },
		is_human  = function(u) return humans[u] == true end,
		is_alive  = function(u) return alive[u] == true end,
		is_downed = function(u) return downed[u] == true end,
		current = nil,
		allow_bots = false,
		skip_downed = false,
	}
	for k, v in pairs(overrides or {}) do
		c[k] = v
	end
	return c
end

local function list_eq(actual, expected, msg)
	t.eq(table.concat(actual, ","), table.concat(expected, ","), msg)
end

-- Swaps globals for the duration of fn, always restoring them afterwards.
local function with_globals(overrides, fn)
	local saved = {}
	for k, v in pairs(overrides) do
		saved[k] = _G[k]
		_G[k] = v
	end
	local ok, err = pcall(fn)
	for k, v in pairs(saved) do
		_G[k] = v
	end
	if not ok then error(err, 0) end
end

local function human_owner()
	return { is_human_controlled = function() return true end }
end

return function()
	t.suite("Follow target selection")

	t.it("without bots, only living humans are candidates", function()
		list_eq(FollowTargets.candidates(ctx()), { "alpha", "bravo" },
			"charlie is a bot, delta is dead")
	end)

	t.it("with bots enabled, living bots join the list in order", function()
		list_eq(FollowTargets.candidates(ctx({ allow_bots = true })), { "alpha", "bravo", "charlie" },
			"charlie should appear between bravo and the dead delta")
	end)

	t.it("skip_downed removes hogtied and downed targets", function()
		list_eq(FollowTargets.candidates(ctx({ skip_downed = true })), { "alpha" },
			"bravo is downed")
	end)

	t.it("skip_downed falls back rather than returning nothing", function()
		local c = ctx({ skip_downed = true, is_downed = function() return true end })
		list_eq(FollowTargets.candidates(c), { "alpha", "bravo" },
			"with every candidate downed, return the unfiltered list instead of nothing")
	end)

	t.it("pick returns the first candidate when there is no current target", function()
		t.eq(FollowTargets.pick(ctx(), nil, 1), "alpha", "should start at the head of the list")
	end)

	t.it("pick advances forwards from the current target", function()
		t.eq(FollowTargets.pick(ctx({ current = "alpha" }), nil, 1), "bravo", "alpha then bravo")
	end)

	t.it("pick wraps forwards past the end", function()
		t.eq(FollowTargets.pick(ctx({ current = "bravo" }), nil, 1), "alpha", "bravo wraps to alpha")
	end)

	t.it("pick walks backwards", function()
		t.eq(FollowTargets.pick(ctx({ current = "bravo" }), nil, -1), "alpha", "bravo back to alpha")
	end)

	t.it("pick wraps backwards past the start", function()
		t.eq(FollowTargets.pick(ctx({ current = "alpha" }), nil, -1), "bravo", "alpha wraps to bravo")
	end)

	t.it("pick honours except_unit", function()
		local c = ctx({ allow_bots = true, current = nil })
		t.eq(FollowTargets.pick(c, "alpha", 1), "bravo", "alpha is excluded")
	end)

	t.it("pick returns nil when there is nobody to follow", function()
		local c = ctx({ player_units = {}, current = nil })
		t.eq(FollowTargets.pick(c, nil, 1), nil, "no candidates means no target")
	end)

	t.it("pick returns the only candidate even when it is the current one", function()
		local c = ctx({ player_units = { "alpha" }, current = "alpha" })
		t.eq(FollowTargets.pick(c, nil, 1), "alpha", "cycling a single target stays put")
	end)

	t.it("a nil direction is treated as forwards", function()
		t.eq(FollowTargets.pick(ctx({ current = "alpha" }), nil, nil), "bravo", "default is next")
	end)

	t.suite("Follow target hook")

	t.it("install registers a hook on _next_follow_unit", function()
		local mod = engine.install({})
		FollowTargets.install(mod, { values = {} })
		local hook = mod:find_hook("_next_follow_unit")
		t.truthy(hook, "no hook registered")
		t.eq(hook.kind, "hook", "must be a wrapping hook, not hook_safe")
	end)

	t.it("the hook repairs a nil _side_id from the heroes side", function()
		local mod = engine.install({})
		FollowTargets.install(mod, { values = {} })
		local hook = mod:find_hook("_next_follow_unit")

		local handler = engine.make_handler({ _side_id = nil })
		handler._side_system = {
			get_side_from_name = function(_, name)
				t.eq(name, "heroes", "must ask for the heroes side")
				return { side_id = 7, player_units = {} }
			end,
			get_side = function(_, id)
				t.eq(id, 7, "must use the repaired id")
				return { side_id = 7, player_units = {} }
			end,
		}

		hook.fn(function() return nil end, handler, nil)
		t.eq(handler._side_id, 7, "_side_id must be repaired, as Perspectives does")
	end)

	t.it("the hook falls back to the original when it cannot build a context", function()
		local mod = engine.install({})
		FollowTargets.install(mod, { values = {} })
		local hook = mod:find_hook("_next_follow_unit")

		local handler = engine.make_handler({ _side_id = nil, _side_system = nil })
		local called = false
		local result = hook.fn(function() called = true; return "vanilla" end, handler, nil)

		t.truthy(called, "the original must run when we cannot decide")
		t.eq(result, "vanilla", "and its result must be returned untouched")
	end)

	t.it("install with no CLASS.CameraHandler records an error and registers no hook", function()
		local mod = engine.install({})
		local saved_camera_handler = _G.CLASS.CameraHandler
		_G.CLASS.CameraHandler = nil

		local ok, err = pcall(FollowTargets.install, mod, { values = {} })

		_G.CLASS.CameraHandler = saved_camera_handler

		t.truthy(ok, "install itself must not throw: " .. tostring(err))
		t.eq(#mod._errors, 1, "should record exactly one error")
		t.truthy(mod._errors[1]:find("CameraHandler", 1, true), "error should name CameraHandler")
		t.falsy(mod:find_hook("_next_follow_unit"), "no hook should be registered")
	end)

	t.it("a pending direction does not leak across an aborted hook call", function()
		local mod = engine.install({})
		FollowTargets.install(mod, { values = {} })
		local hook = mod:find_hook("_next_follow_unit")

		FollowTargets.set_direction(-1)

		local unusable_handler = engine.make_handler({ _side_id = nil, _side_system = nil })
		local vanilla_called = false
		hook.fn(function() vanilla_called = true; return "vanilla" end, unusable_handler, nil)
		t.truthy(vanilla_called, "first call cannot build a context, so it must fall back")

		with_globals({
			ALIVE = { unit1 = 2, unit2 = 2 },
			Managers = { state = { player_unit_spawn = { owner = function() return human_owner() end } } },
		}, function()
			local handler = engine.make_handler({ _side_id = 9 })
			handler._side_system = {
				get_side = function(_, id)
					t.eq(id, 9, "must use the handler's side id")
					return { side_id = 9, player_units = { "unit1", "unit2" } }
				end,
			}
			local result = hook.fn(function() return "vanilla" end, handler, nil)
			t.eq(result, "unit1", "a spent direction request must not apply to a later, unrelated call")
		end)
	end)

	t.it("a successful context build picks a target through is_alive/is_human/is_downed", function()
		local mod = engine.install({})
		FollowTargets.install(mod, { values = { spectate_bots = true, skip_downed_targets = true } })
		local hook = mod:find_hook("_next_follow_unit")

		with_globals({
			ALIVE = { hero = 2 },
			Managers = { state = { player_unit_spawn = { owner = function() return human_owner() end } } },
		}, function()
			local handler = engine.make_handler({ _side_id = 3 })
			handler._side_system = {
				get_side = function(_, id)
					return { side_id = id, player_units = { "hero" } }
				end,
			}
			local func_called = false
			local result = hook.fn(function() func_called = true; return nil end, handler, nil)
			t.eq(result, "hero", "the picked unit should be returned through the hook")
			t.falsy(func_called, "the vanilla path should not run when a target was picked")
		end)
	end)

	t.it("a disabled mod delegates to the vanilla implementation untouched", function()
		local mod = engine.install({})
		FollowTargets.install(mod, { values = { spectate_bots = true, skip_downed_targets = true } })
		local hook = mod:find_hook("_next_follow_unit")
		mod:set_enabled(false)

		with_globals({
			ALIVE = { hero = 2 },
			Managers = { state = { player_unit_spawn = { owner = function() return human_owner() end } } },
		}, function()
			local handler = engine.make_handler({ _side_id = 3 })
			handler._side_system = {
				get_side = function(_, id)
					return { side_id = id, player_units = { "hero" } }
				end,
			}
			local func_called = false
			local result = hook.fn(function() func_called = true; return "vanilla" end, handler, nil)
			t.truthy(func_called, "a disabled mod must call through to the vanilla implementation")
			t.eq(result, "vanilla", "and return its result untouched, even though a context could build")
		end)
	end)

	t.it("a pending direction does not leak across a disabled hook call", function()
		local mod = engine.install({})
		FollowTargets.install(mod, { values = {} })
		local hook = mod:find_hook("_next_follow_unit")

		FollowTargets.set_direction(-1)
		mod:set_enabled(false)

		local disabled_handler = engine.make_handler({ _side_id = nil, _side_system = nil })
		hook.fn(function() return "vanilla" end, disabled_handler, nil)

		mod:set_enabled(true)

		with_globals({
			ALIVE = { unit1 = 2, unit2 = 2 },
			Managers = { state = { player_unit_spawn = { owner = function() return human_owner() end } } },
		}, function()
			local handler = engine.make_handler({ _side_id = 9 })
			handler._side_system = {
				get_side = function(_, id)
					t.eq(id, 9, "must use the handler's side id")
					return { side_id = 9, player_units = { "unit1", "unit2" } }
				end,
			}
			local result = hook.fn(function() return "vanilla" end, handler, nil)
			t.eq(result, "unit1",
				"a direction request from while disabled must not apply to a later, enabled call")
		end)
	end)
end
