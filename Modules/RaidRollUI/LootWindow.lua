-- The "Loot" tab: a black/white replacement for RR_LOOT_FRAME, plus a new
-- flattened "every item + winner" summary view built on top of the WINNER/
-- RECEIVED fields Hook.lua now actually populates. Paging/clearing/linking
-- drive RaidRoll_LootTracker's existing functions (RR_Loot_GotoWindow,
-- RR_ClearItems, RR_LinkLoot, RR_AnnounceMsg, RR_Command) - item data is read
-- directly from RaidRoll_DB["Loot"] instead of calling the native
-- RR_Loot_Display_Refresh(), which paints straight into RaidRoll's own
-- fontstrings (same reasoning as the Rolls tab).
JohnnysRaidRoll.RaidRollUI = JohnnysRaidRoll.RaidRollUI or {}
local RaidRollUI = JohnnysRaidRoll.RaidRollUI
local Skin = JohnnysRaidRoll.Skin

local ROW_HEIGHT = 40

StaticPopupDialogs["JAHUB_RAIDROLL_CLEARLOOT"] = {
	text = "Clear all tracked loot data? This cannot be undone.",
	button1 = "Clear",
	button2 = "Cancel",
	OnAccept = function()
		RR_ClearItems()
		RR_LastLootMessageTime = 0
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- Announces a dedicated "Main Spec Change"/"Off Spec Change" message for the
-- currently active roll's item (not the M1/M2/M3 "Roll [Item] Main Spec"
-- templates, which are a separate, pre-existing feature) and opens the
-- 20-second chat-claim window (RR_StartChatClaimWindow, RaidRoll_OnLoad.lua)
-- so need/ms/want replies get recorded.
local function AnnounceSpecChange(kind)
	if not RR_GetAnnounceChannel then
		return
	end
	local itemLink = rr_Item and rr_CurrentRollID and rr_Item[rr_CurrentRollID]
	if itemLink == ("ID #" .. tostring(rr_CurrentRollID)) then
		itemLink = nil
	end

	local label = (kind == "MS") and "Main Spec Change" or "Off Spec Change"
	local message = itemLink and (label .. ": " .. itemLink) or label

	SendChatMessage(message, RR_GetAnnounceChannel())
	if RR_StartChatClaimWindow then
		RR_StartChatClaimWindow(itemLink, 20)
	end
end

local function CanAnnounce()
	if GetNumRaidMembers() ~= 0 then
		return IsRaidLeader() ~= nil or IsRaidOfficer() ~= nil
	end
	return true
end

local function CurrentWindowData()
	local loot = RaidRoll_DB and RaidRoll_DB["Loot"]
	if not loot then
		return nil, 0
	end
	local window = loot["CURRENT WINDOW"]
	if not window or not loot[window] then
		return nil, 0
	end
	return loot[window], loot[window]["TOTAL ITEMS"] or 0
end

local function CreateLootRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(1, ROW_HEIGHT)
	Skin:StylePanel(row, 0.5)

	local icon = CreateFrame("Button", nil, row)
	icon:SetSize(32, 32)
	icon:SetPoint("LEFT", 4, 0)
	local tex = icon:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	icon.tex = tex

	icon:SetScript("OnEnter", function(self)
		if not self.itemLink then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self.itemLink)
		GameTooltip:Show()
	end)
	icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	icon:SetScript("OnClick", function(self)
		if not self.itemLink then
			return
		end
		if IsControlKeyDown() then
			DressUpItemLink(self.itemLink)
		elseif IsShiftKeyDown() then
			ChatEdit_InsertLink(self.itemLink)
		end
	end)
	row.icon = icon

	local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -2)
	nameText:SetJustifyH("LEFT")
	row.nameText = nameText

	local statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 2)
	statusText:SetJustifyH("LEFT")
	statusText:SetTextColor(0.7, 0.7, 0.7)
	row.statusText = statusText

	local raidRollBtn = Skin:CreateButton(row, 66, 20, "Raid Roll")
	raidRollBtn:SetPoint("RIGHT", -4, 0)
	row.raidRollBtn = raidRollBtn

	local m3 = Skin:CreateButton(row, 32, 20, "M3")
	m3:SetPoint("RIGHT", raidRollBtn, "LEFT", -4, 0)
	local m2 = Skin:CreateButton(row, 32, 20, "M2")
	m2:SetPoint("RIGHT", m3, "LEFT", -2, 0)
	local m1 = Skin:CreateButton(row, 32, 20, "M1")
	m1:SetPoint("RIGHT", m2, "LEFT", -2, 0)
	row.m1, row.m2, row.m3 = m1, m2, m3

	return row
