-- RaidRoll's roll-detection/sorting/master-loot-award engine (RaidRoll_OnLoad.lua,
-- RaidRoll_ExtraRollFrames.lua) stays completely untouched - this file only (a)
-- silences RaidRoll's own native windows so our black/white frame is the only
-- thing the player sees, (b) fills in gaps in RaidRoll's data model:
-- RaidRoll_DB["Loot"][window]["ITEM_n"].WINNER/.RECEIVED exist in the schema
-- but nothing ever writes them, and neither does anything write a corpse's
-- items into our own RaidRoll_DB when we're the one who looted it (RaidRoll's
-- loot tracker only writes on *receiving* another player's "RRL" addon
-- message - SendAddonMessage never loops back to its own sender), and (c)
-- makes sure RaidRoll's countdown/winner chat announcements only ever fire
-- from the raid leader's client, since Neutralize() below keeps their
-- OnUpdate ticker (and so RR_Update_Name_Frame's announce checks) running
-- permanently for every player regardless of raid role. Everything here is
-- additive - no file under RaidRoll\, RaidRoll_EPGP\ or RaidRoll_LootTracker\
-- is edited.
JohnnysRaidRoll.RaidRollUI = JohnnysRaidRoll.RaidRollUI or {}
local RaidRollUI = JohnnysRaidRoll.RaidRollUI

local lockedDown = false
local hooked = false
local lastAutoOpenWindowCount = 0

-- RR_Display() (RaidRoll_OnLoad.lua) is the only thing that ever shows
-- RR_RollFrame/RR_NAME_FRAME, and it's gated on this exact flag - see
-- RaidRoll_OnLoad.lua:1867. Setting it off once silences the native roll
-- window with zero loss of engine functionality (roll capture, sorting,
-- RR_FindWinner and master-loot award all run identically either way).
local function DisableNativeTracking()
	if RaidRoll_DBPC and UnitName then
		RaidRoll_DBPC[UnitName("player")] = RaidRoll_DBPC[UnitName("player")] or {}
		RaidRoll_DBPC[UnitName("player")]["RR_Roll_Tracking_Enabled"] = false
	end
end

-- RaidRoll's countdown/winner chat announcements (RaidRoll_OnLoad.lua:
-- 1553-1633, inside RR_Update_Name_Frame) are gated only by this per-
-- character saved flag (RR_Update_Name_Frame even flips RR_RollCountdown on
-- purely because a roll is active and this flag is set - :1495-1503 - with
-- no concept of "am I the one running this roll"). The other gate,
-- RR_AnnounceCountdowns, only ever becomes true via local button clicks
-- (RR_FinishRolling, the "finish rolling early" button -
-- RaidRoll_ExtraRollFrames.lua:333/686) that our Rolls tab doesn't expose,
-- so it isn't a separate leak path here. Forcing this flag off for everyone
-- except the raid leader is what actually stops a non-leader's client from
-- broadcasting, regardless of how long Neutralize()'s OnUpdate ticker below
-- has been running in the background or what the Settings tab checkbox
-- shows.
local function EnforceAnnounceGate()
	if not (RaidRoll_DBPC and UnitName) then
		return
	end
	if IsRaidLeader and IsRaidLeader() then
		return
	end
	local pc = RaidRoll_DBPC[UnitName("player")]
	if pc and pc["RR_RollCheckBox_Auto_Announce"] == true then
		pc["RR_RollCheckBox_Auto_Announce"] = false
	end
end

-- RR_Command("toggle"/"show") and the loot tracker's auto-open-on-loot path
-- (RaidRoll_LootTracker.lua) call these frames' :Show() directly, bypassing
-- the flag above - belt-and-suspenders hide-on-show for those paths.
local function ForceHide(frame)
	if not frame then
		return
	end
	frame:HookScript("OnShow", function(self)
		self:Hide()
	end)
	if frame:IsShown() then
		frame:Hide()
	end
end

