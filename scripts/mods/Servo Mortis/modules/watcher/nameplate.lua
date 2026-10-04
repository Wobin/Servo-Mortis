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
local require_hook_installed = false

function Nameplate._reset_warning()
	warned = false
end

function Nameplate._reset_hook_state()
	hook_installed = false
	require_hook_installed = false
end

Nameplate.SPECTATOR_ELEMENT_LIST = "scripts/ui/hud/hud_elements_spectator"

Nameplate.SPECTATOR_MARKER_ELEMENT = {
	class_name = "HudElementWorldMarkers",
	filename = "scripts/ui/hud/elements/world_markers/hud_element_world_markers",
	package = "packages/ui/hud/world_markers/world_markers",
	use_hud_scale = true,
	visibility_groups = {
		"dead",
		"alive",
		"communication_wheel",
	},
}

function Nameplate.ensure_spectator_element(elements)
	if type(elements) ~= "table" then
		return false
	end

	for i = 1, #elements do
		local entry = elements[i]
		if type(entry) == "table" and entry.class_name == "HudElementWorldMarkers" then
			return false
		end
	end

	elements[#elements + 1] = Nameplate.SPECTATOR_MARKER_ELEMENT

	return true
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

	if not require_hook_installed and mod.hook_require then
		require_hook_installed = true
		mod:hook_require(Nameplate.SPECTATOR_ELEMENT_LIST, function(elements)
			Nameplate.ensure_spectator_element(elements)
		end)
	end

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

Nameplate.HUDS = { "_spectator_hud", "_hud" }

function Nameplate.hud_element(class_name)
	local ui = Managers and Managers.ui
	if not ui then
		return nil
	end

	for i = 1, #Nameplate.HUDS do
		local hud = ui[Nameplate.HUDS[i]]
		if hud and hud.element then
			local ok, element = pcall(function() return hud:element(class_name) end)
			if ok and element then
				return element
			end
		end
	end

	return nil
end

function Nameplate.refresh()
	local element = Nameplate.hud_element("HudElementWorldMarkers")
	if not element or not element._marker_templates then
		return false
	end

	element._marker_templates[Nameplate.TEMPLATE_NAME] = Nameplate.build_template(configured_distance())

	return true
end

local function ensure_template()
	local element = Nameplate.hud_element("HudElementWorldMarkers")
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
	local triggered, err = pcall(function()
		Managers.event:trigger("add_world_marker_position", Nameplate.TEMPLATE_NAME, position,
			function(marker_id) id = marker_id end,
			{ name = name, colour = colour })
	end)

	if not triggered then
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
		local element = Nameplate.hud_element("HudElementWorldMarkers")
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
