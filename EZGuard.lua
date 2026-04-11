----------------------------------------------------------------
-- EZGuard.lua 
----------------------------------------------------------------

----------------------------------------------------------------
-- Local variables
----------------------------------------------------------------

local VERSION = 1.21
local TIME_DELAY = 0.5
local MAX_MAP_POINTS = 511
local DISTANCE_FIX_COEFFICIENT = 1 / 1.06
local HEALER = "HEALER"
local DPS = "DPS"
local TANK = "TANK"
local LOCAL_PLAYER_NAME = GameData.Player.name

local timeLeft = TIME_DELAY
local isTank = false
local hasGuard = false

local buttonGlowLevel = 0
local buttonActive = false
local mathFloor = math.floor
local tableSort = table.sort
local pairs = pairs

local MapPointTypeFilter = {
	[SystemData.MapPips.PLAYER] = true,
	[SystemData.MapPips.GROUP_MEMBER] = true,
	[SystemData.MapPips.WARBAND_MEMBER] = true,
	[SystemData.MapPips.DESTRUCTION_ARMY] = true,
	[SystemData.MapPips.ORDER_ARMY] = true
}

local GuardAbilityID = {
	[GameData.CareerLine.IRON_BREAKER]		= 1363, -- Guard (Ironbreaker)
	[GameData.CareerLine.CHOSEN]			= 8325, -- Guard (Chosen)
	[GameData.CareerLine.SWORDMASTER]		= 9008, -- Guard (Swordmaster)
	[GameData.CareerLine.BLACK_ORC]			= 1674, -- Save Da Runts (Black Orc)
	[GameData.CareerLine.KNIGHT]			= 8013, -- Guard (Knight of the Blazing Sun)
	[GameData.CareerLine.BLACKGUARD]		= 9325, -- Guard (Blackguard)
}

local ArcheType = {
	[GameData.CareerLine.ZEALOT] 			= HEALER,
	[GameData.CareerLine.ARCHMAGE] 			= HEALER,
	[GameData.CareerLine.SHAMAN] 			= HEALER,
	[GameData.CareerLine.RUNE_PRIEST] 		= HEALER,
	[GameData.CareerLine.WARRIOR_PRIEST] 	= HEALER,
	[GameData.CareerLine.DISCIPLE] 			= HEALER,
	[GameData.CareerLine.ENGINEER] 			= DPS,
	[GameData.CareerLine.SLAYER] 			= DPS,
	[GameData.CareerLine.MARAUDER] 			= DPS,
	[GameData.CareerLine.SHADOW_WARRIOR] 	= DPS,
	[GameData.CareerLine.CHOPPA] 			= DPS,
	[GameData.CareerLine.SQUIG_HERDER] 		= DPS,
	[GameData.CareerLine.WHITE_LION] 		= DPS,
	[GameData.CareerLine.WITCH_ELF] 		= DPS,
	[GameData.CareerLine.SORCERER] 			= DPS,
	[GameData.CareerLine.WITCH_HUNTER] 		= DPS,
	[GameData.CareerLine.MAGUS] 			= DPS,
	[GameData.CareerLine.BRIGHT_WIZARD] 	= DPS,
	[GameData.CareerLine.IRON_BREAKER] 		= TANK,
	[GameData.CareerLine.KNIGHT] 			= TANK,
	[GameData.CareerLine.SWORDMASTER] 		= TANK,
	[GameData.CareerLine.BLACKGUARD] 		= TANK,
	[GameData.CareerLine.CHOSEN] 			= TANK,
	[GameData.CareerLine.BLACK_ORC] 		= TANK,
}
local CareerIDsToLines = {
	[20]	= GameData.CareerLine.IRON_BREAKER,
	[100]	= GameData.CareerLine.SWORDMASTER,
	[64]	= GameData.CareerLine.CHOSEN,
	[24]	= GameData.CareerLine.BLACK_ORC,
	[60]	= GameData.CareerLine.WITCH_HUNTER,
	[102]	= GameData.CareerLine.WHITE_LION,
	[65]	= GameData.CareerLine.MARAUDER,
	[105]	= GameData.CareerLine.WITCH_ELF,
	[62]	= GameData.CareerLine.BRIGHT_WIZARD,
	[67]	= GameData.CareerLine.MAGUS,
	[107]	= GameData.CareerLine.SORCERER,
	[23]	= GameData.CareerLine.ENGINEER,
	[101]	= GameData.CareerLine.SHADOW_WARRIOR,
	[27]	= GameData.CareerLine.SQUIG_HERDER,
	[63]	= GameData.CareerLine.WARRIOR_PRIEST,
	[106]	= GameData.CareerLine.DISCIPLE,
	[103]	= GameData.CareerLine.ARCHMAGE,
	[26]	= GameData.CareerLine.SHAMAN,
	[22]	= GameData.CareerLine.RUNE_PRIEST,
	[66]	= GameData.CareerLine.ZEALOT,
	[104]	= GameData.CareerLine.BLACKGUARD,
	[61]	= GameData.CareerLine.KNIGHT,
	[25]	= GameData.CareerLine.CHOPPA,
	[21]	= GameData.CareerLine.SLAYER,
}