end

-- M1/M2/M3 default to "Roll [Item] Main Spec"/"Roll [Item] Off Spec"
-- (RaidRoll_OnLoad.lua's RR_SetupVariables) - these are the actual MS/OS
-- announce buttons the player sees and clicks, since RR_RollFrame itself is
-- neutralized by Hook.lua. Starting the chat-claim window here (rather than
-- on RaidRoll's own, invisible native MS/OS buttons) is what actually lets
-- RR_RecordChatClaim (RaidRoll_OnLoad.lua) catch raiders' need/ms/want
-- replies for this item over the next 20 seconds.
local function BuildAnnounceHandler(row, id)
	return function()
		if not row.itemLink or not RR_AnnounceMsg then
			return
		end
		local message, channel = RR_AnnounceMsg(id, row.itemLink)
		if message and message ~= "" then
			SendChatMessage(message, channel)
			if RR_StartChatClaimWindow then
				RR_StartChatClaimWindow(row.itemLink, 20)
			end
		end
	end
end

local function CreateSummaryRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(1, 20)
	row:SetBackdrop({ bgFile = Skin.WHITE })
	row:SetBackdropColor(0, 0, 0, 0)

	local cols = { "mob", "item", "ilvl", "winner", "received" }
	local widths = { mob = 120, item = 220, ilvl = 40, winner = 110, received = 130 }
	local x = 4
	for _, key in ipairs(cols) do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", row, "LEFT", x, 0)
		fs:SetWidth(widths[key] - 6)
		fs:SetJustifyH("LEFT")
		row[key] = fs
		x = x + widths[key]
	end

	return row
end

function RaidRollUI.BuildLootTab(parent)
	local pagedRows = {}
	local summaryRows = {}
	local showingSummary = false
	local sortColumn, sortAscending = nil, false

	local header = CreateFrame("Frame", nil, parent)
	header:SetPoint("TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", 0, 0)
	header:SetHeight(24)

	local infoText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	infoText:SetPoint("LEFT", 4, 0)
	infoText:SetTextColor(1, 1, 1)
	infoText:SetJustifyH("LEFT")
	infoText:SetWidth(360)

	local summaryBtn = Skin:CreateButton(header, 90, 22, "Summary")
	summaryBtn:SetPoint("RIGHT", 0, 0)

	-- Paged (per-window) view.
	local pagedFrame = CreateFrame("Frame", nil, parent)
	pagedFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	pagedFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 40)

	-- Named so UIPanelScrollFrameTemplate's "$parent..." child regions (the
	-- scrollbar) don't collide with other anonymous scrollframes' children.
	local pagedScroll = CreateFrame("ScrollFrame", "JohnnysAddonHubRaidRollLootPagedScroll", pagedFrame, "UIPanelScrollFrameTemplate")
	pagedScroll:SetPoint("TOPLEFT", 0, 0)
	pagedScroll:SetPoint("BOTTOMRIGHT", -30, 0)

	local pagedContent = CreateFrame("Frame", nil, pagedScroll)
	pagedContent:SetSize(1, 20)
	pagedScroll:SetScrollChild(pagedContent)

	local function LayoutPagedRows()
		-- pagedContent's own declared width is nominal (rows are given an
		-- explicit width below, not derived from it) - but it still has to be
		-- at least as wide as the rows for the scrollframe's clip region to
		-- show them fully, since a single TOPLEFT anchor + SetWidth (not a
		-- second opposing anchor) is what actually sizes each row here.
		local w = pagedScroll:GetWidth()
		pagedContent:SetWidth(w)
		for i, row in ipairs(pagedRows) do
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", pagedContent, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
			row:SetWidth(w)
		end
		pagedContent:SetHeight(math.max(20, #pagedRows * ROW_HEIGHT))
	end

	-- Summary (all windows, flattened) view.
	local summaryFrame = CreateFrame("Frame", nil, parent)
	summaryFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	summaryFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 40)
	summaryFrame:Hide()

	local summaryColHeader = CreateFrame("Frame", nil, summaryFrame)
	summaryColHeader:SetPoint("TOPLEFT", 0, 0)
	summaryColHeader:SetHeight(18)
	local SUMMARY_LABELS = { mob = "Mob", item = "Item", ilvl = "iLvl", winner = "Winner", received = "Received" }
	local SUMMARY_WIDTHS = { mob = 120, item = 220, ilvl = 40, winner = 110, received = 130 }
	local sx = 4
	for _, key in ipairs({ "mob", "item", "ilvl", "winner", "received" }) do
		local btn = CreateFrame("Button", nil, summaryColHeader)
		btn:SetPoint("LEFT", summaryColHeader, "LEFT", sx, 0)
		btn:SetSize(SUMMARY_WIDTHS[key], 18)
		local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", 2, 0)
		fs:SetTextColor(0.7, 0.7, 0.7)
		fs:SetText(SUMMARY_LABELS[key])
		btn:SetScript("OnClick", function()
			if sortColumn == key then
				sortAscending = not sortAscending
			else
				sortColumn, sortAscending = key, true
			end
			RaidRollUI.RefreshLootTab()
		end)
		sx = sx + SUMMARY_WIDTHS[key]
	end

	local summaryScroll = CreateFrame("ScrollFrame", "JohnnysAddonHubRaidRollLootSummaryScroll", summaryFrame, "UIPanelScrollFrameTemplate")
	summaryScroll:SetPoint("TOPLEFT", summaryColHeader, "BOTTOMLEFT", 0, -2)
	summaryScroll:SetPoint("BOTTOMRIGHT", -30, 0)

	local summaryContent = CreateFrame("Frame", nil, summaryScroll)
	summaryContent:SetSize(1, 20)
	summaryScroll:SetScrollChild(summaryContent)

	local function LayoutSummaryRows()
		local w = summaryScroll:GetWidth()
		summaryContent:SetWidth(w)
		for i, row in ipairs(summaryRows) do
			row:SetWidth(w)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", summaryContent, "TOPLEFT", 0, -(i - 1) * 20)
		end
		summaryContent:SetHeight(math.max(20, #summaryRows * 20))
	end

	-- Bottom control bar (paged view only).
	local firstBtn = Skin:CreateButton(parent, 40, 22, "<<")
	firstBtn:SetPoint("BOTTOMLEFT", 0, 0)
	firstBtn:SetScript("OnClick", function() RR_Loot_GotoWindow("First") end)

	local prevBtn = Skin:CreateButton(parent, 40, 22, "<")
	prevBtn:SetPoint("LEFT", firstBtn, "RIGHT", 4, 0)
	prevBtn:SetScript("OnClick", function() RR_Loot_GotoWindow("Prev") end)

	local nextBtn = Skin:CreateButton(parent, 40, 22, ">")
	nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
	nextBtn:SetScript("OnClick", function() RR_Loot_GotoWindow("Next") end)

	local lastBtn = Skin:CreateButton(parent, 40, 22, ">>")
	lastBtn:SetPoint("LEFT", nextBtn, "RIGHT", 4, 0)
	lastBtn:SetScript("OnClick", function() RR_Loot_GotoWindow("Last") end)

	local clearBtn = Skin:CreateButton(parent, 90, 22, "Clear Data")
	clearBtn:SetPoint("BOTTOMRIGHT", 0, 0)
	clearBtn:SetScript("OnClick", function() StaticPopup_Show("JAHUB_RAIDROLL_CLEARLOOT") end)

	local msChangeBtn = Skin:CreateButton(parent, 100, 22, "MS Change")
	msChangeBtn:SetPoint("BOTTOMLEFT", lastBtn, "BOTTOMRIGHT", 24, 0)
	msChangeBtn:SetScript("OnClick", function() AnnounceSpecChange("MS") end)
	msChangeBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Announce Main Spec Change + open 20s claim window", 1, 1, 1)
		GameTooltip:Show()
	end)
	msChangeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local osChangeBtn = Skin:CreateButton(parent, 100, 22, "OS Change")
	osChangeBtn:SetPoint("LEFT", msChangeBtn, "RIGHT", 4, 0)
	osChangeBtn:SetScript("OnClick", function() AnnounceSpecChange("OS") end)
	osChangeBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Announce Off Spec Change + open 20s claim window", 1, 1, 1)
		GameTooltip:Show()
	end)
	osChangeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local linkBtn = Skin:CreateButton(parent, 90, 22, "Link Loot")
	linkBtn:SetPoint("RIGHT", clearBtn, "LEFT", -4, 0)
	linkBtn:SetScript("OnClick", function()
		if RR_LinkLoot then RR_LinkLoot() end
	end)

	local function RefreshPaged()
		local window, total = CurrentWindowData()
		local loot = RaidRoll_DB and RaidRoll_DB["Loot"]
		local totalWindows = (loot and loot["TOTAL WINDOWS"]) or 0
		local currentWindow = (loot and loot["CURRENT WINDOW"]) or 0

		if window then
			infoText:SetText(string.format("%s  (looted by %s)  [%d/%d]",
				tostring(window["MOB NAME"] or "?"), tostring(window["LOOTER NAME"] or "?"), currentWindow, totalWindows))
		else
			infoText:SetText("No loot tracked yet")
		end

		local function SetEnabled(btn, enabled)
			if enabled then btn:Enable() else btn:Disable() end
		end
		SetEnabled(firstBtn, currentWindow > 1)
		SetEnabled(prevBtn, currentWindow > 1)
		SetEnabled(nextBtn, currentWindow > 0 and currentWindow < totalWindows)
		SetEnabled(lastBtn, currentWindow > 0 and currentWindow < totalWindows)

		local canAnnounce = CanAnnounce()
		local enable3 = RaidRoll_DBPC and UnitName and RaidRoll_DBPC[UnitName("player")]
			and RaidRoll_DBPC[UnitName("player")]["RR_Enable3Messages"] == true

		for i = 1, total do
			local item = window["ITEM_" .. i]
			local row = pagedRows[i]
			if not row then
				row = CreateLootRow(pagedContent)
				pagedRows[i] = row
				row.m1:SetScript("OnClick", BuildAnnounceHandler(row, 1))
				row.m2:SetScript("OnClick", BuildAnnounceHandler(row, 2))
				row.m3:SetScript("OnClick", BuildAnnounceHandler(row, 3))
				row.raidRollBtn:SetScript("OnClick", function()
					if row.itemLink and RR_Command then
						RR_Command(row.itemLink)
					end
				end)
				LayoutPagedRows()
			end

			if item then
				row.itemLink = item.ITEMLINK
				row.icon.itemLink = item.ITEMLINK
				row.icon.tex:SetTexture(item.ICON)
				row.nameText:SetText(string.format("%d. %s", i, item.ITEMLINK or "?"))
				local winner = item.WINNER
				if winner and winner ~= "-" then
					row.statusText:SetTextColor(0.6, 1, 0.6)
					row.statusText:SetText("Won by " .. winner .. ((item.RECEIVED and item.RECEIVED ~= "-") and (" - " .. item.RECEIVED) or ""))
				else
					row.statusText:SetTextColor(0.7, 0.7, 0.7)
					row.statusText:SetText("Unclaimed")
				end

				row.m1:SetWidth(enable3 and 32 or 50)
				row.m2:SetWidth(enable3 and 32 or 50)
				if canAnnounce then
					row.m1:Show()
					row.m2:Show()
					if enable3 then row.m3:Show() else row.m3:Hide() end
					row.raidRollBtn:Show()
				else
					row.m1:Hide()
					row.m2:Hide()
					row.m3:Hide()
					row.raidRollBtn:Hide()
				end
			end
			row:Show()
		end

		for i = total + 1, #pagedRows do
			pagedRows[i]:Hide()
		end
	end

	local function SortValue(entry, column)
		if column == "ilvl" then
			return tonumber(entry.ilvl) or 0
		elseif column == "winner" then
			return entry.winner or ""
		elseif column == "received" then
			return entry.received or ""
		elseif column == "mob" then
			return entry.mob or ""
		end
		return entry.item or ""
	end

	-- Defense-in-depth for the cross-window dedup Hook.lua's RecordLootedItem/
	-- UndoPhantomBroadcastDuplicate already do at write time: if a still-
	-- unclaimed item (same MOB NAME + item identity) shows up twice across
	-- windows, only the first is listed here. Once an item has a WINNER, a
	-- later match is a genuine second drop and stays its own row.
	local function ItemIdOf(itemLink)
		local _, id = strsplit(":", itemLink or "", 3)
		return id
	end

	local function RefreshSummary()
		local loot = RaidRoll_DB and RaidRoll_DB["Loot"]
		local flat = {}
		local unclaimedSeen = {}

		if loot and loot["TOTAL WINDOWS"] then
			for w = 1, loot["TOTAL WINDOWS"] do
				local win = loot[w]
				if win and win["TOTAL ITEMS"] then
					for i = 1, win["TOTAL ITEMS"] do
						local item = win["ITEM_" .. i]
						if item then
							local isUnclaimed = not (item.WINNER and item.WINNER ~= "-")
							local key = isUnclaimed and ((win["MOB NAME"] or "") .. "\1" .. (ItemIdOf(item.ITEMLINK) or ""))
							if not (isUnclaimed and key and unclaimedSeen[key]) then
								if isUnclaimed and key then
									unclaimedSeen[key] = true
								end
								table.insert(flat, {
									mob = win["MOB NAME"],
									item = item.ITEMLINK,
									ilvl = item.ITEMLEVEL,
									winner = (item.WINNER and item.WINNER ~= "-") and item.WINNER or nil,
									received = (item.RECEIVED and item.RECEIVED ~= "-") and item.RECEIVED or nil,
								})
							end
						end
					end
				end
			end
		end

		if sortColumn then
			table.sort(flat, function(a, b)
				local av, bv = SortValue(a, sortColumn), SortValue(b, sortColumn)
				if sortAscending then return av < bv end
				return av > bv
			end)
		end

		for i, entry in ipairs(flat) do
			local row = summaryRows[i]
			if not row then
				row = CreateSummaryRow(summaryContent)
				summaryRows[i] = row
				LayoutSummaryRows()
			end
			row.mob:SetText(tostring(entry.mob or "?"))
			row.item:SetText(entry.item or "?")
			row.ilvl:SetText(tostring(entry.ilvl or ""))
			if entry.winner then
				row.winner:SetTextColor(0.6, 1, 0.6)
				row.winner:SetText(entry.winner)
			else
				row.winner:SetTextColor(0.7, 0.4, 0.4)
				row.winner:SetText("Unclaimed")
			end
			row.received:SetTextColor(0.7, 0.7, 0.7)
			row.received:SetText(entry.received or "")
			row:Show()
		end

		for i = #flat + 1, #summaryRows do
			summaryRows[i]:Hide()
		end
	end

	local function Refresh()
		if showingSummary then
			RefreshSummary()
		else
			RefreshPaged()
		end
	end
	RaidRollUI.RefreshLootTab = Refresh

	local function SetShown(frame, shown)
		if shown then frame:Show() else frame:Hide() end
	end

	summaryBtn:SetScript("OnClick", function()
		showingSummary = not showingSummary
		SetShown(pagedFrame, not showingSummary)
		SetShown(summaryFrame, showingSummary)
		SetShown(firstBtn, not showingSummary)
		SetShown(prevBtn, not showingSummary)
		SetShown(nextBtn, not showingSummary)
		SetShown(lastBtn, not showingSummary)
		SetShown(linkBtn, not showingSummary)
		summaryBtn.text:SetText(showingSummary and "Per-Loot" or "Summary")
		Refresh()
	end)

	return { frame = parent, Refresh = Refresh }
end
