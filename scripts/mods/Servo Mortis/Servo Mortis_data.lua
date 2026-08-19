local mod = get_mod("Servo Mortis")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id    = "third_person_spectate",
				type          = "checkbox",
				default_value = true,
				sub_widgets   = {
					{
						setting_id    = "spectate_bots",
						type          = "checkbox",
						default_value = true,
					},
					{
						setting_id    = "skip_downed_targets",
						type          = "checkbox",
						default_value = true,
					},
				},
			},
			{
				setting_id    = "watcher_skulls",
				type          = "checkbox",
				default_value = true,
				sub_widgets   = {
					{
						setting_id      = "nameplate_distance",
						type            = "numeric",
						default_value   = 10,
						range           = { 2, 50 },
						decimals_number = 0,
					},
					{
						setting_id    = "watcher_test_mode",
						type          = "checkbox",
						default_value = false,
					},
				},
			},
		},
	},
}
