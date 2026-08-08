local Settings = {}

Settings.IDS = {
	"third_person_spectate",
	"spectate_bots",
	"skip_downed_targets",
	"watcher_skulls",
	"nameplate_distance",
	"watcher_test_mode",
}

local id_lookup = {}
for _, id in ipairs(Settings.IDS) do
	id_lookup[id] = true
end

Settings.values = {
	third_person_spectate = true,
	spectate_bots = true,
	skip_downed_targets = true,
	watcher_skulls = true,
	nameplate_distance = 10,
	watcher_test_mode = false,
}

function Settings.refresh(mod)
	if not mod then return end
	for _, id in ipairs(Settings.IDS) do
		local value = mod:get(id)
		if value ~= nil then
			Settings.values[id] = value
		end
	end
end

function Settings.on_changed(mod, id)
	if not mod or not id_lookup[id] then
		return false
	end
	local value = mod:get(id)
	if value ~= nil then
		Settings.values[id] = value
	end
	return true
end

return Settings
