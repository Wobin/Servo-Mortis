-- Entrypoint for the Servo Mortis test suite.

package.path = "./?.lua;" .. package.path

local runner = require("spec.runner")

local SPECS = {
	"spec.parse_spec",
	"spec.settings_lint_spec",
	"spec.follow_targets_spec",
	"spec.spectate_controls_spec",
	"spec.camera_mode_spec",
	"spec.camera_tree_spec",
	"spec.spectate_previous_spec",
	"spec.watcher.placement_spec",
	"spec.watcher.presence_spec",
	"spec.watcher.nameplate_spec",
	"spec.watcher.runtime_spec",
	"spec.watcher.skulls_spec",
	"spec.watcher.test_mode_spec",
	"spec.watcher.watching_spec",
}

for _, name in ipairs(SPECS) do
	local ok, spec = pcall(require, name)
	if not ok then
		print("\n!! could not load " .. name .. ": " .. tostring(spec))
		os.exit(1)
	end
	spec()
end

os.exit(runner.report() and 0 or 1)
