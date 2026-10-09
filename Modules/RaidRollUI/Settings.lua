-- The "Settings" tab: full parity with RaidRoll's Blizzard Interface Options
-- panel (RaidRoll_OptionsMenu.lua), rebuilt in the black/white skin. Every
-- control here drives the *same native widget* the Blizzard panel itself
-- uses (flip the native checkbox + call RaidRoll_CheckButton_Update_Panel(),
-- push a value into the native slider so its own OnValueChanged fires,
-- call RR_Priority_Modify() directly, read/write the native message
-- EditBoxes RR_AnnounceMsg already depends on) rather than writing saved-var
-- keys ourselves - this reuses 100% of RaidRoll's own validation/side-effect
-- logic instead of duplicating it, and stays correct even for the couple of
-- settings (Scale, Extra Width) that only affect the classic native window.
JohnnysRaidRoll.RaidRollUI = JohnnysRaidRoll.RaidRollUI or {}
local RaidRollUI = JohnnysRaidRoll.RaidRollUI
local Skin = JohnnysRaidRoll.Skin

local ROW_H = 22

-- label, native checkbox widget global. All of these route through
-- RaidRoll_CheckButton_Update_Panel() (RaidRoll_OptionsMenu.lua:714), which
-- re-syncs every checkbox it knows about from its current GetChecked() state
-- in one pass - safe to call after flipping just one.
local ROLL_CHECKBOXES = {
	{ "Count rolls nobody announced an item for", "RR_RollCheckBox_Unannounced_panel" },
	{ "Show rolls that aren't 1-100", "RR_RollCheckBox_AllRolls_panel" },
	{ "Allow repeat rolls from the same player", "RR_RollCheckBox_ExtraRolls_panel" },
	{ "Call out players who roll more than once", "RR_RollCheckBox_Multi_Rollers" },
}

local ANNOUNCE_CHECKBOXES = {
	{ "Announce the 10s / 5s countdown and the winner automatically", "RR_RollCheckBox_Auto_Announce" },
	{ "Skip the 10 second countdown when finishing a roll", "RR_RollCheckBox_No_countdown" },
	{ "Also announce the winner in guild chat", "RR_RollCheckBox_GuildAnnounce" },
	{ "   ...in officer chat instead of guild chat", "RR_RollCheckBox_GuildAnnounce_Officer" },
	{ "Close the roll window after awarding", "RR_RollCheckBox_Auto_Close" },
}

local BID_CHECKBOXES = {
	{ "Track !bid in chat and whispers", "RR_RollCheckBox_Track_Bids" },
	{ "Let !bid work without a number (counts as 0)", "RR_RollCheckBox_Num_Not_Req" },
	{ "Track !epgp in chat and whispers", "RR_RollCheckBox_Track_EPGPSays" },
}

local DISPLAY_CHECKBOXES = {
	{ "Show Rank Beside Name", "RR_RollCheckBox_ShowRanks_panel" },
	{ "Show Group Number", "RR_RollCheckBox_ShowGroupNumber_panel" },
	{ "Show Class Colors", "RR_RollCheckBox_ShowClassColors_panel" },
	{ "Give Higher Guild Ranks Priority", "RR_RollCheckBox_RankPrio_panel" },
}

local EPGP_CHECKBOXES = {
	{ "Enable EPGP Mode", "RR_RollCheckBox_EPGPMode_panel" },
	{ "Enable EPGP Threshold Priority", "RR_RollCheckBox_EPGPThreshold_panel" },
	{ "Enable EPGP Alt Mode", "RR_RollCheckBox_Enable_Alt_Mode" },
}

local LOOT_CHECKBOXES = {
	{ "Auto-Open Window On New Loot", "RR_AutoOpenLootWindow" },
	{ "Receive Loot Messages From Guild", "RR_ReceiveGuildMessages" },
	{ "Enable 3 Messages Mode", "RR_Enable3Messages" },
	{ "Only WotLK Dungeons/Raids", "RR_Frame_WotLK_Dung_Only" },
}

