local Presence = {}

Presence.ID = "wobin.servo_mortis"

local vox = nil
local vox_available = false
local watching = nil
local registered = false

local function major_version(v)
	local major = tostring(v or ""):match("^(%d+)")
	return tonumber(major) or 0
end

local function compute_available(m)
	if not m or not m.api then
		return false
	end
	return major_version(m.version) >= 2
end

function Presence._set_vox(v)
	vox = v
	vox_available = compute_available(v)
end

local function resolve_vox()
	if get_mod then
		local current = get_mod("Vox Manifold")
		if current ~= nil and current ~= vox then
			Presence._set_vox(current)
		end
	end

	return vox
end

function Presence.is_available()
	resolve_vox()
	return vox_available
end

function Presence.set_watching(account_id)
	if account_id == watching then
		return
	end

	watching = account_id

	if Presence.is_available() and vox.api.mark_dirty then
		pcall(vox.api.mark_dirty, Presence.ID)
	end
end

function Presence.build_payload()
	if not watching then
		return nil
	end
	return { w = watching }
end

function Presence.is_registered()
	return registered
end

function Presence.install(mod)
	Presence._set_vox(get_mod and get_mod("Vox Manifold") or nil)
	registered = false
	if not Presence.is_available() then
		return false
	end

	local called, result, err = pcall(vox.api.register, Presence.ID, mod, Presence.build_payload)
	if not called then
		err = result
		result = false
	end

	if not result then
		if mod and mod.error then
			pcall(function() mod:error("Servo Mortis: presence registration failed: " .. tostring(err)) end)
		end
		return false
	end

	registered = true
	return true
end

function Presence.uninstall()
	watching = nil
	registered = false
	if not Presence.is_available() then
		return
	end
	if vox.api.unregister then
		pcall(vox.api.unregister, Presence.ID)
	end
end

local watchers_list = {}
local watchers_pool = {}

local function pooled_entry(index)
	local entry = watchers_pool[index]
	if not entry then
		entry = {}
		watchers_pool[index] = entry
	end

	return entry
end

function Presence.watchers()
	local out = watchers_list
	local count = 0

	if Presence.is_available() then
		local members = vox.api.members() or {}
		for i = 1, #members do
			local member = members[i]
			if type(member) == "table" and type(member.account_id) == "function"
				and not vox.api.is_myself(member) then
				local account = member:account_id()
				if type(account) == "string" then
					local payload = vox.api.get(member, Presence.ID)
					if payload and payload.w then
						count = count + 1
						local entry = pooled_entry(count)
						entry.account_id = account
						entry.watching = payload.w
						out[count] = entry
					end
				end
			end
		end
	end

	for i = #out, count + 1, -1 do
		out[i] = nil
	end

	return out
end

return Presence
