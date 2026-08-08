local engine = require("spec.mock_engine")
local t = require("spec.runner")

local Presence = dofile("./scripts/mods/Servo Mortis/modules/watcher/presence.lua")

local ID_PATTERN = "^[a-z0-9_]+%.[a-z0-9_]+$"
local ID_MIN, ID_MAX = 3, 32

local function validate_id(id)
	if type(id) ~= "string" then
		return nil, "mod id must be a string"
	end
	if #id < ID_MIN or #id > ID_MAX then
		return nil, string.format("mod id %q must be %d to %d characters", id, ID_MIN, ID_MAX)
	end
	if not id:match(ID_PATTERN) then
		return nil, string.format(
			"mod id %q must be author-scoped as author.name (lowercase [a-z0-9_], one dot)", id)
	end
	return true
end

local function fake_member(account_id)
	return {
		account_id = function(self) return self._account_id end,
		_account_id = account_id,
	}
end

local function fake_vox(members, values)
	local objects = {}
	for i = 1, #members do
		objects[i] = fake_member(members[i])
	end
	return {
		version = "2.1.0",
		api = {
			register = function(id) return validate_id(id) end,
			unregister = function() end,
			mark_dirty = function() end,
			members = function() return objects end,
			is_myself = function(m) return m._account_id == "me" end,
			get = function(member) return values[member._account_id] end,
			on_update = function() end,
		},
	}
end

return function()
	t.suite("Watcher presence")

	t.it("Presence.ID is a valid author-scoped id", function()
		t.truthy(Presence.ID:match(ID_PATTERN) ~= nil,
			"must be author-scoped as author.name (lowercase [a-z0-9_], one dot)")
		t.truthy(#Presence.ID >= ID_MIN and #Presence.ID <= ID_MAX,
			"must fall within the library's length bounds")
	end)

	t.it("is unavailable with no Vox Manifold", function()
		Presence._set_vox(nil)
		t.eq(Presence.is_available(), false, "no library, no feature")
	end)

	t.it("is unavailable below major version 2", function()
		Presence._set_vox({ version = "1.0.1", api = {} })
		t.eq(Presence.is_available(), false, "1.x multiplexes consumers and must be rejected")
	end)

	t.it("is available at version 2", function()
		Presence._set_vox(fake_vox({}, {}))
		t.eq(Presence.is_available(), true, "2.x is supported")
	end)

	t.it("publishes nothing when not watching", function()
		Presence._set_vox(fake_vox({}, {}))
		Presence.set_watching(nil)
		t.eq(Presence.build_payload(), nil, "a living player publishes nothing")
	end)

	t.it("republishes only when the watched account actually changes", function()
		local dirty = 0
		local vox = fake_vox({}, {})
		vox.api.mark_dirty = function() dirty = dirty + 1 end
		Presence._set_vox(vox)
		Presence.uninstall()
		Presence._set_vox(vox)
		dirty = 0

		Presence.set_watching("acct-a")
		t.eq(dirty, 1, "a newly watched target must publish")

		Presence.set_watching("acct-a")
		Presence.set_watching("acct-a")
		t.eq(dirty, 1, "holding the same target must not republish every frame")

		Presence.set_watching("acct-b")
		t.eq(dirty, 2, "switching target must publish")

		Presence.set_watching(nil)
		t.eq(dirty, 3, "stopping spectating must publish")

		Presence.set_watching(nil)
		t.eq(dirty, 3, "staying stopped must not republish")

		Presence.uninstall()
	end)

	t.it("the guard does not stop the payload reflecting the current target", function()
		Presence._set_vox(fake_vox({}, {}))
		Presence.uninstall()
		Presence._set_vox(fake_vox({}, {}))

		Presence.set_watching("acct-a")
		Presence.set_watching("acct-a")
		t.eq(Presence.build_payload().w, "acct-a", "the payload must still carry the target")

		Presence.uninstall()
	end)

	t.it("publishes who we are watching", function()
		Presence._set_vox(fake_vox({}, {}))
		Presence.set_watching("acct-target")
		local payload = Presence.build_payload()
		t.truthy(payload, "should produce a payload")
		t.eq(payload.w, "acct-target", "carries the watched account id")
	end)

	t.it("reads remote watchers and excludes myself", function()
		Presence._set_vox(fake_vox({ "me", "them" }, {
			me = { w = "acct-a" },
			them = { w = "acct-b" },
		}))
		local list = Presence.watchers()
		t.eq(#list, 1, "only the remote watcher")
		t.eq(list[1].account_id, "them", "the remote member")
		t.eq(list[1].watching, "acct-b", "and who they watch")
	end)

	t.it("watchers() entries carry a string account_id, not the member object", function()
		Presence._set_vox(fake_vox({ "them" }, { them = { w = "acct-b" } }))
		local list = Presence.watchers()
		for i = 1, #list do
			t.eq(type(list[i].account_id), "string",
				"the runtime sorts and compares account_id, it must never be a table")
		end
	end)

	t.it("ignores a member whose account_id is not a function", function()
		local vox = fake_vox({ "them" }, { them = { w = "acct-b" } })
		local members = vox.api.members()
		members[1].account_id = "not-a-function"
		Presence._set_vox(vox)
		local list = Presence.watchers()
		t.eq(#list, 0, "a malformed member must be skipped, not passed through as a table")
	end)

	t.it("ignores members publishing nothing", function()
		Presence._set_vox(fake_vox({ "them", "other" }, { them = { w = "acct-b" } }))
		local list = Presence.watchers()
		t.eq(#list, 1, "a member with no payload is not a watcher")
	end)

	t.it("returns an empty list when unavailable", function()
		Presence._set_vox(nil)
		local list = Presence.watchers()
		t.eq(#list, 0, "no library means no watchers, not an error")
	end)

	t.it("uninstall unregisters from the library", function()
		local unregistered = nil
		local vox = fake_vox({}, {})
		vox.api.unregister = function(id) unregistered = id end
		Presence._set_vox(vox)
		Presence.uninstall()
		t.eq(unregistered, Presence.ID, "must unregister our own id")
	end)

	t.it("uninstall clears what we were watching", function()
		Presence._set_vox(fake_vox({}, {}))
		Presence.set_watching("acct-target")
		Presence.uninstall()
		t.eq(Presence.build_payload(), nil,
			"a disabled mod must publish nothing, not a stale target")
	end)

	t.it("uninstall with no library does not error", function()
		Presence._set_vox(nil)
		local ok = pcall(Presence.uninstall)
		t.truthy(ok, "must tolerate the library being absent")
	end)

	t.it("install registers with the library and reports success", function()
		local mod = engine.install({})
		local result
		engine.with_globals({
			get_mod = function(name)
				if name == "Vox Manifold" then
					return fake_vox({}, {})
				end
				return nil
			end,
		}, function()
			result = Presence.install(mod)
		end)
		t.eq(result, true, "a valid id must register successfully")
		t.eq(Presence.is_registered(), true, "must record that registration succeeded")
	end)

	t.it("install reports failure when the library rejects the id", function()
		local mod = engine.install({})
		local result
		engine.with_globals({
			get_mod = function(name)
				if name == "Vox Manifold" then
					local vox = fake_vox({}, {})
					vox.api.register = function() return nil, "rejected" end
					return vox
				end
				return nil
			end,
		}, function()
			result = Presence.install(mod)
		end)
		t.eq(result, false, "install must not claim success when the library rejects the id")
		t.eq(Presence.is_registered(), false, "must not believe it is registered")
	end)
end
