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
	local hud = Managers and Managers.ui and Managers.ui._hud
	if not hud or not hud.element then
		return nil
	end

	return hud:element("HudElementSpectatorText")
end

function Controls.restore_hint(element)
	element = element or Controls.spectator_element()
	if not element then
		return false
	end

	element._update_spectator_text = true

	return true
end

function Controls.forget_hint()
	hint_text = nil
	hint_device = nil
	hint_built = false
end

function Controls.hint_for(mod, gamepad)
	if hint_built and hint_device == gamepad then
		return hint_text
	end

	hint_text = Controls.build_hint(mod, gamepad)
	hint_device = gamepad
	hint_built = true

	return hint_text
end

function Controls.build_hint(mod, gamepad)
	if not InputUtils or not InputUtils.input_text_for_current_input_device then
		return nil
	end

	if gamepad == nil then
		gamepad = Managers and Managers.input and Managers.input:device_in_use("gamepad")
	end

	local next_ok, next_text = pcall(InputUtils.input_text_for_current_input_device,
		"Ingame", Controls.HINT_NEXT_ALIAS, true)
	local previous_ok, previous_text = pcall(InputUtils.input_text_for_current_input_device,
		"Ingame", Controls.previous_hint_alias(gamepad), true)

	if not next_ok or not previous_ok then
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

function Controls.install(mod)
	if hint_installed or not CLASS or not CLASS.HudElementSpectatorText then
		return false
	end

	local ok = pcall(function()
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
		end)
	end)

	hint_installed = ok

	return ok
end

return Controls
