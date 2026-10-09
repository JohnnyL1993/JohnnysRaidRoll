-- The "Rolls" tab: a black/white replacement for RR_RollFrame. Never calls
-- RR_Display()/RR_Update_Name_Frame() to render (those paint straight into
-- RaidRoll's own XML fontstrings and are hard-capped at 5 visible rows) -
-- instead this polls the same raw per-roll-ID arrays RR_Display itself reads,
-- and drives RaidRoll's existing action functions (RR_Command, RR_Ignore,
-- RR_PrevRoll/RR_NewRoll/RR_NextRoll, RR_FinishRolling) for every action, the
-- same "read the engine's data, invoke the engine's functions" split used
-- throughout this module.
JohnnysRaidRoll.RaidRollUI = JohnnysRaidRoll.RaidRollUI or {}
local RaidRollUI = JohnnysRaidRoll.RaidRollUI
local Skin = JohnnysRaidRoll.Skin

local ROW_HEIGHT = 20
local COLUMN_ORDER = { "pos", "name", "roll", "status" }
local COLUMN_WIDTHS = { pos = 28, name = 170, roll = 76, status = 70 }
-- After the text columns: the icon-marker box, then the Ignore/Restore button.
local MARK_WIDTH = 24
local IGNORE_WIDTH = 62
local ROW_WIDTH = MARK_WIDTH + IGNORE_WIDTH + 6
for _, key in ipairs(COLUMN_ORDER) do
	ROW_WIDTH = ROW_WIDTH + COLUMN_WIDTHS[key]
end

local function ColumnX(key)
	local x = 0
	for _, k in ipairs(COLUMN_ORDER) do
		if k == key then
			return x
		end
		x = x + COLUMN_WIDTHS[k]
	end
	return x
end

local function PlayerOpts()
	return RaidRoll_DBPC and UnitName and RaidRoll_DBPC[UnitName("player")] or nil
end

local function ComputeAwardLabel()
	if not rr_Item or not rr_CurrentRollID or not RR_Timestamp or not rr_rollID then
		return "No Item"
	end

	local hasRealItem = rr_Item[rr_CurrentRollID] ~= ("ID #" .. rr_CurrentRollID)
	local windowClosed = (time() > RR_Timestamp + 59) or (rr_CurrentRollID ~= rr_rollID)

	if hasRealItem and windowClosed then
		local winner = RR_FindWinner(rr_CurrentRollID)
		if winner ~= "" then
			return "Award " .. (winner:sub(1, 1):upper() .. winner:sub(2):lower())
		end
		return "No Winner"
	elseif windowClosed then
		return "No Item"
	else
		if RR_Doing_a_New_Roll == true then
			return "Awaiting Rolls"
		end
		local opts = PlayerOpts()
		local noCountdown = opts and opts["RR_RollCheckBox_No_countdown"] == true
		if (60 - (time() - RR_Timestamp)) <= 11 or noCountdown then
			return "Finish Early"
		end
		return "10 sec + Announce"
	end
end

-- Exact behavior mirror of RR_Roll_5SecAndAnnounce's OnClick
-- (RaidRoll_ExtraRollFrames.lua:308-351) - deliberately not simplified so the
-- early-finish countdown-skip and the plain RR_FinishRolling() fallback stay
-- byte-for-byte identical to the native button.
local function OnAwardClick()
	if RR_Timestamp ~= nil and tonumber(RR_Timestamp) ~= nil then
		if rr_CurrentRollID == rr_rollID then
			local opts = PlayerOpts()
			local noCountdown = opts and opts["RR_RollCheckBox_No_countdown"] == true
			local secsLeft = 60 - (time() - RR_Timestamp)
			if (secsLeft <= 11 or noCountdown) and secsLeft > 0 then
				RR_HasAnnounced_10_Sec = true
				RR_HasAnnounced_5_Sec = true

				if GetNumRaidMembers() ~= 0 then
					rr_AnnounceType = "RAID"
				elseif GetNumPartyMembers() > 0 then
					rr_AnnounceType = "PARTY"
				else
					rr_AnnounceType = "SAY"
				end

				if not noCountdown and RAIDROLL_LOCALE then
					SendChatMessage(RAIDROLL_LOCALE["Finishing_Rolling_Early"], rr_AnnounceType)
				end

				RR_RollCountdown = true
				RR_AnnounceCountdowns = true
				RR_Timestamp = time() - 60
			else
				RR_FinishRolling()
			end
		else
			RR_FinishRolling()
		end
	else
		RR_FinishRolling()
	end