-- RR_RollFrame can't just be Hide()'d like RR_LOOT_FRAME: RR_NAME_FRAME
-- (RaidRoll_ExtraRollFrames.lua:562, "CreateFrame('Frame',nil,RR_RollFrame)")
-- is its child, and its OnUpdate ticker (RaidRoll_OnLoad.lua:1663) - which is
-- what actually SendChatMessage's the "10 seconds left"/"5 seconds left"/
-- auto-winner announcements (RaidRoll_OnLoad.lua:1567-1631) - only fires
-- while every frame in its ancestor chain is shown. A hidden RR_RollFrame
-- silently kills those announcements even though nothing else about the
-- engine changes. Alpha 0 + off-screen + mouse-disabled keeps both frames
-- technically "shown" (so OnUpdate keeps ticking) while making them
-- physically invisible and unclickable - functionally equivalent to hiding
-- them, without the OnUpdate side effect.
local OFFSCREEN = -32000
local function Neutralize(frame)
	if not frame then
		return
	end
	frame:EnableMouse(false)
	frame:SetAlpha(0)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", OFFSCREEN, OFFSCREEN)
	frame:Show()
	-- Re-assert on every OnShow (covers RR_Command("show")/("toggle") calling
	-- :Show() again, which wouldn't otherwise re-run the lines above) and
	-- immediately reverse any :Hide() call (RR_Command("toggle") hides both
	-- frames when currently shown - this makes that a same-tick no-op instead
	-- of actually stopping the OnUpdate chain).
	frame:HookScript("OnShow", function(self)
		self:EnableMouse(false)
		self:SetAlpha(0)
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", OFFSCREEN, OFFSCREEN)
	end)
	frame:HookScript("OnHide", function(self)
		self:Show()
	end)
end

-- RR_Update_Name_Frame's OnUpdate loop (see comment on Neutralize above) only
-- starts once RR_Update_Name_Frame has run at least once - normally that
-- first call comes from RR_Display(), itself only reachable through a manual
-- window interaction. Bootstrapping it here means the 10-sec/5-sec/winner
-- announcements work without requiring the player to click anything first.
-- Before the very first roll of the session, RaidRoll's own per-roll tables
-- (RollerFirst etc.) don't exist yet and RR_Display would error on them, so
-- this is pcall'd and retried every few seconds (from the ticker below) until
-- one attempt succeeds - by the time the first roll actually starts, that
-- data exists (rr_RollSort creates it), so a retry lands well before any
-- 10-second mark could be missed.
local countdownBootstrapped = false
local function TryBootstrapCountdownTicker()
	if countdownBootstrapped then
		return
	end
	if type(RR_Display) ~= "function" or rr_CurrentRollID == nil then
		return
	end
	if pcall(RR_Display, rr_CurrentRollID) then
		countdownBootstrapped = true
	end
end

local function LockdownNativeFrames()
	if lockedDown then
		return
	end
	if not RR_RollFrame then
		return -- RaidRoll hasn't finished loading yet
	end
	lockedDown = true
	DisableNativeTracking()
	EnforceAnnounceGate()
	Neutralize(RR_RollFrame)
	Neutralize(RR_NAME_FRAME)
	ForceHide(RR_LOOT_FRAME)
	TryBootstrapCountdownTicker()

	-- ForceHide(RR_LOOT_FRAME) above silences RaidRoll's own "auto-open on new
	-- loot" call along with everything else about that frame - seed the
	-- counter MaybeAutoOpenLootWindow() compares against from whatever's
	-- already in RaidRoll_DB at this point, so stale/previous-session loot
	-- data doesn't cause an immediate spurious auto-open right at login.
	lastAutoOpenWindowCount = (RaidRoll_DB and RaidRoll_DB["Loot"] and RaidRoll_DB["Loot"]["TOTAL WINDOWS"]) or 0
end

local bootstrapRetryFrame = CreateFrame("Frame")
local bootstrapElapsed = 0
bootstrapRetryFrame:SetScript("OnUpdate", function(self, e)
	if countdownBootstrapped then
		self:SetScript("OnUpdate", nil)
		return
	end
	bootstrapElapsed = bootstrapElapsed + e
	if bootstrapElapsed >= 3 then
		bootstrapElapsed = 0
		TryBootstrapCountdownTicker()
	end
end)

local function TitleCase(name)
	if not name or name == "" then
		return name
	end
	return name:sub(1, 1):upper() .. name:sub(2):lower()
end

-- Mirrors RR_SendItemInfo's accept-rules (RaidRoll_OnLoad.lua:184-240) so a
-- corpse we loot ourselves ends up with the same set of items in our own
-- RaidRoll_DB that a broadcast from someone else looting it would have given
-- us - this isn't a way to widen or narrow what RaidRoll considers "loot
-- worth tracking", just keeping our self-recorded items consistent with it.
local RARE_ITEM_WHITELIST = {
	[46110] = true, -- Alchemist's Cache
	[47556] = true, -- Crusader Orb
	[45087] = true, -- Runed Orb
	[49908] = true, -- Primordial Saronite
}

local EPIC_ITEM_BLACKLIST = {
	[34057] = true, -- Abyss Crystal
	[36931] = true, -- Ametrine
	[36919] = true, -- Cardinal Ruby
	[36928] = true, -- Dreadstone
	[36934] = true, -- Eye of Zul
	[36922] = true, -- King's Amber
	[36925] = true, -- Majestic Zircon
	[47241] = true, -- Emblem of Triumph
	[49426] = true, -- Emblem of Frost
}

local ACCEPTABLE_ZONES = {
	["Trial of the Crusader"] = true,
	["Icecrown Citadel"] = true,
	["Naxxramas"] = true,
	["Onyxia's Lair"] = true,
	["The Eye of Eternity"] = true,
	["The Obsidian Sanctum"] = true,
	["Ulduar"] = true,
	["Vault of Archavon"] = true,
}

local function IsAcceptableZone()
	if ACCEPTABLE_ZONES[GetRealZoneText()] then
		return true
	end
	-- RR_Frame_WotLK_Dung_Only == false means "also accept any raid instance,
	-- not just the WotLK zones above" - RaidRoll_OnLoad.lua:233-240.
	if RaidRoll_DBPC and UnitName and RaidRoll_DBPC[UnitName("player")]
		and RaidRoll_DBPC[UnitName("player")]["RR_Frame_WotLK_Dung_Only"] == false then
		local _, insType = GetInstanceInfo()
		if insType == "raid" then
			return true
		end
	end
	return false
end

local function ShouldTrackLootSlot(itemId, rarity)
	if itemId and EPIC_ITEM_BLACKLIST[itemId] then
		return false
	end
	if itemId and RARE_ITEM_WHITELIST[itemId] then
		return true
	end
	return rarity ~= nil and rarity > 3
end

-- Replaces RaidRoll's own "RR_AutoOpenLootWindow" auto-open
-- (RaidRoll_LootTracker.lua:391/538, RR_LOOT_FRAME:Show()) - that call still
-- happens natively on the receive path, but ForceHide() above immediately
-- re-hides RR_LOOT_FRAME no matter who calls :Show() on it, and nothing
-- previously opened our own replacement window in its place. Called after
-- every write to RaidRoll_DB["Loot"] (both our own self-loot scan below and,
-- via the hooksecurefunc on RR_AddonMessageReceived in EnsureHooked, other
-- players' broadcasts) and only actually opens the window when
-- "TOTAL WINDOWS" just grew - i.e. a genuinely new corpse, not every single
-- item within one - matching RaidRoll's own auto-open granularity.
local function MaybeAutoOpenLootWindow()
	local loot = RaidRoll_DB and RaidRoll_DB["Loot"]
	local total = (loot and loot["TOTAL WINDOWS"]) or 0
	local isNewWindow = total > lastAutoOpenWindowCount
	lastAutoOpenWindowCount = total
	if not isNewWindow then
		return
	end
	if not (RaidRoll_DBPC and UnitName and RaidRoll_DBPC[UnitName("player")]
		and RaidRoll_DBPC[UnitName("player")]["RR_AutoOpenLootWindow"] == true) then
		return
	end
	if JohnnysRaidRoll.RaidLootUI and JohnnysRaidRoll.RaidLootUI.Show then
		JohnnysRaidRoll.RaidLootUI:Show()
	end
end

-- Cross-window duplicate guard: someone re-opening a corpse whose loot is
-- still sitting there (checking it again before handing an item out, a
-- second raider peeking at the same corpse, etc.) re-triggers RR_SendItemInfo
-- and re-announces items that were already recorded - but more than 30
-- seconds after the original recording, which lands them in a brand-new
-- window instead of tripping the same-window dedup below. Searches windows
-- strictly before `beforeWindow` (the current-window check above already
-- covers the latest one) for an entry matching this item's identity and MOB
-- NAME that's still unclaimed - same "unclaimed + look back a handful of
-- windows" idiom FindUnclaimedLootEntry uses further down for roll winners.
-- Requiring "still unclaimed" is what keeps a genuine second drop (the same
-- item dropping again after the first copy was already awarded) from being
-- folded away. Known accepted limitation: two separate kills of the same
-- trash mob type dropping the same item while the first copy is still
-- unclaimed would also fold together here - matching by MOB NAME rather than
-- the corpse's actual GUID is the best available signal, since the "Beta_2"
-- broadcast protocol RaidRoll uses doesn't carry one.
local function FindUnclaimedDuplicate(mobName, itemLink, beforeWindow)
	local loot = RaidRoll_DB and RaidRoll_DB["Loot"]
	if not loot or not beforeWindow or beforeWindow < 1 then
		return nil
	end
	local _, itemId = strsplit(":", itemLink or "", 3)
	if not itemId then
		return nil
	end

	local window = beforeWindow
	local windowsChecked = 0
	while window and window >= 1 and windowsChecked < 6 do
		local win = loot[window]
		if win and win["MOB NAME"] == mobName and win["TOTAL ITEMS"] then
			for i = 1, win["TOTAL ITEMS"] do
				local item = win["ITEM_" .. i]
				if item and item.WINNER == "-" and item.ITEMLINK then
					local _, thisId = strsplit(":", item.ITEMLINK, 3)
					if thisId == itemId then
						return item
					end
				end
			end
		end
		window = window - 1
		windowsChecked = windowsChecked + 1
	end
	return nil
end

-- Writes using the exact schema RR_AddonMessageReceived writes
-- (RaidRoll_LootTracker.lua:404-487): same TOTAL WINDOWS/CURRENT WINDOW
-- bookkeeping, same 30-second new-window threshold (sharing its actual
-- RR_LastLootMessageTime global so a corpse's items land in one window
-- whether they arrive via broadcast, our own scan, or both), same per-item
-- fields, and the same dedup-by-LOOTNAME-within-the-current-window check
-- RR_DuplicateItemFound does - so this is safe to call even if a given
-- server core turns out to loop "RRL" addon messages back to their own
-- sender after all.
--
-- winner/receivedAt are optional - HandleChatMsgLoot (below) already knows who
-- received the item at capture time, while ScanAndRecordOwnLoot doesn't. If a
-- duplicate LOOTNAME is found in the current window and it hasn't been
-- credited to anyone yet, this fills in WINNER/RECEIVED on that existing
-- entry instead of just bailing out, so the two capture paths merge into one
-- row no matter which of them happens to run first for a given item.
local function RecordLootedItem(mobName, looterName, lootName, itemLink, icon, itemLevel, winner, receivedAt)
	if not RaidRoll_DB then
		return
	end
	if RaidRoll_DB["Loot"] == nil then RaidRoll_DB["Loot"] = {} end
	local loot = RaidRoll_DB["Loot"]
	if loot["TOTAL WINDOWS"] == nil then loot["TOTAL WINDOWS"] = 0 end
	if loot["CURRENT WINDOW"] == nil then loot["CURRENT WINDOW"] = 0 end

	local totalWindows = loot["TOTAL WINDOWS"]
	if totalWindows > 0 and loot[totalWindows] and loot[totalWindows]["TOTAL ITEMS"] then
		for i = 1, loot[totalWindows]["TOTAL ITEMS"] do
			local existing = loot[totalWindows]["ITEM_" .. i]
			if existing and existing.LOOTNAME == lootName then
				if winner and (existing.WINNER == nil or existing.WINNER == "-") then
					existing.WINNER = winner
					existing.RECEIVED = receivedAt or existing.RECEIVED
				end
				return -- duplicate, same as RR_DuplicateItemFound
			end
		end
	end

	if totalWindows > 0 then
		local crossWindowMatch = FindUnclaimedDuplicate(mobName, itemLink, totalWindows - 1)
		if crossWindowMatch then
			if winner and (crossWindowMatch.WINNER == nil or crossWindowMatch.WINNER == "-") then
				crossWindowMatch.WINNER = winner
				crossWindowMatch.RECEIVED = receivedAt or crossWindowMatch.RECEIVED
			end
			return -- re-announcement of an already-recorded, still-unclaimed drop
		end
	end

	if RR_LastLootMessageTime == nil then RR_LastLootMessageTime = 0 end
	if GetTime() > (RR_LastLootMessageTime + 30) then
		RR_LastLootMessageTime = GetTime()
		totalWindows = totalWindows + 1
		loot["TOTAL WINDOWS"] = totalWindows
		if loot["CURRENT WINDOW"] == totalWindows - 1 then
			loot["CURRENT WINDOW"] = totalWindows
		end
	end

	if loot[totalWindows] == nil then loot[totalWindows] = {} end
	local window = loot[totalWindows]
	window["LOOTER NAME"] = looterName
	window["MOB NAME"] = mobName
	if window["TOTAL ITEMS"] == nil then window["TOTAL ITEMS"] = 0 end
	window["TOTAL ITEMS"] = window["TOTAL ITEMS"] + 1

	local itemNumber = window["TOTAL ITEMS"]
	window["ITEM_" .. itemNumber] = {
		LOOTNAME = lootName,
		ITEMLINK = itemLink,
		ICON = icon,
		WINNER = winner or "-",
		RECEIVED = winner and (receivedAt or date("%Y-%m-%d %H:%M:%S")) or "-",
		ITEMLEVEL = itemLevel,
	}

	if RR_Loot_SortByItemLevel then
		RR_Loot_SortByItemLevel()
	end

	MaybeAutoOpenLootWindow()
end

-- Fired on our own LOOT_OPENED (a second, independent listener - RaidRoll's
-- own LOOT_OPENED handler, RaidRoll_OnLoad.lua:74-82, keeps broadcasting to
-- everyone else exactly as before). Without this, whichever corpse *we*
-- loot never shows up in our own Raid Loot window, because RR_SendItemInfo
-- only ever calls SendAddonMessage - it never writes RaidRoll_DB itself, and
-- Blizzard doesn't loop addon messages back to their own sender.
local function ScanAndRecordOwnLoot()
	if not (RaidRoll_DB and RaidRoll_LootTrackerLoaded == true) then
		return
	end
	if UnitInRaid and UnitInRaid("player") == nil then
		return -- mirrors RR_SendItemInfo only ever sending to "RAID"
	end
	if not IsAcceptableZone() then
		return
	end

	local numLootItems = GetNumLootItems()
	if not numLootItems or numLootItems == 0 then
		return
	end

	local playerName = UnitName("player")
	local mobName = UnitName("target") or "Unknown"
	local mobGUID = UnitGUID("target")
	if mobGUID then
		-- Same GUID-type breakdown as RaidRoll_OnLoad.lua:104-114 (3 == NPC).
		local typeBits = tonumber(mobGUID:sub(5, 5), 16)
		if not typeBits or (typeBits % 8) ~= 3 then
			mobName = "Unknown"
		end
	end

	-- Same same-name-collision suffixing as RR_Check_lootName/LootCount in
	-- RR_SendItemInfo (RaidRoll_OnLoad.lua:254-267), so two drops with an
	-- identical name on one corpse don't look like a duplicate to
	-- RecordLootedItem's dedup check above.
	local seenCount = {}
	for i = 1, numLootItems do
		if LootSlotIsItem(i) then
			local icon, lootName, _, rarity = GetLootSlotInfo(i)
			local itemLink = GetLootSlotLink(i)
			if itemLink and lootName then
				local _, _, _, _, itemId = string.find(itemLink,
					"|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
				itemId = tonumber(itemId)

				local dedupedName = lootName
				local count = seenCount[lootName] or 0
				if count > 0 then
					dedupedName = lootName .. count
				end
				seenCount[lootName] = count + 1

				if ShouldTrackLootSlot(itemId, rarity) then
					local _, _, _, itemLevel = GetItemInfo(itemId)
					RecordLootedItem(mobName, playerName, dedupedName, itemLink, icon, tonumber(itemLevel) or 0)
				end
			end
		end
	end
end

-- Universal capture path: ScanAndRecordOwnLoot only sees loot *you* personally
-- open, and the native "RRL" broadcast only reaches you if whoever else
-- looted the item also happens to be running RaidRoll_LootTracker. Neither
-- covers "someone else in the raid loots something and I'm not the looter and
-- they don't run this addon" - which is the common case for anyone who isn't
-- the master looter. CHAT_MSG_LOOT is the server's own loot-announcement
-- system message, sent to every group member for every loot event regardless
-- of addons, so parsing it (the standard technique loot-announcement addons
-- use) closes that gap entirely.
local function BuildLootPattern(globalString)
	if type(globalString) ~= "string" then
		return nil
	end
	-- Protect the "%s"/"%d" placeholders behind unique markers first, escape
	-- every remaining magic character (GLOBALSTRINGS ship with plain
	-- punctuation - colons, periods, "x" - that must be matched literally),
	-- then swap the markers for the real pattern pieces. Doing the escape
	-- pass in between (rather than before) avoids re-escaping the "%" this
	-- function itself introduces for %d+.
	local marked = globalString:gsub("%%s", "\1"):gsub("%%d", "\2")
	local escaped = marked:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
	escaped = escaped:gsub("\1", "(.+)"):gsub("\2", "%%d+")
	return escaped
end

local selfPatterns = {
	BuildLootPattern(LOOT_ITEM_SELF_MULTIPLE),
	BuildLootPattern(LOOT_ITEM_SELF),
}
local otherPatterns = {
	BuildLootPattern(LOOT_ITEM_MULTIPLE),
	BuildLootPattern(LOOT_ITEM),
}

-- GetItemInfo(itemId) can return nil for an item this client has never seen
-- before (not yet cached from the server). There's no GET_ITEM_INFO_RECEIVED
-- event in this client version, so - same style as bootstrapRetryFrame above -
-- poll it back on a short OnUpdate ticker for a few seconds before giving up.
local pendingChatLoot = {}
local chatLootRetryFrame = CreateFrame("Frame")
local chatLootRetryElapsed = 0
chatLootRetryFrame:Hide()
chatLootRetryFrame:SetScript("OnUpdate", function(self, e)
	chatLootRetryElapsed = chatLootRetryElapsed + e
	if chatLootRetryElapsed < 0.5 then
		return
	end
	chatLootRetryElapsed = 0

	local stillPending = {}
	for _, pending in ipairs(pendingChatLoot) do
		local _, _, rarity = GetItemInfo(pending.itemId)
		pending.attempts = pending.attempts + 1
		if rarity then
			if ShouldTrackLootSlot(pending.itemId, rarity) then
				local _, _, _, itemLevel, _, _, _, _, _, icon = GetItemInfo(pending.itemId)
				RecordLootedItem(pending.mobName, pending.recipient, pending.lootName,
					pending.itemLink, icon or pending.icon, tonumber(itemLevel) or 0,
					pending.recipient, pending.receivedAt)
			end
		elseif pending.attempts < 10 then
			table.insert(stillPending, pending)
		end
	end
	pendingChatLoot = stillPending
	if #pendingChatLoot == 0 then
		self:Hide()
	end
end)

local function MatchLootMessage(msg, patterns)
	for _, pattern in ipairs(patterns) do
		if pattern then
			local itemLink = msg:match(pattern)
			if itemLink then
				return itemLink
			end
		end
	end
	return nil
end

local function HandleChatMsgLoot(msg)
	if not (RaidRoll_DB and RaidRoll_LootTrackerLoaded == true) then
		return
	end
	-- Same raid-only/zone-only gating as ScanAndRecordOwnLoot, so this new
	-- capture path honors the same "raid instances only" design the self-loot
	-- scan already enforces, rather than picking up 5-man/world loot too.
	if UnitInRaid and UnitInRaid("player") == nil then
		return
	end
	if not IsAcceptableZone() then
		return
	end

	local recipient
	local itemLink = MatchLootMessage(msg, selfPatterns)
	if itemLink then
		recipient = UnitName("player")
	else
		-- LOOT_ITEM/LOOT_ITEM_MULTIPLE capture the player's name as their
		-- first "(.+)" group and the item link as the second - re-match
		-- against whichever pattern actually hit to pull both out.
		for _, pattern in ipairs(otherPatterns) do
			if pattern then
				local name, link = msg:match(pattern)
				if name and link then
					recipient, itemLink = name, link
					break
				end
			end
		end
	end
	if not recipient or not itemLink then
		return
	end

	local _, itemId = strsplit(":", itemLink, 3)
	itemId = tonumber(itemId)
	if not itemId then
		return
	end

	local lootName = itemLink:match("%[(.-)%]") or itemLink
	local mobName = UnitName("target") or "Unknown"
	local icon = select(10, GetItemInfo(itemId))
	local receivedAt = date("%Y-%m-%d %H:%M:%S")

	local _, _, rarity = GetItemInfo(itemId)
	if rarity == nil then
		table.insert(pendingChatLoot, {
			itemId = itemId,
			itemLink = itemLink,
			lootName = lootName,
			mobName = mobName,
			icon = icon,
			recipient = recipient,
			receivedAt = receivedAt,
			attempts = 0,
		})
		chatLootRetryFrame:Show()
		return
	end

	if ShouldTrackLootSlot(itemId, rarity) then
		local _, _, _, itemLevel = GetItemInfo(itemId)
		RecordLootedItem(mobName, recipient, lootName, itemLink, icon, tonumber(itemLevel) or 0, recipient, receivedAt)
	end
end

-- Searches the current loot window backward through a handful of prior ones
-- for the first still-unclaimed ("-") entry whose item ID matches. Matching
-- by item ID (not an exact link) mirrors what RR_FinishRolling itself already
-- does at RaidRoll_ExtraRollFrames.lua:728-729 when it locates the item on
-- the loot corpse. A corrective re-award of an already-claimed single copy of
-- an item won't find an unclaimed slot to update - RaidRoll's data model has
-- no authoritative link between "a roll" and "a specific loot-drop entry", so
-- this heuristic is the best available without inventing one. That's a known,
-- accepted limitation, not a bug.
local function FindUnclaimedLootEntry(itemId)
	local loot = RaidRoll_DB and RaidRoll_DB["Loot"]
	if not loot or not loot["TOTAL WINDOWS"] or loot["TOTAL WINDOWS"] == 0 then
		return nil
	end

	local window = loot["CURRENT WINDOW"] or loot["TOTAL WINDOWS"]
	local windowsChecked = 0

	while window and window >= 1 and windowsChecked < 6 do
		local win = loot[window]
		if win and win["TOTAL ITEMS"] then
			for i = 1, win["TOTAL ITEMS"] do
				local item = win["ITEM_" .. i]
				if item and item.WINNER == "-" and item.ITEMLINK then
					local _, thisId = strsplit(":", item.ITEMLINK, 3)
					if thisId == itemId then
						return item
					end
				end
			end
		end
		window = window - 1
		windowsChecked = windowsChecked + 1
	end

	return nil
end

-- Post-hook on RR_ReallyGiveLoot (RaidRoll_ExtraRollFrames.lua:790) - by the
-- time this runs the loot slot has already been consumed by GiveMasterLoot,
-- so the item is identified from rr_Item[rr_CurrentRollID] (the same global
-- the engine itself matched against the loot slot before calling this
-- function), not by re-reading the slot.
local function RecordWinner(player)
	if not rr_Item or not rr_CurrentRollID then
		return
	end

	local itemLink = rr_Item[rr_CurrentRollID]
	if not itemLink or itemLink == ("ID #" .. rr_CurrentRollID) then
		return -- no real item was ever set for this roll
	end

	local _, itemId = strsplit(":", itemLink, 3)
	if not itemId then
		return
	end

	local entry = FindUnclaimedLootEntry(itemId)
	if entry then
		entry.WINNER = TitleCase(player)
		entry.RECEIVED = date("%Y-%m-%d %H:%M:%S")
	end
end

-- Post-hook on RR_AddonMessageReceived (native, RaidRoll_LootTracker.lua:
-- 321-637) - by the time this runs, the native function has already written
-- its own new item using its own same-window-only dedup, which misses the
-- case FindUnclaimedDuplicate above exists for: a corpse re-announced more
-- than 30 seconds after its loot was first recorded, landing the same
-- still-unclaimed item in a brand-new window. Always operates on the tail
-- window/item, since that's the only slot RR_AddonMessageReceived ever
-- writes to. Rolling the window itself back (not just the item) when it was
-- only created for this one now-removed entry keeps an empty phantom window
-- from being left in the pager.
local function UndoPhantomBroadcastDuplicate()
	local loot = RaidRoll_DB and RaidRoll_DB["Loot"]
	local totalWindows = loot and loot["TOTAL WINDOWS"]
	if not totalWindows or totalWindows < 1 then
		return
	end
	local window = loot[totalWindows]
	local itemCount = window and window["TOTAL ITEMS"]
	if not itemCount or itemCount < 1 then
		return
	end

	local justAdded = window["ITEM_" .. itemCount]
	if not justAdded or not justAdded.ITEMLINK then
		return
	end

	local crossWindowMatch = FindUnclaimedDuplicate(window["MOB NAME"], justAdded.ITEMLINK, totalWindows - 1)
	if not crossWindowMatch then
		return
	end

	window["ITEM_" .. itemCount] = nil
	window["TOTAL ITEMS"] = itemCount - 1

	if window["TOTAL ITEMS"] == 0 then
		loot[totalWindows] = nil
		loot["TOTAL WINDOWS"] = totalWindows - 1
		if loot["CURRENT WINDOW"] == totalWindows then
			loot["CURRENT WINDOW"] = totalWindows - 1
		end
	end
end

local function EnsureHooked()
	LockdownNativeFrames()

	if hooked then
		return
	end
	if type(RR_ReallyGiveLoot) ~= "function" then
		return -- RaidRoll hasn't finished loading yet
	end
	hooked = true

	hooksecurefunc("RR_ReallyGiveLoot", function(player)
		RecordWinner(player)
	end)

	-- Post-hook so another raid member's loot (received via "RRL" addon
	-- message, RaidRoll_LootTracker.lua:321-490) also triggers
	-- MaybeAutoOpenLootWindow() - not just our own self-loot scan above.
	-- UndoPhantomBroadcastDuplicate runs first so a rolled-back phantom
	-- window doesn't make MaybeAutoOpenLootWindow think a real new window
	-- just appeared.
	if type(RR_AddonMessageReceived) == "function" then
		hooksecurefunc("RR_AddonMessageReceived", function()
			UndoPhantomBroadcastDuplicate()
			MaybeAutoOpenLootWindow()
		end)
	end

	-- RR_Display (RaidRoll_OnLoad.lua:1724-1739) only resizes RR_NAME_FRAME -
	-- the invisible frame that actually owns the tooltip's OnEnter/OnLeave
	-- (RaidRoll_ExtraRollFrames.lua:562-625) - while the 60-second roll
	-- countdown is still running (via RR_Update_Name_Frame). Once the timer
	-- expires, or Last/Next pages to a different roll, RR_Display's other
	-- branch updates RR_Itemname's text but leaves RR_NAME_FRAME at its old
	-- width, so the visible item link often extends past its actual hoverable
	-- hitbox and hovering it shows no tooltip. Re-syncing the width after
	-- every RR_Display call (regardless of branch) fixes that without ever
	-- touching RaidRoll_OnLoad.lua itself.
	if type(RR_Display) == "function" then
		hooksecurefunc("RR_Display", function()
			if RR_NAME_FRAME and _G["RR_Itemname"] then
				RR_NAME_FRAME:SetWidth(_G["RR_Itemname"]:GetWidth() + 20)
			end
		end)
	end
end

-- Exposed so Init.lua's Toggle() can call this defensively too - by the time
-- a user actually opens the window every addon has certainly finished
-- loading, which covers the (should-be-rare-thanks-to-OptionalDeps) case
-- where PLAYER_LOGIN fired before RaidRoll was fully set up.
RaidRollUI.EnsureHooked = EnsureHooked

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", EnsureHooked)

-- Independent of RaidRoll's own LOOT_OPENED listener - WoW allows multiple
-- frames to register the same event, so RaidRoll's broadcast-to-everyone-
-- else behavior (RaidRoll_OnLoad.lua:74-82) is untouched by this.
local lootScanFrame = CreateFrame("Frame")
lootScanFrame:RegisterEvent("LOOT_OPENED")
lootScanFrame:SetScript("OnEvent", ScanAndRecordOwnLoot)

-- Catches loot for every group member, not just our own (see HandleChatMsgLoot
-- above) - the server sends this system message to the whole party/raid for
-- every loot event regardless of who's running what addon.
local chatLootFrame = CreateFrame("Frame")
chatLootFrame:RegisterEvent("CHAT_MSG_LOOT")
chatLootFrame:SetScript("OnEvent", function(_, _, msg) HandleChatMsgLoot(msg) end)

-- Re-checked on every roster change / leader handoff so a promotion or
-- demotion mid-raid takes effect without needing a reload.
local announceGateFrame = CreateFrame("Frame")
announceGateFrame:RegisterEvent("RAID_ROSTER_UPDATE")
announceGateFrame:RegisterEvent("PARTY_LEADER_CHANGED")
announceGateFrame:SetScript("OnEvent", EnforceAnnounceGate)
