local CLASS = CLASS

local ok_input, InputUtils = pcall(require, "scripts/managers/input/input_utils")
if not ok_input then
	InputUtils = nil
end

local Controls = {}

Controls.PREVIOUS_MOUSE_BUTTON = "right"
Controls.PREVIOUS_PAD_BUTTON = "b"

Controls.HINT_NEXT_ALIAS = "spectate_next"
Controls.HINT_PREVIOUS_PAD_ALIAS = "crouch"
Controls.HINT_PREVIOUS_MOUSE_ALIAS = "action_two"

local hint_installed = false
local hint_text = nil
local hint_device = nil
local hint_built = false
local hint_attempts = 0
local hint_attempt_device = nil

Controls.MOUSE_BUTTON_LABELS = {
	left = "LMB",
	right = "RMB",
	middle = "MMB",
	extra_1 = "Mouse 4",
	extra_2 = "Mouse 5",
}

local function usable(name)
	return type(name) == "string" and name ~= ""
end

function Controls.button_label(locale_name, raw_name, category)
	if usable(locale_name) then
		if category == "keyboard" then
			return "[" .. locale_name:upper() .. "]"
		end

		return locale_name
	end

	if not usable(raw_name) then
		return nil
	end

	if category == "mouse" then
		return Controls.MOUSE_BUTTON_LABELS[raw_name] or raw_name:upper()
	end

	return "[" .. raw_name:upper() .. "]"
end

local function device_pressed(device, name)
	if not device or not device.pressed or not device.button_index then
		return false
	end

	local index = device.button_index(name)
	if type(index) ~= "number" then
		return false
	end

	return device.pressed(index) == true
end

function Controls.previous_pressed(mouse, pad)
	return device_pressed(mouse, Controls.PREVIOUS_MOUSE_BUTTON)
		or device_pressed(pad, Controls.PREVIOUS_PAD_BUTTON)
end

function Controls.previous_hint_alias(gamepad_in_use)
	if gamepad_in_use then
		return Controls.HINT_PREVIOUS_PAD_ALIAS
	end

	return Controls.HINT_PREVIOUS_MOUSE_ALIAS
end

function Controls.spectator_element()
	local ui = Managers and Managers.ui
	if not ui then
		return nil
	end

	local huds = { ui._spectator_hud, ui._hud }
	for i = 1, #huds do
		local hud = huds[i]
		if hud and hud.element then
			local element = hud:element("HudElementSpectatorText")
			if element then
				return element
			end
		end
	end

	return nil
end

function Controls.restore_hint(element)
	element = element or Controls.spectator_element()
	if not element then
		return false
	end

	element._update_spectator_text = true

	return true
end

Controls.MAX_HINT_ATTEMPTS = 10

function Controls.forget_hint()
	hint_text = nil
	hint_device = nil
	hint_built = false
	hint_attempts = 0
	hint_attempt_device = nil
end

function Controls.hint_for(mod, gamepad)
	if hint_built and hint_device == gamepad then
		return hint_text
	end

	if hint_attempt_device ~= gamepad then
		hint_attempt_device = gamepad
		hint_attempts = 0
	end

	if hint_attempts >= Controls.MAX_HINT_ATTEMPTS then
		return nil
	end

	local text = Controls.build_hint(mod, gamepad)
	if not text then
		hint_attempts = hint_attempts + 1
		return nil
	end

	hint_text = text
	hint_device = gamepad
	hint_built = true
	hint_attempts = 0

	return hint_text
end

local KEYBOARD_DEVICES = { "keyboard", "mouse" }

function Controls.compose_keystring(keystring, enablers, disablers, label_for)
	if type(enablers) == "table" then
		for i = 1, #enablers do
			local label = label_for(enablers[i])
			if not label then
				return nil
			end
			keystring = label .. "+" .. keystring
		end
	end

	if type(disablers) == "table" then
		for i = 1, #disablers do
			local label = label_for(disablers[i])
			if not label then
				return nil
			end
			keystring = keystring .. "-" .. label
		end
	end

	return keystring