local PartyTargetEvent = {
	[1] = SystemData.Events.TARGET_GROUP_MEMBER_1,
	[2] = SystemData.Events.TARGET_GROUP_MEMBER_2,
	[3] = SystemData.Events.TARGET_GROUP_MEMBER_3,
	[4] = SystemData.Events.TARGET_GROUP_MEMBER_4,
	[5] = SystemData.Events.TARGET_GROUP_MEMBER_5,
	[6] = SystemData.Events.TARGET_GROUP_MEMBER_6,
}

local function fixString (str)
	if (str == nil) then return nil end
	local str = str
	local pos = str:find (L"^", 1, true)
	if (pos) then str = str:sub (1, pos - 1) end
	return str
end

----------------------------------------------------------------
-- EZGuard
----------------------------------------------------------------
EZGuard = EZGuard or {}
EZGuard.DefaultSettings = {
	version = VERSION,
	enabled = true,
	guardDistance = 50,
	burnEffects = true,
	healerWeight = 100,
	dpsWeight = 125,
	tankWeight = 150,
	autoTarget = false,
}
EZGuard.Player = {}
EZGuard.Party = {}
EZGuard.NewGuardTargetIndex = 0
EZGuard.CurrentFriendlyTarget = {
	name = L"",
	healthPercent = 0,
}
EZGuard.CurrentGuardTarget = {
	index = 0,
	name = L"",
	healthPercent = 0,
}

EZGuard.NewGuardTarget = {
	index = 0,
	name = L"",
	healthPercent = 0,
}

function EZGuard.Initialize()
	if ArcheType[ CareerIDsToLines[GameData.Player.career.id] ] == TANK
	--and GameData.Player.level >= 10 -- No Guard ability until level 10
	then
		isTank = true
	else
		isTank = false
		return
	end
	
	EZGuard.CheckGuard()
	
	if not EZGuard.Settings then
		EZGuard.Settings = EZGuard.DefaultSettings
	elseif not EZGuard.Settings.version or EZGuard.Settings.version ~= VERSION then
		EZGuard.Settings = EZGuard.DefaultSettings
	end
	
	EZGuard.PrintSettings()
	
	LibSlash.RegisterSlashCmd("ezguard", function(input) EZGuard_Config.Slash(input) end)
	LibSlash.RegisterSlashCmd("ezg", function(input) EZGuard_Config.Slash(input) end)
	
	RegisterEventHandler(SystemData.Events.PLAYER_TARGET_UPDATED, "EZGuard.UpdateFriendlyTarget")
	RegisterEventHandler(SystemData.Events.PLAYER_TARGET_HIT_POINTS_UPDATED, "EZGuard.UpdateFriendlyTarget")
	RegisterEventHandler(SystemData.Events.PLAYER_EFFECTS_UPDATED, "EZGuard.UpdateGuardTarget")
	RegisterEventHandler(SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "EZGuard.UpdateGuardTarget")
	RegisterEventHandler(SystemData.Events.GROUP_UPDATED, "EZGuard.UpdateGroup")
	RegisterEventHandler(SystemData.Events.GROUP_STATUS_UPDATED, "EZGuard.UpdateGroup")
	RegisterEventHandler(SystemData.Events.PLAYER_HOT_BAR_UPDATED, "EZGuard.CheckGuard")
end

