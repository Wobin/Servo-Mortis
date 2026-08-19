--[[
	Name: Servo Mortis
	Author: Wobin
	Date: 20/08/2026
]]--

local mod = get_mod("Servo Mortis")
mod.version = mod.get_metadata and mod:get_metadata("version") or "unknown"

local Settings = mod:io_dofile("Servo Mortis/scripts/mods/Servo Mortis/modules/settings")
local FollowTargets = mod:io_dofile("Servo Mortis/scripts/mods/Servo Mortis/modules/follow_targets")
local CameraMode = mod:io_dofile("Servo Mortis/scripts/mods/Servo Mortis/modules/camera_mode")
local SpectateControls = mod:io_dofile("Servo Mortis/scripts/mods/Servo Mortis/modules/spectate_controls")
local Placement = mod:io_dofile("Servo Mortis/scripts/mods/Servo Mortis/modules/watcher/placement")
local Presence = mod:io_dofile("Servo Mortis/scripts/mods/Servo Mortis/modules/watcher/presence")
local Skulls = mod:io_dofile("Servo Mortis/scripts/mods/Servo Mortis/modules/watcher/skulls")
local Nameplate = mod:io_dofile("Servo Mortis/scripts/mods/Servo Mortis/modules/watcher/nameplate")
local Runtime = mod:io_dofile("Servo Mortis/scripts/mods/Servo Mortis/modules/watcher/runtime")
local TestMode = mod:io_dofile("Servo Mortis/scripts/mods/Servo Mortis/modules/watcher/test_mode")
local Watching = mod:io_dofile("Servo Mortis/scripts/mods/Servo Mortis/modules/watcher/watching")

mod.on_setting_changed = function(id)
	if Settings.on_changed(mod, id) then
		CameraMode.apply_to_live_handler(mod, Settings)
	end
end

mod.on_settings_reset = function()
	Settings.refresh(mod)
	CameraMode.apply_to_live_handler(mod, Settings)
end

mod.spectate_previous = function()
	if not mod:is_enabled() then
		return
	end

	local handler = CameraMode.live_handler()
	if not handler or handler._mode ~= "observer" then
		return
	end

	FollowTargets.set_direction(-1)

	local ok, err = pcall(function()
		local unit = handler:_next_follow_unit(nil)
		if unit then
			handler:_switch_follow_target(unit)
			handler:_update_follow(true)
		end
	end)

	if not ok then
		FollowTargets.set_direction(nil)
		Runtime.report("stepping back to the previous spectate target failed: " .. tostring(err))
	end
end

local function account_of(unit)
	local spawn_manager = Managers and Managers.state and Managers.state.player_unit_spawn
	local owner = spawn_manager and spawn_manager:owner(unit)
	if not owner or not owner.account_id then
		return nil
	end
	return owner:account_id()
end

local function local_watching_account()
	local player_manager = Managers and Managers.player
	local player = player_manager and player_manager:local_player_safe(1)
	local handler = player and player.camera_handler
	if not handler then
		return nil
	end

	return Watching.watched_account(handler._mode, handler._camera_follow_unit,
		player.player_unit, ALIVE, account_of)
end

local COLLISION_FILTER = "filter_interactable_line_of_sight_check"

local function raycast_clear(from_x, from_y, from_z, dir_x, dir_y, dir_z, distance)
	local world = Managers.world and Managers.world:world("level_world")
	local physics_world = world and World.physics_world(world)
	if not physics_world then
		return false, nil
	end

	local hit, _, hit_distance = PhysicsWorld.raycast(physics_world,
		Vector3(from_x, from_y, from_z),
		Vector3(dir_x, dir_y, dir_z),
		distance, "closest", "collision_filter", COLLISION_FILTER)

	return hit, hit_distance
end

