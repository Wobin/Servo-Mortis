return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Servo Mortis` encountered an error loading the Darktide Mod Framework.")

		new_mod("Servo Mortis", {
			mod_script       = "Servo Mortis/scripts/mods/Servo Mortis/Servo Mortis",
			mod_data         = "Servo Mortis/scripts/mods/Servo Mortis/Servo Mortis_data",
			mod_localization = "Servo Mortis/scripts/mods/Servo Mortis/Servo Mortis_localization",
		})
	end,
	version = "1.0.0",
	packages = {},
}