local function AddSectionLabel(container, y, text)
	local fs = Skin:Heading(container, 11, Skin.C.muted)
	fs:SetPoint("TOPLEFT", 4, -y)
	fs:SetText(string.upper(text))
	local rule = Skin:Solid(container, "ARTWORK", Skin.C.rule)
	rule:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -(y + 15))
	rule:SetWidth(400)
	rule:SetHeight(1)
	return y + ROW_H
end

-- RaidRoll ships its own explanation of every option (RAIDROLL_LOCALE, keyed
-- by the native widget's name) for its Blizzard options panel - reuse that
-- text here rather than describing someone else's settings from scratch.
-- Its lines are hard-wrapped and end with "Recommended: On/Off".
local function ShowOptionTooltip(owner, title, widgetName)
	local text = RAIDROLL_LOCALE and RAIDROLL_LOCALE[widgetName]
	GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
	GameTooltip:AddLine((string.gsub(title, "^%s*%.*%s*", "")), 1, 1, 1)
	if type(text) == "string" and text ~= "" then
		local body, recommended = string.match(text, "^(.-)%s*Recommended[^:]*:%s*(.-)%s*$")
		body = body or text
		body = string.gsub(body, "%s*\n%s*", " ")
		body = string.gsub(body, "^%s+", "")
		body = string.gsub(body, "%s+$", "")
		if body ~= "" and body ~= title then
			GameTooltip:AddLine(body, nil, nil, nil, true)
		end
		if recommended and recommended ~= "" then
			GameTooltip:AddLine("RaidRoll recommends: " .. recommended, 0.6, 0.66, 0.65)
		end
	end
	GameTooltip:Show()
end

-- Returns {box=..., widgetName=...} so the caller can refresh its checked
-- state from the native widget each tick.
local function AddCheckbox(container, y, label, widgetName, entries)
	local native = _G[widgetName]
	local initial = native and native:GetChecked()

	local box = Skin:CreateCheckbox(container, 16, initial, function(newState)
		local widget = _G[widgetName]
		if not widget then
			return
		end
		widget:SetChecked(newState)
		if RaidRoll_CheckButton_Update_Panel then
			RaidRoll_CheckButton_Update_Panel()
		end
	end)
	box:SetPoint("TOPLEFT", 8, -y)

	local fs = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", box, "RIGHT", 6, 0)
	fs:SetTextColor(0.9, 0.9, 0.9)
	fs:SetText(label)

	-- Hovering the box or its label explains the option.
	box:SetScript("OnEnter", function(self) ShowOptionTooltip(self, label, widgetName) end)
	box:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local hover = CreateFrame("Frame", nil, container)
	hover:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, 4)
	hover:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 0, -4)
	hover:EnableMouse(true)
	hover:SetScript("OnEnter", function() ShowOptionTooltip(box, label, widgetName) end)
	hover:SetScript("OnLeave", function() GameTooltip:Hide() end)

	table.insert(entries, { box = box, widgetName = widgetName })
	return y + ROW_H
end

local function AddCheckboxGroup(container, y, list, entries)
	for _, def in ipairs(list) do
		y = AddCheckbox(container, y, def[1], def[2], entries)
	end
	return y
end