end

-- Exact behavior mirror of RaidRoll_AnnounceWinnerButton's OnClick
-- (RaidRoll_ExtraRollFrames.lua:261-296).
local function OnAnnounceWinnerClick()
	if not rr_CurrentRollID or not rr_Item then
		return
	end

	local winner, roll, epgp = RR_FindWinner(rr_CurrentRollID)
	local message

	if winner ~= "" and RAIDROLL_LOCALE then
		local displayName = winner:sub(1, 1):upper() .. winner:sub(2):lower()
		local opts = PlayerOpts()
		if opts and opts["RR_EPGP_Enabled"] == true then
			if rr_Item[rr_CurrentRollID] == "ID #" .. rr_CurrentRollID then
				message = string.format(RAIDROLL_LOCALE["won_PR_value"], displayName, epgp)
			else
				message = string.format(RAIDROLL_LOCALE["won_item_PR_value"], displayName, rr_Item[rr_CurrentRollID], epgp)
			end
		else
			if rr_Item[rr_CurrentRollID] == "ID #" .. rr_CurrentRollID then
				message = string.format(RAIDROLL_LOCALE["won_with"], displayName, roll)
			else
				message = string.format(RAIDROLL_LOCALE["won_item_with"], displayName, rr_Item[rr_CurrentRollID], roll)
			end
		end
	elseif RAIDROLL_LOCALE then
		message = string.format(RAIDROLL_LOCALE["No_winner_for"], rr_Item[rr_CurrentRollID])
	end

	if not message then
		return
	end

	SendChatMessage(message, rr_AnnounceType or "SAY")

	if RR_RollCheckBox_GuildAnnounce and RR_RollCheckBox_GuildAnnounce:GetChecked() then
		if RR_RollCheckBox_GuildAnnounce_Officer and RR_RollCheckBox_GuildAnnounce_Officer:GetChecked() then
			SendChatMessage(message, "OFFICER")
		else
			SendChatMessage(message, "GUILD")
		end
	end
end

-- What clicking the Award button will do in each of its states, shown on the
-- line above the button bar (the button's own label is ComputeAwardLabel's).
local function AwardHelp(label)
	if label == "Awaiting Rolls" then
		return "Rolling is open - waiting for rolls.", true
	elseif label == "10 sec + Announce" then
		return "Click to give a 10 second warning, then announce the winner.", true
	elseif label == "Finish Early" then
		return "Click to close rolling now and announce the winner.", true
	elseif label == "No Winner" then
		return "Rolling is closed and nobody has an eligible roll.", false
	elseif label == "No Item" then
		return "No item is being rolled for. Start one from the Raid Loot window or with New Roll.", false
	end
	-- "Award <Name>"
	return "Rolling is closed. Click to award the item to the winner.", true
end

local function CreateRollRow(parent)
	local C = Skin.C
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(ROW_WIDTH, ROW_HEIGHT)
	row:SetBackdrop({ bgFile = Skin.WHITE })
	row:SetBackdropColor(0, 0, 0, 0)

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture(Skin.WHITE)
	highlight:SetVertexColor(1, 1, 1, 0.06)

	-- Lime bar down the left edge of whoever is currently winning.
	row.leadBar = Skin:Solid(row, "ARTWORK", C.accent)
	row.leadBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.leadBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.leadBar:SetWidth(2)
	row.leadBar:Hide()

	for _, key in ipairs(COLUMN_ORDER) do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", row, "LEFT", ColumnX(key) + 6, 0)
		fs:SetWidth(COLUMN_WIDTHS[key] - 8)
		fs:SetJustifyH("LEFT")
		row[key] = fs
	end

	-- Raid-target icon marker for this player (RaidRoll's own "mark" command).
	local mark = CreateFrame("Button", nil, row)
	mark:SetSize(MARK_WIDTH - 4, ROW_HEIGHT - 2)
	mark:SetPoint("LEFT", row, "LEFT", ColumnX("status") + COLUMN_WIDTHS.status + 2, 0)
	Skin:StyleButton(mark)
	local markText = mark:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	markText:SetPoint("CENTER")
	markText:SetTextColor(1, 1, 1)
	mark.text = markText
	mark:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mark:SetScript("OnClick", function(self, button)
		if not row.index then
			return
		end
		if button == "RightButton" or IsShiftKeyDown() then
			RR_Command("unmark " .. row.index)
		else
			RR_Command("mark " .. row.index)
		end
	end)
	mark:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Icon marker", 1, 1, 1)
		GameTooltip:AddLine("Click to put an icon by this player, click again to change it.", nil, nil, nil, true)
		GameTooltip:AddLine("Right-click to clear it.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	mark:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.mark = mark

	-- Ignore / Restore: takes this player's roll out of the running (or puts
	-- it back). Used to be a right-click on the marker box.
	local ignoreBtn = Skin:CreateButton(row, IGNORE_WIDTH - 4, ROW_HEIGHT - 2, "Ignore")
	ignoreBtn:SetPoint("LEFT", mark, "RIGHT", 4, 0)
	ignoreBtn:SetScript("OnClick", function()
		if row.index then
			RR_Ignore(row.index)
		end
	end)
	ignoreBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if row.ignored then
			GameTooltip:AddLine("Restore", 1, 1, 1)
			GameTooltip:AddLine("Counts this player's roll again.", nil, nil, nil, true)
		else
			GameTooltip:AddLine("Ignore", 1, 1, 1)
			GameTooltip:AddLine("Takes this player's roll out of the running for this item. They stay in the list so you can restore them.", nil, nil, nil, true)
		end
		GameTooltip:Show()
	end)
	ignoreBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.ignoreBtn = ignoreBtn

	row:SetScript("OnEnter", function(self)
		if not self.itemLink then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self.itemLink)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)

	return row
