local table_sort = table.sort
local math_sqrt = math.sqrt
local math_exp = math.exp
local math_atan2 = math.atan2
local math_cos = math.cos
local math_sin = math.sin

local ORBIT_ANCHOR_EPSILON = 0.01
local HUMAN_BODY_HEIGHT = 1.65
local ORBIT_HEIGHT = 1.2
local LOOK_EPSILON = 0.0001
local HOVER_SPREAD = 0.6
local AVOID_STRENGTH = 0.8
local NAMEPLATE_LIFT = 0.4
local COLLISION_MARGIN = 0.35
local MIN_CLEAR_DISTANCE = 0.5

local Runtime = {}

Runtime.SMOOTHING = 6.0
Runtime.CLEAR_RELEASE = 2.0
Runtime.FACING_SMOOTHING = 2.5
Runtime.FACING_TURN_RATE = 1.6
Runtime.TRAVEL_MIN_SPEED_SQ = 0.25
Runtime.CUT_DISTANCE = 25.0
Runtime.MAX_DELETE_ATTEMPTS = 3

local reporter = nil
local reported = {}

function Runtime._set_reporter(fn)
	reporter = fn
	reported = {}
end

function Runtime.report(message)
	if not message or reported[message] then
		return false
	end

	reported[message] = true

	if reporter then
		reporter(message)
	end

	return true
end

function Runtime.slot_for(account_id, ordered_ids)
	local sorted = {}
	for i = 1, #ordered_ids do
		sorted[i] = ordered_ids[i]
	end
	table_sort(sorted)

	for i = 1, #sorted do
		if sorted[i] == account_id then
			return i
		end
	end

	return 1
end

