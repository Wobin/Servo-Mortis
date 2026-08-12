local engine = require("spec.mock_engine")
local t = require("spec.runner")

local CameraMode = dofile("./scripts/mods/Servo Mortis/modules/camera_mode.lua")

local function settings(third_person)
	return { values = { third_person_spectate = third_person } }
end

return function()
	t.suite("Camera mode")

	t.it("the flag is cleared when the feature is on", function()
		t.eq(CameraMode.desired_flag(settings(true)), false,
			"third person spectating means first-person spectating is off")
	end)

	t.it("the flag is restored when the feature is off", function()
		t.eq(CameraMode.desired_flag(settings(false)), true, "vanilla is true")
	end)

	t.it("apply writes the flag onto a handler", function()
		local handler = engine.make_handler()
		CameraMode.apply(handler, settings(true))
		t.eq(handler._first_person_spectating_mode, false, "flag should be cleared")
	end)

	t.it("apply restores the flag when the feature is turned off", function()
		local handler = engine.make_handler({ _first_person_spectating_mode = false })
		CameraMode.apply(handler, settings(false))
		t.eq(handler._first_person_spectating_mode, true,
			"turning the setting off must actively restore vanilla, not leave it cleared")
	end)

	t.it("apply on a nil handler does not error", function()
		local ok = pcall(CameraMode.apply, nil, settings(true))
		t.truthy(ok, "must tolerate no handler")
	end)

	t.it("apply reports success when the field is present", function()
		local handler = engine.make_handler()
		t.eq(CameraMode.apply(handler, settings(true)), true, "should report that it applied")
	end)

	t.it("apply refuses a handler with no such field", function()
		local handler = engine.make_handler()
		handler._first_person_spectating_mode = nil -- as if a patch renamed it

		t.eq(CameraMode.apply(handler, settings(true)), false,
			"a missing field means the engine changed; do not invent it")
		t.eq(handler._first_person_spectating_mode, nil, "must not create the field")
	end)

	t.it("the init hook logs once when the field is gone", function()
		local mod = engine.install({})
		CameraMode.install(mod, settings(true))
		local hook = mod:find_hook("init")

		local handler = engine.make_handler()
		handler._first_person_spectating_mode = nil

		hook.fn(handler)
		hook.fn(handler)

		local complaints = 0
		for _, line in ipairs(mod._logs) do
			if tostring(line):find("first_person_spectating_mode", 1, true) then
				complaints = complaints + 1
			end
		end
		t.eq(complaints, 1, "log the breakage once, not once per handler build")
	end)

	t.it("install registers both hooks", function()
		local mod = engine.install({})
		CameraMode.install(mod, settings(true))
		t.truthy(mod:find_hook("init"), "no init hook")
		t.truthy(mod:find_hook("is_observing"), "no is_observing hook")
	end)

	t.it("the is_observing repair ignores the flag", function()
		local mod = engine.install({})
		CameraMode.install(mod, settings(true))
		local hook = mod:find_hook("is_observing")

		local handler = engine.make_handler({ _mode = "observer", _first_person_spectating_mode = false })
		t.eq(hook.fn(function() return handler:is_observing() end, handler), true,
			"observing in third person is still observing")
	end)

	t.it("the is_observing repair still reports false outside observer mode", function()
		local mod = engine.install({})
		CameraMode.install(mod, settings(true))
		local hook = mod:find_hook("is_observing")

		local handler = engine.make_handler({ _mode = "first_person", _first_person_spectating_mode = false })
		t.eq(hook.fn(function() return handler:is_observing() end, handler), false,
			"first person is not observing")
	end)

	t.it("the init hook applies the flag to a freshly built handler", function()
		local mod = engine.install({})
		CameraMode.install(mod, settings(true))
		local hook = mod:find_hook("init")

		local handler = engine.make_handler()
		hook.fn(handler)
		t.eq(handler._first_person_spectating_mode, false, "init must apply the setting")
	end)

	t.it("the init hook restores vanilla on a fresh handler while disabled", function()
		local mod = engine.install({})
		CameraMode.install(mod, settings(true))
		mod:set_enabled(false)
		local hook = mod:find_hook("init")

		local handler = engine.make_handler()
		hook.fn(handler)
		t.eq(handler._first_person_spectating_mode, true,
			"a disabled mod must not clear the flag on a newly built handler")
	end)

	t.it("the init hook still applies the setting once re-enabled", function()
		local mod = engine.install({})
		CameraMode.install(mod, settings(true))
		mod:set_enabled(false)
		mod:set_enabled(true)
		local hook = mod:find_hook("init")

		local handler = engine.make_handler()
		hook.fn(handler)
		t.eq(handler._first_person_spectating_mode, false,
			"re-enabling must restore normal init behaviour")
	end)

	t.it("the disabled-path apply still refuses a handler with no such field", function()
		local mod = engine.install({})
		CameraMode.install(mod, settings(true))
		mod:set_enabled(false)
		local hook = mod:find_hook("init")

		local handler = engine.make_handler()
		handler._first_person_spectating_mode = nil

		hook.fn(handler)
		t.eq(handler._first_person_spectating_mode, nil,
			"a missing field must not be invented while disabled either")
	end)

	t.it("live_handler uses local_player_safe, not local_player", function()
		local handler = engine.make_handler()

		engine.with_globals({
			Managers = { player = {
				-- Deliberately no local_player field: the unsafe variant must never be reached.
				local_player_safe = function(_) return { camera_handler = handler } end,
			} },
		}, function()
			local ok, result = pcall(CameraMode.live_handler)
			t.truthy(ok, "must not error: " .. tostring(result))
			t.eq(result, handler, "should return the handler from local_player_safe")
		end)
	end)

	t.it("live_handler tolerates a player manager with no local_player_safe at all", function()
		engine.with_globals({
			Managers = { player = {} },
		}, function()
			local ok, result = pcall(CameraMode.live_handler)
			t.truthy(ok, "must not error: " .. tostring(result))
			t.eq(result, nil, "must fall back to nil, never call the unsafe variant")
		end)
	end)

	t.it("apply_to_live_handler leaves a disabled mod's handler at vanilla, not cleared", function()
		local mod = engine.install({})
		mod:set_enabled(false)

		local handler = engine.make_handler({ _first_person_spectating_mode = true })

		engine.with_globals({
			Managers = { player = { local_player_safe = function(_) return { camera_handler = handler } end } },
		}, function()
			CameraMode.apply_to_live_handler(mod, settings(true))
		end)

		t.eq(handler._first_person_spectating_mode, true,
			"a disabled mod must not clear first_person_spectating_mode on the live handler")
	end)

	t.it("apply_to_live_handler applies the setting once the mod is enabled", function()
		local mod = engine.install({})

		local handler = engine.make_handler({ _first_person_spectating_mode = true })

		engine.with_globals({
			Managers = { player = { local_player_safe = function(_) return { camera_handler = handler } end } },
		}, function()
			CameraMode.apply_to_live_handler(mod, settings(true))
		end)

		t.eq(handler._first_person_spectating_mode, false,
			"an enabled mod must apply the live setting")
	end)

	t.suite("Camera mode: cooperating with Perspectives")

	local function fake_perspectives(log)
		return {
			autoswitch = function(reason, to_3p, stack)
				log[#log + 1] = "push:" .. tostring(reason) .. ":" .. tostring(to_3p) .. ":" .. tostring(stack)
			end,
			clear_reason = function(reason) log[#log + 1] = "clear:" .. tostring(reason) end,
		}
	end

	local function with_perspectives(mod_table, body)
		local saved = _G.get_mod
		_G.get_mod = function(name)
			if name == "Perspectives" then return mod_table end
			return saved and saved(name) or nil
		end
		CameraMode._reset_cooperation()
		local ok, err = pcall(body)
		_G.get_mod = saved
		CameraMode._reset_cooperation()
		if not ok then error(err, 0) end
	end

	t.it("pushes a reason onto the stack when spectating starts", function()
		local log = {}
		with_perspectives(fake_perspectives(log), function()
			CameraMode.cooperate(true)
		end)
		t.eq(log[1], "push:" .. CameraMode.PERSPECTIVES_REASON .. ":true:true",
			"it must push onto the stack, which is what makes Perspectives request third person")
	end)

	t.it("clears the reason when spectating ends", function()
		local log = {}
		with_perspectives(fake_perspectives(log), function()
			CameraMode.cooperate(true)
			CameraMode.cooperate(false)
		end)
		t.eq(log[2], "clear:" .. CameraMode.PERSPECTIVES_REASON,
			"leaving it pushed would strand Perspectives in third person")
	end)

	t.it("does not touch the stack every frame while nothing changes", function()
		local log = {}
		with_perspectives(fake_perspectives(log), function()
			for _ = 1, 50 do CameraMode.cooperate(true) end
		end)
		t.eq(#log, 1, "the stack must only be touched on a transition")
	end)

	t.it("does not query the third person state while we are not spectating", function()
		local queries = 0
		local p = fake_perspectives({})
		p.is_requesting_third_person = function() queries = queries + 1 return false end

		CameraMode._reset_cooperation()
		with_perspectives(p, function()
			for _ = 1, 50 do CameraMode.cooperate(false) end
		end)

		t.eq(queries, 0, "cooperation_action only reads is_active on the wants-third-person "
			.. "branch, so querying it while alive is a per-frame pcall for a discarded value")
	end)

	t.it("still queries it while spectating, which is where the self-heal depends on it", function()
		local queries = 0
		local p = fake_perspectives({})
		p.is_requesting_third_person = function() queries = queries + 1 return true end

		CameraMode._reset_cooperation()
		with_perspectives(p, function()
			CameraMode.cooperate(true)
			CameraMode.cooperate(true)
		end)

		t.truthy(queries > 0, "without the query a wiped switch_stack would never be re-asserted")
	end)

	t.it("reports failure when Perspectives is absent so our own hook still runs", function()
		with_perspectives(nil, function()
			t.falsy(CameraMode.cooperate(true), "without Perspectives there is nothing to cooperate with")
		end)
	end)

	t.it("an incomplete Perspectives api is refused rather than half driven", function()
		with_perspectives({ autoswitch = function() end }, function()
			t.falsy(CameraMode.cooperate(true), "a mod missing clear_reason could never be released")
		end)
	end)

	t.it("the transition decision is by state change, not by value", function()
		t.eq(CameraMode.cooperation_action(nil, true), "push", "first request pushes")
		t.eq(CameraMode.cooperation_action(true, true), "none", "holding is a no-op")
		t.eq(CameraMode.cooperation_action(true, false), "clear", "stopping clears")
		t.eq(CameraMode.cooperation_action(false, false), "none", "staying stopped is a no-op")
	end)

	t.it("re-asserts when Perspectives drops the reason while we still want it", function()
		t.eq(CameraMode.cooperation_action(true, true, false), "push",
			"spectating yourself makes Perspectives clear the reason; an edge-triggered push "
			.. "never recovers and the camera stays locked inside the body")
	end)

	t.it("stays quiet while Perspectives is honouring the request", function()
		t.eq(CameraMode.cooperation_action(true, true, true), "none",
			"re-pushing every frame would fight Perspectives' own stack")
	end)

	t.it("does not re-push when the request state cannot be read", function()
		t.eq(CameraMode.cooperation_action(true, true, nil), "none",
			"an unknown state must not be treated as a drop")
	end)

	t.it("still pushes the first time even when reported inactive", function()
		t.eq(CameraMode.cooperation_action(nil, true, false), "push",
			"the opening request must survive the new guard")
	end)

	t.it("an inactive report never resurrects a released camera", function()
		t.eq(CameraMode.cooperation_action(false, false, false), "none",
			"not wanting third person outranks any activity reading")
		t.eq(CameraMode.cooperation_action(true, false, true), "clear",
			"leaving spectate clears even while Perspectives still reports active")
	end)
end
