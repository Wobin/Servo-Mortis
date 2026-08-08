local t = require("spec.runner")

local Controls = dofile("./scripts/mods/Servo Mortis/modules/spectate_controls.lua")

return function()
t.suite("Spectate controls: previous input")

	local function fake_device(pressed_index, indices)
		return {
			button_index = function(name) return indices[name] end,
			pressed = function(index) return index == pressed_index end,
		}
	end

	local MOUSE = { right = 1, left = 0 }
	local PAD = { b = 13, a = 0 }

	t.it("right mouse steps to the previous target", function()
		local mouse = fake_device(1, MOUSE)
		t.truthy(Controls.previous_pressed(mouse, nil), "right click must trigger previous")
	end)

	t.it("left mouse does not, since that is the game's own next", function()
		local mouse = fake_device(0, MOUSE)
		t.falsy(Controls.previous_pressed(mouse, nil),
			"left click is spectate_next and must not also go backwards")
	end)

	t.it("the controller B button steps to the previous target", function()
		local pad = fake_device(13, PAD)
		t.truthy(Controls.previous_pressed(nil, pad), "B/Circle must trigger previous")
	end)

	t.it("the controller A button does not, since that is the game's own next", function()
		local pad = fake_device(0, PAD)
		t.falsy(Controls.previous_pressed(nil, pad),
			"A/Cross is spectate_next and must not also go backwards")
	end)

	t.it("nothing pressed does nothing", function()
		t.falsy(Controls.previous_pressed(fake_device(99, MOUSE), fake_device(99, PAD)),
			"idle input must not cycle the target every frame")
	end)

	t.it("absent devices are tolerated", function()
		local ok, result = pcall(Controls.previous_pressed, nil, nil)
		t.truthy(ok, "no devices at all must not throw")
		t.falsy(result, "and must not report a press")
	end)

	t.it("an unknown button name is gated rather than pressed", function()
		local device = {
			button_index = function() return nil end,
			pressed = function() return true end,
		}
		t.falsy(Controls.previous_pressed(device, nil),
			"a button the device does not know must never read as pressed")
	end)

	t.it("a device missing its query functions is gated", function()
		t.falsy(Controls.previous_pressed({}, {}),
			"a device without button_index or pressed must not be queried at all")
	end)

	t.suite("Spectate controls: caption")

	t.it("fills both input slots into the caption", function()
		local text = Controls.cycle_hint("Press {next} to cycle player, {prev} to go back",
			"[LMB]", "[RMB]")
		t.eq(text, "Press [LMB] to cycle player, [RMB] to go back",
			"both the forward and the backward input must appear")
	end)

	t.it("mentions the backward input at all", function()
		local text = Controls.cycle_hint("Press {next} to cycle player, {prev} to go back",
			"[LMB]", "[RMB]")
		t.truthy(text:find("[RMB]", 1, true),
			"the caption exists to tell the player about going back")
	end)

	t.it("a missing input renders as nothing rather than the raw token", function()
		local text = Controls.cycle_hint("Press {next} / {prev}", nil, nil)
		t.falsy(text:find("{next}", 1, true), "an unresolved token must not reach the screen")
		t.falsy(text:find("{prev}", 1, true), "nor the backward one")
	end)

	t.it("a non-string template is refused rather than crashing the HUD", function()
		t.falsy(Controls.cycle_hint(nil, "[LMB]", "[RMB]"), "nil template must return nil")
	end)

	t.it("the backward glyph follows the device actually in use", function()
		t.eq(Controls.previous_hint_alias(false), "action_two",
			"on mouse and keyboard action_two is bound to right mouse")
		t.eq(Controls.previous_hint_alias(true), "crouch",
			"on a controller crouch is bound to B and Circle")
	end)

	t.it("the forward glyph uses the game's own spectate action", function()
		t.eq(Controls.HINT_NEXT_ALIAS, "spectate_next",
			"the forward half must stay whatever the game itself binds")
	end)

	t.suite("Spectate controls: caption teardown")

	t.it("disabling flags the caption for the game to rebuild", function()
		local element = { _update_spectator_text = nil }
		t.truthy(Controls.restore_hint(element), "restoring must report success")
		t.eq(element._update_spectator_text, true,
			"the game rebuilds its own caption only when this flag is set")
	end)

	t.it("restoring without a spectator element does not throw", function()
		local ok, result = pcall(Controls.restore_hint, nil)
		t.truthy(ok, "tearing down outside a mission must not throw")
		t.falsy(result, "and must report that nothing was restored")
	end)

	t.it("the mod restores the caption when disabled and when unloaded", function()
		local f = assert(io.open("./scripts/mods/Servo Mortis/Servo Mortis.lua", "r"))
		local main = f:read("*a")
		f:close()

		local disabled = main:match("mod%.on_disabled = function%(%)(.-)end")
		local unloaded = main:match("mod%.on_unload = function%(%)(.-)end")

		t.truthy(disabled and disabled:find("restore_hint", 1, true),
			"disabling must hand the caption back, or it lies about a control that no longer works")
		t.truthy(unloaded and unloaded:find("restore_hint", 1, true),
			"unloading must hand the caption back too")
	end)

	t.suite("Spectate controls: caption caching")

	t.it("the caption is built once and reused while the device is unchanged", function()
		Controls.forget_hint()
		local builds = 0
		local real = Controls.build_hint
		Controls.build_hint = function() builds = builds + 1 return "cached text" end

		for _ = 1, 100 do
			Controls.hint_for(nil, false)
		end

		Controls.build_hint = real
		Controls.forget_hint()

		t.eq(builds, 1, "rebuilding a fixed string every frame is pure waste in a HUD path")
	end)

	t.it("changing input device rebuilds the caption", function()
		Controls.forget_hint()
		local builds = 0
		local real = Controls.build_hint
		Controls.build_hint = function(_, gamepad)
			builds = builds + 1
			return gamepad and "pad" or "mouse"
		end

		local a = Controls.hint_for(nil, false)
		local b = Controls.hint_for(nil, true)
		local c = Controls.hint_for(nil, true)

		Controls.build_hint = real
		Controls.forget_hint()

		t.eq(a, "mouse", "mouse and keyboard gets the mouse caption")
		t.eq(b, "pad", "picking up a controller must switch the glyphs")
		t.eq(c, "pad", "and then stay cached")
		t.eq(builds, 2, "exactly one rebuild per device change")
	end)

	t.it("forgetting the caption forces a rebuild", function()
		Controls.forget_hint()
		local builds = 0
		local real = Controls.build_hint
		Controls.build_hint = function() builds = builds + 1 return "text" end

		Controls.hint_for(nil, false)
		Controls.forget_hint()
		Controls.hint_for(nil, false)

		Controls.build_hint = real
		Controls.forget_hint()

		t.eq(builds, 2, "a reload changes the localized string, so the cache must be dropped")
	end)

	t.it("the mod drops the cached caption on enable, disable and unload", function()
		local f = assert(io.open("./scripts/mods/Servo Mortis/Servo Mortis.lua", "r"))
		local main = f:read("*a")
		f:close()

		for _, hook in ipairs({ "on_enabled", "on_disabled", "on_unload" }) do
			local body = main:match("mod%." .. hook .. " = function%(%)(.-)end")
			t.truthy(body and body:find("forget_hint", 1, true),
				hook .. " must drop the cached caption, or a stale string survives a reload")
		end
	end)

	t.it("a caption that cannot be built is not retried every frame", function()
		Controls.forget_hint()
		local attempts = 0
		local real = Controls.build_hint
		Controls.build_hint = function() attempts = attempts + 1 return nil end

		for _ = 1, 50 do
			Controls.hint_for(nil, false)
		end

		Controls.build_hint = real
		Controls.forget_hint()

		t.eq(attempts, 1, "a permanent failure must not cost a full rebuild every frame")
	end)
end
