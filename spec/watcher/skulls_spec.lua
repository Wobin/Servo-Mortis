local engine = require("spec.mock_engine")
local t = require("spec.runner")

local Skulls = dofile("./scripts/mods/Servo Mortis/modules/watcher/skulls.lua")

return function()
	t.suite("Watcher skulls")

	t.it("there are two skull models", function()
		t.eq(#Skulls.PATHS, 2, "two variants were chosen")
	end)

	t.it("slots map to models deterministically", function()
		t.eq(Skulls.path_for_slot(1), Skulls.path_for_slot(1), "same slot, same model")
	end)

	t.it("adjacent slots get different models", function()
		t.truthy(Skulls.path_for_slot(1) ~= Skulls.path_for_slot(2),
			"neighbouring watchers should be visually distinct")
	end)

	t.it("every slot maps to a real path", function()
		for slot = 1, 4 do
			local p = Skulls.path_for_slot(slot)
			local found = false
			for _, known in ipairs(Skulls.PATHS) do
				if known == p then found = true end
			end
			t.truthy(found, "slot " .. slot .. " returned an unknown path")
		end
	end)

	t.it("ensure_package returns false while packages are still loading, and logs no error", function()
		engine.reset_packages()
		local mod = engine.install({})
		Skulls.release(mod)
		Skulls._reset_warning()

		local result = Skulls.ensure_package(mod)

		t.eq(result, false, "must not report ready while packages are loading")
		t.eq(#mod._errors, 0, "loading is normal, not an error")
	end)

	t.it("ensure_package returns true once every path reports has_loaded", function()
		engine.reset_packages()
		local mod = engine.install({})
		Skulls.release(mod)
		Skulls._reset_warning()

		Skulls.ensure_package(mod)
		for _, path in ipairs(Skulls.PATHS) do
			engine.finish_package_load(path)
		end

		t.eq(Skulls.ensure_package(mod), true, "every path is resident now")
		t.eq(#mod._errors, 0, "no error on the happy path")
	end)

	t.it("ensure_package requests each package only once across repeated calls, even while loading", function()
		engine.reset_packages()
		local mod = engine.install({})
		Skulls.release(mod)
		Skulls._reset_warning()

		local calls = 0
		local real_load = _G.Managers.package.load
		_G.Managers.package.load = function(self, path, owner)
			calls = calls + 1
			return real_load(self, path, owner)
		end

		Skulls.ensure_package(mod)
		Skulls.ensure_package(mod)
		Skulls.ensure_package(mod)

		_G.Managers.package.load = real_load

		t.eq(calls, #Skulls.PATHS, "each path must be requested exactly once, not once per call")
	end)

	t.it("ensure_package reports exactly one error when a package is neither loaded nor loading after being requested", function()
		engine.reset_packages()
		local mod = engine.install({})
		Skulls.release(mod)
		Skulls._reset_warning()

		local real_has_loaded = _G.Managers.package.has_loaded
		local real_is_loading = _G.Managers.package.is_loading
		_G.Managers.package.has_loaded = function() return false end
		_G.Managers.package.is_loading = function() return false end

		local ok1 = Skulls.ensure_package(mod)
		local ok2 = Skulls.ensure_package(mod)

		_G.Managers.package.has_loaded = real_has_loaded
		_G.Managers.package.is_loading = real_is_loading

		t.eq(ok1, false, "should report failure")
		t.eq(ok2, false, "still failing")
		t.eq(#mod._errors, 1, "must complain once, not once per call")
	end)

	t.it("ensure_package returns false without throwing when Managers.package is missing", function()
		engine.reset_packages()
		local mod = engine.install({})
		Skulls.release(mod)
		Skulls._reset_warning()

		local ok, result = pcall(function()
			local captured
			engine.with_globals({ Managers = {} }, function()
				captured = Skulls.ensure_package(mod)
			end)
			return captured
		end)

		t.truthy(ok, "must not throw when the package manager is missing")
		t.eq(result, false, "missing package manager must return false")
	end)

	t.it("a released path can be requested again afterwards", function()
		engine.reset_packages()
		local mod = engine.install({})
		Skulls.release(mod)
		Skulls._reset_warning()

		Skulls.ensure_package(mod)
		for _, path in ipairs(Skulls.PATHS) do
			engine.finish_package_load(path)
		end
		t.eq(Skulls.ensure_package(mod), true, "sanity: loaded before release")

		Skulls.release(mod)
		Skulls._reset_warning()

		t.eq(Skulls.ensure_package(mod), false, "a released path starts loading again, not resident")
	end)

	t.suite("Watcher skulls: orbit radius")

	local fallback_radius = Skulls.FALLBACK_CAMERA_DISTANCE * Skulls.RADIUS_FRACTION

	t.it("radius_from_distance scales a real distance by the fraction", function()
		t.eq(Skulls.radius_from_distance(5), 3.0, "5 * 0.6 == 3.0")
	end)

	t.it("radius_from_distance falls back on nil, zero and negative input", function()
		t.eq(Skulls.radius_from_distance(nil), fallback_radius, "nil falls back")
		t.eq(Skulls.radius_from_distance(0), fallback_radius, "zero falls back")
		t.eq(Skulls.radius_from_distance(-2), fallback_radius, "negative falls back")
		t.truthy(fallback_radius > 0, "the fallback radius must be positive")
	end)

	t.it("orbit_radius falls back to the fallback radius when no camera is available", function()
		local ok, radius = pcall(Skulls.orbit_radius)
		t.truthy(ok, "orbit_radius must not throw when nothing is available")
		t.eq(radius, fallback_radius, "should land on the fallback radius offline")
	end)

	t.it("measure_camera_distance returns nil rather than throwing when nothing is wired up", function()
		local ok, distance = pcall(Skulls.measure_camera_distance)
		t.truthy(ok, "measure_camera_distance must not throw")
		t.falsy(distance, "no player manager means no measurement")
	end)

	t.it("the resulting radius is always strictly less than the distance it was derived from", function()
		local samples = { 1, 2.9, 4.8, 10, 100 }
		for _, distance in ipairs(samples) do
			local radius = Skulls.radius_from_distance(distance)
			t.truthy(radius < distance,
				"radius " .. radius .. " must stay inside distance " .. distance)
		end
		t.truthy(fallback_radius < Skulls.FALLBACK_CAMERA_DISTANCE,
			"the fallback radius must stay inside the fallback distance too")
	end)
end
