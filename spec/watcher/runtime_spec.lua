local t = require("spec.runner")
local engine = require("spec.mock_engine")

local Runtime = dofile("./scripts/mods/Servo Mortis/modules/watcher/runtime.lua")

return function()
	t.suite("Watcher runtime: slots")

	t.it("slots are stable regardless of input order", function()
		local a = Runtime.slot_for("bravo", { "alpha", "bravo", "charlie" })
		local b = Runtime.slot_for("bravo", { "charlie", "bravo", "alpha" })
		t.eq(a, b, "sorted derivation must not depend on arrival order")
	end)

	t.it("different watchers get different slots", function()
		local ids = { "alpha", "bravo", "charlie" }
		local seen = {}
		for _, id in ipairs(ids) do
			local slot = Runtime.slot_for(id, ids)
			t.falsy(seen[slot], "slot " .. tostring(slot) .. " was assigned twice")
			seen[slot] = true
		end
	end)

	t.it("an unknown id gets slot 1 rather than nil", function()
		t.eq(Runtime.slot_for("nobody", { "alpha" }), 1, "must never return nil")
	end)

	t.suite("Watcher runtime: reconcile")

	t.it("new watchers are added", function()
		local add, remove = Runtime.reconcile({ "alpha" }, {})
		t.eq(#add, 1, "one to add")
		t.eq(add[1], "alpha", "the new watcher")
		t.eq(#remove, 0, "nothing to remove")
	end)

	t.it("departed watchers are removed", function()
		local add, remove = Runtime.reconcile({}, { alpha = true })
		t.eq(#remove, 1, "one to remove")
		t.eq(remove[1], "alpha", "the departed watcher")
		t.eq(#add, 0, "nothing to add")
	end)

	t.it("unchanged watchers are left alone", function()
		local add, remove = Runtime.reconcile({ "alpha" }, { alpha = true })
		t.eq(#add, 0, "no churn")
		t.eq(#remove, 0, "no churn")
	end)

	t.it("a mixed change adds and removes in one pass", function()
		local add, remove = Runtime.reconcile({ "bravo" }, { alpha = true })
		t.eq(add[1], "bravo", "bravo arrives")
		t.eq(remove[1], "alpha", "alpha leaves")
	end)

	t.it("reconcile tolerates empty input on both sides", function()
		local add, remove = Runtime.reconcile({}, {})
		t.eq(#add, 0, "nothing")
		t.eq(#remove, 0, "nothing")
	end)

	t.suite("Watcher runtime: identity")

	t.it("an unknown account falls back to the id and still returns a colour", function()
		local name, colour = Runtime.identity_for("test-watcher-1", 2)
		t.eq(name, "test-watcher-1", "fall back to the id so test mode has a label")
		t.truthy(colour ~= nil, "must never return a nil colour")
	end)

	t.it("different slots give different fallback colours", function()
		local _, c1 = Runtime.identity_for("unknown-a", 1)
		local _, c2 = Runtime.identity_for("unknown-b", 2)
		t.truthy(c1 ~= c2, "slot must drive the colour so watchers stay distinguishable")
	end)

	t.it("a slot beyond the palette still returns a colour", function()
		local _, colour = Runtime.identity_for("unknown-c", 99)
		t.truthy(colour ~= nil, "must wrap rather than index off the end")
	end)

	t.suite("Watcher runtime: update loop")

	local Placement = dofile("./scripts/mods/Servo Mortis/modules/watcher/placement.lua")

	local function ctx_for(watchers, spawner, marker_log)
		engine.finish_package_load("skull/path")
		return {
			Placement = Placement,
			Skulls = {
				orbit_radius = function() return 2.0 end,
				path_for_slot = function() return "skull/path" end,
				ensure_package = function() return true end,
			},
			Presence = { watchers = function() return watchers end },
			Nameplate = {
				add = function(name) marker_log[#marker_log + 1] = name return #marker_log end,
				remove = function(id) marker_log.removed = id end,
				move = function(_, _)
					marker_log.moves = (marker_log.moves or 0) + 1
					if marker_log.move_fails then
						return false
					end
					return true
				end,
			},
			mod = engine.install({}),
			velocity_for = function() return _G.Vector3(0, 0, 0) end,
			enabled = true,
			time = 0,
			spawner = spawner,
			watchers = watchers,
		}
	end

	t.it("spawns one skull per watcher", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		t.eq(#spawner.spawned, 1, "one watcher, one skull")
	end)

	t.it("does not spawn a second skull on the next frame", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		Runtime.update(0.1, ctx)
		t.eq(#spawner.spawned, 1, "must reuse the existing skull")
	end)

	t.it("moves the skull each frame", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		local first = engine.unit_position(spawner.spawned[1].unit)
		local fx, fy = first.x, first.y
		Runtime.update(0.5, ctx)
		local second = engine.unit_position(spawner.spawned[1].unit)
		t.truthy(math.abs(second.x - fx) > 0.001 or math.abs(second.y - fy) > 0.001,
			"the orbit must advance")
	end)

	t.it("despawns when the watcher leaves", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		ctx.watchers = {}
		Runtime.update(0.1, ctx)
		t.eq(#spawner.deleted, 1, "the skull must be removed")
	end)

	t.it("adds exactly one nameplate per skull", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		Runtime.update(0.1, ctx)
		t.eq(#log, 1, "the marker must not be re-added every frame")
	end)

	t.it("a disabled context despawns everything", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		ctx.enabled = false
		Runtime.update(0.1, ctx)
		t.eq(#spawner.deleted, 1, "disabling must leave nothing behind")
	end)

	t.it("a missing target despawns rather than spawning", function()
		local spawner = engine.make_spawner()
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-gone" } }, spawner, log)
		Runtime._set_unit_lookup(function() return nil end)
		Runtime.update(0.1, ctx)
		t.eq(#spawner.spawned, 0, "no target, no skull")
	end)

	t.it("does not spawn a skull when ensure_package reports the package is not ready", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		ctx.Skulls.ensure_package = function() return false end
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		t.eq(#spawner.spawned, 0,
			"the async package gate must block the spawn, this is what prevents the null-pointer crash")
	end)

	t.it("does not spawn when the unit resource is not obtainable, even if ensure_package says ready", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		ctx.Skulls.path_for_slot = function() return "skull/not-actually-resident" end
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		t.eq(#spawner.spawned, 0,
			"can_get_resource is a second gate on top of ensure_package, not a replacement for it")
	end)

	t.it("resource_ready never throws when Application is missing", function()
		local saved_application = _G.Application
		_G.Application = nil
		local ok, result = pcall(Runtime.resource_ready, "skull/path")
		_G.Application = saved_application
		t.truthy(ok, "must not throw when Application is missing")
		t.eq(result, false, "a missing Application must read as not ready")
	end)

	t.it("moves the marker instead of re-adding it as the skull orbits", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		Runtime.update(0.5, ctx)
		t.eq(#log, 1, "the marker must be created exactly once")
		t.truthy((log.moves or 0) >= 1, "the marker must move in place as the skull orbits")
	end)

	t.suite("Watcher runtime: body height")

	t.it("an ogryn is orbited higher than a human", function()
		local human = Runtime.orbit_height_for(1.65)
		local ogryn = Runtime.orbit_height_for(2.2)
		t.truthy(ogryn > human, "a taller target must be orbited higher")
		t.near(ogryn / human, 2.2 / 1.65, 0.0001, "the lift must scale with body height")
	end)

	t.it("a human keeps the tuned height exactly", function()
		t.near(Runtime.orbit_height_for(1.65), 1.2, 0.0001,
			"the human case must be unchanged by the scaling")
	end)

	t.it("an unknown or absent height falls back to the human height", function()
		t.near(Runtime.orbit_height_for(nil), 1.2, 0.0001, "no breed data must not drop the skull")
		t.near(Runtime.orbit_height_for(0), 1.2, 0.0001, "a zero height must not collapse the orbit")
		t.near(Runtime.orbit_height_for(-3), 1.2, 0.0001, "a negative height must not invert it")
		t.near(Runtime.orbit_height_for("tall"), 1.2, 0.0001, "a non-number must not throw")
	end)

	t.it("the skull actually rides higher on a taller target", function()
		local function height_of(body_height)
			local spawner = engine.make_spawner()
			engine.place_unit("target", 0, 0, 0)
			local log = {}
			local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
			ctx.body_height_for = function() return body_height end
			Runtime._set_unit_lookup(function() return "target" end)
			for _ = 1, 120 do
				Runtime.update(1 / 60, ctx)
			end
			local entry
			for _, e in pairs(ctx.live) do entry = e end
			return entry.pz
		end

		local human = height_of(1.65)
		local ogryn = height_of(2.2)
		t.truthy(ogryn > human + 0.2,
			"the ogryn skull must sit clearly higher: human " .. human .. " ogryn " .. ogryn)
	end)

	t.suite("Watcher runtime: geometry pull-in")

	local BASE = _G.Vector3(0, 0, 0)
	local DESIRED = _G.Vector3(3, 0, 1.2)

	t.it("a clear line allows the full desired distance", function()
		local allowed = Runtime.clear_distance(function() return false, nil end, BASE, DESIRED)
		t.near(allowed, 3, 0.0001, "an unobstructed skull must keep its full reach")
	end)

	t.it("a wall allows only up to one margin short of the impact", function()
		local allowed = Runtime.clear_distance(function() return true, 2.0 end, BASE, DESIRED)
		t.near(allowed, 2.0 - 0.35, 0.0001, "it must stop one margin short of the impact point")
	end)

	t.it("a hit closer than the minimum still leaves the skull off the target", function()
		local allowed = Runtime.clear_distance(function() return true, 0.1 end, BASE, DESIRED)
		t.near(allowed, 0.5, 0.0001, "it must clamp to the minimum, not collapse onto the target")
	end)

	t.it("geometry beyond the skull does not drag it in", function()
		local allowed = Runtime.clear_distance(function() return true, 99 end, BASE, DESIRED)
		t.near(allowed, 3, 0.0001, "a hit past the desired distance must not shorten the reach")
	end)

	t.it("a throwing or absent raycast allows the full distance", function()
		local thrown = Runtime.clear_distance(function() error("no physics world") end, BASE, DESIRED)
		t.near(thrown, 3, 0.0001, "a throwing raycast must not move or crash the skull")
		local absent = Runtime.clear_distance(nil, BASE, DESIRED)
		t.near(absent, 3, 0.0001, "no raycast at all must leave the skull alone")
	end)

	t.it("limit_radius shortens the reach without swinging the bearing", function()
		local far = _G.Vector3(3, 4, 1.2)
		local result = Runtime.limit_radius(BASE, far, 1.0)
		local bearing_before = math.atan2(far.y, far.x)
		local bearing_after = math.atan2(result.y, result.x)
		t.near(bearing_after, bearing_before, 0.0001,
			"limiting must shorten the reach, never swing the skull to a new bearing")
		local dx, dy = result.x, result.y
		local dz = result.z - 1.2
		t.near(math.sqrt(dx * dx + dy * dy + dz * dz), 1.0, 0.0001, "it must sit exactly at the limit")
	end)

	t.it("pulling in is instant but releasing is eased", function()
		local tightened = Runtime.ease_limit(3.0, 0.6, 1 / 60)
		t.near(tightened, 0.6, 0.0001, "a closer wall must take effect immediately, with no easing")

		local released = Runtime.ease_limit(0.6, 3.0, 1 / 60)
		t.truthy(released > 0.6, "the skull must begin moving back out once the wall is gone")
		t.truthy(released < 1.0, "but it must ease out, not snap back to full reach in one frame")
	end)

	t.it("orbiting past a wall never leaves the skull inside it", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)

		ctx.raycast = function(_, _, _, dir_x, _, _, _)
			if dir_x <= 0.5 then
				return false, nil
			end
			return true, 1.0
		end

		local entry
		local worst_penetration = 0
		for _ = 1, 400 do
			Runtime.update(1 / 60, ctx)
			for _, e in pairs(ctx.live) do entry = e end

			local dx, dy = entry.px, entry.py
			local dz = entry.pz - 1.2
			local reach = math.sqrt(dx * dx + dy * dy + dz * dz)
			if reach > 0.0001 then
				local dir_x = dx / reach
				if dir_x > 0.5 then
					local penetration = reach - (1.0 - 0.35)
					if penetration > worst_penetration then
						worst_penetration = penetration
					end
				end
			end
		end

		t.truthy(worst_penetration < 0.05,
			"the skull must never sit past the wall surface: worst overshoot was " .. worst_penetration)
	end)

	t.it("entering follow from a stale facing does not jump the skull", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)

		local x, y = 0, 0
		local vx_cur, vy_cur = 0, 0
		ctx.velocity_for = function() return _G.Vector3(vx_cur, vy_cur, 0) end

		local function walk(vx, vy, frames)
			vx_cur, vy_cur = vx, vy
			for _ = 1, frames do
				x = x + vx * (1 / 60)
				y = y + vy * (1 / 60)
				engine.place_unit("target", x, y, 0)
				Runtime.update(1 / 60, ctx)
			end
		end

		walk(0, 0, 90)

		local entry
		for _, e in pairs(ctx.live) do entry = e end
		t.eq(entry.mode, "orbit", "a stationary target must leave the skull orbiting")

		local bearing = math.atan2(entry.py - y, entry.px - x)
		entry.facing_angle = Placement.facing_for_bearing(entry.slot, bearing + math.pi, 2.0, 0.6)

		local before_x, before_y = entry.px, entry.py
		walk(5, 0, 1)
		local dx, dy = entry.px - before_x, entry.py - before_y
		local step = math.sqrt(dx * dx + dy * dy)

		t.eq(entry.mode, "hover", "moving off must switch the skull into follow mode")
		t.truthy(step < 0.08,
			"entering follow must not jump the skull: step was " .. step)
	end)

	t.it("the skull trails the direction of travel, not the direction the target looks", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)

		ctx.velocity_for = function() return _G.Vector3(4, 0, 0) end
		local saved_forward = _G.Quaternion.forward
		_G.Quaternion.forward = function() return _G.Vector3(0, 1, 0) end

		for _ = 1, 400 do
			Runtime.update(1 / 60, ctx)
		end

		local entry
		for _, e in pairs(ctx.live) do entry = e end
		_G.Quaternion.forward = saved_forward

		t.eq(entry.mode, "hover", "the target is moving, so the skull must be following")
		t.truthy(entry.px < -0.5,
			"travelling along +x must put the skull behind on -x, not beside it")
		t.truthy(math.abs(entry.py) < math.abs(entry.px),
			"the skull must not sit behind the look direction (+y) instead of the travel direction")
	end)

	t.it("the trail direction is held when the target stops rather than snapping", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)

		local moving = true
		ctx.velocity_for = function()
			if moving then
				return _G.Vector3(4, 0, 0)
			end
			return _G.Vector3(0, 0, 0)
		end

		for _ = 1, 400 do
			Runtime.update(1 / 60, ctx)
		end

		local entry
		for _, e in pairs(ctx.live) do entry = e end
		local held = entry.travel_angle
		t.truthy(held, "a moving target must establish a travel direction")

		moving = false
		Runtime.update(1 / 60, ctx)
		t.eq(entry.travel_angle, held,
			"a stationary target must keep the last direction moved, not reset to zero")
	end)

	t.it("a target spinning on the spot does not whip the following skull around", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)

		local heading = 0
		ctx.velocity_for = function()
			return _G.Vector3(4 * math.cos(heading), 4 * math.sin(heading), 0)
		end

		for _ = 1, 60 do
			Runtime.update(1 / 60, ctx)
		end

		local entry
		for _, e in pairs(ctx.live) do entry = e end
		t.eq(entry.mode, "hover", "the target is moving, so the skull must be following")

		local worst_step = 0
		local last_x, last_y = entry.px, entry.py
		for _ = 1, 120 do
			heading = heading + 0.35
			Runtime.update(1 / 60, ctx)
			local dx = entry.px - last_x
			local dy = entry.py - last_y
			local step = math.sqrt(dx * dx + dy * dy)
			if step > worst_step then
				worst_step = step
			end
			last_x, last_y = entry.px, entry.py
		end

		t.truthy(worst_step < 0.10,
			"a spinning target must not whip the skull: worst frame step was " .. worst_step)
	end)

	t.it("the skull turns to face the target it is orbiting", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		for _ = 1, 10 do
			Runtime.update(0.1, ctx)
		end

		local entry
		for _, e in pairs(ctx.live) do entry = e end
		local rotation = engine.unit_rotation(entry.unit)
		t.truthy(rotation and rotation.look, "the skull must be given a look rotation")

		local lx, ly = rotation.look.x, rotation.look.y
		local look_len = math.sqrt(lx * lx + ly * ly)
		t.truthy(look_len > 0.0001, "the look direction must not be degenerate")

		local dx, dy = 0 - entry.px, 0 - entry.py
		local to_target = math.sqrt(dx * dx + dy * dy)
		t.truthy(to_target > 0.0001, "the skull must be offset from the target for this to mean anything")

		local dot = (lx / look_len) * (dx / to_target) + (ly / look_len) * (dy / to_target)
		t.near(dot, 1, 0.001, "the skull must look toward the target, not away from it")
	end)

	t.it("resumes the orbit from where the skull already is when follow mode ends", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)

		local moving = true
		ctx.velocity_for = function()
			if moving then
				return _G.Vector3(4, 0, 0)
			end
			return _G.Vector3(0, 0, 0)
		end

		for _ = 1, 40 do
			Runtime.update(0.1, ctx)
		end

		local entry
		for _, e in pairs(ctx.live) do entry = e end
		t.eq(entry.mode, "hover", "the skull must be in follow mode while the target moves")

		local base_x, base_y = 0, 0
		local before = math.atan2(entry.py - base_y, entry.px - base_x)

		moving = false
		Runtime.update(0.1, ctx)
		t.eq(entry.mode, "orbit", "the skull must return to orbit once the target stops")

		local after = math.atan2(entry.py - base_y, entry.px - base_x)
		local delta = math.abs(after - before) % (2 * math.pi)
		if delta > math.pi then
			delta = 2 * math.pi - delta
		end
		t.near(delta, 0, 0.01,
			"the orbit must resume at the skull's current bearing, not snap across the target")
	end)

	t.it("re-adds the marker when the HUD element has been rebuilt under it", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		t.eq(#log, 1, "the marker is created once up front")

		log.move_fails = true
		Runtime.update(0.1, ctx)
		t.eq(#log, 2, "a marker that no longer exists must be re-added, not moved forever")

		log.move_fails = false
		Runtime.update(0.1, ctx)
		t.eq(#log, 2, "once the marker is back it is moved, not re-added")
	end)

	t.suite("Watcher runtime: slot assignment")

	t.it("an existing entry's slot is refreshed every frame, not frozen at spawn", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		t.eq(ctx.live.alpha.slot, 1, "alpha alone takes slot 1")

		ctx.watchers = {
			{ account_id = "aaron", watching = "acct-target" },
			{ account_id = "alpha", watching = "acct-target" },
		}
		Runtime.update(0.1, ctx)

		t.eq(ctx.live.aaron.slot, 1, "aaron sorts first and takes slot 1")
		t.eq(ctx.live.alpha.slot, 2, "alpha must be recomputed to slot 2, not left frozen at 1")
	end)

	t.it("two live watchers never share a slot after membership churns", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)

		ctx.watchers = {
			{ account_id = "aaron", watching = "acct-target" },
			{ account_id = "alpha", watching = "acct-target" },
		}
		Runtime.update(0.1, ctx)

		t.truthy(ctx.live.aaron.slot ~= ctx.live.alpha.slot,
			"a stale frozen slot must never collide with a live watcher's current slot")
	end)

	t.it("a watcher's own player slot is used when a player object can be resolved", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)

		local saved_player = _G.Managers.player
		_G.Managers.player = {
			players = function()
				return {
					{ account_id = function() return "alpha" end, slot = function() return 3 end },
				}
			end,
		}

		Runtime.update(0.1, ctx)

		_G.Managers.player = saved_player

		t.eq(ctx.live.alpha.slot, 3, "the player's own slot must be used so every client agrees")
	end)

	t.it("falls back to sorted-index derivation when no player object can be resolved", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "test-watcher-1", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		t.eq(ctx.live["test-watcher-1"].slot,
			Runtime.slot_for("test-watcher-1", { "test-watcher-1" }),
			"with no player object, slot_for's sorted derivation is still the fallback")
	end)

	t.suite("Watcher runtime: dodge avoidance reachability")

	t.it("sustained closing velocity toward a lagging skull triggers avoidance", function()
		local RealPlacement = Placement
		local closing_results = {}
		local avoid_results = {}
		local SpyPlacement = {}
		for k, v in pairs(RealPlacement) do
			SpyPlacement[k] = v
		end
		SpyPlacement.is_closing = function(...)
			local result = RealPlacement.is_closing(...)
			closing_results[#closing_results + 1] = result
			return result
		end
		SpyPlacement.avoid_offset = function(...)
			local ax, ay = RealPlacement.avoid_offset(...)
			avoid_results[#avoid_results + 1] = { ax, ay }
			return ax, ay
		end

		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		ctx.Placement = SpyPlacement
		Runtime._set_unit_lookup(function() return "target" end)

		local x, y = 0, 0
		local vx_cur, vy_cur = 4, 0
		ctx.velocity_for = function() return _G.Vector3(vx_cur, vy_cur, 0) end

		local function walk(vx, vy, frames)
			vx_cur, vy_cur = vx, vy
			for _ = 1, frames do
				x = x + vx * (1 / 60)
				y = y + vy * (1 / 60)
				engine.place_unit("target", x, y, 0)
				Runtime.update(1 / 60, ctx)
			end
		end

		walk(4, 0, 120)

		local entry
		for _, e in pairs(ctx.live) do entry = e end
		local to_x, to_y = entry.px - x, entry.py - y
		local reach = math.sqrt(to_x * to_x + to_y * to_y)

		closing_results = {}
		avoid_results = {}

		walk(9 * to_x / reach, 9 * to_y / reach, 20)

		local triggered = false
		for i = 1, #closing_results do
			if closing_results[i] == true then
				triggered = true
			end
		end
		t.truthy(triggered,
			"sustained closing velocity toward a lagging skull must eventually read as a dodge")

		local displaced = false
		for i = 1, #avoid_results do
			if math.abs(avoid_results[i][2]) > 0.3 then
				displaced = true
			end
		end
		t.truthy(displaced, "the resulting target must be displaced laterally once avoidance runs")
	end)

	t.it("stores the entry's position as numeric components, never a retained Vector3", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)

		local entry = ctx.live.alpha
		t.eq(type(entry.px), "number", "px must be a plain number, not a frame-local Vector3 field")
		t.eq(type(entry.py), "number", "py must be a plain number, not a frame-local Vector3 field")
		t.eq(type(entry.pz), "number", "pz must be a plain number, not a frame-local Vector3 field")
		t.falsy(entry.position, "entry.position must not exist; a retained Vector3 reads a recycled slot next frame")
	end)

	t.it("the skull does not snap straight to the nominal offset on the first frame", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)

		local pos = engine.unit_position(spawner.spawned[1].unit)
		local dist = math.sqrt(pos.x * pos.x + pos.y * pos.y)
		t.truthy(dist < 2.0 - 0.01,
			"a snapped skull would sit exactly at the orbit radius; a lagging one must not yet")
	end)

	t.suite("Watcher runtime: mission-end teardown")

	t.it("purges every live entry when the spawner disappears", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(0.1, ctx)
		t.eq(#spawner.spawned, 1, "sanity: the skull spawned")

		ctx.spawner = nil
		Runtime.update(0.1, ctx)

		t.eq(#spawner.deleted, 1,
			"a stale unit handle must not survive to alias a recycled unit next mission")
		t.eq(log.removed, 1, "the marker must be removed too")
	end)

	t.it("does not error when the spawner disappears with nothing live", function()
		local spawner = engine.make_spawner()
		local log = {}
		local ctx = ctx_for({}, spawner, log)
		ctx.spawner = nil
		local ok = pcall(Runtime.update, 0.1, ctx)
		t.truthy(ok, "must not throw with an empty live table and no spawner")
	end)

	t.suite("Watcher runtime: test mode target resolution")

	t.it("a fake test-mode watcher survives to a spawn even when the bot has no account id", function()
		local Test = dofile("./scripts/mods/Servo Mortis/modules/watcher/test_mode.lua")
		local spawner = engine.make_spawner()
		engine.place_unit("bot-unit", 1, 2, 3)
		local log = {}
		local fake_watchers = { { account_id = "Vorn-42", watching = Test.TARGET_ID } }
		local ctx = ctx_for(fake_watchers, spawner, log)
		Runtime._set_unit_lookup(function(id)
			if id == Test.TARGET_ID then
				return "bot-unit"
			end
			return nil
		end)
		Runtime.update(0.1, ctx)
		t.eq(#spawner.spawned, 1, "a synthetic test target with no account id must still produce a skull")
	end)

	t.suite("Watcher runtime: Skulls interface")

	t.it("the real Skulls module matches the interface this runtime expects", function()
		local RealSkulls = dofile("./scripts/mods/Servo Mortis/modules/watcher/skulls.lua")
		t.eq(type(RealSkulls.orbit_radius), "function",
			"orbit_radius must be a function, not a cached field")
		t.falsy(RealSkulls.ORBIT_RADIUS,
			"ORBIT_RADIUS must not exist as a static field, callers must call orbit_radius()")
	end)

	t.suite("Watcher runtime: failed teardown")

	local function hostile_spawner()
		return {
			spawned = {},
			deleted = {},
			spawn_unit = function(self, path) return "unit" end,
			mark_for_deletion = function() error("unit already gone") end,
		}
	end

	t.it("a skull that will not delete is retried rather than forgotten", function()
		local live = { alpha = { unit = "skull", spawner = hostile_spawner() } }
		engine.place_unit("skull", 0, 0, 0)
		local Nameplate = { remove = function() end }

		local ok = Runtime.despawn(live, "alpha", Nameplate)

		t.falsy(ok, "a failed deletion must report failure")
		t.truthy(live.alpha, "the entry must be kept so a later pass can try again")
		t.eq(live.alpha.delete_attempts, 1, "the attempt must be counted")
	end)

	t.it("it gives up after a bounded number of attempts rather than retrying forever", function()
		local live = { alpha = { unit = "skull", spawner = hostile_spawner() } }
		engine.place_unit("skull", 0, 0, 0)
		local Nameplate = { remove = function() end }

		local attempts = 0
		local result
		repeat
			attempts = attempts + 1
			result = Runtime.despawn(live, "alpha", Nameplate)
		until result or attempts > 10

		t.truthy(result, "it must eventually stop retrying")
		t.eq(attempts, Runtime.MAX_DELETE_ATTEMPTS, "and stop at the documented bound")
		t.falsy(live.alpha, "the entry is finally released")
	end)

	t.it("giving up is reported rather than silent", function()
		local seen = {}
		Runtime._set_reporter(function(message) seen[#seen + 1] = message end)

		local live = { alpha = { unit = "skull", spawner = hostile_spawner() } }
		engine.place_unit("skull", 0, 0, 0)
		local Nameplate = { remove = function() end }
		for _ = 1, Runtime.MAX_DELETE_ATTEMPTS do
			Runtime.despawn(live, "alpha", Nameplate)
		end

		Runtime._set_reporter(nil)

		t.eq(#seen, 1, "a leaked skull must be reported exactly once")
		t.truthy(seen[1]:find("remain in the level", 1, true),
			"the report must say what the consequence is")
	end)

	t.it("a successful teardown reports nothing and releases the entry", function()
		local seen = {}
		Runtime._set_reporter(function(message) seen[#seen + 1] = message end)

		local spawner = engine.make_spawner()
		engine.place_unit("skull", 0, 0, 0)
		local live = { alpha = { unit = "skull", spawner = spawner } }
		local ok = Runtime.despawn(live, "alpha", { remove = function() end })

		Runtime._set_reporter(nil)

		t.truthy(ok, "a clean teardown succeeds")
		t.falsy(live.alpha, "and releases the entry")
		t.eq(#seen, 0, "with nothing reported")
	end)

	t.it("the same failure is only reported once, not every frame", function()
		local seen = {}
		Runtime._set_reporter(function(message) seen[#seen + 1] = message end)
		Runtime.report("identical message")
		Runtime.report("identical message")
		Runtime.report("identical message")
		Runtime._set_reporter(nil)
		t.eq(#seen, 1, "repeating a report every frame would drown the log")
	end)

	t.it("a revived entry does not carry a stale delete count", function()
		local spawner = engine.make_spawner()
		engine.place_unit("target", 0, 0, 0)
		local log = {}
		local ctx = ctx_for({ { account_id = "alpha", watching = "acct-target" } }, spawner, log)
		Runtime._set_unit_lookup(function() return "target" end)
		Runtime.update(1 / 60, ctx)

		local entry
		for _, e in pairs(ctx.live) do entry = e end
		entry.delete_attempts = Runtime.MAX_DELETE_ATTEMPTS - 1

		Runtime.update(1 / 60, ctx)

		t.falsy(entry.delete_attempts,
			"an entry still in use must start its next teardown with a full retry budget")
	end)

	t.suite("Watcher runtime: orbit radius is per target")

	t.it("a skull keeps its distance when you switch who YOU are spectating", function()
		-- camera measured against an ogryn, then against a human: the ogryn's skull must not move
		local from_ogryn = Runtime.radius_for(3.0, 2.2, 2.2)
		local from_human = Runtime.radius_for(2.25, 1.65, 2.2)
		t.near(from_ogryn, from_human, 0.0001,
			"the same ogryn target must orbit at the same radius regardless of who you spectate")
	end)

	t.it("a bigger target is orbited wider", function()
		local human = Runtime.radius_for(2.0, 1.65, 1.65)
		local ogryn = Runtime.radius_for(2.0, 1.65, 2.2)
		t.truthy(ogryn > human, "an ogryn needs a wider orbit than a human")
		t.near(ogryn / human, 2.2 / 1.65, 0.0001, "and it must scale with body height")
	end)

	t.it("measuring against a human leaves a human target unchanged", function()
		t.near(Runtime.radius_for(2.0, 1.65, 1.65), 2.0, 0.0001,
			"the common case must pass the camera derived radius straight through")
	end)

	t.it("unknown heights fall back to human rather than collapsing the orbit", function()
		t.near(Runtime.radius_for(2.0, nil, nil), 2.0, 0.0001, "no breed data must not move the skull")
		t.near(Runtime.radius_for(2.0, 0, 0), 2.0, 0.0001, "zero heights must not divide by zero")
		t.near(Runtime.radius_for(2.0, "tall", "short"), 2.0, 0.0001, "non numbers must not throw")
	end)

	t.it("a nil or zero base radius is passed through untouched", function()
		t.eq(Runtime.radius_for(nil, 1.65, 2.2), nil, "nothing to scale")
		t.eq(Runtime.radius_for(0, 1.65, 2.2), 0, "zero stays zero")
	end)

	t.it("two skulls on differently sized targets get different radii in one frame", function()
		local spawner = engine.make_spawner()
		engine.place_unit("ogryn", 0, 0, 0)
		engine.place_unit("human", 20, 0, 0)
		local log = {}
		local watchers = {
			{ account_id = "a", watching = "acct-ogryn" },
			{ account_id = "b", watching = "acct-human" },
		}
		local ctx = ctx_for(watchers, spawner, log)
		ctx.body_height_for = function(u) return u == "ogryn" and 2.2 or 1.65 end
		Runtime._set_unit_lookup(function(w)
			return w == "acct-ogryn" and "ogryn" or "human"
		end)

		for _ = 1, 120 do
			Runtime.update(1 / 60, ctx)
		end

		local reach = {}
		for _, e in pairs(ctx.live) do
			local base = e.watching == "acct-ogryn" and 0 or 20
			local dx, dy = e.px - base, e.py
			reach[e.watching] = math.sqrt(dx * dx + dy * dy)
		end

		t.truthy(reach["acct-ogryn"] and reach["acct-human"], "both skulls must be placed")
		t.truthy(reach["acct-ogryn"] > reach["acct-human"],
			"the ogryn's skull must sit wider than the human's in the same frame")
	end)
end
