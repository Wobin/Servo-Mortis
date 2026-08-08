local ok_status, PlayerUnitStatus = pcall(require, "scripts/utilities/attack/player_unit_status")
if not ok_status then
	PlayerUnitStatus = nil
end

local CLASS = CLASS

local FollowTargets = {}

local function collect(ctx, apply_skip_downed)
	local out = {}
	local units = ctx.player_units
	if not units then return out end

	for i = 1, #units do
		local unit = units[i]
		local keep = ctx.is_alive(unit)

		if keep and not ctx.allow_bots and not ctx.is_human(unit) then
			keep = false
		end

		if keep and apply_skip_downed and ctx.is_downed(unit) then
			keep = false
		end

		if keep then
			out[#out + 1] = unit
		end
	end

	return out
end

function FollowTargets.candidates(ctx)
	local filtered = collect(ctx, ctx.skip_downed)
	if #filtered > 0 then
		return filtered
	end
	return collect(ctx, false)
end

function FollowTargets.pick(ctx, except_unit, direction)
	local step = direction == -1 and -1 or 1
	local all = FollowTargets.candidates(ctx)

	local list = {}
	for i = 1, #all do
		if all[i] ~= except_unit then
			list[#list + 1] = all[i]
		end
	end

	local count = #list
	if count == 0 then
		return nil
	end

	local current_index
	for i = 1, count do
		if list[i] == ctx.current then
			current_index = i
			break
		end
	end

	if not current_index then
		return step == 1 and list[1] or list[count]
	end

	local next_index = current_index + step
	if next_index > count then
		next_index = 1
	elseif next_index < 1 then
		next_index = count
	end

	return list[next_index]
end

local pending_direction = nil

function FollowTargets.set_direction(direction)
	pending_direction = direction
end

function FollowTargets.build_context(handler, settings)
	if not handler then return nil end

	local side_system = handler._side_system
	if not side_system then return nil end

	if not handler._side_id and side_system.get_side_from_name then
		local heroes = side_system:get_side_from_name("heroes")
		handler._side_id = heroes and heroes.side_id
	end

	if not handler._side_id or not side_system.get_side then return nil end

	local side = side_system:get_side(handler._side_id)
	local player_units = side and side.player_units
	if not player_units then return nil end

	local spawn_manager = Managers and Managers.state and Managers.state.player_unit_spawn
	if not spawn_manager then return nil end

	local values = settings and settings.values or {}

	return {
		player_units = player_units,
		current = handler._camera_follow_unit,
		allow_bots = values.spectate_bots ~= false,
		skip_downed = values.skip_downed_targets ~= false,
		is_alive = function(unit)
			return ALIVE[unit] ~= nil
		end,
		is_human = function(unit)
			local owner = spawn_manager:owner(unit)
			return owner ~= nil and owner:is_human_controlled() and true or false
		end,
		is_downed = function(unit)
			if not PlayerUnitStatus then return false end
			local unit_data = ScriptUnit and ScriptUnit.has_extension(unit, "unit_data_system")
			if not unit_data then return false end
			local character_state = unit_data:read_component("character_state")
			if not character_state then return false end
			return PlayerUnitStatus.is_hogtied(character_state) or PlayerUnitStatus.is_dead(character_state)
		end,
	}
end

function FollowTargets.install(mod, Settings)
	if not CLASS or not CLASS.CameraHandler then
		mod:error("Servo Mortis: CLASS.CameraHandler not found, follow-target selection is disabled")
		return
	end

	mod:hook(CLASS.CameraHandler, "_next_follow_unit", function(func, self, except_unit)
		local direction = pending_direction or 1
		pending_direction = nil

		if not mod:is_enabled() then
			return func(self, except_unit)
		end

		local ctx = FollowTargets.build_context(self, Settings)
		if not ctx then
			return func(self, except_unit)
		end

		local unit = FollowTargets.pick(ctx, except_unit, direction)
		if unit == nil then
			return func(self, except_unit)
		end
		return unit
	end)
end

return FollowTargets
