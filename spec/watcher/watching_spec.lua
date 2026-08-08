local t = require("spec.runner")

local Watcher = dofile("./scripts/mods/Servo Mortis/modules/watcher/watching.lua")

local ALIVE_UNITS = { alpha = 1, self_unit = 1 }

local function account_of(unit)
	return "acct-" .. tostring(unit)
end

return function()
	t.suite("Watcher watching: watched_account")

	t.it("not in observer mode returns nil", function()
		local account = Watcher.watched_account("first_person", "alpha", "self_unit", ALIVE_UNITS, account_of)
		t.eq(account, nil, "only observer mode can be watching anyone")
	end)

	t.it("observer mode following another unit returns that unit's account", function()
		local account = Watcher.watched_account("observer", "alpha", "self_unit", ALIVE_UNITS, account_of)
		t.eq(account, "acct-alpha", "the working case: watching a teammate")
	end)

	t.it("observer mode following the player's own unit returns nil", function()
		local account = Watcher.watched_account("observer", "self_unit", "self_unit", ALIVE_UNITS, account_of)
		t.eq(account, nil, "downed/hogtied self-follow must never publish as watching yourself")
	end)

	t.it("a followed unit not in ALIVE returns nil", function()
		local account = Watcher.watched_account("observer", "gone", "self_unit", ALIVE_UNITS, account_of)
		t.eq(account, nil, "a dead/despawned followed unit is not a real watch target")
	end)

	t.it("a missing owner or account id returns nil rather than throwing", function()
		local ok, account = pcall(Watcher.watched_account, "observer", "alpha", "self_unit", ALIVE_UNITS,
			function() return nil end)
		t.truthy(ok, "must not throw when account_of cannot resolve an account")
		t.eq(account, nil, "no account means no watcher")
	end)

	t.it("no followed unit returns nil", function()
		local account = Watcher.watched_account("observer", nil, "self_unit", ALIVE_UNITS, account_of)
		t.eq(account, nil, "nothing followed means nothing watched")
	end)

	t.it("a missing alive_lookup returns nil rather than throwing", function()
		local ok, account = pcall(Watcher.watched_account, "observer", "alpha", "self_unit", nil, account_of)
		t.truthy(ok, "must not throw when the alive table itself is absent")
		t.eq(account, nil, "no alive table means no confirmed target")
	end)
end
