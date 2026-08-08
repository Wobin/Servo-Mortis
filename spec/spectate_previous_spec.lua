local engine = require("spec.mock_engine")
local t = require("spec.runner")

return function()
	t.suite("Spectate previous keybind")

	local function fresh()
		local mod = engine.install({
			third_person_spectate = true,
			spectate_bots = true,
			skip_downed_targets = false,
		})
		dofile(engine.MOD_ROOT .. "/scripts/mods/Servo Mortis/Servo Mortis.lua")
		mod.on_all_mods_loaded()
		return mod
	end

	local function make_rich_handler()
		local handler = engine.make_handler({ _mode = "observer" })
		handler._side_id = 7
		handler._side_system = {
			get_side = function(_, _)
				return { side_id = 7, player_units = { "alpha", "bravo", "charlie" } }
			end,
		}
		return handler
	end

	local ALIVE_TRIO = { alpha = 1, bravo = 1, charlie = 1 }

	local function player_manager_for(handler)
		return { state = _G.Managers.state, player = {
			local_player_safe = function(_) return handler and { camera_handler = handler } or nil end,
		} }
	end

	t.it("disabled mod does not latch direction", function()
		local mod = fresh()
		local handler = make_rich_handler()
		mod:set_enabled(false)

		engine.with_globals({
			ALIVE = ALIVE_TRIO,
			Managers = player_manager_for(handler),
		}, function()
			mod.spectate_previous()

			mod:set_enabled(true)

			handler._camera_follow_unit = "alpha"
			local hook = mod:find_hook("_next_follow_unit")
			local result = hook.fn(function() return nil end, handler, nil)

			t.eq(result, "bravo", "forwards step confirms no backwards latched")
		end)
	end)

	t.it("no live handler does not latch direction", function()
		local mod = fresh()
		local handler = make_rich_handler()

		engine.with_globals({
			Managers = player_manager_for(nil),
		}, function()
			mod.spectate_previous()
		end)

		engine.with_globals({
			ALIVE = ALIVE_TRIO,
			Managers = player_manager_for(handler),
		}, function()
			handler._camera_follow_unit = "alpha"
			local hook = mod:find_hook("_next_follow_unit")
			local result = hook.fn(function() return nil end, handler, nil)

			t.eq(result, "bravo", "forwards step confirms no backwards latched")
		end)
	end)

	t.it("non-observing handler does not latch direction", function()
		local mod = fresh()
		local handler = make_rich_handler()
		handler._mode = "first_person"

		engine.with_globals({
			ALIVE = ALIVE_TRIO,
			Managers = player_manager_for(handler),
		}, function()
			mod.spectate_previous()

			handler._mode = "observer"

			handler._camera_follow_unit = "alpha"
			local hook = mod:find_hook("_next_follow_unit")
			local result = hook.fn(function() return nil end, handler, nil)

			t.eq(result, "bravo", "forwards step confirms no backwards latched")
		end)
	end)

	t.it("enabled observer mode steps backwards and switches target", function()
		local mod = fresh()
		local handler = make_rich_handler()

		engine.with_globals({
			ALIVE = ALIVE_TRIO,
			Managers = player_manager_for(handler),
		}, function()
			local hook = mod:find_hook("_next_follow_unit")
			t.truthy(hook, "hook should be registered")

			handler._camera_follow_unit = "bravo"
			handler._next_follow_unit = function(_, except_unit)
				return hook.fn(function() return nil end, handler, except_unit)
			end

			mod.spectate_previous()

			t.truthy(handler._switch_calls[1], "should call _switch_follow_target")
			t.eq(handler._follow_updates, 1, "should call _update_follow")
			t.eq(handler._switch_calls[1], "alpha", "backwards from bravo wraps to alpha")
		end)
	end)
end
