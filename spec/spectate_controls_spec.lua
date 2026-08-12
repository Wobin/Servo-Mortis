local t = require("spec.runner")
local engine = require("spec.mock_engine")

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

	t.suite("Spectate controls: button labels")

	t.it("falls back to the raw name when the locale name is an EMPTY string", function()
		t.eq(Controls.button_label("", "right", "mouse"), "RMB",
			"Darktide returns '' (not nil) from button_locale_name for every mouse button, "
			.. "so a plain `locale or raw` fallback never fires and the glyph renders blank")
	end)

	t.it("labels every mouse button the spectate controls actually use", function()
		t.eq(Controls.button_label("", "left", "mouse"), "LMB", "spectate_next is bound to mouse_left")
		t.eq(Controls.button_label("", "extra_1", "mouse"), "Mouse 4", "crouch can sit on a side button")
	end)

	t.it("keeps a real locale name when the engine supplies one", function()
		t.eq(Controls.button_label("Space", "space", "keyboard"), "[SPACE]",
			"keyboard keys already resolve, and must keep vanilla's bracketed uppercase form")
	end)

	t.it("never returns an empty string, which is what caused the blank caption", function()
		for _, case in ipairs({ {"", "right", "mouse"}, {"", "space", "keyboard"} }) do
			local label = Controls.button_label(case[1], case[2], case[3])
			t.truthy(label and label ~= "", "a resolvable button must never render as nothing")
		end
	end)

	t.it("reports nil when there is genuinely no name, rather than inventing one", function()
		t.falsy(Controls.button_label("", "", "mouse"), "no name at all must be nil, not \"\"")
		t.falsy(Controls.button_label(nil, nil, "mouse"), "nor when both are absent")
	end)

	t.suite("Spectate controls: caption cache invalidation")

	t.it("does not cache a failed build, so a later frame can recover", function()
		Controls.forget_hint()
		local real = Controls.build_hint
		local answers = { nil, "recovered" }
		local call = 0
		Controls.build_hint = function()
			call = call + 1
			return answers[call]
		end

		local first = Controls.hint_for(nil, false)
		local second = Controls.hint_for(nil, false)
		Controls.build_hint = real
		Controls.forget_hint()

		t.falsy(first, "the first build genuinely failed")
		t.eq(second, "recovered", "caching the failure would blank the caption for the whole "
			.. "session, since nothing else invalidates it until the mod is toggled")
	end)

	t.it("still caches a successful build", function()
		Controls.forget_hint()
		local real = Controls.build_hint
		local builds = 0
		Controls.build_hint = function() builds = builds + 1 return "text" end

		Controls.hint_for(nil, false)
		Controls.hint_for(nil, false)
		Controls.hint_for(nil, false)
		Controls.build_hint = real
		Controls.forget_hint()

		t.eq(builds, 1, "a working caption must not be rebuilt every frame")
	end)

	t.it("install hooks the input-changed event so a rebind refreshes the glyph", function()
		Controls._reset_install()
		local mod = engine.install({})
		Controls.install(mod)
		t.truthy(mod:find_hook("event_on_input_changed"),
			"rebinding spectate_next mid-session leaves a stale glyph otherwise")
		Controls._reset_install()
	end)

	t.suite("Spectate controls: revealing a suppressed caption")

	t.it("re-enables a pass another mod switched off", function()
		local style = { style_id_1 = { visible = false, font_size = 24 } }
		t.eq(Controls.reveal_passes(style), 1, "one hidden pass must be revealed")
		t.truthy(style.style_id_1.visible, "RingHud sets cycle_text.style_id_1 = false, which is "
			.. "why the caption never rendered")
	end)

	t.it("leaves an untouched pass alone", function()
		local style = { style_id_1 = { font_size = 24 } }
		t.eq(Controls.reveal_passes(style), 0, "a pass with no explicit visible flag is already drawn")
		t.falsy(style.style_id_1.visible, "and must not be given one needlessly")
	end)

	t.it("does not disturb a pass that is already visible", function()
		local style = { style_id_1 = { visible = true } }
		t.eq(Controls.reveal_passes(style), 0, "nothing to do means no reported change")
	end)

	t.it("survives a style table holding non-table values", function()
		local style = { style_id_1 = { visible = false }, font_type = "machine_medium", size = 12 }
		t.eq(Controls.reveal_passes(style), 1, "scalar style entries must be skipped, not indexed")
	end)

	t.it("refuses a missing style rather than throwing in the HUD", function()
		t.eq(Controls.reveal_passes(nil), 0, "a widget without a style must not crash the draw path")
	end)

	t.suite("Spectate controls: icon-font glyphs")

	local MOUSE_RIGHT_GLYPH = string.char(238, 129, 164)

	t.it("passes an icon-font glyph through untouched", function()
		t.eq(Controls.button_label(MOUSE_RIGHT_GLYPH, "right", "mouse"), MOUSE_RIGHT_GLYPH,
			"U+E064 is the mouse-button icon and renders correctly once the pass is visible; "
			.. "the earlier blank caption was RingHud hiding cycle_text, not a bad glyph")
	end)

	t.it("does not uppercase or bracket a non-keyboard glyph", function()
		local label = Controls.button_label(MOUSE_RIGHT_GLYPH, "right", "mouse")
		t.falsy(label:find("[", 1, true), "bracketing is the keyboard convention only")
	end)

	t.it("still falls back to the raw name when there is genuinely no locale name", function()
		t.eq(Controls.button_label("", "right", "mouse"), "RMB",
			"an empty locale name must not render as nothing")
		t.eq(Controls.button_label(nil, "extra_1", "mouse"), "Mouse 4",
			"nor an absent one")
	end)

	t.it("keeps vanilla's bracketed uppercase form for keyboard keys", function()
		t.eq(Controls.button_label("Space", "space", "keyboard"), "[SPACE]",
			"keyboard names are words and keep their vanilla presentation")
	end)

	t.suite("Spectate controls: modifier composition")

	local function labeller(map)
		return function(name) return map[name] end
	end

	t.it("an EMPTY enabler list leaves the key untouched", function()
		t.eq(Controls.compose_keystring("RMB", {}, {}, labeller({})), "RMB",
			"Darktide supplies empty enabler/disabler tables on ordinary binds, and bailing "
			.. "on their mere presence is what blanked the caption")
	end)

	t.it("a nil enabler list is treated the same as an empty one", function()
		t.eq(Controls.compose_keystring("RMB", nil, nil, labeller({})), "RMB",
			"absent modifiers must not discard the key")
	end)

	t.it("real modifiers compose in vanilla's order and separators", function()
		local map = { keyboard_leftshift = "[SHIFT]", keyboard_leftalt = "[ALT]" }
		t.eq(Controls.compose_keystring("RMB", { "keyboard_leftshift" }, { "keyboard_leftalt" },
			labeller(map)), "[SHIFT]+RMB-[ALT]",
			"enablers prefix with + and disablers suffix with -, as input_utils does")
	end)

	t.it("an unresolvable modifier fails the whole binding rather than lying about it", function()
		t.falsy(Controls.compose_keystring("RMB", { "keyboard_unknown" }, nil, labeller({})),
			"showing a bare RMB when the real bind is SHIFT+RMB would misinform the player")
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

	t.it("a caption that cannot be built gives up after a bounded number of retries", function()
		Controls.forget_hint()
		local attempts = 0
		local real = Controls.build_hint
		Controls.build_hint = function() attempts = attempts + 1 return nil end

		for _ = 1, 50 do
			Controls.hint_for(nil, false)
		end

		Controls.build_hint = real
		Controls.forget_hint()

		t.eq(attempts, Controls.MAX_HINT_ATTEMPTS,
			"a permanent failure must not cost a full rebuild every frame, but a few retries "
			.. "are needed so a transient one on the first spectator frame can recover")
	end)

	t.suite("Spectate controls: finding the spectator element")

	local function with_ui(ui, body)
		local saved = _G.Managers.ui
		_G.Managers.ui = ui
		local ok, err = pcall(body)
		_G.Managers.ui = saved
		if not ok then error(err, 0) end
	end

	local function fake_hud(has_element)
		return {
			element = function(_, name)
				if has_element and name == "HudElementSpectatorText" then
					return { name = name }
				end
				return nil
			end,
		}
	end

	t.it("finds the element on the spectator hud, which is a separate hud", function()
		with_ui({ _spectator_hud = fake_hud(true), _hud = fake_hud(false) }, function()
			t.truthy(Controls.spectator_element(),
				"the spectator text lives on _spectator_hud, not the main _hud")
		end)
	end)

	t.it("still finds it on the main hud when there is no spectator hud", function()
		with_ui({ _hud = fake_hud(true) }, function()
			t.truthy(Controls.spectator_element(), "the main hud must remain a fallback")
		end)
	end)

	t.it("returns nothing when neither hud has it", function()
		with_ui({ _spectator_hud = fake_hud(false), _hud = fake_hud(false) }, function()
			t.falsy(Controls.spectator_element(), "no element means no element")
		end)
	end)

	t.it("tolerates the ui manager being absent entirely", function()
		with_ui(nil, function()
			local ok, result = pcall(Controls.spectator_element)
			t.truthy(ok, "outside a mission this must not throw")
			t.falsy(result, "and must find nothing")
		end)
	end)
end