end

function RaidRollUI.BuildRollTab(parent)
	local C = Skin.C
	local rows = {}

	local header = CreateFrame("Frame", nil, parent)
	header:SetPoint("TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", 0, 0)
	header:SetHeight(32)

	-- Icon for the currently active roll's item. GameTooltip:SetHyperlink is
	-- the same call used on every other tooltip in this module - holding
	-- Shift while hovering triggers the client's own built-in equipped-item
	-- compare tooltip automatically.
	local itemIcon = CreateFrame("Button", nil, header)
	itemIcon:SetSize(28, 28)
	itemIcon:SetPoint("LEFT", 2, 0)
	local itemIconTex = itemIcon:CreateTexture(nil, "ARTWORK")
	itemIconTex:SetAllPoints()
	itemIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	itemIcon.tex = itemIconTex
	itemIcon:SetScript("OnEnter", function(self)
		if not self.itemLink then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self.itemLink)
		GameTooltip:Show()
	end)
	itemIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Countdown: its own large number on the right of the header, rather
	-- than "(37)" tucked in front of the item name. Red for the last 10s.
	local timerText = Skin:Heading(header, 22, C.text)
	timerText:SetPoint("RIGHT", header, "RIGHT", -4, 0)
	timerText:SetJustifyH("RIGHT")
	local timerLabel = Skin:Heading(header, 10, C.muted)
	timerLabel:SetPoint("RIGHT", timerText, "LEFT", -6, -2)
	timerLabel:SetText("TIME LEFT")

	local itemText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	itemText:SetPoint("LEFT", itemIcon, "RIGHT", 6, 0)
	itemText:SetTextColor(1, 1, 1)
	itemText:SetJustifyH("LEFT")
	itemText:SetWidth(300)

	local itemFrame = CreateFrame("Frame", nil, header)
	itemFrame:SetAllPoints(itemText)
	itemFrame:SetScript("OnEnter", function(self)
		if not self.itemLink then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self.itemLink)
		GameTooltip:Show()
	end)
	itemFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local colHeader = CreateFrame("Frame", nil, parent)
	colHeader:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	colHeader:SetSize(ROW_WIDTH, 18)
	local LABELS = { pos = "#", name = "NAME", roll = "ROLL", status = "" }
	local rollHeader
	for _, key in ipairs(COLUMN_ORDER) do
		local fs = Skin:Heading(colHeader, 10, C.muted)
		fs:SetPoint("LEFT", colHeader, "LEFT", ColumnX(key) + 6, 0)
		fs:SetText(LABELS[key])
		if key == "roll" then
			rollHeader = fs
		end
	end
	local headRule = Skin:Solid(colHeader, "ARTWORK", C.rule)
	headRule:SetPoint("BOTTOMLEFT", colHeader, "BOTTOMLEFT", 0, 0)
	headRule:SetPoint("BOTTOMRIGHT", colHeader, "BOTTOMRIGHT", 0, 0)
	headRule:SetHeight(1)

	-- Named so UIPanelScrollFrameTemplate's "$parent..." child regions (the
	-- scrollbar) don't collide with other anonymous scrollframes' children.
	local listScroll = CreateFrame("ScrollFrame", "JohnnysAddonHubRaidRollRollScroll", parent, "UIPanelScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, -4)
	listScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, 68)
	listScroll:SetWidth(ROW_WIDTH)

	local listContent = CreateFrame("Frame", nil, listScroll)
	listContent:SetSize(ROW_WIDTH, 20)
	listScroll:SetScrollChild(listContent)

	local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyText:SetPoint("TOPLEFT", listScroll, "TOPLEFT", 6, -8)
	emptyText:SetWidth(ROW_WIDTH - 12)
	emptyText:SetJustifyH("LEFT")
	emptyText:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
	emptyText:SetText("No rolls yet for this item.")
	emptyText:Hide()

	local function LayoutRows()
		for i, row in ipairs(rows) do
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
		end
		listContent:SetHeight(math.max(20, #rows * ROW_HEIGHT))
	end

	-- Two status lines between the list and the buttons: rolls the list is
	-- leaving out (and why), then what the Award button will do right now.
	local hiddenText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hiddenText:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 48)
	hiddenText:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 48)
	hiddenText:SetJustifyH("LEFT")
	hiddenText:SetTextColor(C.short[1], C.short[2], C.short[3])

	local helpText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	helpText:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 30)
	helpText:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 30)
	helpText:SetJustifyH("LEFT")
	helpText:SetTextColor(C.muted[1], C.muted[2], C.muted[3])

	local function Tip(btn, anchor, title, body)
		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, anchor)
			GameTooltip:AddLine(title, 1, 1, 1)
			if body then
				GameTooltip:AddLine(body, nil, nil, nil, true)
			end
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	-- Bottom control bar.
	local prevBtn = Skin:CreateButton(parent, 54, 22, "< Prev")
	prevBtn:SetPoint("BOTTOMLEFT", 0, 0)
	prevBtn:SetScript("OnClick", function() RR_PrevRoll() end)
	Tip(prevBtn, "ANCHOR_RIGHT", "Previous roll", "Look back at the roll before this one.")

	local newBtn = Skin:CreateButton(parent, 70, 22, "New Roll")
	newBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
	newBtn:SetScript("OnClick", function() RR_NewRoll() end)
	Tip(newBtn, "ANCHOR_RIGHT", "New roll", "Start a fresh roll with an empty list and a new timer.")

	local nextBtn = Skin:CreateButton(parent, 54, 22, "Next >")
	nextBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)
	nextBtn:SetScript("OnClick", function() RR_NextRoll() end)
	Tip(nextBtn, "ANCHOR_RIGHT", "Next roll", "Move forward to the roll after this one.")

	local rollBtn = Skin:CreateButton(parent, 44, 22, "Roll")
	rollBtn:SetPoint("LEFT", nextBtn, "RIGHT", 4, 0)
	rollBtn:SetScript("OnClick", function() RandomRoll(1, 100) end)
	Tip(rollBtn, "ANCHOR_RIGHT", "Roll", "Makes your own /roll 1-100.")

	local announceBtn = Skin:CreateButton(parent, 70, 22, "Announce")
	announceBtn:SetPoint("BOTTOMRIGHT", 0, 0)
	announceBtn:SetScript("OnClick", OnAnnounceWinnerClick)
	Tip(announceBtn, "ANCHOR_LEFT", "Announce winner", "Posts the current winner and their roll to the group, without awarding anything.")

	local awardBtn = Skin:CreateButton(parent, 150, 22, "Awaiting Rolls")
	awardBtn:SetPoint("RIGHT", announceBtn, "LEFT", -4, 0)
	awardBtn:SetScript("OnClick", OnAwardClick)
	-- Painted in Refresh (lime while it awards, greyed while it does nothing),
	-- so drop StyleButton's own press/release repaint.
	awardBtn:SetScript("OnMouseDown", nil)
	awardBtn:SetScript("OnMouseUp", nil)

	local function PaintAward(label, enabled)
		if not enabled then
			awardBtn:Disable()
			awardBtn:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 0.95)
			awardBtn:SetBackdropBorderColor(C.rule[1], C.rule[2], C.rule[3], 1)
			awardBtn.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
			return
		end
		awardBtn:Enable()
		if string.sub(label, 1, 6) == "Award " then
			awardBtn:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)
			awardBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
			awardBtn.text:SetTextColor(C.ground[1], C.ground[2], C.ground[3])
		else
			awardBtn:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 0.95)
			awardBtn:SetBackdropBorderColor(C.rule2[1], C.rule2[2], C.rule2[3], 1)
			awardBtn.text:SetTextColor(C.text[1], C.text[2], C.text[3])
		end
	end

	local function Refresh()
		local player = UnitName("player")
		local opts = RaidRoll_DBPC and RaidRoll_DBPC[player]
		local epgp = opts and opts["RR_EPGP_Enabled"] == true
		rollHeader:SetText(epgp and "PR" or "ROLL")

		-- Item header + countdown, from the same values RR_Display would have
		-- used (RaidRoll_OnLoad.lua:1734-1739) without calling it.
		local rollingOpen = false
		if rr_Item and rr_CurrentRollID and rr_Item[rr_CurrentRollID] then
			local link = rr_Item[rr_CurrentRollID]
			itemFrame.itemLink = link:find("item:") and link or nil
			itemIcon.itemLink = itemFrame.itemLink
			local icon = itemIcon.itemLink and GetItemIcon(itemIcon.itemLink)
			itemIcon.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			itemText:SetText(link)
			if RR_Timestamp and rr_rollID == rr_CurrentRollID and time() < RR_Timestamp + 60 then
				rollingOpen = true
				local left = 60 - time() + RR_Timestamp
				timerText:SetText(left .. "s")
				if left <= 10 then
					timerText:SetTextColor(C.short[1], C.short[2], C.short[3])
				else
					timerText:SetTextColor(C.text[1], C.text[2], C.text[3])
				end
			end
		else
			itemFrame.itemLink = nil
			itemIcon.itemLink = nil
			itemIcon.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			itemText:SetText("No roll yet")
		end
		if rollingOpen then
			timerText:Show()
			timerLabel:Show()
		else
			timerText:Hide()
			timerLabel:Hide()
		end

		local awardLabel = ComputeAwardLabel()
		local help, awardEnabled = AwardHelp(awardLabel)
		awardBtn.text:SetText(awardLabel)
		PaintAward(awardLabel, awardEnabled)
		helpText:SetText(help)

		if rr_rollID and rr_rollID ~= 0 then
			if rr_CurrentRollID < rr_rollID then nextBtn:Enable() else nextBtn:Disable() end
			if rr_CurrentRollID > 0 then prevBtn:Enable() else prevBtn:Disable() end
		else
			nextBtn:Disable()
			prevBtn:Disable()
		end

		-- Row data: the same raw arrays RR_Display reads, not RR_Display
		-- itself (see file header comment). RaidRoll keeps them ranked, best
		-- first, so the first row that isn't ignored is the current winner
		-- (the same rule RR_FindWinner applies).
		local rollID = rr_CurrentRollID
		local count = 0
		local hiddenRange, hiddenExtra = 0, 0
		local leaderValue
		local shown = {}
		if rollID and MaxPlayers and MaxPlayers[rollID] and RollerName and RollerName[rollID] then
			local acceptAll = opts and opts["RR_Accept_All_Rolls"] == true
			local allowExtra = opts and opts["RR_AllowExtraRolls"] == true

			for j = 1, MaxPlayers[rollID] do
				local name = RollerName[rollID][j]
				if name and name ~= "" then
					local legit = RaidRoll_LegitRoll and RaidRoll_LegitRoll[rollID] and RaidRoll_LegitRoll[rollID][j]
					local first = RollerFirst and RollerFirst[rollID] and RollerFirst[rollID][j]

					if legit == false and not acceptAll then
						hiddenRange = hiddenRange + 1
					elseif not allowExtra and first == false then
						hiddenExtra = hiddenExtra + 1
					else
						count = count + 1
						local row = rows[count]
						if not row then
							row = CreateRollRow(listContent)
							rows[count] = row
							LayoutRows()
						end

						row.index = j
						local nameLower = name:lower()
						local ignored = RR_IgnoredList and RR_IgnoredList[rollID] and RR_IgnoredList[rollID][nameLower]
						row.ignored = ignored and true or false

						row.pos:SetText(tostring(j))

						-- Main-spec chat claim (RaidRoll_DB["ChatClaims"] is written
						-- by RaidRoll_OnLoad.lua's RR_RecordChatClaim during the
						-- MS/OS buttons' 20-second listening window).
						local claimTag = ""
						if RaidRoll_DB and RaidRoll_DB["ChatClaims"] and RaidRoll_DB["ChatClaims"][nameLower] then
							claimTag = "  |cffb9e24aMS|r"
						end

						local color = (RollerColor and RollerColor[rollID] and RollerColor[rollID][j]) or ""
						if ignored then
							row.name:SetTextColor(0.6, 0.3, 0.3)
							row.name:SetText(name .. claimTag)
						else
							row.name:SetTextColor(1, 1, 1)
							if color ~= "" then
								row.name:SetText(color .. name .. "|r" .. claimTag)
							else
								row.name:SetText(name .. claimTag)
							end
						end

						local value
						if epgp then
							local pr = RR_EPGP_PRValue and RR_EPGP_PRValue[rollID] and RR_EPGP_PRValue[rollID][j] or 0
							local above = RR_EPGPAboveThreshold and RR_EPGPAboveThreshold[rollID] and RR_EPGPAboveThreshold[rollID][j]
							row.roll:SetTextColor(above and 0.67 or 0.77, above and 0.83 or 0.12, above and 0.45 or 0.23)
							row.roll:SetText(tostring(pr))
							value = pr
						else
							local rollVal = RollerRoll and RollerRoll[rollID] and RollerRoll[rollID][j] or 0
							local extra = (legit == false) and "*" or ""
							row.roll:SetTextColor(1, 1, 1)
							if first == false then
								local n = Roll_Number and Roll_Number[rollID] and Roll_Number[rollID][j] or "?"
								row.roll:SetText(string.format("(%s) %d%s", tostring(n), rollVal, extra))
							else
								row.roll:SetText(tostring(rollVal) .. extra)
							end
							value = rollVal
						end
						row.value = value
						if not ignored and leaderValue == nil then
							leaderValue = value
							row.isLeader = true
						else
							row.isLeader = false
						end

						local markIcon = opts and opts["RR_NameMark"] and opts["RR_NameMark"][nameLower]
						row.mark.text:SetText(markIcon and (opts["RR_PlayerIcon"] and opts["RR_PlayerIcon"][nameLower]) or "")
						row.ignoreBtn.text:SetText(ignored and "Restore" or "Ignore")

						local link = rr_Item and rr_Item[rollID]
						row.itemLink = link and link:find("item:") and link or nil

						table.insert(shown, row)
						row:Show()
					end
				end
			end
		end

		-- Second pass, now the leader is known: status tag, lime bar, ties.
		local tie = false
		for _, row in ipairs(shown) do
			if not row.ignored and not row.isLeader and leaderValue ~= nil and row.value == leaderValue then
				tie = true
			end
		end
		for _, row in ipairs(shown) do
			if row.ignored then
				row.status:SetText("IGNORED")
				row.status:SetTextColor(0.6, 0.3, 0.3)
				row.leadBar:Hide()
				row:SetBackdropColor(0, 0, 0, 0)
			elseif row.isLeader then
				row.status:SetText(tie and "TIED" or (rollingOpen and "LEADS" or "WINNER"))
				row.status:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
				row.leadBar:Show()
				row:SetBackdropColor(0.122, 0.153, 0.169, 0.9)
			elseif tie and row.value == leaderValue then
				row.status:SetText("TIED")
				row.status:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
				row.leadBar:Hide()
				row:SetBackdropColor(0.122, 0.153, 0.169, 0.9)
			else
				row.status:SetText("")
				row.leadBar:Hide()
				row:SetBackdropColor(0, 0, 0, 0)
			end
		end

		for i = count + 1, #rows do
			rows[i].index = nil
			rows[i]:Hide()
		end

		if count == 0 and rollID and rr_Item and rr_Item[rollID] then
			emptyText:Show()
		else
			emptyText:Hide()
		end

		-- Say when rolls are being left out, and why - both are settings.
		local parts = {}
		if hiddenRange > 0 then
			table.insert(parts, hiddenRange .. " not 1-100")
		end
		if hiddenExtra > 0 then
			table.insert(parts, hiddenExtra .. (hiddenExtra == 1 and " repeat roll" or " repeat rolls"))
		end
		if #parts > 0 then
			hiddenText:SetText((hiddenRange + hiddenExtra) .. " hidden: " .. table.concat(parts, ", ") .. ". Allow them in Settings to see them.")
		else
			hiddenText:SetText("")
		end
	end

	return { frame = parent, Refresh = Refresh }
end
