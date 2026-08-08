local t = require("spec.runner")

local Test = dofile("./scripts/mods/Servo Mortis/modules/watcher/test_mode.lua")

local function sequence(values)
	local i = 0
	return function()
		i = i + 1
		return values[((i - 1) % #values) + 1]
	end
end

local function stub_ids(body)
	local saved = Test.target_id_for
	Test.target_id_for = function(unit) return unit and ("id:" .. tostring(unit)) or nil end
	local ok, err = pcall(body)
	Test.target_id_for = saved
	Test.reset()
	if not ok then
		error(err, 0)
	end
end

return function()
	t.suite("Watcher test mode: watchers")

	t.it("creates exactly two skulls", function()
		Test.reset()
		local list = Test.ensure_watchers(sequence({ 1, 20, 2, 30 }))
		t.eq(#list, Test.SKULL_COUNT, "test mode simulates two watchers")
		t.eq(Test.SKULL_COUNT, 2, "and that count is two")
		Test.reset()
	end)

	t.it("gives each skull a distinct name", function()
		Test.reset()
		local list = Test.ensure_watchers(sequence({ 1, 20, 2, 30 }))
		t.truthy(list[1].account_id ~= list[2].account_id,
			"two watchers sharing a name would collapse into one skull")
		Test.reset()
	end)

	t.it("keeps the same names across frames", function()
		Test.reset()
		local first = Test.ensure_watchers(sequence({ 1, 20, 2, 30 }))
		local names = { first[1].account_id, first[2].account_id }
		local again = Test.ensure_watchers(sequence({ 5, 55, 6, 66 }))
		t.eq(again[1].account_id, names[1], "a skull's name must not flicker every frame")
		t.eq(again[2].account_id, names[2], "nor the second's")
		Test.reset()
	end)

	t.it("names are drawn from the pool and carry a suffix", function()
		local name = Test.random_name(sequence({ 1, 42 }))
		t.eq(name, Test.NAMES[1] .. "-42", "a name is a pool entry plus a number")
	end)

	t.suite("Watcher test mode: target rotation")

	t.it("assigns a target as soon as it starts", function()
		stub_ids(function()
			Test.reset()
			local list = Test.update(0, { "a", "b", "c" }, sequence({ 1 }))
			t.truthy(list[1].watching, "the first skull must have a target immediately")
			t.truthy(list[2].watching, "and so must the second")
		end)
	end)

	t.it("puts the two skulls on different targets when it can", function()
		stub_ids(function()
			Test.reset()
			local list = Test.update(0, { "a", "b", "c" }, sequence({ 1 }))
			t.truthy(list[1].watching ~= list[2].watching,
				"with several targets available the skulls must spread out")
		end)
	end)

	t.it("holds its targets until the interval elapses", function()
		stub_ids(function()
			Test.reset()
			local list = Test.update(0, { "a", "b", "c" }, sequence({ 1 }))
			local first, second = list[1].watching, list[2].watching

			for _ = 1, 9 do
				Test.update(1.0, { "a", "b", "c" }, sequence({ 2 }))
			end

			t.eq(list[1].watching, first, "targets must be stable inside the interval")
			t.eq(list[2].watching, second, "including the second skull")
		end)
	end)

	t.it("moves to new targets once ten seconds have passed", function()
		stub_ids(function()
			Test.reset()
			local list = Test.update(0, { "a", "b", "c" }, sequence({ 1 }))
			local first = list[1].watching

			for _ = 1, 10 do
				Test.update(1.0, { "a", "b", "c" }, sequence({ 2 }))
			end

			t.truthy(list[1].watching ~= first,
				"after the interval the skull must have moved to another player")
		end)
	end)

	t.it("the interval is ten seconds", function()
		t.eq(Test.ROTATE_SECONDS, 10.0, "the brief asks for a move every ten seconds")
	end)

	t.it("a single available target is shared rather than dropped", function()
		stub_ids(function()
			Test.reset()
			local list = Test.update(0, { "only" }, sequence({ 1 }))
			t.eq(list[1].watching, "id:only", "the first skull takes the only target")
			t.eq(list[2].watching, "id:only", "and the second shares it")
		end)
	end)

	t.it("no available targets clears the watching state rather than erroring", function()
		stub_ids(function()
			Test.reset()
			local ok, list = pcall(Test.update, 0, {}, sequence({ 1 }))
			t.truthy(ok, "an empty level must not throw")
			t.falsy(list[1].watching, "with nobody to watch, the skull watches nothing")
		end)
	end)

	t.it("reset clears names and timing so a new session starts fresh", function()
		stub_ids(function()
			Test.reset()
			local before = Test.update(0, { "a", "b" }, sequence({ 1 }))[1].account_id
			Test.reset()
			local after = Test.update(0, { "a", "b" }, sequence({ 3, 77, 4, 88 }))[1].account_id
			t.truthy(before ~= after, "a fresh session must re-roll the simulated watchers")
		end)
	end)

	t.suite("Watcher test mode: target identity")

	t.it("each target gets its own id so a switch is visible to the runtime", function()
		local owners = {
			unit_a = { unique_id = function() return "host:2:2" end },
			unit_b = { unique_id = function() return "host:3:3" end },
		}
		local saved = _G.Managers.state.player_unit_spawn
		_G.Managers.state.player_unit_spawn = {
			owner = function(_, unit) return owners[unit] end,
		}

		local a = Test.target_id_for("unit_a")
		local b = Test.target_id_for("unit_b")
		local a_again = Test.target_id_for("unit_a")
		local none = Test.target_id_for(nil)
		local unowned = Test.target_id_for("unit_c")

		_G.Managers.state.player_unit_spawn = saved

		t.truthy(a, "a real unit must produce an id")
		t.truthy(a ~= b, "two targets must not share an id, or a switch looks like no change")
		t.eq(a_again, a, "the id for one unit must be stable across frames")
		t.falsy(none, "no unit means no id")
		t.falsy(unowned, "a unit with no owning player must not produce an id")
	end)

	t.it("the target id does not rely on tostring(unit), which is not unique", function()
		local owners = {
			unit_a = { unique_id = function() return "host:2:2" end },
			unit_b = { unique_id = function() return "host:3:3" end },
		}
		local saved = _G.Managers.state.player_unit_spawn
		_G.Managers.state.player_unit_spawn = {
			owner = function(_, unit) return owners[unit] end,
		}
		local a = Test.target_id_for("unit_a")
		local b = Test.target_id_for("unit_b")
		_G.Managers.state.player_unit_spawn = saved

		t.truthy(a:find("2:2", 1, true) ~= nil, "the id must carry the owning player's identity")
		t.truthy(b:find("3:3", 1, true) ~= nil, "and it must differ per player")
	end)

	t.suite("Watcher test mode: target selection")

	t.it("returns nothing rather than throwing when no managers exist", function()
		local saved = _G.Managers
		_G.Managers = nil
		local ok, units = pcall(Test.alive_target_units)
		_G.Managers = saved
		t.truthy(ok, "must not throw when Managers is absent")
		t.eq(#units, 0, "no managers means no targets")
	end)

	t.it("returns nothing rather than throwing with the offline stubs", function()
		local ok, units = pcall(Test.alive_target_units)
		t.truthy(ok, "must not throw with the default offline stubs")
		t.eq(#units, 0, "the offline stubs have no side system, so no targets are found")
	end)
end