-- Pushes into the *native* slider so its own OnValueChanged runs (Scale sets
-- RR_RollFrame's scale + RaidRoll_DB["Scale"]; ExtraWidth/RollingTime also
-- call RaidRoll_CheckButton_Update_Panel()) - `syncing` stops the pull-from-
-- native refresh below from re-triggering this push right back out.
local function AddSlider(container, y, label, nativeName, min, max, format)
	AddSectionLabel(container, y, label)
	y = y + 18

	-- Named (not anonymous) because OptionsSliderTemplate's Low/High/Text
	-- regions are defined via "$parent..." in the template XML - an unnamed
	-- frame would make every such slider's children resolve to the same
	-- bare global names and silently collide with each other.
	local slider = CreateFrame("Slider", "JohnnysAddonHubRaidRoll" .. nativeName .. "Mirror", container, "OptionsSliderTemplate")
	slider:SetOrientation("HORIZONTAL")
	slider:SetWidth(260)
	slider:SetHeight(16)
	slider:SetPoint("TOPLEFT", 12, -y)
	slider:SetMinMaxValues(min, max)
	slider:SetValueStep(1)
	_G[slider:GetName() .. "Low"]:SetText("")
	_G[slider:GetName() .. "High"]:SetText("")
	_G[slider:GetName() .. "Text"]:SetText("")

	local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	valueText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
	valueText:SetTextColor(1, 1, 1)

	local syncing = false
	slider:SetScript("OnValueChanged", function(self, value)
		valueText:SetText(format and format(value) or tostring(value))
		if syncing then
			return
		end
		local native = _G[nativeName]
		if native then
			native:SetValue(value)
		end
	end)

	return y + 30, slider, valueText, function()
		local native = _G[nativeName]
		if native then
			syncing = true
			slider:SetValue(native:GetValue())
			syncing = false
		end
	end
end

local function AddNamedEditBox(container, y, label, widgetName)
	AddSectionLabel(container, y, label)
	y = y + 18

	local holder = Skin:CreateEditBox(container, 380, 20)
	holder:SetPoint("TOPLEFT", 12, -y)
	local edit = holder.editBox

	local function PushToNative()
		local native = _G[widgetName]
		if native then
			native:SetText(edit:GetText())
		end
	end
	edit:SetScript("OnTextChanged", PushToNative)
	edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	return y + 28, function()
		if edit:HasFocus() then
			return -- don't stomp on in-progress typing
		end
		local native = _G[widgetName]
		if native then
			edit:SetText(native:GetText() or "")
		end
	end
end

local function AddMessageEditBox(container, y, label, id)
	return AddNamedEditBox(container, y, label, "Raid_Roll_SetMsg" .. id .. "_EditBox")
end

