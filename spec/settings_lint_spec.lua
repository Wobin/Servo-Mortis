local engine = require("spec.mock_engine")
local t = require("spec.runner")

local function strip_comments(text)
	local newline = "\n"
	local pattern = "%-%-[^" .. newline .. "]*"
	return text:gsub(pattern, "")
end

local function declared_ids()
	local f = assert(io.open("./scripts/mods/Servo Mortis/Servo Mortis_data.lua", "r"))
	local text = f:read("*a")
	f:close()
	local cleaned = strip_comments(text)
	local ids = {}
	for id in cleaned:gmatch('setting_id%s*=%s*"([%w_]+)"') do
		ids[id] = true
	end
	return ids
end

local function localized_ids()
	local f = assert(io.open("./scripts/mods/Servo Mortis/Servo Mortis_localization.lua", "r"))
	local text = f:read("*a")
	f:close()
	local cleaned = strip_comments(text)
	local keys = {}
	for key in cleaned:gmatch("([%w_]+)%s*=%s*{") do
		keys[key] = true
	end
	return keys
end

return function()
	t.suite("Settings lint")

	local Settings = dofile("./scripts/mods/Servo Mortis/modules/settings.lua")

	t.it("every id the module reads is declared in _data.lua", function()
		local declared = declared_ids()
		for _, id in ipairs(Settings.IDS) do
			t.truthy(declared[id], "undeclared setting id: " .. id)
		end
	end)

	t.it("every declared id has a localization entry", function()
		local declared = declared_ids()
		local localized = localized_ids()
		for id in pairs(declared) do
			t.truthy(localized[id], "setting id without a loc key: " .. id)
		end
	end)

	t.it("comment stripping ignores settings in commented lines", function()
		local fake_content = 'setting_id = "real"\n-- setting_id = "fake"\n'
		local cleaned = strip_comments(fake_content)
		local ids = {}
		for id in cleaned:gmatch('setting_id%s*=%s*"([%w_]+)"') do
			ids[id] = true
		end
		t.truthy(ids["real"], "should match real setting_id")
		t.falsy(ids["fake"], "should not match commented setting_id")
	end)

	t.it("refresh reads every id from the mod", function()
		local mod = engine.install({
			third_person_spectate = true,
			spectate_bots = false,
			skip_downed_targets = true,
		})
		Settings.refresh(mod)
		t.eq(Settings.values.third_person_spectate, true, "third_person_spectate")
		t.eq(Settings.values.spectate_bots, false, "spectate_bots")
		t.eq(Settings.values.skip_downed_targets, true, "skip_downed_targets")
		for _, id in ipairs(Settings.IDS) do
			t.truthy(mod._gets[id], "refresh never read " .. id)
		end
	end)

	t.it("on_changed updates one value and claims the id", function()
		local mod = engine.install({ spectate_bots = true })
		Settings.refresh(mod)
		mod._settings.spectate_bots = false
		t.eq(Settings.on_changed(mod, "spectate_bots"), true, "should claim its own id")
		t.eq(Settings.values.spectate_bots, false, "value should follow the change")
	end)

	t.it("on_changed ignores a foreign id", function()
		local mod = engine.install({})
		t.eq(Settings.on_changed(mod, "some_other_mod_setting"), false, "should not claim a foreign id")
	end)

	t.it("every keybind function_name exists on the mod", function()
		local f = assert(io.open("./scripts/mods/Servo Mortis/Servo Mortis_data.lua", "r"))
		local data = f:read("*a")
		f:close()

		local g = assert(io.open("./scripts/mods/Servo Mortis/Servo Mortis.lua", "r"))
		local main = g:read("*a")
		g:close()

		for name in data:gmatch('function_name%s*=%s*"([%w_]+)"') do
			t.truthy(main:find("mod%." .. name .. "%s*="),
				"keybind target not defined on the mod: " .. name)
		end
	end)

	t.it("spectate previous is driven by input, not by a keybind setting", function()
		local f = assert(io.open("./scripts/mods/Servo Mortis/Servo Mortis_data.lua", "r"))
		local data = f:read("*a")
		f:close()

		local g = assert(io.open("./scripts/mods/Servo Mortis/Servo Mortis.lua", "r"))
		local main = g:read("*a")
		g:close()

		t.falsy(data:find("spectate_previous", 1, true),
			"the keybind setting must be gone from the options")
		t.truthy(main:find("mod%.spectate_previous%s*="),
			"the action itself must still be defined")
		t.truthy(main:find("SpectateControls%.previous_pressed"),
			"the action must be driven by the input check, or nothing can trigger it")
	end)

	t.it("the test mode label matches what test mode actually does", function()
		local f = assert(io.open("./scripts/mods/Servo Mortis/Servo Mortis_localization.lua", "r"))
		local loc = f:read("*a")
		f:close()

		local Test = dofile("./scripts/mods/Servo Mortis/modules/watcher/test_mode.lua")
		local label = loc:match('watcher_test_mode%s*=%s*{%s*en%s*=%s*"([^"]+)"')

		t.truthy(label, "the test mode setting must have a label")
		t.truthy(label:lower():find("two", 1, true),
			"the label says how many skulls, so it must agree with SKULL_COUNT")
		t.eq(Test.SKULL_COUNT, 2, "and SKULL_COUNT must still be two")
		t.truthy(label:find(tostring(math.floor(Test.ROTATE_SECONDS)), 1, true),
			"the label quotes the rotation interval, so it must agree with ROTATE_SECONDS")
	end)
end