function EZGuard.OnShutdown()
	UnregisterEventHandler(SystemData.Events.PLAYER_TARGET_UPDATED, "EZGuard.UpdateFriendlyTarget")
	UnregisterEventHandler(SystemData.Events.PLAYER_TARGET_HIT_POINTS_UPDATED, "EZGuard.UpdateFriendlyTarget")
	UnregisterEventHandler(SystemData.Events.PLAYER_EFFECTS_UPDATED, "EZGuard.UpdateGuardTarget")
	UnregisterEventHandler(SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "EZGuard.UpdateGuardTarget")
	UnregisterEventHandler(SystemData.Events.GROUP_UPDATED, "EZGuard.UpdateGroup")
	UnregisterEventHandler(SystemData.Events.GROUP_STATUS_UPDATED, "EZGuard.UpdateGroup")
	UnregisterEventHandler(SystemData.Events.PLAYER_HOT_BAR_UPDATED, "EZGuard.CheckGuard")
end

function EZGuard.OnUpdate(elapsed)
	timeLeft = timeLeft - elapsed
    if timeLeft > 0 then
        return
    end
    timeLeft = TIME_DELAY

	if not isTank then return end
	-- if not EZGuard.Settings.enabled then return end

	if EZGuard.Settings.enabled
	and hasGuard
	and not buttonActive
	then
		EZGuard.Enable()
	end

	if EZGuard.Settings.enabled and GetNumGroupmates() > 0 then
		EZGuard.SelectHurtPlayer()
	end
	
	EZGuard.UpdateButtonGlow()
	EZGuard.AutoTarget()	
end

-- function EZGuard.CheckGuard()
	-- if GuardAbilityID[GameData.Player.career.line] then
		-- hasGuard = true
	-- end
-- end

function EZGuard.CheckGuard(slot, actionType, actionId)
	if actionId == GuardAbilityID[GameData.Player.career.line] then
		hasGuard = true
	end
end

-- function EZGuard.CheckGuard()
	-- local hbar, buttonid, button
	-- local actionId
	-- for i = 1, 60 do
		-- _, actionId = GetHotbarData(i)
		-- if actionId == GuardAbilityID[GameData.Player.career.line] then
			-- hasGuard = true
		-- end
	-- end
-- end

function EZGuard.Slash(input)
	input = string.lower(input)
	if input == "" then
		EZGuard.Settings.enabled = not EZGuard.Settings.enabled
	elseif tonumber(input) then
		EZGuard.Settings.guardDistance = tonumber(input)
		EZGuard.Settings.enabled = true
	end
	EZGuard.PrintSettings()
end

function EZGuard.PrintSettings()
	if EZGuard.Settings.enabled then
		TextLogAddEntry("Chat", 0, L"<icon57> EZGuard enabled.")
	else
		TextLogAddEntry("Chat", 0, L"<icon58> EZGuard disbled.")
	end
end

function EZGuard.ToggleEnabled()
	if EZGuard.Settings.enabled then
		EZGuard.Disable()
	else
		EZGuard.Enable()
	end
end

function EZGuard.Enable()
	EZGuard.Settings.enabled = true
	EZGuard.SetButtonActive(true)
	EZGuard.PrintSettings()
end

function EZGuard.Disable()
	EZGuard.Settings.enabled = false
	EZGuard.SetButtonActive(false)
	EZGuard.PrintSettings()
end

function EZGuard.UpdateButtonGlow()
	if EZGuard.Settings.enabled
	and EZGuard.Settings.burnEffects
	and EZGuard.NewGuardTarget.index ~= 0
	and EZGuard.NewGuardTarget.name ~= EZGuard.CurrentGuardTarget.name
	then
		EZGuard.SetButtonGlow(true, 2)
	else
		EZGuard.SetButtonGlow(false, 0)
	end
end

function EZGuard.AutoTarget()
	if EZGuard.Settings.enabled
	and EZGuard.Settings.autoTarget
	and EZGuard.NewGuardTarget.index ~= 0
	and EZGuard.NewGuardTarget.name ~= EZGuard.CurrentGuardTarget.name
	then
		BroadcastEvent(PartyTargetEvent[EZGuard.NewGuardTarget.index])
	end
end

function EZGuard.UpdateFriendlyTarget()
	EZGuard.CurrentFriendlyTarget.name, EZGuard.CurrentFriendlyTarget.healthPercent = EZGuard.GetFriendlyTarget()
end

