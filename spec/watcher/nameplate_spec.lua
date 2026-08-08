local engine = require("spec.mock_engine")
local t = require("spec.runner")

local Nameplate = dofile("./scripts/mods/Servo Mortis/modules/watcher/nameplate.lua")

return function()
	t.suite("Watcher nameplate")

	t.it("the template carries the configured distance", function()
		local tmpl = Nameplate.build_template(10)
		t.eq(tmpl.max_distance, 10, "max_distance drives the engine out_of_reach cull")
	end)

	t.it("a different setting produces a different distance", function()
		t.eq(Nameplate.build_template(25).max_distance, 25, "setting must reach the template")
	end)

	t.it("the template does not clamp to screen edges", function()
		t.eq(Nameplate.build_template(10).screen_clamp, false,
			"a watcher name pinned to the screen edge during a fight is intrusive")
	end)

	t.it("the template is named for this mod", function()
		t.eq(Nameplate.build_template(10).name, Nameplate.TEMPLATE_NAME, "stable template name")
	end)

	t.it("the widget builder centres the text on the anchor", function()
		local captured
		local fake_widget = {
			create_definition = function(passes, scenegraph_id, _, size)
				captured = passes
				return { scenegraph_id = scenegraph_id, size = size }
			end,
		}
		local fake_font_settings = {
			hud_body = {
				text_color = { 255, 200, 200, 200 },
				font_type = "machine_medium",
				font_size = 18,
			},
		}
		Nameplate._set_ui(fake_widget, fake_font_settings)

		local tmpl = Nameplate.build_template(10)
		local def = tmpl.create_widget_defintion(tmpl, "scenegraph")

		t.truthy(def ~= nil, "must return a definition")
		local style = captured[1].style
		t.eq(style.offset[1], -tmpl.size[1] / 2, "offset x centres on the anchor")
		t.eq(style.offset[2], -tmpl.size[2] / 2, "offset y centres on the anchor")
		t.eq(style.offset[3], 2, "offset z lifts the text above the marker plane")
		t.eq(style.text_color, fake_font_settings.hud_body.text_color,
			"text_color must come from the injected font settings")
		t.eq(style.font_type, fake_font_settings.hud_body.font_type,
			"font_type must come from the injected font settings")
		t.eq(style.font_size, fake_font_settings.hud_body.font_size,
			"font_size must come from the injected font settings")
	end)

	t.it("install registers an init hook", function()
		local mod = engine.install({})
		Nameplate.install(mod, { values = { nameplate_distance = 10 } })
		t.truthy(mod:find_hook("init"), "must hook HudElementWorldMarkers.init")
	end)

	t.it("install called twice registers the hook only once", function()
		Nameplate._reset_hook_state()
		local mod = engine.install({})
		Nameplate.install(mod, { values = { nameplate_distance = 10 } })
		Nameplate.install(mod, { values = { nameplate_distance = 15 } })
		local init_hook_count = 0
		for _, h in ipairs(mod._hooks) do
			if h.method == "init" then
				init_hook_count = init_hook_count + 1
			end
		end
		t.eq(init_hook_count, 1, "calling install twice must not register the hook twice")
	end)

	t.it("install reports and does not hook when the class is missing", function()
		local mod = engine.install({})
		local saved = _G.CLASS.HudElementWorldMarkers
		_G.CLASS.HudElementWorldMarkers = nil
		Nameplate._reset_warning()
		Nameplate.install(mod, { values = { nameplate_distance = 10 } })
		_G.CLASS.HudElementWorldMarkers = saved
		t.eq(#mod._errors, 1, "must complain loudly rather than silently doing nothing")
	end)

	t.it("move returns false for a nil id", function()
		t.eq(Nameplate.move(nil, { x = 0, y = 0, z = 0 }), false, "no id, nothing to move")
	end)

	t.it("move returns false for a nil position", function()
		t.eq(Nameplate.move("marker-1", nil), false, "no position, nothing to move")
	end)

	t.it("move does not throw when no HUD exists", function()
		local ok = pcall(Nameplate.move, "marker-1", { x = 0, y = 0, z = 0 })
		t.truthy(ok, "move must not throw when the HUD is absent, only no-op")
	end)

	t.it("add returns nil and does not trigger the event when the HUD cannot be reached", function()
		local saved_ui = _G.Managers.ui
		_G.Managers.ui = nil
		local id = Nameplate.add("bob", nil, { x = 0, y = 0, z = 0 })
		_G.Managers.ui = saved_ui
		t.eq(id, nil, "no HUD, no marker, and no event triggered on a nil template")
	end)

	t.it("add installs the missing template on the live element before triggering the event", function()
		local element = { _marker_templates = {} }
		local hud = { element = function(_, name) return name == "HudElementWorldMarkers" and element or nil end }
		local triggered = false

		local saved_ui = _G.Managers.ui
		local saved_event = _G.Managers.event
		_G.Managers.ui = { _hud = hud }
		_G.Managers.event = {
			trigger = function(_, _, _, _, callback, _)
				triggered = true
				callback("marker-1")
			end,
		}

		local id = Nameplate.add("bob", nil, { x = 0, y = 0, z = 0 })

		_G.Managers.ui = saved_ui
		_G.Managers.event = saved_event

		t.truthy(element._marker_templates[Nameplate.TEMPLATE_NAME],
			"the template must be installed on the live element before the event fires")
		t.truthy(triggered, "the event must fire once the template is in place")
		t.eq(id, "marker-1", "the id returned by the event callback")
	end)

	t.it("add does not clobber an already-installed template", function()
		local sentinel = { name = "sentinel" }
		local element = { _marker_templates = { [Nameplate.TEMPLATE_NAME] = sentinel } }
		local hud = { element = function() return element end }

		local saved_ui = _G.Managers.ui
		local saved_event = _G.Managers.event
		_G.Managers.ui = { _hud = hud }
		_G.Managers.event = {
			trigger = function(_, _, _, _, callback, _)
				callback("marker-1")
			end,
		}

		Nameplate.add("bob", nil, { x = 0, y = 0, z = 0 })

		_G.Managers.ui = saved_ui
		_G.Managers.event = saved_event

		t.eq(element._marker_templates[Nameplate.TEMPLATE_NAME], sentinel,
			"an existing template must not be replaced")
	end)
end