function RaidRollUI.BuildSettingsTab(parent)
	-- Named so UIPanelScrollFrameTemplate's "$parent..." child regions (the
	-- scrollbar) don't collide with other anonymous scrollframes' children.
	local scroll = CreateFrame("ScrollFrame", "JohnnysAddonHubRaidRollSettingsScroll", parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", -30, 0)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(560, 20)
	scroll:SetScrollChild(content)

	local checkboxEntries = {}
	local sliderPulls = {}
	local editPulls = {}
	local y = 4

	y = AddSectionLabel(content, y, "Which rolls count")
	y = AddCheckboxGroup(content, y, ROLL_CHECKBOXES, checkboxEntries)
	y = y + 8

	y = AddSectionLabel(content, y, "Countdown and announcing")
	y = AddCheckboxGroup(content, y, ANNOUNCE_CHECKBOXES, checkboxEntries)
	y = y + 8

	y = AddSectionLabel(content, y, "Bids and chat commands")
	y = AddCheckboxGroup(content, y, BID_CHECKBOXES, checkboxEntries)
	y = y + 8

	-- Chat Claims: the keyword list M1/M2/M3's 20-second listening window
	-- (LootWindow.lua's BuildAnnounceHandler, via RR_StartChatClaimWindow)
	-- scans raid/party chat for, e.g. "need, ms, want" (RaidRoll_OnLoad.lua's
	-- RR_ChatClaims_MessageMatches).
	local claimKwY, pullClaimKeywords = AddNamedEditBox(content, y, "Main-spec claim keywords (comma separated)", "RR_ChatClaimKeywords_EditBox")
	y = claimKwY
	table.insert(editPulls, pullClaimKeywords)
	y = y + 8

	y = AddSectionLabel(content, y, "Display")
	y = AddCheckboxGroup(content, y, DISPLAY_CHECKBOXES, checkboxEntries)
	y = y + 8

	y = AddSectionLabel(content, y, "EPGP")
	y = AddCheckboxGroup(content, y, EPGP_CHECKBOXES, checkboxEntries)
	y = y + 8

	local scaleY, _, _, pullScale = AddSlider(content, y, "Scale (classic window only)", "RaidRoll_Scale_Slider", 1, 200, function(v) return v .. "%" end)
	y = scaleY
	table.insert(sliderPulls, pullScale)

	local widthY, _, _, pullWidth = AddSlider(content, y, "Extra Rank Width (classic window only)", "RaidRoll_ExtraWidth_Slider", 0, 200, function(v) return tostring(v) end)
	y = widthY
	table.insert(sliderPulls, pullWidth)

	local timeY, _, _, pullTime = AddSlider(content, y, "Roll Time (seconds)", "RaidRoll_Rolling_Time_Slider", -55, 60, function(v) return tostring(v + 60) end)
	y = timeY
	table.insert(sliderPulls, pullTime)
	y = y + 8

	-- Guild rank priority table (11 rows, 11 = "Not in Guild"). Reuses
	-- RR_Priority_Modify(i) directly (RaidRoll_OptionsMenu.lua:699) for the
	-- 0-10 click-to-cycle behavior instead of reimplementing it.
	y = AddSectionLabel(content, y, "Guild Rank Priority (click a number to cycle 0-10)")
	y = y + 4
	local priorityLabels = {}
	for i = 1, 11 do
		local rankName
		if i == 11 then
			rankName = "Not in Guild"
		elseif IsInGuild() and GuildControlGetRankName then
			rankName = GuildControlGetRankName(i) or ("Rank " .. i)
		else
			rankName = "Rank " .. i
		end

		local label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", 12, -y)
		label:SetWidth(160)
		label:SetJustifyH("LEFT")
		label:SetTextColor(0.9, 0.9, 0.9)
		label:SetText(rankName)

		local btn = Skin:CreateButton(content, 30, 18, "0")
		btn:SetPoint("LEFT", label, "RIGHT", 6, 0)
		btn:SetScript("OnClick", function()
			if RR_Priority_Modify then
				RR_Priority_Modify(i)
			end
		end)
		priorityLabels[i] = btn

		y = y + 20
	end
	y = y + 8

	-- Loot Window section - only meaningful if RaidRoll_LootTracker is
	-- installed (its native widgets don't exist otherwise).
	if RaidRoll_LootTrackerLoaded == true then
		y = AddSectionLabel(content, y, "Loot Window")
		y = AddCheckboxGroup(content, y, LOOT_CHECKBOXES, checkboxEntries)
		y = y + 8

		local msg1Y, pullMsg1 = AddMessageEditBox(content, y, "Message 1 (M1) - use [item] as a placeholder", 1)
		y = msg1Y
		local msg2Y, pullMsg2 = AddMessageEditBox(content, y, "Message 2 (M2)", 2)
		y = msg2Y
		local msg3Y, pullMsg3 = AddMessageEditBox(content, y, "Message 3 (M3)", 3)
		y = msg3Y
		table.insert(editPulls, pullMsg1)
		table.insert(editPulls, pullMsg2)
		table.insert(editPulls, pullMsg3)
	end

	content:SetHeight(math.max(20, y))

	local function Refresh()
		for _, entry in ipairs(checkboxEntries) do
			local native = _G[entry.widgetName]
			if native then
				entry.box:SetChecked(native:GetChecked())
			end
		end
		for _, pull in ipairs(sliderPulls) do
			pull()
		end
		for _, pull in ipairs(editPulls) do
			pull()
		end
		for i = 1, 11 do
			local val = RaidRoll_DB and RaidRoll_DB["Rank Priority"] and RaidRoll_DB["Rank Priority"][i]
			priorityLabels[i].text:SetText(tostring(val or 0))
		end
	end

	return { frame = parent, Refresh = Refresh }
end
