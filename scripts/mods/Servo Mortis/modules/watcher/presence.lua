local Presence = {}

Presence.ID = "wobin.servo_mortis"

local vox = nil
local watching = nil
local registered = false

function Presence._set_vox(v)
	vox = v
end

local function major_version(v)
	local major = tostring(v or ""):match("^(%d+)")
	return tonumber(major) or 0
end

function Presence.is_available()
	if not vox or not vox.api then
		return false
	end
	return major_version(vox.version) >= 2
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
	Presence._set_vox(get_mod("Vox Manifold"))
	registered = false
	if not Presence.is_available() then
		return false
	end
	local ok, err = vox.api.register(Presence.ID, mod, Presence.build_payload)
	if not ok then
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

function Presence.watchers()
	local out = {}
	if not Presence.is_available() then
		return out
	end

	local members = vox.api.members() or {}
	for i = 1, #members do
		local member = members[i]
		if type(member) == "table" and type(member.account_id) == "function"
			and not vox.api.is_myself(member) then
			local account = member:account_id()
			if type(account) == "string" then
				local payload = vox.api.get(member, Presence.ID)
				if payload and payload.w then
					out[#out + 1] = { account_id = account, watching = payload.w }
				end
			end
		end
	end

	return out
end

return Presence
