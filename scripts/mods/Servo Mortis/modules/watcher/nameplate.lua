local CLASS = CLASS

local Nameplate = {}

local installed_mod = nil
local reported = {}

function Nameplate.report(message)
	if not message or reported[message] then
		return false
	end

	reported[message] = true

	if installed_mod and installed_mod.error then
		installed_mod:error("Servo Mortis: " .. message)
	end

	return true
end

Nameplate.TEMPLATE_NAME = "servo_mortis_watcher"

local warned = false
local hook_installed = false

function Nameplate._reset_warning()
	warned = false
end

function Nameplate._reset_hook_state()
	hook_installed = false
end

local ui_widget = nil
local ui_font_settings = nil

local function resolve_ui()
	if not ui_widget then
		ui_widget = require("scripts/managers/ui/ui_widget")
	end
	if not ui_font_settings then
		ui_font_settings = require("scripts/managers/ui/ui_font_settings")
	end
	return ui_widget, ui_font_settings
end

function Nameplate._set_ui(widget_module, font_settings_module)
	ui_widget = widget_module
	ui_font_settings = font_settings_module
end

function Nameplate.build_template(distance)
	local template = {}

	template.name = Nameplate.TEMPLATE_NAME
	template.size = { 400, 20 }
	template.position_offset = { 0, 0, 0 }
	template.check_line_of_sight = false
	template.max_distance = distance
	template.screen_clamp = false
	template.scale_settings = {
		distance_max = distance,
		distance_min = 2,
		scale_from = 0.8,
		scale_to = 1,
	}

	template.create_widget_defintion = function(tmpl, scenegraph_id)
		local UIWidget, UIFontSettings = resolve_ui()
		local font = UIFontSettings.hud_body
		local w, h = tmpl.size[1], tmpl.size[2]

		local passes = {
			{
				pass_type = "text",
				style_id = "header_text",
				value = "watcher",
				value_id = "header_text",
				style = {
					horizontal_alignment = "center",
					text_horizontal_alignment = "center",
					text_vertical_alignment = "center",
					vertical_alignment = "center",
					offset = { -w / 2, -h / 2, 2 },
					text_color = font.text_color,
					font_type = font.font_type,
					font_size = font.font_size,
				},
			},
		}

		return UIWidget.create_definition(passes, scenegraph_id, nil, tmpl.size)
	end

	template.on_enter = function(widget, marker)
		local data = marker and marker.data
		local content = widget.content
		content.header_text = (data and data.name) or "watcher"
		if data and data.colour then
			widget.style.header_text.text_color = data.colour
		end
	end

	return template
end

local installed_settings = nil

local function configured_distance()
	local values = installed_settings and installed_settings.values or {}
	return values.nameplate_distance or 10
end

function Nameplate.install(mod, Settings)
	installed_settings = Settings
	installed_mod = mod

	if not CLASS or not CLASS.HudElementWorldMarkers then
		if not warned then
			warned = true
			mod:error("Servo Mortis: CLASS.HudElementWorldMarkers not found, watcher names are disabled")
		end
		return
	end

	if not hook_installed then
		hook_installed = true
		mod:hook_safe(CLASS.HudElementWorldMarkers, "init", function(self)
			local distance = configured_distance()
			if self._marker_templates then
				self._marker_templates[Nameplate.TEMPLATE_NAME] = Nameplate.build_template(distance)
			end
		end)
	end
end

local function ensure_template()
	local hud = Managers.ui and Managers.ui._hud
	local element = hud and hud:element("HudElementWorldMarkers")
	if not element then
		return false
	end
	if not element._marker_templates then
		return false
	end
	if not element._marker_templates[Nameplate.TEMPLATE_NAME] then
		element._marker_templates[Nameplate.TEMPLATE_NAME] = Nameplate.build_template(configured_distance())
	end
	return true
end

function Nameplate.add(name, colour, position)
	local ok, ready = pcall(ensure_template)
	if not ok or not ready then
		return nil
	end

	local id = nil
	local ok, err = pcall(function()
		Managers.event:trigger("add_world_marker_position", Nameplate.TEMPLATE_NAME, position,
			function(marker_id) id = marker_id end,
			{ name = name, colour = colour })
	end)

	if not ok then
		Nameplate.report("could not create a watcher name marker: " .. tostring(err))
	end

	return id
end

function Nameplate.move(id, position)
	if not id or not position then
		return false
	end
	local found = false
	local ok = pcall(function()
		local hud = Managers.ui and Managers.ui._hud
		local element = hud and hud:element("HudElementWorldMarkers")
		local marker = element and element._markers_by_id and element._markers_by_id[id]
		if marker and marker.world_position then
			Vector3Box.store(marker.world_position, position)
			found = true
		end
	end)
	return ok and found
end

function Nameplate.remove(id)
	if not id then
		return
	end
	local ok, err = pcall(function()
		Managers.event:trigger("remove_world_marker", id)
	end)

	if not ok then
		Nameplate.report("could not remove a watcher name marker: " .. tostring(err))
	end

	return ok
end

return Nameplate
