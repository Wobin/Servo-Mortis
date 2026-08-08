local math_pi = math.pi
local math_cos = math.cos
local math_sin = math.sin
local math_floor = math.floor

local Placement = {}

Placement.SLOTS = 4
Placement.ORBIT_SPEED = 0.6

local TWO_PI = math_pi * 2

local function normalise_slot(slot)
	if type(slot) ~= "number" then
		return 1
	end
	local n = math_floor(slot)
	if n < 1 then
		return 1
	end
	return ((n - 1) % Placement.SLOTS) + 1
end

function Placement.orbit_angle(slot, t)
	slot = normalise_slot(slot)
	local share = TWO_PI / Placement.SLOTS
	return (slot - 1) * share + (t or 0) * Placement.ORBIT_SPEED
end

function Placement.orbit_offset(slot, t, radius, height, phase)
	local angle = Placement.orbit_angle(slot, t) + (phase or 0)
	return math_cos(angle) * radius, math_sin(angle) * radius, height
end

function Placement.phase_for_bearing(slot, t, bearing)
	return bearing - Placement.orbit_angle(slot, t)
end

function Placement.ease_angle(previous, target, alpha, max_step)
	if not previous then
		return target
	end

	local delta = (target - previous) % TWO_PI
	if delta > math_pi then
		delta = delta - TWO_PI
	end

	delta = delta * alpha

	if max_step then
		if delta > max_step then
			delta = max_step
		elseif delta < -max_step then
			delta = -max_step
		end
	end

	return previous + delta
end

local math_sqrt = math.sqrt
local math_atan2 = math.atan2

Placement.ENTER_HOVER_SPEED_SQ = 1.0
Placement.EXIT_HOVER_SPEED_SQ = 0.16

function Placement.next_mode(current_mode, speed_sq)
	if speed_sq >= Placement.ENTER_HOVER_SPEED_SQ then
		return "hover"
	end
	if speed_sq <= Placement.EXIT_HOVER_SPEED_SQ then
		return "orbit"
	end
	return current_mode == "hover" and "hover" or "orbit"
end

local function hover_geometry(slot, distance, spread)
	slot = normalise_slot(slot)

	local lateral = ((slot - 1) - (Placement.SLOTS - 1) * 0.5) * spread
	local max_lateral = distance * 0.9
	if lateral > max_lateral then
		lateral = max_lateral
	end
	if lateral < -max_lateral then
		lateral = -max_lateral
	end

	return lateral, math_sqrt(distance * distance - lateral * lateral)
end

function Placement.hover_offset(slot, facing_x, facing_y, distance, height, spread)
	local len = math_sqrt(facing_x * facing_x + facing_y * facing_y)
	local fx, fy
	if len < 0.0001 then
		fx, fy = 1, 0
	else
		fx, fy = facing_x / len, facing_y / len
	end

	local lateral, back = hover_geometry(slot, distance, spread)
	local back_x, back_y = -fx * back, -fy * back
	local side_x, side_y = -fy * lateral, fx * lateral

	return back_x + side_x, back_y + side_y, height
end

function Placement.facing_for_bearing(slot, bearing, distance, spread)
	local lateral, back = hover_geometry(slot, distance, spread)

	return bearing - math_atan2(lateral, -back)
end

Placement.AVOID_DISTANCE = 1.2
Placement.AVOID_DOT = 0.5

function Placement.is_closing(to_skull_x, to_skull_y, vel_x, vel_y, distance)
	if distance > Placement.AVOID_DISTANCE then
		return false
	end

	local to_len = math_sqrt(to_skull_x * to_skull_x + to_skull_y * to_skull_y)
	local vel_len = math_sqrt(vel_x * vel_x + vel_y * vel_y)
	if to_len < 0.0001 or vel_len < 0.0001 then
		return false
	end

	local dot = (to_skull_x / to_len) * (vel_x / vel_len)
		+ (to_skull_y / to_len) * (vel_y / vel_len)

	return dot >= Placement.AVOID_DOT
end

function Placement.avoid_offset(slot, vel_x, vel_y, amount)
	slot = normalise_slot(slot)
	local len = math_sqrt(vel_x * vel_x + vel_y * vel_y)
	if len < 0.0001 then
		return 0, 0
	end

	local side = (slot % 2 == 1) and 1 or -1
	local vx, vy = vel_x / len, vel_y / len

	return -vy * amount * side, vx * amount * side
end

return Placement
