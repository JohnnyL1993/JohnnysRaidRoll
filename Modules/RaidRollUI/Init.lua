-- Shell for the "Raid Roll" window: title bar, close button, a Rolls/Settings
-- tab strip (same flat black/white skin as every other module here), and one
-- shared poll ticker that refreshes whichever tab is currently active.
-- RaidRoll's data updates via chat/loot events regardless of whether this
-- window is open, so - same reasoning as RaidBrowserUI - this polls while
-- shown instead of hooking into RaidRoll's internals.
--
-- Loot tracking lives in its own separate window (LootFrame.lua /
-- JohnnysRaidRoll.RaidLootUI) rather than a third tab here - RaidRollUI:ShowSettings()
-- below exists so that window's settings shortcut can jump straight into the
-- Settings tab on this one without duplicating the settings UI.
JohnnysRaidRoll.RaidRollUI = JohnnysRaidRoll.RaidRollUI or {}
local RaidRollUI = JohnnysRaidRoll.RaidRollUI
local Skin = JohnnysRaidRoll.Skin

-- Width is snug against the Rolls tab's content, not arbitrary. Since the
-- Rank/Group columns were dropped, the roll table (RollWindow.lua's
-- ROW_WIDTH, 290px + 30px scrollbar clearance = 320px) is no longer the
-- limiting factor - the bottom control bar is: Prev/New Roll/Next/R on the
-- left (242px) and Award/Announce on the right (194px) need ~436px between
-- them to avoid overlapping, inside this frame's 16px tab-frame margins on
-- each side (436 + 16 + 16 = 468) - going much narrower overlaps those
-- buttons.
local FRAME_WIDTH, FRAME_HEIGHT = 476, 560
local TAB_HEIGHT = 24

local mainFrame, refreshTicker
local tabs = {}
local tabOrder = { "Rolls", "Settings" }
local activeTab

local function SelectTab(name)
	activeTab = name
	for tabName, tab in pairs(tabs) do
		if tabName == name then
			tab.frame:Show()
			tab.button:SetBackdropColor(0.22, 0.22, 0.22, 0.95)
			tab.button:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
		else
			tab.frame:Hide()
			tab.button:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
			tab.button:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
		end
	end
	if tabs[name] and tabs[name].Refresh then
		tabs[name].Refresh()
	end
end

local function BuildFrame()
	mainFrame = CreateFrame("Frame", "JohnnysAddonHubRaidRollFrame", UIParent)
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
		JohnnysRaidRoll.WindowSettings:Register(mainFrame, "rolls", "Raid Roll")
	end

	local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetText("Raid Roll")

	local close = Skin:CreateButton(mainFrame, 20, 20, "X")
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() RaidRollUI:Toggle() end)

	if JohnnysRaidRoll.WindowSettings then
		JohnnysRaidRoll.WindowSettings:AttachButton(mainFrame)
	end

	local tabX = 16
	for _, name in ipairs(tabOrder) do
		local btn = Skin:CreateButton(mainFrame, 100, TAB_HEIGHT, name)
		btn:SetPoint("TOPLEFT", tabX, -44)
		btn:SetScript("OnClick", function() SelectTab(name) end)
		tabX = tabX + 104

		local tabFrame = CreateFrame("Frame", nil, mainFrame)
		tabFrame:SetPoint("TOPLEFT", 16, -76)
		tabFrame:SetPoint("BOTTOMRIGHT", -16, 16)
		tabFrame:Hide()

		tabs[name] = { button = btn, frame = tabFrame }
	end

	tabs["Rolls"].Refresh = RaidRollUI.BuildRollTab(tabs["Rolls"].frame).Refresh
	tabs["Settings"].Refresh = RaidRollUI.BuildSettingsTab(tabs["Settings"].frame).Refresh

	refreshTicker = CreateFrame("Frame")
	refreshTicker:Hide()
	local elapsed = 0
	refreshTicker:SetScript("OnUpdate", function(self, e)
		elapsed = elapsed + e
		if elapsed >= 0.2 then
			elapsed = 0
			if activeTab and tabs[activeTab] and tabs[activeTab].Refresh then
				tabs[activeTab].Refresh()
			end
		end
	end)

	mainFrame:SetScript("OnShow", function()
		SelectTab(activeTab or "Rolls")
		refreshTicker:Show()
	end)
	mainFrame:SetScript("OnHide", function()
		refreshTicker:Hide()
	end)
end

function RaidRollUI:Toggle()
	if RaidRollUI.EnsureHooked then
		RaidRollUI.EnsureHooked()
	end

	if not RR_RollFrame or type(RR_Command) ~= "function" then
		JohnnysRaidRoll:Print("RaidRoll addon not found - can't open Raid Roll.")
		return
	end

	if not mainFrame then
		BuildFrame()
	end

	if mainFrame:IsShown() then
		mainFrame:Hide()
	else
		mainFrame:Show()
	end
end

-- Used by the separate Raid Loot window's Settings shortcut - opens this
-- window (building it on first use, same guard as Toggle()) and switches
-- straight to the Settings tab instead of defaulting to Rolls.
function RaidRollUI:ShowSettings()
	if RaidRollUI.EnsureHooked then
		RaidRollUI.EnsureHooked()
	end

	if not RR_RollFrame or type(RR_Command) ~= "function" then
		JohnnysRaidRoll:Print("RaidRoll addon not found - can't open Raid Roll settings.")
		return
	end

	if not mainFrame then
		BuildFrame()
	end

	activeTab = "Settings"
	if not mainFrame:IsShown() then
		mainFrame:Show()
	else
		SelectTab("Settings")
	end
end
