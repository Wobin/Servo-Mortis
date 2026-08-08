local Watcher = {}

function Watcher.watched_account(mode, followed_unit, own_unit, alive_lookup, account_of)
	if mode ~= "observer" then
		return nil
	end

	if not followed_unit then
		return nil
	end

	if followed_unit == own_unit then
		return nil
	end

	if not alive_lookup or not alive_lookup[followed_unit] then
		return nil
	end

	if not account_of then
		return nil
	end

	return account_of(followed_unit)
end

return Watcher
