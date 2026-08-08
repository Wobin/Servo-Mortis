local Skulls = {}

local BASE = "content/characters/player/companion_servo_skull/attachments_base/"

Skulls.PATHS = {
	BASE .. "cryptic_scanning_01/servo_skull_scanning",
	BASE .. "cryptic_scanning_03/servo_skull_scanning_03",
}

Skulls.RADIUS_FRACTION = 0.6
Skulls.FALLBACK_CAMERA_DISTANCE = 4.8

local handles = {}
local warned = false

function Skulls._reset_warning()
	warned = false
end

function Skulls.path_for_slot(slot)
	local index = ((slot - 1) % #Skulls.PATHS) + 1
	return Skulls.PATHS[index]
end

function Skulls.radius_from_distance(distance)
	if type(distance) ~= "number" or distance <= 0 then
		return Skulls.FALLBACK_CAMERA_DISTANCE * Skulls.RADIUS_FRACTION
	end
	return distance * Skulls.RADIUS_FRACTION
end

function Skulls.measure_camera_distance()
	local player_manager = Managers and Managers.player
	if not player_manager or not player_manager.local_player_safe then
		return nil
	end

	local player = player_manager:local_player_safe(1)
	if not player then
		return nil
	end

	local camera_handler = player.camera_handler
	if not camera_handler then
		return nil
	end

	local followed_unit = camera_handler._camera_follow_unit
	if not followed_unit then
		return nil
	end

	if not ALIVE[followed_unit] then
		return nil
	end

	local camera_manager = Managers.state and Managers.state.camera
	if not camera_manager then
		return nil
	end

	local ok, distance = pcall(function()
		local camera = camera_manager:camera(player.viewport_name)
		if not camera then
			return nil
		end
		local camera_position = Camera.world_position(camera)
		local unit_position = Unit.world_position(followed_unit, 1)
		return Vector3.distance(camera_position, unit_position)
	end)

	if not ok or not distance then
		return nil
	end

	return distance
end

function Skulls.orbit_radius()
	return Skulls.radius_from_distance(Skulls.measure_camera_distance())
end

function Skulls.ensure_package(mod)
	local package_manager = Managers and Managers.package
	if not package_manager or not package_manager.load or not package_manager.has_loaded
		or not package_manager.is_loading then
		return false
	end

	local all_loaded = true
	local problem = false

	for _, path in ipairs(Skulls.PATHS) do
		if not handles[path] and not package_manager:is_loading(path) then
			handles[path] = package_manager:load(path, "Servo Mortis")
		end

		if not package_manager:has_loaded(path) then
			if package_manager:is_loading(path) then
				all_loaded = false
			else
				all_loaded = false
				problem = true
			end
		end
	end

	if problem and not warned then
		warned = true
		mod:error("Servo Mortis: watcher skull package did not load, watcher skulls are disabled")
	end

	return all_loaded
end

function Skulls.release(mod)
	local package_manager = Managers and Managers.package
	for path, handle in pairs(handles) do
		if handle and package_manager and package_manager.release then
			package_manager:release(handle)
		end
		handles[path] = nil
	end
end

return Skulls
