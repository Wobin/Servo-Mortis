local engine = require("spec.mock_engine")
local t = require("spec.runner")

local CameraMode = dofile("./scripts/mods/Servo Mortis/modules/camera_mode.lua")

local function settings(third_person)
	return { values = { third_person_spectate = third_person } }
end

local function install_hook(mod, Settings)
	CameraMode.install(mod, Settings)
	return mod:find_hook("camera_tree_node")
end

local function with_player(handler, fn)
	engine.with_globals({
		Managers = { state = _G.Managers.state, player = {
			local_player_safe = function(_) return handler and { camera_handler = handler } or nil end,
		} },
	}, fn)
end

return function()
	t.suite("Camera tree node")

	t.it("install registers the camera_tree_node hook", function()
		local mod = engine.install({})
		local hook = install_hook(mod, settings(true))
		t.truthy(hook, "no camera_tree_node hook registered")
		t.eq(hook.kind, "hook", "must be a wrapping hook, not hook_safe")
	end)

	t.it("while spectating with the mod enabled and the setting on, the tree becomes third person", function()
		local mod = engine.install({})
		local hook = install_hook(mod, settings(true))

		local ext = engine.make_husk_extension({ _unit = "teammate" })
		local handler = engine.make_handler({ _mode = "observer", _camera_follow_unit = "teammate" })

		local object_marker = {}
		local tree, node, object
		with_player(handler, function()
			tree, node, object = hook.fn(function() return "first_person", "first_person", object_marker end, ext)
		end)

		t.eq(tree, "third_person", "tree should switch to third person")
		t.eq(node, "third_person", "node should switch to third person")
		t.truthy(object == object_marker, "object must pass through unchanged")
	end)

	t.it("an already third person replicated tree keeps its own state specific node", function()
		local mod = engine.install({})
		local hook = install_hook(mod, settings(true))

		local ext = engine.make_husk_extension({ _unit = "teammate" })
		local handler = engine.make_handler({ _mode = "observer", _camera_follow_unit = "teammate" })

		local hips = {}
		local tree, node, object
		with_player(handler, function()
			tree, node, object = hook.fn(function() return "third_person", "consumed", hips end, ext)
		end)

		t.eq(tree, "third_person", "tree was already third person")
		t.eq(node, "consumed", "a grabbed teammate keeps their state specific node")
		t.truthy(object == hips, "object must pass through unchanged")
	end)

	t.it("a hogtied teammate keeps their own node rather than the generic one", function()
		local mod = engine.install({})
		local hook = install_hook(mod, settings(true))

		local ext = engine.make_husk_extension({ _unit = "teammate" })
		local handler = engine.make_handler({ _mode = "observer", _camera_follow_unit = "teammate" })

		local node
		with_player(handler, function()
			local _
			_, node = hook.fn(function() return "third_person", "hogtied", nil end, ext)
		end)

		t.eq(node, "hogtied", "must not flatten a state specific node to third_person")
	end)

	t.it("a different followed unit leaves the tree untouched", function()
		local mod = engine.install({})
		local hook = install_hook(mod, settings(true))

		local ext = engine.make_husk_extension({ _unit = "teammate" })
		local handler = engine.make_handler({ _mode = "observer", _camera_follow_unit = "someone_else" })

		local tree, node
		with_player(handler, function()
			tree, node = hook.fn(function() return "first_person", "first_person", nil end, ext)
		end)

		t.eq(tree, "first_person", "should not touch a different unit's tree")
		t.eq(node, "first_person", "should not touch a different unit's node")
	end)

	t.it("outside observer mode the tree is left untouched", function()
		local mod = engine.install({})
		local hook = install_hook(mod, settings(true))

		local ext = engine.make_husk_extension({ _unit = "teammate" })
		local handler = engine.make_handler({ _mode = "first_person", _camera_follow_unit = "teammate" })

		local tree
		with_player(handler, function()
			tree = hook.fn(function() return "first_person", "first_person", nil end, ext)
		end)

		t.eq(tree, "first_person", "must stay first person outside observer mode")
	end)

	t.it("a disabled mod leaves the tree untouched", function()
		local mod = engine.install({})
		local hook = install_hook(mod, settings(true))
		mod:set_enabled(false)

		local ext = engine.make_husk_extension({ _unit = "teammate" })
		local handler = engine.make_handler({ _mode = "observer", _camera_follow_unit = "teammate" })

		local tree
		with_player(handler, function()
			tree = hook.fn(function() return "first_person", "first_person", nil end, ext)
		end)

		t.eq(tree, "first_person", "a disabled mod must not touch the camera tree")
	end)

	t.it("third_person_spectate off leaves the tree untouched", function()
		local mod = engine.install({})
		local hook = install_hook(mod, settings(false))

		local ext = engine.make_husk_extension({ _unit = "teammate" })
		local handler = engine.make_handler({ _mode = "observer", _camera_follow_unit = "teammate" })

		local tree
		with_player(handler, function()
			tree = hook.fn(function() return "first_person", "first_person", nil end, ext)
		end)

		t.eq(tree, "first_person", "third_person_spectate off must leave vanilla behaviour")
	end)

	t.it("no live handler leaves the tree untouched and does not error", function()
		local mod = engine.install({})
		local hook = install_hook(mod, settings(true))

		local ext = engine.make_husk_extension({ _unit = "teammate" })

		local ok, tree
		with_player(nil, function()
			ok, tree = pcall(function()
				return hook.fn(function() return "first_person", "first_person", nil end, ext)
			end)
		end)

		t.truthy(ok, "must not error with no live handler")
		t.eq(tree, "first_person", "must fall back to vanilla with no handler")
	end)

	t.it("install with no CLASS.PlayerHuskCameraExtension records an error and registers no hook", function()
		local mod = engine.install({})
		local saved = _G.CLASS.PlayerHuskCameraExtension
		_G.CLASS.PlayerHuskCameraExtension = nil

		local ok, err = pcall(CameraMode.install, mod, settings(true))

		_G.CLASS.PlayerHuskCameraExtension = saved

		t.truthy(ok, "install itself must not throw: " .. tostring(err))

		local found = false
		for _, e in ipairs(mod._errors) do
			if e:find("PlayerHuskCameraExtension", 1, true) then found = true end
		end
		t.truthy(found, "error should name PlayerHuskCameraExtension")
		t.falsy(mod:find_hook("camera_tree_node"), "no hook should be registered")
	end)
end