function EZGuard.UpdateGuardTarget()
	 -- Check that we have guard active
	if EZGuard.IsGuardingTarget(GameData.BuffTargetType.SELF) then
		 -- Check if current target is being guarded by us
		if EZGuard.IsGuardingTarget(GameData.BuffTargetType.TARGET_FRIENDLY)
		and EZGuard.CurrentFriendlyTarget.name ~= fixString(LOCAL_PLAYER_NAME)
		and EZGuard.CurrentFriendlyTarget.name ~= L""
		then
			EZGuard.CurrentGuardTarget.name = EZGuard.CurrentFriendlyTarget.name
			EZGuard.CurrentGuardTarget.healthPercent = EZGuard.CurrentFriendlyTarget.healthPercent
		end
	-- We are not guarding anyone
	else
		EZGuard.CurrentGuardTarget.index = 0
		EZGuard.CurrentGuardTarget.name = L""
		EZGuard.CurrentGuardTarget.healthPercent = 0
	end
end

function EZGuard.IsGuardingTarget(targetType)
	local buffs = GetBuffs(targetType)
	
	for _, v in pairs(buffs) do
		if v.abilityId == GuardAbilityID[GameData.Player.career.line]
		and v.castByPlayer
		then
			return true
		end
	end
	return false
end

function EZGuard.GetFriendlyTarget()
	TargetInfo:UpdateFromClient()
	local target = TargetInfo.m_Units[TargetInfo.FRIENDLY_TARGET]
	if target
	and not target.isNPC
	and target.name ~= L""
	then
		return fixString(target.name), target.healthPercent
	elseif target
	and target.entityid == 0
	then -- Treat no target as self target
		return fixString(LOCAL_PLAYER_NAME), GameData.Player.hitPoints.current
	else
		return L"", 0 -- else ignore
	end
end