end

function Controls.resolve_input(alias_key, gamepad)
	if not InputUtils or gamepad then
		return nil
	end

	local input = Managers and Managers.input
	if not input or not input.alias_object then
		return nil
	end

	local function label_for(global_name)
		local device_type = InputUtils.key_device_type(global_name)
		local device = device_type and InputUtils.get_first_device_of_type(device_type)
		local index = device and InputUtils.button_index(global_name, device, device_type)
		if not index then
			return nil
		end

		return Controls.button_label(device.button_locale_name(index),
			device.button_name(index), device.category())
	end

	local ok, label = pcall(function()
		local alias = input:alias_object("Ingame")
		local key_info = alias and alias:get_keys_for_alias(alias_key, KEYBOARD_DEVICES)
		local main = key_info and key_info.main
		if not main then
			return nil
		end

		local keystring = label_for(main)
		if not keystring then
			return nil
		end

		return Controls.compose_keystring(keystring, key_info.enablers, key_info.disablers,
			label_for)
	end)

	if not ok or not label then
		return nil
	end

	if InputUtils.apply_color_to_input_text and Color and Color.ui_input_color then
		local tinted_ok, tinted = pcall(function()
			return InputUtils.apply_color_to_input_text(label, Color.ui_input_color(255, true))
		end)
		if tinted_ok and tinted then
			return tinted
		end
	end

	return label
end

function Controls.input_text(alias_key, gamepad)
	local resolved = Controls.resolve_input(alias_key, gamepad)
	if resolved then
		return resolved
	end

	if not InputUtils or not InputUtils.input_text_for_current_input_device then
		return nil
	end

	local ok, text = pcall(InputUtils.input_text_for_current_input_device, "Ingame", alias_key, true)
	if not ok then
		return nil
	end

	return text
end

function Controls.build_hint(mod, gamepad)
	if not InputUtils then
		return nil
	end

	if gamepad == nil then
		gamepad = Managers and Managers.input and Managers.input:device_in_use("gamepad")
	end

	local next_text = Controls.input_text(Controls.HINT_NEXT_ALIAS, gamepad)
	local previous_text = Controls.input_text(Controls.previous_hint_alias(gamepad), gamepad)

	if not next_text or not previous_text then
		return nil
	end

	return Controls.cycle_hint(mod:localize("spectate_cycle_hint"), next_text, previous_text)
end

function Controls.cycle_hint(template, next_text, previous_text)
	if type(template) ~= "string" then
		return nil
	end

	local filled = template:gsub("{next}", function() return next_text or "" end)
	filled = filled:gsub("{prev}", function() return previous_text or "" end)

	return filled
end

function Controls.reveal_passes(style)
	if type(style) ~= "table" then
		return 0
	end

	local revealed = 0
	for _, pass in pairs(style) do
		if type(pass) == "table" and pass.visible == false then
			pass.visible = true
			revealed = revealed + 1
		end
	end

	return revealed
end

function Controls._reset_install()
	hint_installed = false
	Controls.forget_hint()
end

function Controls.install(mod)
	if hint_installed or not CLASS or not CLASS.HudElementSpectatorText then
		return false
	end

	local ok = pcall(function()
		mod:hook_safe(CLASS.HudElementSpectatorText, "event_on_input_changed", function()
			Controls.forget_hint()
		end)

		mod:hook_safe(CLASS.HudElementSpectatorText, "update", function(self)
			if not mod:is_enabled() then
				return
			end

			local widget = self._widgets_by_name and self._widgets_by_name.cycle_text
			if not widget or not widget.content then
				return
			end

			local gamepad = Managers and Managers.input and Managers.input:device_in_use("gamepad")
			local text = Controls.hint_for(mod, gamepad)

			if text and widget.content.text ~= text then
				widget.content.text = text
			end

			if Controls.reveal_passes(widget.style) > 0 then
				widget.dirty = true
			end
		end)
	end)

	hint_installed = ok

	return ok
end

return Controls
