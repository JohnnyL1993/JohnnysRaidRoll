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
local COLUMN_ORDER = { "pos", "name", "roll" }
local COLUMN_WIDTHS = { pos = 26, name = 150, roll = 90 }
local MARK_WIDTH = 24
local ROW_WIDTH = MARK_WIDTH
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

local function CreateRollRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(ROW_WIDTH, ROW_HEIGHT)
	row:SetBackdrop({ bgFile = Skin.WHITE })
	row:SetBackdropColor(0, 0, 0, 0)

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture(Skin.WHITE)
	highlight:SetVertexColor(1, 1, 1, 0.06)

	for _, key in ipairs(COLUMN_ORDER) do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", row, "LEFT", ColumnX(key) + 4, 0)
		fs:SetWidth(COLUMN_WIDTHS[key] - 6)
		fs:SetJustifyH(key == "name" and "LEFT" or "CENTER")
		row[key] = fs
	end

	local mark = CreateFrame("Button", nil, row)
	mark:SetSize(MARK_WIDTH - 4, ROW_HEIGHT - 2)
	mark:SetPoint("LEFT", row, "LEFT", ColumnX("roll") + COLUMN_WIDTHS.roll + 2, 0)
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
		if button == "RightButton" then
			RR_Ignore(row.index)
		elseif IsShiftKeyDown() then
			RR_Command("unmark " .. row.index)
		else
			RR_Command("mark " .. row.index)
		end
	end)
	mark:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Left-click: mark/cycle icon", 1, 1, 1)
		GameTooltip:AddLine("Shift+Left-click: unmark", 1, 1, 1)
		GameTooltip:AddLine("Right-click: ignore/unignore", 1, 1, 1)
		GameTooltip:Show()
	end)
	mark:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.mark = mark

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
	local rows = {}

	local header = CreateFrame("Frame", nil, parent)
	header:SetPoint("TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", 0, 0)
	header:SetHeight(32)

	-- Icon for the currently active roll's item, mirroring the Loot tab's row
	-- icons (LootWindow.lua's CreateLootRow). GameTooltip:SetHyperlink is the
	-- same call used on every other tooltip in this module - holding Shift
	-- while hovering triggers the client's own built-in equipped-item compare
	-- tooltip automatically, nothing extra to wire up for that.
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

	local itemText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	itemText:SetPoint("LEFT", itemIcon, "RIGHT", 6, 0)
	itemText:SetTextColor(1, 1, 1)
	itemText:SetJustifyH("LEFT")
	itemText:SetWidth(370)

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
	local LABELS = { pos = "#", name = "Name", roll = "Roll/PR" }
	for _, key in ipairs(COLUMN_ORDER) do
		local fs = colHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", colHeader, "LEFT", ColumnX(key) + 4, 0)
		fs:SetTextColor(0.7, 0.7, 0.7)
		fs:SetText(LABELS[key])
	end

	-- Named so UIPanelScrollFrameTemplate's "$parent..." child regions (the
	-- scrollbar) don't collide with other anonymous scrollframes' children.
	local listScroll = CreateFrame("ScrollFrame", "JohnnysAddonHubRaidRollRollScroll", parent, "UIPanelScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, -4)
	listScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, 40)
	listScroll:SetWidth(ROW_WIDTH)

	local listContent = CreateFrame("Frame", nil, listScroll)
	listContent:SetSize(ROW_WIDTH, 20)
	listScroll:SetScrollChild(listContent)

	local function LayoutRows()
		for i, row in ipairs(rows) do
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
		end
		listContent:SetHeight(math.max(20, #rows * ROW_HEIGHT))
	end

	-- Bottom control bar.
	local prevBtn = Skin:CreateButton(parent, 60, 22, "< Prev")
	prevBtn:SetPoint("BOTTOMLEFT", 0, 0)
	prevBtn:SetScript("OnClick", function() RR_PrevRoll() end)

	local newBtn = Skin:CreateButton(parent, 80, 22, "New Roll")
	newBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
	newBtn:SetScript("OnClick", function() RR_NewRoll() end)

	local nextBtn = Skin:CreateButton(parent, 60, 22, "Next >")
	nextBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)
	nextBtn:SetScript("OnClick", function() RR_NextRoll() end)

	local rollBtn = Skin:CreateButton(parent, 30, 22, "R")
	rollBtn:SetPoint("LEFT", nextBtn, "RIGHT", 4, 0)
	rollBtn:SetScript("OnClick", function() RandomRoll(1, 100) end)
	rollBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Quick /roll 1-100", 1, 1, 1)
		GameTooltip:Show()
	end)
	rollBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local announceBtn = Skin:CreateButton(parent, 30, 22, "A")
	announceBtn:SetPoint("BOTTOMRIGHT", 0, 0)
	announceBtn:SetScript("OnClick", OnAnnounceWinnerClick)
	announceBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Announce current winner", 1, 1, 1)
		GameTooltip:Show()
	end)
	announceBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local awardBtn = Skin:CreateButton(parent, 160, 22, "Awaiting Rolls")
	awardBtn:SetPoint("RIGHT", announceBtn, "LEFT", -4, 0)
	awardBtn:SetScript("OnClick", OnAwardClick)

	local function Refresh()
		local player = UnitName("player")
		local opts = RaidRoll_DBPC and RaidRoll_DBPC[player]

		-- Item header + countdown, mirroring the RR_Itemname text RR_Display
		-- would have shown (RaidRoll_OnLoad.lua:1734-1739) without calling it.
		if rr_Item and rr_CurrentRollID and rr_Item[rr_CurrentRollID] then
			local link = rr_Item[rr_CurrentRollID]
			itemFrame.itemLink = link:find("item:") and link or nil
			itemIcon.itemLink = itemFrame.itemLink
			local icon = itemIcon.itemLink and GetItemIcon(itemIcon.itemLink)
			itemIcon.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			if RR_Timestamp and rr_rollID == rr_CurrentRollID and time() < RR_Timestamp + 60 then
				itemText:SetText(string.format("(%d) %s", 60 - time() + RR_Timestamp, link))
			else
				itemText:SetText(link)
			end
		else
			itemFrame.itemLink = nil
			itemIcon.itemLink = nil
			itemIcon.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			itemText:SetText("No roll yet")
		end

		awardBtn.text:SetText(ComputeAwardLabel())

		if rr_rollID and rr_rollID ~= 0 then
			if rr_CurrentRollID < rr_rollID then nextBtn:Enable() else nextBtn:Disable() end
			if rr_CurrentRollID > 0 then prevBtn:Enable() else prevBtn:Disable() end
		else
			nextBtn:Disable()
			prevBtn:Disable()
		end

		-- Row data: the same raw arrays RR_Display reads, not RR_Display
		-- itself (see file header comment).
		local rollID = rr_CurrentRollID
		local count = 0
		if rollID and MaxPlayers and MaxPlayers[rollID] and RollerName and RollerName[rollID] then
			local acceptAll = opts and opts["RR_Accept_All_Rolls"] == true
			local allowExtra = opts and opts["RR_AllowExtraRolls"] == true

			for j = 1, MaxPlayers[rollID] do
				local name = RollerName[rollID][j]
				if name and name ~= "" then
					local legit = RaidRoll_LegitRoll and RaidRoll_LegitRoll[rollID] and RaidRoll_LegitRoll[rollID][j]
					local first = RollerFirst and RollerFirst[rollID] and RollerFirst[rollID][j]
					local hidden = (legit == false and not acceptAll) or (not allowExtra and first == false)

					if not hidden then
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

						row.pos:SetText(tostring(j))

						-- Chat-claim mark: additive prefix only, doesn't touch the
						-- ignored/class-color logic below (RaidRoll_DB["ChatClaims"]
						-- is written by RaidRoll_OnLoad.lua's RR_RecordChatClaim
						-- during the MS/OS buttons' 20-second listening window).
						local claimMark = ""
						if RaidRoll_DB and RaidRoll_DB["ChatClaims"] and RaidRoll_DB["ChatClaims"][nameLower] then
							claimMark = "|cFFFFD200*|r "
						end

						local color = (RollerColor and RollerColor[rollID] and RollerColor[rollID][j]) or ""
						if ignored then
							row.name:SetTextColor(0.6, 0.3, 0.3)
							row.name:SetText(claimMark .. name)
						else
							row.name:SetTextColor(1, 1, 1)
							if color ~= "" then
								row.name:SetText(claimMark .. color .. name .. "|r")
							else
								row.name:SetText(claimMark .. name)
							end
						end

						if opts and opts["RR_EPGP_Enabled"] == true then
							local pr = RR_EPGP_PRValue and RR_EPGP_PRValue[rollID] and RR_EPGP_PRValue[rollID][j] or 0
							local above = RR_EPGPAboveThreshold and RR_EPGPAboveThreshold[rollID] and RR_EPGPAboveThreshold[rollID][j]
							row.roll:SetTextColor(above and 0.67 or 0.77, above and 0.83 or 0.12, above and 0.45 or 0.23)
							row.roll:SetText(tostring(pr))
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
						end

						local markIcon = opts and opts["RR_NameMark"] and opts["RR_NameMark"][nameLower]
						row.mark.text:SetText(markIcon and (opts["RR_PlayerIcon"] and opts["RR_PlayerIcon"][nameLower]) or "")
						row.mark:SetBackdropColor(ignored and 0.3 or 0.06, ignored and 0.08 or 0.06, ignored and 0.08 or 0.06, 0.95)

						local link = rr_Item and rr_Item[rollID]
						row.itemLink = link and link:find("item:") and link or nil

						row:Show()
					end
				end
			end
		end

		for i = count + 1, #rows do
			rows[i].index = nil
			rows[i]:Hide()
		end
	end

	return { frame = parent, Refresh = Refresh }
end