function EZGuard.UpdateGroup()
	if not EZGuard.Settings.enabled then return end
	EZGuard.Player.name = fixString(LOCAL_PLAYER_NAME)
	local players = {}
	local partyIndex, memberIndex
	local partyData = {}
	
	-- In a Warband (will include self!)
	if IsWarBandActive() then
		partyIndex, memberIndex = PartyUtils.IsPlayerInWarband(EZGuard.Player.name) -- Get our partyindex and our partyslot
		partyData = PartyUtils.GetWarbandParty(partyIndex).players
	
	-- Group or Scenario Group (Will not include self!)
	else
		partyData  = PartyUtils.GetPartyData()
	end

	for i = 1, #partyData do
		players[#players + 1] = {}
		players[#players].index = i
		players[#players].name = fixString(partyData[i].name)
		players[#players].health = partyData[i].healthPercent
		players[#players].isDistant = partyData[i].isDistant
		
		if ArcheType[partyData[i].careerLine] == HEALER then
			players[#players].weight = EZGuard.Settings.healerWeight
		elseif ArcheType[partyData[i].careerLine] == DPS then
			players[#players].weight = EZGuard.Settings.dpsWeight
		elseif ArcheType[partyData[i].careerLine] == TANK then
			players[#players].weight = EZGuard.Settings.tankWeight
		else
			players[#players].weight = 999999
		end
		
		if players[#players].name == EZGuard.CurrentGuardTarget.name then
			EZGuard.CurrentGuardTarget.index = players[#players].index
		end
	end

	EZGuard.SetPlayersDistance(players)
	
	local sortFunc = function (k1, k2)
		if k1.health < k2.health then
			return true
		elseif k1.health == k2.health
		and k1.distance < k2.distance
		then
			return true
		end
		return false
	end

	tableSort(players, sortFunc)	
	
	EZGuard.Party = players
end

function EZGuard.SetPlayersDistance(players)
	local defaultDistance = 999999
	local playerDistances = {}
	
	-- build table of player distances
	for i = 1, MAX_MAP_POINTS do
		local mpd = GetMapPointData("EA_Window_OverheadMapMapDisplay", i)
		if (not mpd or not MapPointTypeFilter[mpd.pointType] or not mpd.name) then continue end
		playerDistances[fixString(mpd.name)] = mathFloor(mpd.distance * DISTANCE_FIX_COEFFICIENT)
	end
	
	-- look up and set distances
	for i = 1, #players do
		players[i].distance = playerDistances[players[i].name] or defaultDistance
	end
end

function EZGuard.SelectHurtPlayer()
	local players = EZGuard.Party
	
	-- Initial compare values
	local cmpPlayer = {
		index = 0,
		name = L"",
		health = 101,
		distance = 999999,
		weight = 1000,
	}
	
	EZGuard.NewGuardTarget = {}
	EZGuard.NewGuardTarget.index = 0
	EZGuard.NewGuardTarget.name = L""
	
	for i = 1, #players do
		if players[i].name ~= fixString(LOCAL_PLAYER_NAME)										-- Ignore self
		and players[i].health > 0																-- Ignore dead player
		and players[i].distance <= EZGuard.Settings.guardDistance								-- Within Guard range
		and players[i].health * players[i].weight < cmpPlayer.health * cmpPlayer.weight			-- Health is lower than previous player weighted by archetype (healer: 100, dps: 125, tank: 150)
		then
			cmpPlayer = players[i]
		end
	end
	
	if (cmpPlayer.index > 0 and cmpPlayer.health < 100 and cmpPlayer.name ~= EZGuard.CurrentGuardTarget.name)	-- Guard unless already guarded
	or (cmpPlayer.index > 0 and cmpPlayer.health == 100 and EZGuard.CurrentGuardTarget.name == L"")				-- No current guarded player
	or (cmpPlayer.index > 0 and cmpPlayer.health == 100 and EZGuard.CurrentGuardTarget.healthPercent == 0)		-- Current guarded player is dead
	then
		EZGuard.NewGuardTarget = cmpPlayer
	end
end

function EZGuard.SetButtonGlow(setglow, glowLevel)
	local hbar, buttonid, button
	local actionId
	for i = 1, 60 do
		_, actionId = GetHotbarData(i)
		if actionId == GuardAbilityID[GameData.Player.career.line] then
			hbar, buttonid = ActionBars:BarAndButtonIdFromSlot(i)
			if hbar and buttonid then
				button = hbar.m_Buttons[buttonid]
				if setglow and EZGuard.Settings.enabled then
					button.m_Windows[6]:StopAnimation (true)
					button.m_Windows[6]:SetAnimationTexture ("anim_fury_" .. glowLevel)
					button.m_Windows[6]:StartAnimation (0, true, false, 0)
				else
					button.m_Windows[6]:StopAnimation (true)
				end
				buttonGlowLevel = glowLevel
			end
		end
	end
end

function EZGuard.SetButtonActive(enable)
	local hbar, buttonid, button
	local actionId
	for i = 1, 60 do
		_, actionId = GetHotbarData(i)
		if actionId == GuardAbilityID[GameData.Player.career.line] then
			hbar, buttonid = ActionBars:BarAndButtonIdFromSlot(i)
			if hbar and buttonid then
				button = hbar.m_Buttons[buttonid]
				if enable then
					button.m_Windows[7]:Show(true)
					button.m_Windows[7]:SetText("<icon00057>")
				else
					button.m_Windows[7]:Show(true)
					button.m_Windows[7]:SetText("<icon00058>")
				end
				buttonActive = enable
			end
		end
	end
end
 
---------------------------------------------------------------
-- Hooks
----------------------------------------------------------------
local orgActionButtonOnLButtonDown = ActionButton.OnLButtonDown
function ActionButton.OnLButtonDown(self, flags, x, y)
	if EZGuard.Settings.enabled
	and flags == SystemData.ButtonFlags.GAME_ACTION
	and not EZGuard.Settings.autoTarget
	and self.m_ActionId == GuardAbilityID[GameData.Player.career.line]			-- only when using Guard ability
	and GetHotbarCooldown(self:GetSlot()) == 0 									-- and not on GCD
	and EZGuard.NewGuardTarget.index >= 1 and EZGuard.NewGuardTarget.index <= 6	-- and valid party index
	then
		BroadcastEvent(PartyTargetEvent[EZGuard.NewGuardTarget.index]) 			-- target party member
	elseif self.m_ActionId == GuardAbilityID[GameData.Player.career.line]
	and flags == SystemData.ButtonFlags.CONTROL									-- Toggle on CTRL-Mouse Click
	then
		EZGuard.ToggleEnabled()
	end
	orgActionButtonOnLButtonDown(self, flags, x, y)
end

local orgActionButtonUpdateBurning = ActionButton.UpdateBurning
function ActionButton.UpdateBurning (self, flags, x, y)
	if self.m_ActionId ~= GuardAbilityID[GameData.Player.career.line] then
		orgActionButtonUpdateBurning(self, flags, x, y)
	end
end

local orgActionButtonUpdateInventory = ActionButton.UpdateInventory
function ActionButton.UpdateInventory (self, flags, x, y)
	if self.m_ActionId == GuardAbilityID[GameData.Player.career.line] then
		EZGuard.SetButtonActive(EZGuard.Settings.enabled)
	else
		orgActionButtonUpdateInventory(self, flags, x, y)
	end
end
