local t = require("spec.runner")

local P = dofile("./scripts/mods/Servo Mortis/modules/watcher/placement.lua")

return function()
	t.suite("Watcher placement: orbit")

	t.it("slots are spread evenly around the circle", function()
		local a1 = P.orbit_angle(1, 0)
		local a2 = P.orbit_angle(2, 0)
		local step = math.abs(a2 - a1)
		t.near(step, (2 * math.pi) / P.SLOTS, 0.0001, "adjacent slots differ by one full share")
	end)

	t.it("the same slot at the same time is always the same angle", function()
		t.near(P.orbit_angle(3, 12.5), P.orbit_angle(3, 12.5), 0.0000001,
			"placement must be deterministic so every client agrees")
	end)

	t.it("different slots never coincide at the same time", function()
		local seen = {}
		for slot = 1, P.SLOTS do
			local a = string.format("%.4f", P.orbit_angle(slot, 3.0) % (2 * math.pi))
			t.falsy(seen[a], "slot " .. slot .. " collided with another slot")
			seen[a] = true
		end
	end)

	t.it("the orbit advances over time", function()
		local a = P.orbit_angle(1, 0)
		local b = P.orbit_angle(1, 1.0)
		t.truthy(math.abs(b - a) > 0.01, "angle should change as time passes")
	end)

	t.it("offset sits at the requested radius and height", function()
		local x, y, z = P.orbit_offset(1, 0, 2.0, 1.5)
		t.near(math.sqrt(x * x + y * y), 2.0, 0.0001, "horizontal distance is the radius")
		t.near(z, 1.5, 0.0001, "z is the height")
	end)

	t.it("a zero radius collapses to the player position", function()
		local x, y, z = P.orbit_offset(2, 5, 0, 0)
		t.near(x, 0, 0.0001, "x")
		t.near(y, 0, 0.0001, "y")
		t.near(z, 0, 0.0001, "z")
	end)

	t.it("slot 0 does not collide with slot 4", function()
		local a0 = P.orbit_angle(0, 0) % (2 * math.pi)
		local a4 = P.orbit_angle(4, 0) % (2 * math.pi)
		t.truthy(math.abs(a0 - a4) > 0.0001, "slot 0 must differ from slot 4")
	end)

	t.it("a negative slot does not collide with a valid slot", function()
		local aMinus1 = P.orbit_angle(-1, 0) % (2 * math.pi)
		local a3 = P.orbit_angle(3, 0) % (2 * math.pi)
		t.truthy(math.abs(aMinus1 - a3) > 0.0001, "slot -1 must differ from slot 3")
	end)

	t.it("slots above SLOTS wrap predictably", function()
		local a5 = P.orbit_angle(5, 0)
		local a1 = P.orbit_angle(1, 0)
		t.near(a5, a1, 0.0001, "slot 5 wraps to slot 1")
	end)

	t.it("a non-numeric slot returns a usable angle rather than erroring", function()
		local angle = P.orbit_angle(nil, 0)
		t.truthy(type(angle) == "number", "orbit_angle(nil, 0) must return a number")
	end)

	t.suite("Watcher placement: hover and hysteresis")

	t.it("thresholds are the squares of 1.0 and 0.4", function()
		t.near(P.ENTER_HOVER_SPEED_SQ, 1.0, 0.0001, "enter threshold squared")
		t.near(P.EXIT_HOVER_SPEED_SQ, 0.16, 0.0001, "exit threshold squared")
	end)

	t.it("standing still stays in orbit", function()
		t.eq(P.next_mode("orbit", 0), "orbit", "no movement, no hover")
	end)

	t.it("moving fast enters hover", function()
		t.eq(P.next_mode("orbit", 16), "hover", "4 m/s squared is well above the enter threshold")
	end)

	t.it("crouch walking counts as moving", function()
		t.eq(P.next_mode("orbit", 1.4 * 1.4), "hover", "1.4 m/s is above the enter threshold")
	end)

	t.it("inside the band, orbit stays orbit", function()
		t.eq(P.next_mode("orbit", 0.5), "orbit", "0.7 m/s must not trigger hover")
	end)

	t.it("inside the band, hover stays hover", function()
		t.eq(P.next_mode("hover", 0.5), "hover", "the band holds the current mode")
	end)

	t.it("dropping below the exit threshold returns to orbit", function()
		t.eq(P.next_mode("hover", 0.01), "orbit", "0.1 m/s is below the exit threshold")
	end)

	t.it("hover sits behind the facing direction", function()
		local x, y = P.hover_offset(1, 1, 0, 2.0, 1.0, 0)
		t.truthy(x < 0, "facing +x means the skull trails at -x")
		t.near(y, 0, 0.0001, "no lateral offset with zero spread")
	end)

	t.it("hover slots spread laterally", function()
		local _, y1 = P.hover_offset(1, 1, 0, 2.0, 1.0, 0.5)
		local _, y2 = P.hover_offset(2, 1, 0, 2.0, 1.0, 0.5)
		t.truthy(math.abs(y1 - y2) > 0.01, "different slots must not stack in one spot")
	end)

	t.it("hover distance is respected", function()
		local x, y = P.hover_offset(1, 0, 1, 3.0, 0, 0)
		t.near(math.sqrt(x * x + y * y), 3.0, 0.0001, "trails at the requested distance")
	end)

	t.it("a zero facing vector does not produce nan", function()
		local x, y, z = P.hover_offset(1, 0, 0, 2.0, 1.0, 0.5)
		t.eq(x == x, true, "x must not be nan")
		t.eq(y == y, true, "y must not be nan")
		t.eq(z == z, true, "z must not be nan")
	end)

	t.it("hover_offset with a non-numeric slot returns numbers and does not throw", function()
		local x, y, z = P.hover_offset(nil, 1, 0, 2.0, 1.0, 0)
		t.eq(type(x) == "number", true, "x must be a number")
		t.eq(type(y) == "number", true, "y must be a number")
		t.eq(type(z) == "number", true, "z must be a number")
	end)

	t.it("hover_offset(0, ...) and hover_offset(5, ...) produce same lateral as their normalized equivalents", function()
		local _, y0 = P.hover_offset(0, 1, 0, 2.0, 1.0, 0.5)
		local _, y1 = P.hover_offset(1, 1, 0, 2.0, 1.0, 0.5)
		t.near(y0, y1, 0.0001, "slot 0 must normalize to slot 1")
		local _, y5 = P.hover_offset(5, 1, 0, 2.0, 1.0, 0.5)
		local _, y1b = P.hover_offset(1, 1, 0, 2.0, 1.0, 0.5)
		t.near(y5, y1b, 0.0001, "slot 5 must normalize to slot 1")
	end)

	t.it("the trailing distance holds at the requested value with non-zero spread", function()
		local x1, y1 = P.hover_offset(1, 1, 0, 2.0, 0, 0.5)
		local dist1 = math.sqrt(x1 * x1 + y1 * y1)
		t.near(dist1, 2.0, 0.0001, "slot 1 must trail at exactly 2.0 with spread 0.5")
		local x2, y2 = P.hover_offset(2, 1, 0, 2.0, 0, 0.5)
		local dist2 = math.sqrt(x2 * x2 + y2 * y2)
		t.near(dist2, 2.0, 0.0001, "slot 2 must trail at exactly 2.0 with spread 0.5")
	end)

	t.it("lateral spread larger than the distance is clamped and does not produce nan", function()
		local x, y, z = P.hover_offset(1, 1, 0, 1.0, 1.0, 5.0)
		t.eq(x == x, true, "x must not be nan")
		t.eq(y == y, true, "y must not be nan")
		t.eq(z == z, true, "z must not be nan")
		local dist = math.sqrt(x * x + y * y)
		t.near(dist, 1.0, 0.0001, "distance must hold at 1.0 even with large spread")
	end)

	t.it("next_mode at exact boundary 1.0 squared enters hover", function()
		t.eq(P.next_mode("orbit", 1.0), "hover", "speed_sq exactly 1.0 must trigger hover")
	end)

	t.it("next_mode at exact boundary 0.16 squared returns to orbit", function()
		t.eq(P.next_mode("hover", 0.16), "orbit", "speed_sq exactly 0.16 must exit hover")
	end)

	t.suite("Watcher placement: dodge avoidance")

	t.it("closing while near is a dodge", function()
		t.eq(P.is_closing(1, 0, 1, 0, 0.5), true, "moving straight at a nearby skull")
	end)

	t.it("closing from far away is not a dodge", function()
		t.eq(P.is_closing(1, 0, 1, 0, 50), false, "distance disqualifies it")
	end)

	t.it("moving away while near is not a dodge", function()
		t.eq(P.is_closing(1, 0, -1, 0, 0.5), false, "velocity points away")
	end)

	t.it("moving sideways while near is not a dodge", function()
		t.eq(P.is_closing(1, 0, 0, 1, 0.5), false, "perpendicular movement does not close")
	end)

	t.it("a still player is never dodging", function()
		t.eq(P.is_closing(1, 0, 0, 0, 0.5), false, "zero velocity cannot close")
	end)

	t.it("avoidance is perpendicular to the movement", function()
		local x, y = P.avoid_offset(1, 1, 0, 1.0)
		t.near(x, 0, 0.0001, "no component along the movement axis")
		t.truthy(math.abs(y) > 0.5, "displaced sideways")
	end)

	t.it("odd and even slots avoid to opposite sides", function()
		local _, y1 = P.avoid_offset(1, 1, 0, 1.0)
		local _, y2 = P.avoid_offset(2, 1, 0, 1.0)
		t.truthy(y1 * y2 < 0, "slots must not both pick the same side and collide")
	end)

	t.it("a zero velocity does not produce nan", function()
		local x, y = P.avoid_offset(1, 0, 0, 1.0)
		t.eq(x == x, true, "x must not be nan")
		t.eq(y == y, true, "y must not be nan")
	end)

	t.it("avoid_offset with a non-numeric slot returns numbers and does not throw", function()
		local x, y = P.avoid_offset(nil, 1, 0, 1.0)
		t.eq(type(x) == "number", true, "x must be a number")
		t.eq(type(y) == "number", true, "y must be a number")
	end)

	t.it("avoid_offset(0, ...) and avoid_offset(4, ...) do not return the same side", function()
		local _, y0 = P.avoid_offset(0, 1, 0, 1.0)
		local _, y4 = P.avoid_offset(4, 1, 0, 1.0)
		t.truthy(y0 * y4 < 0, "slot 0 and slot 4 must normalize to odd and even respectively")
	end)

	t.suite("Watcher placement: orbit phase anchoring")

	t.it("a phased orbit starts at exactly the requested bearing, for every slot and time", function()
		local radius = 2.4
		local worst = 0
		for slot = 1, P.SLOTS do
			for step = 0, 20 do
				local time = step * 1.7
				for b = 0, 23 do
					local bearing = -math.pi + (b / 24) * 2 * math.pi
					local phase = P.phase_for_bearing(slot, time, bearing)
					local ox, oy = P.orbit_offset(slot, time, radius, 1.2, phase)
					local produced = math.atan2(oy, ox)
					local delta = math.abs(produced - bearing) % (2 * math.pi)
					if delta > math.pi then
						delta = 2 * math.pi - delta
					end
					if delta > worst then
						worst = delta
					end
				end
			end
		end
		t.near(worst, 0, 0.0001, "the phased orbit must begin on the requested bearing everywhere")
	end)

	t.it("phasing preserves the orbit radius", function()
		local phase = P.phase_for_bearing(2, 9.3, 1.1)
		local ox, oy = P.orbit_offset(2, 9.3, 3.0, 1.2, phase)
		t.near(math.sqrt(ox * ox + oy * oy), 3.0, 0.0001, "the skull must stay on the circle")
	end)

	t.suite("Watcher placement: hover anchoring")

	t.it("facing_for_bearing places the hover spot on exactly the requested bearing", function()
		local worst = 0
		for slot = 1, P.SLOTS do
			for distance_step = 1, 4 do
				local distance = 0.8 + distance_step * 0.6
				for b = 0, 23 do
					local bearing = -math.pi + (b / 24) * 2 * math.pi
					local facing = P.facing_for_bearing(slot, bearing, distance, 0.6)
					local ox, oy = P.hover_offset(slot, math.cos(facing), math.sin(facing),
						distance, 1.2, 0.6)
					local produced = math.atan2(oy, ox)
					local delta = math.abs(produced - bearing) % (2 * math.pi)
					if delta > math.pi then
						delta = 2 * math.pi - delta
					end
					if delta > worst then
						worst = delta
					end
				end
			end
		end
		t.near(worst, 0, 0.0001,
			"the anchored hover spot must land on the bearing the skull already occupies")
	end)

	t.it("the anchored hover spot keeps the full hover distance", function()
		local facing = P.facing_for_bearing(2, 1.1, 1.4, 0.6)
		local ox, oy = P.hover_offset(2, math.cos(facing), math.sin(facing), 1.4, 1.2, 0.6)
		t.near(math.sqrt(ox * ox + oy * oy), 1.4, 0.0001,
			"anchoring must not pull the skull off its hover radius")
	end)

	t.suite("Watcher placement: facing easing")

	t.it("no previous angle adopts the target immediately", function()
		t.eq(P.ease_angle(nil, 1.3, 0.5), 1.3, "the first frame must not ease from nowhere")
	end)

	t.it("easing moves part way, not all the way", function()
		local result = P.ease_angle(0, 1.0, 0.25)
		t.near(result, 0.25, 0.0001, "a quarter step must cover a quarter of the gap")
	end)

	t.it("easing takes the short way around the wrap point", function()
		local just_below = math.pi - 0.1
		local just_above = -math.pi + 0.1
		local result = P.ease_angle(just_below, just_above, 0.5)
		local delta = result - just_below
		t.truthy(delta > 0,
			"crossing from +pi to -pi must continue forwards, not spin the long way back")
		t.truthy(math.abs(delta) < 0.5,
			"the short way is 0.2 radians, so a half step must be about 0.1")
	end)

	t.it("a rate limit caps how far the facing can swing in one frame", function()
		local unlimited = P.ease_angle(0, 3.0, 1.0)
		t.near(unlimited, 3.0, 0.0001, "with no limit it may take the whole gap")
		local limited = P.ease_angle(0, 3.0, 1.0, 0.05)
		t.near(limited, 0.05, 0.0001, "the limit must cap a large forward swing")
		local backward = P.ease_angle(0, -3.0, 1.0, 0.05)
		t.near(backward, -0.05, 0.0001, "and cap it symmetrically going the other way")
	end)

	t.it("a rate limit does not inflate a small step", function()
		local result = P.ease_angle(0, 0.02, 1.0, 0.5)
		t.near(result, 0.02, 0.0001, "a step already inside the limit must be left alone")
	end)

	t.it("easing a full half turn does not pick an arbitrary direction", function()
		local a = P.ease_angle(0, math.pi * 0.9, 0.5)
		t.truthy(a > 0, "a target ahead must ease forwards")
		local b = P.ease_angle(0, -math.pi * 0.9, 0.5)
		t.truthy(b < 0, "a target behind must ease backwards")
	end)

	t.it("an absent phase keeps the original unphased placement", function()
		local ax, ay = P.orbit_offset(3, 4.2, 2.0, 1.2)
		local bx, by = P.orbit_offset(3, 4.2, 2.0, 1.2, nil)
		t.near(ax, bx, 0.0000001, "x must be unchanged when no phase is supplied")
		t.near(ay, by, 0.0000001, "y must be unchanged when no phase is supplied")
	end)
end
