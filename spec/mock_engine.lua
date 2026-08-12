-- Test stubs: no engine loading.

local engine = {}

engine.MOD_ROOT = "."

-- Stub the engine's CLASS registry so modules that hook CLASS.CameraHandler load offline.
_G.CLASS = _G.CLASS or {}
_G.CLASS.CameraHandler = _G.CLASS.CameraHandler or {}
_G.CLASS.PlayerHuskCameraExtension = _G.CLASS.PlayerHuskCameraExtension or {}
_G.CLASS.HudElementWorldMarkers = _G.CLASS.HudElementWorldMarkers or {}
_G.CLASS.HudElementSpectatorText = _G.CLASS.HudElementSpectatorText or {}

-- Stub Managers so CameraMode.live_handler and build_context can work.
_G.Managers = _G.Managers or {}
_G.Managers.player = _G.Managers.player or {
	local_player_safe = function() return nil end,
}
_G.Managers.state = _G.Managers.state or {
	player_unit_spawn = {
		owner = function(_, _) return { is_human_controlled = function() return true end } end,
	},
}

-- Stub globals for build_context checks.
_G.ALIVE = _G.ALIVE or {}

local function noop() end

local last_installed_mod = nil

function engine.install(settings)
	local mod = {
		_settings = settings or {},
		_gets = {},
		_hooks = {},
		_logs = {},
		_errors = {},
		_warnings = {},
		_enabled = true,
	}

	function mod:get(id)
		self._gets[id] = (self._gets[id] or 0) + 1
		return self._settings[id]
	end

	function mod:set(id, value)
		self._settings[id] = value
	end

	function mod:hook(class, method, fn)
		self._hooks[#self._hooks + 1] = { class = class, method = method, fn = fn, kind = "hook" }
	end

	function mod:hook_safe(class, method, fn)
		self._hooks[#self._hooks + 1] = { class = class, method = method, fn = fn, kind = "hook_safe" }
	end

	function mod:info(msg)
		self._logs[#self._logs + 1] = msg
	end

	function mod:error(msg)
		self._logs[#self._logs + 1] = msg
		self._errors[#self._errors + 1] = msg
	end

	function mod:warning(msg)
		self._logs[#self._logs + 1] = msg
		self._warnings[#self._warnings + 1] = msg
	end

	mod.echo = mod.info

	function mod:localize(key)
		return key
	end

	function mod:io_dofile(path)
		local file = path:gsub("^Servo Mortis/", "./") .. ".lua"
		return dofile(file)
	end

	function mod:is_enabled()
		return self._enabled
	end

	function mod:set_enabled(value)
		self._enabled = value
	end

	-- Look up a registered hook so a spec can invoke it directly.
	function mod:find_hook(method)
		for _, h in ipairs(self._hooks) do
			if h.method == method then return h end
		end
		return nil
	end

	last_installed_mod = mod
	return mod
end

-- Stub get_mod so main mod files can load offline.
function _G.get_mod(name)
	if name == "Servo Mortis" then
		return last_installed_mod
	end
	return nil
end

-- A stand-in CameraHandler instance. Only the fields this mod reads or writes.
function engine.make_handler(fields)
	local handler = {
		_first_person_spectating_mode = true,
		_mode = "first_person",
		_camera_follow_unit = nil,
		_side_id = nil, -- unset by default; overrides can't nil a defaulted field
		_player = { player_unit = "self_unit" },
	}
	for k, v in pairs(fields or {}) do
		handler[k] = v
	end
	function handler:is_observing()
		return self._mode == "observer" and self._first_person_spectating_mode
	end
	handler._switch_calls = {}
	function handler:_switch_follow_target(unit)
		self._camera_follow_unit = unit
		self._switch_calls[#self._switch_calls + 1] = unit
	end
	handler._follow_updates = 0
	function handler:_update_follow()
		self._follow_updates = self._follow_updates + 1
	end
	return handler
end

-- A stand-in PlayerHuskCameraExtension. Only the field the camera_tree_node hook reads.
function engine.make_husk_extension(fields)
	local extension = {
		_unit = "husk_unit",
	}
	for k, v in pairs(fields or {}) do
		extension[k] = v
	end
	return extension
end

-- Swaps top-level globals for the duration of fn, always restoring them afterwards.
function engine.with_globals(overrides, fn)
	local saved = {}
	for k, v in pairs(overrides) do
		saved[k] = _G[k]
		_G[k] = v
	end
	local ok, err = pcall(fn)
	for k, v in pairs(saved) do
		_G[k] = v
	end
	if not ok then error(err, 0) end
end

_G.Managers.package = _G.Managers.package or {
	_state = {},
	_next_id = 0,
	load = function(self, path, owner)
		if not self._state[path] then
			self._state[path] = "loading"
		end
		self._next_id = self._next_id + 1
		return { path = path, id = self._next_id, owner = owner }
	end,
	has_loaded = function(self, path)
		return self._state[path] == "loaded"
	end,
	is_loading = function(self, path)
		return self._state[path] == "loading"
	end,
	release = function(self, handle)
		if handle and handle.path then
			self._state[handle.path] = nil
		end
	end,
}

function engine.finish_package_load(path)
	_G.Managers.package._state[path] = "loaded"
end

function engine.reset_packages()
	_G.Managers.package._state = {}
end

_G.Application = _G.Application or {}
_G.Application.can_get_resource = _G.Application.can_get_resource or function(_, path)
	return _G.Managers.package._state[path] == "loaded"
end

_G.Vector3 = _G.Vector3 or setmetatable({}, {
	__call = function(_, x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end,
})
_G.Vector3.distance = _G.Vector3.distance or function(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end
_G.Quaternion = _G.Quaternion or {
	identity = function() return { id = true } end,
	forward = function(_) return _G.Vector3(1, 0, 0) end,
	look = function(direction, up)
		return { look = { x = direction.x, y = direction.y, z = direction.z }, up = up }
	end,
}
_G.Matrix4x4 = _G.Matrix4x4 or {
	from_quaternion_position = function(_, pos) return { pos = pos } end,
}

local unit_positions = {}
_G.Unit = _G.Unit or {}
_G.Unit.alive = _G.Unit.alive or function(u) return u ~= nil and unit_positions[u] ~= nil end
_G.Unit.world_position = _G.Unit.world_position or function(u)
	return unit_positions[u] or _G.Vector3(0, 0, 0)
end
_G.Unit.world_rotation = _G.Unit.world_rotation or function() return { id = true } end
_G.Unit.set_local_position = _G.Unit.set_local_position or function(u, _, pos)
	unit_positions[u] = pos
end

local unit_rotations = {}
_G.Unit.set_local_rotation = _G.Unit.set_local_rotation or function(u, _, rotation)
	unit_rotations[u] = rotation
end

function engine.unit_rotation(unit)
	return unit_rotations[unit]
end

function engine.place_unit(unit, x, y, z)
	unit_positions[unit] = _G.Vector3(x, y, z)
	_G.ALIVE[unit] = 1
	return unit
end

function engine.unit_position(unit)
	return unit_positions[unit]
end

function engine.make_spawner()
	local spawner = { spawned = {}, deleted = {} }
	function spawner:spawn_unit(path, pose)
		local unit = "unit-" .. tostring(#self.spawned + 1)
		self.spawned[#self.spawned + 1] = { unit = unit, path = path }
		unit_positions[unit] = (pose and pose.pos) or _G.Vector3(0, 0, 0)
		_G.ALIVE[unit] = 1
		return unit
	end
	function spawner:mark_for_deletion(unit)
		self.deleted[#self.deleted + 1] = unit
		unit_positions[unit] = nil
		_G.ALIVE[unit] = nil
	end
	return spawner
end

engine.noop = noop

return engine