function Runtime.reconcile(watchers, live)
	local wanted = {}
	for i = 1, #watchers do
		wanted[watchers[i]] = true
	end

	local to_add = {}
	for i = 1, #watchers do
		local id = watchers[i]
		if not live[id] then
			to_add[#to_add + 1] = id
		end
	end

	local to_remove = {}
	for id in pairs(live) do
		if not wanted[id] then
			to_remove[#to_remove + 1] = id
		end
	end
	table_sort(to_remove)

	return to_add, to_remove
end

local FALLBACK_COLOURS = {
	{ 255, 220, 220, 220 },
	{ 255, 120, 200, 255 },
	{ 255, 255, 200, 120 },
	{ 255, 160, 255, 160 },
}

local function player_for_account(account_id)
	local player_manager = Managers and Managers.player
	if not player_manager or not player_manager.players then
		return nil
	end
	for _, player in pairs(player_manager:players()) do
		if player.account_id and player:account_id() == account_id then
			return player
		end
	end
	return nil
end

local function default_unit_for_account(account_id)
	local player = player_for_account(account_id)
	return player and player.player_unit
end

function Runtime.identity_for(account_id, slot)
	local player = player_for_account(account_id)
	local name = account_id
	local colour = nil

	if player then
		if player.name then
			name = player:name() or account_id
		end
		local ok, UISettings = pcall(require, "scripts/settings/ui/ui_settings")
		if ok and UISettings and UISettings.player_slot_colors and player.slot then
			colour = UISettings.player_slot_colors[player:slot()]
		end
	end

	if not colour then
		local index = ((slot - 1) % #FALLBACK_COLOURS) + 1
		colour = FALLBACK_COLOURS[index]
	end

	return name, colour
end

function Runtime.slot_for_watcher(account_id, ordered_ids)
	local player = player_for_account(account_id)
	if player and player.slot then
		local slot = player:slot()
		if type(slot) == "number" then
			return slot
		end
	end
	return Runtime.slot_for(account_id, ordered_ids)
end

local unit_for_account = default_unit_for_account

function Runtime._set_unit_lookup(fn)
	unit_for_account = fn or default_unit_for_account
end

function Runtime.despawn(live, account_id, Nameplate)
	local entry = live[account_id]
	if not entry then
		return true
	end

	Nameplate.remove(entry.marker_id)
	entry.marker_id = nil

	local spawner = entry.spawner or (Managers and Managers.state and Managers.state.unit_spawner)
	if spawner and entry.unit and Unit.alive(entry.unit) then
		local ok, err = pcall(function() spawner:mark_for_deletion(entry.unit) end)

		if not ok then
			entry.delete_attempts = (entry.delete_attempts or 0) + 1

			if entry.delete_attempts < Runtime.MAX_DELETE_ATTEMPTS then
				return false
			end

			Runtime.report("could not delete a watcher skull after " ..
				tostring(entry.delete_attempts) .. " attempts, it will remain in the level: " ..
				tostring(err))
		end
	end

	live[account_id] = nil

	return true
end

function Runtime.despawn_all(live, Nameplate)
	for account_id in pairs(live) do
		Runtime.despawn(live, account_id, Nameplate)
	end
end

function Runtime.radius_for(base_radius, measured_height, target_height)
	if type(base_radius) ~= "number" or base_radius <= 0 then
		return base_radius
	end

	local from = HUMAN_BODY_HEIGHT
	if type(measured_height) == "number" and measured_height > 0 then
		from = measured_height
	end

	local to = HUMAN_BODY_HEIGHT
	if type(target_height) == "number" and target_height > 0 then
		to = target_height
	end

	return base_radius * (to / from)
end

function Runtime.orbit_height_for(body_height)
	if type(body_height) ~= "number" or body_height <= 0 then
		return ORBIT_HEIGHT
	end

	return ORBIT_HEIGHT * (body_height / HUMAN_BODY_HEIGHT)
end

function Runtime.clear_distance(raycast, base, desired, height)
	local anchor_x, anchor_y, anchor_z = base.x, base.y, base.z + (height or ORBIT_HEIGHT)
	local dx = desired.x - anchor_x
	local dy = desired.y - anchor_y
	local dz = desired.z - anchor_z
	local distance = math_sqrt(dx * dx + dy * dy + dz * dz)

	if not raycast or distance <= COLLISION_MARGIN then
		return distance
	end

	local ok, hit, hit_distance = pcall(raycast,
		anchor_x, anchor_y, anchor_z,
		dx / distance, dy / distance, dz / distance,
		distance)

	if not ok or not hit or type(hit_distance) ~= "number" then
		return distance
	end

	local allowed = hit_distance - COLLISION_MARGIN
	if allowed > distance then
		allowed = distance
	end
	if allowed < MIN_CLEAR_DISTANCE then
		allowed = MIN_CLEAR_DISTANCE
	end

	return allowed
end

function Runtime.should_cut(px, py, pz, target_position)
	if not px or not target_position then
		return false
	end

	local dx = target_position.x - px
	local dy = target_position.y - py
	local dz = target_position.z - pz

	return math_sqrt(dx * dx + dy * dy + dz * dz) > Runtime.CUT_DISTANCE
end

function Runtime.ease_limit(previous, allowed, dt)
	if not previous or allowed <= previous then
		return allowed
	end

	return previous + (allowed - previous) * (1 - math_exp(-Runtime.CLEAR_RELEASE * dt))
end

function Runtime.limit_radius(base, position, limit, height)
	if not limit then
		return position
	end

	local anchor_x, anchor_y, anchor_z = base.x, base.y, base.z + (height or ORBIT_HEIGHT)
	local dx = position.x - anchor_x
	local dy = position.y - anchor_y
	local dz = position.z - anchor_z
	local distance = math_sqrt(dx * dx + dy * dy + dz * dz)

	if distance <= limit or distance <= LOOK_EPSILON then
		return position
	end

	local scale = limit / distance
	return Vector3(
		anchor_x + dx * scale,
		anchor_y + dy * scale,
		anchor_z + dz * scale)
end

function Runtime.resource_ready(path)
	if not Application or not Application.can_get_resource then
		return false
	end
	return Application.can_get_resource("unit", path) == true
end

local function ensure_entry(live, watcher, target_unit, slot, spawner, Skulls)
	local account_id = watcher.account_id
	local entry = live[account_id]

	if entry then
		entry.slot = slot
		entry.delete_attempts = nil

		if entry.watching ~= watcher.watching then
			entry.watching = watcher.watching
			entry.orbit_phase = nil
			entry.clear_limit = nil
			entry.facing_angle = nil
			entry.travel_angle = nil
			entry.cut = Runtime.should_cut(entry.px, entry.py, entry.pz,
				Unit.world_position(target_unit, 1))
		end

		return entry
	end

	local path = Skulls.path_for_slot(slot)
	if not Runtime.resource_ready(path) then
		return nil
	end

	local spawn_position = Unit.world_position(target_unit, 1)
	local pose = Matrix4x4.from_quaternion_position(Quaternion.identity(), spawn_position)
	local ok, unit = pcall(function() return spawner:spawn_unit(path, pose) end)
	if not ok or not unit then
		return nil
	end

	entry = {
		unit = unit,
		slot = slot,
		mode = "orbit",
		spawner = spawner,
		watching = watcher.watching,
		px = spawn_position.x,
		py = spawn_position.y,
		pz = spawn_position.z,
	}
	live[account_id] = entry

	return entry
end

local function face_target(entry, base, skull_pos, orbit_height)
	local look_x = base.x - skull_pos.x
	local look_y = base.y - skull_pos.y

	if look_x * look_x + look_y * look_y <= LOOK_EPSILON then
		return
	end

	local look_z = (base.z + orbit_height) - skull_pos.z
	Unit.set_local_rotation(entry.unit, 1,
		Quaternion.look(Vector3(look_x, look_y, look_z), Vector3(0, 0, 1)))
end

local function update_marker(entry, account_id, skull_pos, Nameplate)
	local marker_pos = Vector3(skull_pos.x, skull_pos.y, skull_pos.z + NAMEPLATE_LIFT)

	if entry.marker_id and Nameplate.move then
		if not Nameplate.move(entry.marker_id, marker_pos) then
			entry.marker_id = nil
		end
	end

	if not entry.marker_id then
		local name, colour = Runtime.identity_for(account_id, entry.slot)
		entry.marker_id = Nameplate.add(name, colour, marker_pos)
	end
end

local function desired_offset(entry, previous_mode, ctx, dt, radius, orbit_height,
		to_x, to_y, dist, speed_sq, vel, fwd)
	local Placement = ctx.Placement

	if entry.mode == "hover" then
		if speed_sq > Runtime.TRAVEL_MIN_SPEED_SQ then
			entry.travel_angle = math_atan2(vel.y, vel.x)
		end

		if previous_mode ~= "hover" then
			if dist > ORBIT_ANCHOR_EPSILON then
				entry.facing_angle = Placement.facing_for_bearing(entry.slot,
					math_atan2(to_y, to_x), radius, HOVER_SPREAD)
			else
				entry.facing_angle = nil
			end
		end

		entry.facing_angle = Placement.ease_angle(entry.facing_angle,
			entry.travel_angle or math_atan2(fwd.y, fwd.x),
			1 - math_exp(-Runtime.FACING_SMOOTHING * dt),
			Runtime.FACING_TURN_RATE * dt)

		return Placement.hover_offset(entry.slot,
			math_cos(entry.facing_angle), math_sin(entry.facing_angle),
			radius, orbit_height, HOVER_SPREAD)
	end

	if previous_mode ~= "orbit" or not entry.orbit_phase then
		if dist > ORBIT_ANCHOR_EPSILON then
			entry.orbit_phase = Placement.phase_for_bearing(entry.slot,
				ctx.time, math_atan2(to_y, to_x))
		else
			entry.orbit_phase = 0
		end
	end

	return Placement.orbit_offset(entry.slot, ctx.time, radius, orbit_height, entry.orbit_phase)
end

local function place_entry(entry, account_id, target_unit, base_radius, measured_height, dt, ctx)
	local Placement, Nameplate = ctx.Placement, ctx.Nameplate

	local body_height = ctx.body_height_for and ctx.body_height_for(target_unit)
	local orbit_height = Runtime.orbit_height_for(body_height)
	local radius = Runtime.radius_for(base_radius, measured_height, body_height)
	local base = Unit.world_position(target_unit, 1)
	local fwd = Quaternion.forward(Unit.world_rotation(target_unit, 1))
	local vel = ctx.velocity_for and ctx.velocity_for(target_unit) or Vector3(0, 0, 0)
	local speed_sq = vel.x * vel.x + vel.y * vel.y

	local previous_mode = entry.mode
	entry.mode = Placement.next_mode(previous_mode, speed_sq)

	local cur = entry.px and Vector3(entry.px, entry.py, entry.pz) or base
	local to_x, to_y = cur.x - base.x, cur.y - base.y
	local dist = math_sqrt(to_x * to_x + to_y * to_y)

	local ox, oy, oz = desired_offset(entry, previous_mode, ctx, dt, radius, orbit_height,
		to_x, to_y, dist, speed_sq, vel, fwd)

	local target_pos = Vector3(base.x + ox, base.y + oy, base.z + oz)
	if Placement.is_closing(to_x, to_y, vel.x, vel.y, dist) then
		local ax, ay = Placement.avoid_offset(entry.slot, vel.x, vel.y, AVOID_STRENGTH)
		target_pos = Vector3(target_pos.x + ax, target_pos.y + ay, target_pos.z)
	end

	local allowed = Runtime.clear_distance(ctx.raycast, base, target_pos, orbit_height)
	entry.clear_limit = Runtime.ease_limit(entry.clear_limit, allowed, dt)
	target_pos = Runtime.limit_radius(base, target_pos, entry.clear_limit, orbit_height)

	local skull_pos
	if entry.cut then
		entry.cut = nil
		skull_pos = target_pos
	else
		local alpha = 1 - math_exp(-Runtime.SMOOTHING * dt)
		skull_pos = Vector3(
			cur.x + (target_pos.x - cur.x) * alpha,
			cur.y + (target_pos.y - cur.y) * alpha,
			cur.z + (target_pos.z - cur.z) * alpha)
	end

	skull_pos = Runtime.limit_radius(base, skull_pos,
		Runtime.clear_distance(ctx.raycast, base, skull_pos, orbit_height), orbit_height)

	entry.px, entry.py, entry.pz = skull_pos.x, skull_pos.y, skull_pos.z
	Unit.set_local_position(entry.unit, 1, skull_pos)

	face_target(entry, base, skull_pos, orbit_height)
	update_marker(entry, account_id, skull_pos, Nameplate)
end

function Runtime.update(dt, ctx)
	if not ctx then
		return
	end

	local Placement, Skulls, Presence, Nameplate =
		ctx.Placement, ctx.Skulls, ctx.Presence, ctx.Nameplate

	local live = ctx.live
	if not live then
		live = {}
		ctx.live = live
	end

	if not ctx.enabled then
		if Nameplate then
			Runtime.despawn_all(live, Nameplate)
		end
		return
	end

	if not Placement or not Skulls or not Presence or not Nameplate then
		return
	end

	local watchers = ctx.watchers or Presence.watchers()
	local ids = {}
	for i = 1, #watchers do
		ids[i] = watchers[i].account_id
	end

	local to_add, to_remove = Runtime.reconcile(ids, live)
	for i = 1, #to_remove do
		Runtime.despawn(live, to_remove[i], Nameplate)
	end

	if #to_add > 0 and not Skulls.ensure_package(ctx.mod) then
		return
	end

	local spawner = ctx.spawner or (Managers and Managers.state and Managers.state.unit_spawner)
	if not spawner then
		Runtime.despawn_all(live, Nameplate)
		return
	end

	if #watchers == 0 then
		return
	end

	local base_radius = Skulls.orbit_radius()
	local measured_unit = Skulls.measured_unit and Skulls.measured_unit()
	local measured_height = measured_unit and ctx.body_height_for and ctx.body_height_for(measured_unit)

	ctx.time = (ctx.time or 0) + dt

	for i = 1, #watchers do
		local watcher = watchers[i]
		local account_id = watcher.account_id
		local target_unit = unit_for_account(watcher.watching)

		if not target_unit or not ALIVE[target_unit] then
			Runtime.despawn(live, account_id, Nameplate)
		else
			local slot = Runtime.slot_for_watcher(account_id, ids)
			local entry = ensure_entry(live, watcher, target_unit, slot, spawner, Skulls)

			if entry and entry.unit and Unit.alive(entry.unit) then
				place_entry(entry, account_id, target_unit, base_radius, measured_height, dt, ctx)
			end
		end
	end
end

return Runtime