local function body_height_for(unit)
	local spawn_manager = Managers and Managers.state and Managers.state.player_unit_spawn
	local owner = spawn_manager and spawn_manager:owner(unit)
	if not owner or not owner.profile then
		return nil
	end

	local profile = owner:profile()
	local breed = profile and profile.archetype and profile.archetype.breed
	if not breed then
		return nil
	end

	local settings_ok, BreedSettings = pcall(require, "scripts/settings/breed/breed_settings")
	local heights = settings_ok and BreedSettings and BreedSettings.base_player_body_size_heights

	return heights and heights[breed .. "_sized"]
end

local function velocity_for(unit)
	local locomotion = ScriptUnit and ScriptUnit.has_extension(unit, "locomotion_system")
	if not locomotion or not locomotion.current_velocity then
		return Vector3(0, 0, 0)
	end

	local ok, velocity = pcall(function() return locomotion:current_velocity() end)
	if not ok or not velocity then
		return Vector3(0, 0, 0)
	end

	return velocity
end

local watcher_ctx = {
	Placement = Placement,
	Skulls = Skulls,
	Presence = Presence,
	Nameplate = Nameplate,
	mod = mod,
	velocity_for = velocity_for,
	raycast = raycast_clear,
	body_height_for = body_height_for,
	live = {},
	time = 0,
}

local test_units_by_id = {}

local function test_unit_lookup(id)
	return test_units_by_id[id]
end

mod.update = function(dt)
	if not mod:is_enabled() then
		Runtime.despawn_all(watcher_ctx.live, Nameplate)
		return
	end

	if SpectateControls.previous_pressed(rawget(_G, "Mouse"), rawget(_G, "Pad1")) then
		mod.spectate_previous()
	end

	CameraMode.cooperate(CameraMode.spectating(mod, Settings))

	Presence.set_watching(local_watching_account())

	local values = Settings.values
	watcher_ctx.enabled = values.watcher_skulls ~= false

	if values.watcher_test_mode then
		local units = TestMode.alive_target_units()

		test_units_by_id = {}
		for i = 1, #units do
			local id = TestMode.target_id_for(units[i])
			if id then
				test_units_by_id[id] = units[i]
			end
		end

		Runtime._set_unit_lookup(test_unit_lookup)
		watcher_ctx.watchers = TestMode.update(dt, units)
	else
		test_units_by_id = {}
		TestMode.reset()
		Runtime._set_unit_lookup(nil)
		watcher_ctx.watchers = nil
	end

	Runtime.update(dt, watcher_ctx)
end

mod.on_all_mods_loaded = function()
	Runtime._set_reporter(function(message)
		mod:error("Servo Mortis: " .. message)
	end)
	Settings.refresh(mod)
	FollowTargets.install(mod, Settings)
	SpectateControls.install(mod)
	CameraMode.install(mod, Settings)
	CameraMode.apply_to_live_handler(mod, Settings)
	Nameplate.install(mod, Settings)
	Presence.install(mod)
	mod:info("Servo Mortis " .. tostring(mod.version) .. " loaded")
end

mod.on_disabled = function()
	CameraMode.apply(CameraMode.live_handler(), { values = { third_person_spectate = false } })
	Runtime.despawn_all(watcher_ctx.live, Nameplate)
	TestMode.reset()
	CameraMode.cooperate(false)
	CameraMode._reset_cooperation()
	SpectateControls.forget_hint()
	SpectateControls.restore_hint()
	Presence.uninstall()
end

mod.on_enabled = function()
	SpectateControls.forget_hint()
	Settings.refresh(mod)
	CameraMode.apply_to_live_handler(mod, Settings)
	Nameplate.install(mod, Settings)
	Presence.install(mod)
end

mod.on_unload = function()
	CameraMode.apply(CameraMode.live_handler(), { values = { third_person_spectate = false } })
	Runtime.despawn_all(watcher_ctx.live, Nameplate)
	TestMode.reset()
	CameraMode.cooperate(false)
	CameraMode._reset_cooperation()
	SpectateControls.forget_hint()
	SpectateControls.restore_hint()
	Presence.uninstall()
	Skulls.release(mod)
end
