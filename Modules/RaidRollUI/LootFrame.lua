-- Shell for the standalone "Raid Loot" window - the Loot tab's content
-- (RaidRollUI.BuildLootTab, in LootWindow.lua) shown in its own frame instead
-- of as a tab alongside Rolls, so the two can be moved/opened independently.
-- Settings stays owned by the Rolls window (Init.lua); this just gets a
-- shortcut button that jumps there via RaidRollUI:ShowSettings() rather than
-- duplicating the settings UI in a second place.
JohnnysRaidRoll.RaidLootUI = JohnnysRaidRoll.RaidLootUI or {}
local RaidLootUI = JohnnysRaidRoll.RaidLootUI
local RaidRollUI = JohnnysRaidRoll.RaidRollUI
local Skin = JohnnysRaidRoll.Skin

local FRAME_WIDTH, FRAME_HEIGHT = 640, 480

local mainFrame, refreshTicker, content

local function BuildFrame()
	mainFrame = CreateFrame("Frame", "JohnnysAddonHubRaidLootFrame", UIParent)
	mainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
	mainFrame:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
	mainFrame:SetFrameStrata("DIALOG")
	mainFrame:SetMovable(true)
	mainFrame:EnableMouse(true)
	mainFrame:RegisterForDrag("LeftButton")
	mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
	mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
	Skin:StylePanel(mainFrame, 0.95)
	mainFrame:Hide()

	-- Per-window scale/opacity (see Modules\RaidRollUI\WindowSettings.lua).
	-- Guarded so a stale .toc (client not fully restarted after the file was
	-- added) just skips the feature instead of erroring the whole window.
	if JohnnysRaidRoll.WindowSettings then
		JohnnysRaidRoll.WindowSettings:Register(mainFrame, "loot", "Raid Loot")
	end

	Skin:AddHeader(mainFrame, "Raid Loot")

	local close = Skin:CreateButton(mainFrame, 20, 20, "X")
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() RaidLootUI:Toggle() end)

	if JohnnysRaidRoll.WindowSettings then
		JohnnysRaidRoll.WindowSettings:AttachButton(mainFrame)
	end

	local settingsBtn = Skin:CreateButton(mainFrame, 70, 20, "Settings")
	-- Title is top-left now, so these two sit left of the Cfg button.
	settingsBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -166, -4)
	settingsBtn:SetScript("OnClick", function()
		if RaidRollUI and RaidRollUI.ShowSettings then
			RaidRollUI:ShowSettings()
		end
	end)

	-- Opens RaidRoll's own native "Main Specs" window (RR_CHATCLAIMS_FRAME,
	-- RaidRoll_ChatClaims.lua) via its slash-command dispatcher, same as the
	-- Rolls window's row-mark buttons call RR_Command("mark "..i) - that
	-- window isn't neutralized by Hook.lua (only RR_RollFrame/RR_LOOT_FRAME
	-- are), so it renders normally without needing a themed replacement here.
	local claimsBtn = Skin:CreateButton(mainFrame, 90, 20, "Main Specs")
	claimsBtn:SetPoint("LEFT", settingsBtn, "RIGHT", 4, 0)
	claimsBtn:SetScript("OnClick", function()
		if RR_Command then
			RR_Command("claims")
		end
	end)

	content = CreateFrame("Frame", nil, mainFrame)
	content:SetPoint("TOPLEFT", 16, -40)
	content:SetPoint("BOTTOMRIGHT", -16, 16)

	local tab = RaidRollUI.BuildLootTab(content)

	refreshTicker = CreateFrame("Frame")
	refreshTicker:Hide()
	local elapsed = 0
	refreshTicker:SetScript("OnUpdate", function(self, e)
		elapsed = elapsed + e
		if elapsed >= 1.5 then
			elapsed = 0
			tab.Refresh()
		end
	end)

	mainFrame:SetScript("OnShow", function()
		tab.Refresh()
		refreshTicker:Show()
	end)
	mainFrame:SetScript("OnHide", function()
		refreshTicker:Hide()
	end)
end

local function EnsureFrame()
	if RaidRollUI and RaidRollUI.EnsureHooked then
		RaidRollUI.EnsureHooked()
	end

	if not RR_RollFrame or type(RR_Command) ~= "function" then
		return false
	end

	if not mainFrame then
		BuildFrame()
	end

	return true
end

-- Open-only (never closes an already-open window) - Hook.lua's auto-open-on-
-- new-loot check calls this instead of Toggle(), since RaidRoll's own
-- "RR_AutoOpenLootWindow" auto-open (RaidRoll_LootTracker.lua:391/538) is
-- silenced along with the rest of RR_LOOT_FRAME by ForceHide() in Hook.lua,
-- and nothing previously replaced it for our own replacement window.
function RaidLootUI:Show()
	if not EnsureFrame() then
		return
	end
	if not mainFrame:IsShown() then
		mainFrame:Show()
	end
end

function RaidLootUI:Toggle()
	if not EnsureFrame() then
		JohnnysRaidRoll:Print("RaidRoll addon not found - can't open Raid Loot.")
		return
	end

	if mainFrame:IsShown() then
		mainFrame:Hide()
	else
		mainFrame:Show()
	end
end
