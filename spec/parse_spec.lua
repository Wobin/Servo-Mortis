local t = require("spec.runner")

local SOURCES = {
	"/Servo Mortis.mod",
	"/scripts/mods/Servo Mortis/Servo Mortis.lua",
	"/scripts/mods/Servo Mortis/Servo Mortis_data.lua",
	"/scripts/mods/Servo Mortis/Servo Mortis_localization.lua",
	"/scripts/mods/Servo Mortis/modules/camera_mode.lua",
	"/scripts/mods/Servo Mortis/modules/follow_targets.lua",
	"/scripts/mods/Servo Mortis/modules/settings.lua",
	"/scripts/mods/Servo Mortis/modules/spectate_controls.lua",
	"/scripts/mods/Servo Mortis/modules/watcher/nameplate.lua",
	"/scripts/mods/Servo Mortis/modules/watcher/placement.lua",
	"/scripts/mods/Servo Mortis/modules/watcher/presence.lua",
	"/scripts/mods/Servo Mortis/modules/watcher/runtime.lua",
	"/scripts/mods/Servo Mortis/modules/watcher/skulls.lua",
	"/scripts/mods/Servo Mortis/modules/watcher/test_mode.lua",
	"/scripts/mods/Servo Mortis/modules/watcher/watching.lua",
}

local function read(path)
	local f = io.open("." .. path, "r")
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	return text
end

return function()
	t.suite("Parse and version")

	for _, path in ipairs(SOURCES) do
		t.it(path .. " parses", function()
			local text = read(path)
			t.truthy(text, "missing file: " .. path)
			local chunk, err = loadstring(text, "@" .. path)
			t.truthy(chunk, "parse error in " .. path .. ": " .. tostring(err))
		end)
	end

	t.it("no em-dash in any source", function()
		for _, path in ipairs(SOURCES) do
			local text = read(path) or ""
			t.falsy(text:find("\226\128\148", 1, true), "em-dash found in " .. path)
		end
	end)

	t.it(".mod version matches mod.version", function()
		local manifest = read("/Servo Mortis.mod") or ""
		local main = read("/scripts/mods/Servo Mortis/Servo Mortis.lua") or ""
		local manifest_version = manifest:match('version%s*=%s*"([%d%.]+)"')
		local mod_version = main:match('mod%.version%s*=%s*"([%d%.]+)"')
		t.truthy(manifest_version, "no version in the .mod manifest")
		t.eq(mod_version, manifest_version, "mod.version must match the .mod version")
	end)

	t.it("header version matches mod.version", function()
		local main = read("/scripts/mods/Servo Mortis/Servo Mortis.lua") or ""
		local header_version = main:match("Version:%s*([%d%.]+)")
		local mod_version = main:match('mod%.version%s*=%s*"([%d%.]+)"')
		t.eq(header_version, mod_version, "header Version must match mod.version")
	end)

	t.it("info.json parses and its version matches the mod", function()
		local f = assert(io.open("./info.json", "r"))
		local text = f:read("*a")
		f:close()

		t.truthy(text:find('"name"%s*:%s*"Servo Mortis"'), "info.json must name the mod")
		t.truthy(text:find('"author"%s*:%s*"Wobin"'), "info.json must name the author")
		t.truthy(text:find('"order"'), "info.json must carry the load order block")
		t.truthy(text:find('"nexusId"%s*:%s*"1153"'),
			"the Nexus mod id must stay on the mod page it publishes to")

		local json_version = text:match('"version"%s*:%s*"([%d%.]+)"')
		t.truthy(json_version, "info.json must declare a version")

		local g = assert(io.open("./Servo Mortis.mod", "r"))
		local manifest = g:read("*a")
		g:close()
		local mod_version = manifest:match('version%s*=%s*"([%d%.]+)"')

		local h = assert(io.open("./scripts/mods/Servo Mortis/Servo Mortis.lua", "r"))
		local main = h:read("*a")
		h:close()
		local lua_version = main:match('mod%.version%s*=%s*"([%d%.]+)"')
		local header_version = main:match('Version:%s*([%d%.]+)')

		t.eq(json_version, mod_version, "info.json and the .mod must agree on the version")
		t.eq(json_version, lua_version, "info.json and mod.version must agree")
		t.eq(json_version, header_version, "info.json and the Lua header must agree")
	end)
end
