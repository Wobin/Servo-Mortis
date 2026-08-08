local math_random = math.random
local table_sort = table.sort

local Test = {}

Test.TARGET_ID = "servo_mortis_test_target"
Test.SKULL_COUNT = 2
Test.ROTATE_SECONDS = 10.0

Test.NAMES = {
	"Vorn", "Thorne", "Sable", "Rictus", "Kell", "Vashti",
	"Grimm", "Ardent", "Halberd", "Vex", "Marrow", "Cadia",
}

local watchers = nil
local elapsed = 0

function Test.reset()
	watchers = nil
	elapsed = 0
end

function Test.random_name(random)
	random = random or math_random

	return Test.NAMES[random(#Test.NAMES)] .. "-" .. random(10, 99)
end

function Test.ensure_watchers(random)
	if watchers then
		return watchers
	end

	watchers = {}

	local used = {}
	for i = 1, Test.SKULL_COUNT do
		local name = Test.random_name(random)
		local attempts = 0
		while used[name] and attempts < 32 do
			name = Test.random_name(random)
			attempts = attempts + 1
		end
		used[name] = true
		watchers[i] = { account_id = name }
	end

	return watchers
end

function Test.assign_targets(list, units, random)
	random = random or math_random

	if #units == 0 then
		for i = 1, #list do
			list[i].watching = nil
		end
		return list
	end

	local offset = random(#units)
	for i = 1, #list do
		local index = ((offset + i - 2) % #units) + 1
		list[i].watching = Test.target_id_for(units[index])
	end

	return list
end

function Test.update(dt, units, random)
	local list = Test.ensure_watchers(random)

	elapsed = elapsed + (dt or 0)

	if not list[1].watching or elapsed >= Test.ROTATE_SECONDS then
		elapsed = 0
		Test.assign_targets(list, units or {}, random)
	end

	return list
end

function Test.target_id_for(unit)
	if not unit then
		return nil
	end

	local spawn_manager = Managers and Managers.state and Managers.state.player_unit_spawn
	local owner = spawn_manager and spawn_manager:owner(unit)
	if not owner or not owner.unique_id then
		return nil
	end

	local unique_id = owner:unique_id()
	if not unique_id then
		return nil
	end

	return Test.TARGET_ID .. "#" .. tostring(unique_id)
end

function Test.alive_target_units()
	local extension_manager = Managers and Managers.state and Managers.state.extension
	local side_system = extension_manager and extension_manager:system("side_system")
	local side = side_system and side_system:get_side(1)
	local units = side and side.player_units
	local player_manager = Managers and Managers.player
	local player = player_manager and player_manager:local_player_safe(1)
	if not units or not player or not player.player_unit then
		return {}
	end

	local origin = Unit.world_position(player.player_unit, 1)
	local found = {}
	for i = 1, #units do
		local unit = units[i]
		if ALIVE[unit] then
			found[#found + 1] = {
				unit = unit,
				distance = Vector3.distance(Unit.world_position(unit, 1), origin),
			}
		end
	end

	table_sort(found, function(a, b) return a.distance < b.distance end)

	local ordered = {}
	for i = 1, #found do
		ordered[i] = found[i].unit
	end

	return ordered
end

return Test
