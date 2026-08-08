local CLASS = CLASS

local CameraMode = {}

local OBSERVER = "observer"
local THIRD_PERSON = "third_person"
local FIRST_PERSON = "first_person"

function CameraMode.desired_flag(Settings)
	local values = Settings and Settings.values or {}
	return values.third_person_spectate == false
end

function CameraMode.apply(handler, Settings)
	if not handler then return false end
	if handler._first_person_spectating_mode == nil then
		return false
	end
	handler._first_person_spectating_mode = CameraMode.desired_flag(Settings)
	return true
end

function CameraMode.live_handler()
	local player_manager = Managers and Managers.player
	if not player_manager or not player_manager.local_player_safe then
		return nil
	end
	local player = player_manager:local_player_safe(1)
	return player and player.camera_handler or nil
end

function CameraMode.apply_to_live_handler(mod, Settings)
	local active_settings = Settings
	if not mod or not mod:is_enabled() then
		active_settings = { values = { third_person_spectate = false } }
	end
	CameraMode.apply(CameraMode.live_handler(), active_settings)
end

local function should_use_third_person(mod, Settings, self)
	if not mod or not mod:is_enabled() then return false end

	local values = Settings and Settings.values or {}
	if not values.third_person_spectate then return false end

	if not self or not self._unit then return false end

	local handler = CameraMode.live_handler()
	if not handler or handler._mode ~= OBSERVER then return false end

	return handler._camera_follow_unit == self._unit
end

local warned_missing_field = false

function CameraMode.install(mod, Settings)
	if not CLASS or not CLASS.CameraHandler then
		mod:error("Servo Mortis: CLASS.CameraHandler not found, third person spectating is disabled")
	else
		mod:hook_safe(CLASS.CameraHandler, "init", function(self)
			local active_settings = Settings
			if not mod:is_enabled() then
				active_settings = { values = { third_person_spectate = false } }
			end

			if CameraMode.apply(self, active_settings) then
				return
			end
			if self and not warned_missing_field then
				warned_missing_field = true
				mod:error("Servo Mortis: CameraHandler._first_person_spectating_mode is missing. "
					.. "The game has changed and third person spectating is disabled.")
			end
		end)

		mod:hook(CLASS.CameraHandler, "is_observing", function(func, self)
			if not self then return func(self) end
			return self._mode == OBSERVER
		end)
	end

	CameraMode.install_camera_tree(mod, Settings)
end

function CameraMode.install_camera_tree(mod, Settings)
	if not CLASS or not CLASS.PlayerHuskCameraExtension then
		mod:error("Servo Mortis: CLASS.PlayerHuskCameraExtension not found, third person spectating is disabled")
		return
	end

	mod:hook(CLASS.PlayerHuskCameraExtension, "camera_tree_node", function(func, self)
		local tree, node, object = func(self)

		if tree == FIRST_PERSON and should_use_third_person(mod, Settings, self) then
			tree = THIRD_PERSON
			node = THIRD_PERSON
		end

		return tree, node, object
	end)
end

return CameraMode
