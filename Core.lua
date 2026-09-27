JohnnysRaidRoll = LibStub("AceAddon-3.0"):NewAddon("JohnnysRaidRoll", "AceConsole-3.0")

-- This addon otherwise persists nothing of its own (it drives the classic
-- RaidRoll addon's RaidRoll_DB). JohnnysRaidRollDB is a plain SavedVariable
-- (declared in the .toc) added only for the per-window scale/opacity settings
-- in Modules\RaidRollUI\WindowSettings.lua. Just make sure the table exists.
function JohnnysRaidRoll:OnInitialize()
	JohnnysRaidRollDB = JohnnysRaidRollDB or {}
end
