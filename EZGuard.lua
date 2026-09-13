----------------------------------------------------------------
-- EZGuard.lua
----------------------------------------------------------------

----------------------------------------------------------------
-- Local variables
----------------------------------------------------------------

local VERSION = 1.22
local TIME_DELAY = 0.5
local MAX_MAP_POINTS = 511
local DISTANCE_FIX_COEFFICIENT = 1 / 1.06
local SNAPSHOT_FALLBACK_INTERVAL = 2
local TRANSIENT_REFRESH_INTERVAL = TIME_DELAY
local TARGET_REFRESH_INTERVAL = TIME_DELAY
local PARTY_AUTO_TARGET_THROTTLE = 0.25
local EZGUARD_CHAT_PREFIX_TEXT = "EZGuard"
local EZGUARD_CHAT_PREFIX_COLOR = { 0, 255, 255 }
local HEALER = "HEALER"
local DPS = "DPS"
local TANK = "TANK"
local LOCAL_PLAYER_NAME = GameData.Player.name

local timeLeft = TIME_DELAY
local currentTime = 0
local isTank = false
local hasGuard = false
local loadingEndEventRegistered = false
local activeEventsRegistered = false
local actionButtonHooksInstalled = false
local slashCommandsRegistered = false

local mathFloor = math.floor
local mathMax = math.max
local tableSort = table.sort
local pairs = pairs
local ipairs = ipairs

local MapPointTypeFilter = {
	[SystemData.MapPips.PLAYER] = true,
	[SystemData.MapPips.GROUP_MEMBER] = true,
	[SystemData.MapPips.WARBAND_MEMBER] = true,
	[SystemData.MapPips.DESTRUCTION_ARMY] = true,
	[SystemData.MapPips.ORDER_ARMY] = true,
}

local GuardAbilityID = {
	[GameData.CareerLine.IRON_BREAKER] = 1363,
	[GameData.CareerLine.CHOSEN] = 8325,
	[GameData.CareerLine.SWORDMASTER] = 9008,
	[GameData.CareerLine.BLACK_ORC] = 1674,
	[GameData.CareerLine.KNIGHT] = 8013,
	[GameData.CareerLine.BLACKGUARD] = 9325,
}

local ArcheType = {
	[GameData.CareerLine.ZEALOT] = HEALER,
	[GameData.CareerLine.ARCHMAGE] = HEALER,
	[GameData.CareerLine.SHAMAN] = HEALER,
	[GameData.CareerLine.RUNE_PRIEST] = HEALER,
	[GameData.CareerLine.WARRIOR_PRIEST] = HEALER,
	[GameData.CareerLine.DISCIPLE] = HEALER,
	[GameData.CareerLine.ENGINEER] = DPS,
	[GameData.CareerLine.SLAYER] = DPS,
	[GameData.CareerLine.MARAUDER] = DPS,
	[GameData.CareerLine.SHADOW_WARRIOR] = DPS,
	[GameData.CareerLine.CHOPPA] = DPS,
	[GameData.CareerLine.SQUIG_HERDER] = DPS,
	[GameData.CareerLine.WHITE_LION] = DPS,
	[GameData.CareerLine.WITCH_ELF] = DPS,
	[GameData.CareerLine.SORCERER] = DPS,
	[GameData.CareerLine.WITCH_HUNTER] = DPS,
	[GameData.CareerLine.MAGUS] = DPS,
	[GameData.CareerLine.BRIGHT_WIZARD] = DPS,
	[GameData.CareerLine.IRON_BREAKER] = TANK,
	[GameData.CareerLine.KNIGHT] = TANK,
	[GameData.CareerLine.SWORDMASTER] = TANK,
	[GameData.CareerLine.BLACKGUARD] = TANK,
	[GameData.CareerLine.CHOSEN] = TANK,
	[GameData.CareerLine.BLACK_ORC] = TANK,
}

local CareerIDsToLines = {
	[20] = GameData.CareerLine.IRON_BREAKER,
	[100] = GameData.CareerLine.SWORDMASTER,
	[64] = GameData.CareerLine.CHOSEN,
	[24] = GameData.CareerLine.BLACK_ORC,
	[60] = GameData.CareerLine.WITCH_HUNTER,
	[102] = GameData.CareerLine.WHITE_LION,
	[65] = GameData.CareerLine.MARAUDER,
	[105] = GameData.CareerLine.WITCH_ELF,
	[62] = GameData.CareerLine.BRIGHT_WIZARD,
	[67] = GameData.CareerLine.MAGUS,
	[107] = GameData.CareerLine.SORCERER,
	[23] = GameData.CareerLine.ENGINEER,
	[101] = GameData.CareerLine.SHADOW_WARRIOR,
	[27] = GameData.CareerLine.SQUIG_HERDER,
	[63] = GameData.CareerLine.WARRIOR_PRIEST,
	[106] = GameData.CareerLine.DISCIPLE,
	[103] = GameData.CareerLine.ARCHMAGE,
	[26] = GameData.CareerLine.SHAMAN,
	[22] = GameData.CareerLine.RUNE_PRIEST,
	[66] = GameData.CareerLine.ZEALOT,
	[104] = GameData.CareerLine.BLACKGUARD,
	[61] = GameData.CareerLine.KNIGHT,
	[25] = GameData.CareerLine.CHOPPA,
	[21] = GameData.CareerLine.SLAYER,
}

local PartyTargetEvent = {
	[1] = SystemData.Events.TARGET_GROUP_MEMBER_1,
	[2] = SystemData.Events.TARGET_GROUP_MEMBER_2,
	[3] = SystemData.Events.TARGET_GROUP_MEMBER_3,
	[4] = SystemData.Events.TARGET_GROUP_MEMBER_4,
	[5] = SystemData.Events.TARGET_GROUP_MEMBER_5,
	[6] = SystemData.Events.TARGET_GROUP_MEMBER_6,
}

local orgActionButtonOnLButtonDown = nil
local orgActionButtonUpdateBurning = nil
local orgActionButtonUpdateInventory = nil

local function fixString(str)
	if str == nil then
		return nil
	end
	local pos = str:find(L"^", 1, true)
	if pos then
		str = str:sub(1, pos - 1)
	end
	return str
end

local function toWString(value)
	if value == nil then
		return L""
	end
	if type(value) == "string" then
		return towstring(value)
	end
	return value
end

local function getChatPrefixWString(includeSpace)
	local r = EZGUARD_CHAT_PREFIX_COLOR[1]
	local g = EZGUARD_CHAT_PREFIX_COLOR[2]
	local b = EZGUARD_CHAT_PREFIX_COLOR[3]
	local coloredPartRaw = string.format(
		"<LINK data=\"0\" color=\"%d,%d,%d\" text=\"%s\">",
		r, g, b, EZGUARD_CHAT_PREFIX_TEXT
	)
	local prefix = L"[" .. towstring(coloredPartRaw) .. L"]"
	if includeSpace then
		prefix = prefix .. L" "
	end
	return prefix
end

local function registerSlashCommands()
	if slashCommandsRegistered then
		return
	end
	if type(LibSlash) ~= "table" or type(LibSlash.RegisterSlashCmd) ~= "function" then
		return
	end
	LibSlash.RegisterSlashCmd("ezguard", function(input) EZGuard_Config.Slash(input) end)
	LibSlash.RegisterSlashCmd("ezg", function(input) EZGuard_Config.Slash(input) end)
	slashCommandsRegistered = true
end

local function clampHealthPercent(value)
	value = tonumber(value) or 0
	if value < 0 then
		return 0
	end
	if value > 100 then
		return 100
	end
	return value
end

local function clampPositiveNumber(value, fallback)
	value = tonumber(value)
	if value == nil or value <= 0 then
		return fallback
	end
	return value
end

local function mergeSettings(defaults, current)
	local merged = {}
	current = type(current) == "table" and current or {}

	for key, defaultValue in pairs(defaults) do
		local currentValue = current[key]
		if type(defaultValue) == "table" then
			merged[key] = mergeSettings(defaultValue, currentValue)
		elseif currentValue == nil then
			merged[key] = defaultValue
		else
			merged[key] = currentValue
		end
	end

	return merged
end

local function migrateSettings(settings)
	settings = type(settings) == "table" and settings or {}
	if settings.rangeCheck == nil then
		settings.rangeCheck = true
	end
	return settings
end

local function normalizeSettings(settings)
	settings.guardDistance = clampPositiveNumber(settings.guardDistance, 50)
	settings.healerWeight = clampPositiveNumber(settings.healerWeight, 100)
	settings.dpsWeight = clampPositiveNumber(settings.dpsWeight, 125)
	settings.tankWeight = clampPositiveNumber(settings.tankWeight, 150)
	settings.version = VERSION
	return settings
end

local function initializeSettings(currentSettings)
	local settings = mergeSettings(EZGuard.DefaultSettings, migrateSettings(currentSettings))
	return normalizeSettings(settings)
end

local function checkIsTank()
	local career = GameData.Player and GameData.Player.career or {}
	local careerLine = career.line or CareerIDsToLines[career.id]
	return ArcheType[careerLine] == TANK
end

local function isAddonActive()
	return isTank and EZGuard.Settings and EZGuard.Settings.enabled
end

local function markPlayersDirty()
	EZGuard.RefreshState.playersDirty = true
	EZGuard.RefreshState.transientDirty = true
end

local function markTargetDirty()
	EZGuard.RefreshState.targetDirty = true
end

local function markAllDirty()
	markPlayersDirty()
	markTargetDirty()
	EZGuard.RefreshState.nextPlayersSnapshotTime = 0
	EZGuard.RefreshState.nextTransientRefreshTime = 0
	EZGuard.RefreshState.nextTargetRefreshTime = 0
end

local function sortTrackedPlayers(players)
	local sortFunc = function(k1, k2)
		if k1.health < k2.health then
			return true
		elseif k1.health == k2.health and k1.distance < k2.distance then
			return true
		end
		return false
	end
	tableSort(players, sortFunc)
end

local function getArchetypeWeight(careerLine)
	if ArcheType[careerLine] == HEALER then
		return EZGuard.Settings.healerWeight
	elseif ArcheType[careerLine] == DPS then
		return EZGuard.Settings.dpsWeight
	elseif ArcheType[careerLine] == TANK then
		return EZGuard.Settings.tankWeight
	end
	return 999999
end

local function getOwnPartyTargetEvents()
	local ownPartyTargetEvents = {}

	if IsWarBandActive and IsWarBandActive() then
		local playerName = fixString(LOCAL_PLAYER_NAME)
		local partyIndex = PartyUtils.IsPlayerInWarband(playerName)
		local warbandParty = partyIndex and PartyUtils.GetWarbandParty(partyIndex)
		local partyData = (warbandParty and warbandParty.players) or {}
		for index, member in ipairs(partyData) do
			local memberName = fixString(member and member.name)
			if memberName and memberName ~= L"" and PartyTargetEvent[index] then
				ownPartyTargetEvents[memberName] = PartyTargetEvent[index]
			end
		end
	else
		local partyData = PartyUtils.GetPartyData and PartyUtils.GetPartyData() or {}
		for index, member in ipairs(partyData) do
			local memberName = fixString(member and member.name)
			if memberName and memberName ~= L"" and PartyTargetEvent[index] then
				ownPartyTargetEvents[memberName] = PartyTargetEvent[index]
			end
		end
	end

	return ownPartyTargetEvents
end

local function pushPlayer(playersByName, ownPartyTargetEvents, name, health, careerLine, partyIndex)
	name = fixString(name)
	if not name or name == L"" then
		return
	end

	local normalizedHealth = clampHealthPercent(health)
	local targetEvent = ownPartyTargetEvents[name]
	local existing = playersByName[name]

	if not existing then
		playersByName[name] = {
			index = partyIndex or 0,
			name = name,
			health = normalizedHealth,
			weight = getArchetypeWeight(careerLine),
			distance = 999999,
			targetEvent = targetEvent,
			partyIndex = partyIndex,
		}
		return
	end

	if normalizedHealth < existing.health then
		existing.health = normalizedHealth
	end
	if partyIndex and partyIndex > 0 then
		existing.index = partyIndex
		existing.partyIndex = partyIndex
	end
	if targetEvent then
		existing.targetEvent = targetEvent
	end
	if careerLine then
		existing.weight = getArchetypeWeight(careerLine)
	end
end

local function resolveTargetEvent(player)
	if not player then
		return nil
	end
	if player.targetEvent then
		return player.targetEvent
	end
	if player.partyIndex and player.partyIndex >= 1 and player.partyIndex <= 6 then
		return PartyTargetEvent[player.partyIndex]
	end
	if player.index and player.index >= 1 and player.index <= 6 then
		return PartyTargetEvent[player.index]
	end
	return nil
end

local function getGuardButton()
	local slot = EZGuard.GuardButtonState.hotbarSlot
	if not slot or not ActionBars then
		return nil
	end
	local hbar, buttonid = ActionBars:BarAndButtonIdFromSlot(slot)
	if hbar and buttonid and hbar.m_Buttons then
		return hbar.m_Buttons[buttonid]
	end
	return nil
end

local function setGuardButtonGlow(button, glowLevel)
	if not button or not button.m_Windows or not button.m_Windows[6] then
		return
	end
	if glowLevel and glowLevel > 0 then
		button.m_Windows[6]:StopAnimation(true)
		button.m_Windows[6]:SetAnimationTexture("anim_fury_" .. glowLevel)
		button.m_Windows[6]:StartAnimation(0, true, false, 0)
	else
		button.m_Windows[6]:StopAnimation(true)
	end
end

local function setGuardButtonActiveOverlay(button, enabled)
	if not button or not button.m_Windows or not button.m_Windows[7] then
		return
	end
	button.m_Windows[7]:Show(true)
	if enabled then
		button.m_Windows[7]:SetText("<icon00057>")
	else
		button.m_Windows[7]:SetText("<icon00058>")
	end
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
	rangeCheck = true,
}

EZGuard.Player = {}
EZGuard.Party = {}
EZGuard.PlayerDistances = {}
EZGuard.OwnPartyTargetEvents = {}
EZGuard.RefreshState = {
	playersDirty = true,
	transientDirty = true,
	targetDirty = true,
	nextPlayersSnapshotTime = 0,
	nextTransientRefreshTime = 0,
	nextTargetRefreshTime = 0,
}
EZGuard.AutoTargetState = {
	pendingName = L"",
	pendingIndex = 0,
	nextAllowedTime = 0,
}
EZGuard.GuardButtonState = {
	hotbarSlot = nil,
	glowLevel = 0,
	buttonActive = false,
}
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
	distance = 999999,
	weight = 1000,
	targetEvent = nil,
	partyIndex = 0,
}

local function resetRuntimeState()
	EZGuard.Party = {}
	EZGuard.PlayerDistances = {}
	EZGuard.OwnPartyTargetEvents = {}
	EZGuard.CurrentFriendlyTarget.name = L""
	EZGuard.CurrentFriendlyTarget.healthPercent = 0
	EZGuard.CurrentGuardTarget.index = 0
	EZGuard.CurrentGuardTarget.name = L""
	EZGuard.CurrentGuardTarget.healthPercent = 0
	EZGuard.NewGuardTarget.index = 0
	EZGuard.NewGuardTarget.name = L""
	EZGuard.NewGuardTarget.healthPercent = 0
	EZGuard.NewGuardTarget.distance = 999999
	EZGuard.NewGuardTarget.weight = 1000
	EZGuard.NewGuardTarget.targetEvent = nil
	EZGuard.NewGuardTarget.partyIndex = 0
	EZGuard.AutoTargetState.pendingName = L""
	EZGuard.AutoTargetState.pendingIndex = 0
	EZGuard.AutoTargetState.nextAllowedTime = 0
	EZGuard.GuardButtonState.glowLevel = 0
	markAllDirty()
	timeLeft = 0
	EZGuard.RefreshGuardButtonAppearance()
end

function EZGuard.Initialize()
	EZGuard.Settings = initializeSettings(EZGuard.Settings)
	isTank = checkIsTank()
	registerSlashCommands()

	if not loadingEndEventRegistered then
		RegisterEventHandler(SystemData.Events.LOADING_END, "EZGuard.LOADING_END")
		loadingEndEventRegistered = true
	end

	if isTank then
		EZGuard.RegisterEventHandlers(EZGuard.Settings.enabled)
		if isAddonActive() then
			markAllDirty()
		else
			resetRuntimeState()
		end
	end
end

function EZGuard.OnShutdown()
	uninstallActionButtonHooks()
	EZGuard.RegisterEventHandlers(false)
	if loadingEndEventRegistered then
		UnregisterEventHandler(SystemData.Events.LOADING_END, "EZGuard.LOADING_END")
		loadingEndEventRegistered = false
	end
end

function EZGuard.RegisterEventHandlers(enabled)
	local shouldRegister = enabled and isTank

	if shouldRegister and not activeEventsRegistered then
		RegisterEventHandler(SystemData.Events.PLAYER_TARGET_UPDATED, "EZGuard.PLAYER_TARGET_UPDATED")
		RegisterEventHandler(SystemData.Events.PLAYER_TARGET_HIT_POINTS_UPDATED, "EZGuard.PLAYER_TARGET_HIT_POINTS_UPDATED")
		RegisterEventHandler(SystemData.Events.PLAYER_EFFECTS_UPDATED, "EZGuard.PLAYER_EFFECTS_UPDATED")
		RegisterEventHandler(SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "EZGuard.PLAYER_TARGET_EFFECTS_UPDATED")
		RegisterEventHandler(SystemData.Events.GROUP_UPDATED, "EZGuard.GROUP_UPDATED")
		RegisterEventHandler(SystemData.Events.GROUP_STATUS_UPDATED, "EZGuard.GROUP_STATUS_UPDATED")
		RegisterEventHandler(SystemData.Events.SCENARIO_GROUP_UPDATED, "EZGuard.GROUP_UPDATED")
		RegisterEventHandler(SystemData.Events.SCENARIO_PLAYER_HITS_UPDATED, "EZGuard.GROUP_UPDATED")
		RegisterEventHandler(SystemData.Events.BATTLEGROUP_UPDATED, "EZGuard.GROUP_UPDATED")
		RegisterEventHandler(SystemData.Events.BATTLEGROUP_MEMBER_UPDATED, "EZGuard.GROUP_UPDATED")
		RegisterEventHandler(SystemData.Events.PLAYER_HOT_BAR_UPDATED, "EZGuard.PLAYER_HOT_BAR_UPDATED")
		activeEventsRegistered = true
		markAllDirty()
	elseif activeEventsRegistered and not shouldRegister then
		UnregisterEventHandler(SystemData.Events.PLAYER_TARGET_UPDATED, "EZGuard.PLAYER_TARGET_UPDATED")
		UnregisterEventHandler(SystemData.Events.PLAYER_TARGET_HIT_POINTS_UPDATED, "EZGuard.PLAYER_TARGET_HIT_POINTS_UPDATED")
		UnregisterEventHandler(SystemData.Events.PLAYER_EFFECTS_UPDATED, "EZGuard.PLAYER_EFFECTS_UPDATED")
		UnregisterEventHandler(SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "EZGuard.PLAYER_TARGET_EFFECTS_UPDATED")
		UnregisterEventHandler(SystemData.Events.GROUP_UPDATED, "EZGuard.GROUP_UPDATED")
		UnregisterEventHandler(SystemData.Events.GROUP_STATUS_UPDATED, "EZGuard.GROUP_STATUS_UPDATED")
		UnregisterEventHandler(SystemData.Events.SCENARIO_GROUP_UPDATED, "EZGuard.GROUP_UPDATED")
		UnregisterEventHandler(SystemData.Events.SCENARIO_PLAYER_HITS_UPDATED, "EZGuard.GROUP_UPDATED")
		UnregisterEventHandler(SystemData.Events.BATTLEGROUP_UPDATED, "EZGuard.GROUP_UPDATED")
		UnregisterEventHandler(SystemData.Events.BATTLEGROUP_MEMBER_UPDATED, "EZGuard.GROUP_UPDATED")
		UnregisterEventHandler(SystemData.Events.PLAYER_HOT_BAR_UPDATED, "EZGuard.PLAYER_HOT_BAR_UPDATED")
		activeEventsRegistered = false
		resetRuntimeState()
	end
end

function EZGuard.LOADING_END()
	isTank = checkIsTank()
	registerSlashCommands()
	if isTank then
		installActionButtonHooks()
		EZGuard.RefreshGuardHotbarSlot()
		EZGuard.RegisterEventHandlers(EZGuard.Settings.enabled)
		if isAddonActive() then
			markAllDirty()
		else
			resetRuntimeState()
		end
		EZGuard.RefreshGuardButtonAppearance()
	else
		uninstallActionButtonHooks()
		EZGuard.RegisterEventHandlers(false)
	end
end

function EZGuard.PLAYER_TARGET_UPDATED()
	refreshFriendlyTargetState()
	if EZGuard.CurrentFriendlyTarget.name == EZGuard.AutoTargetState.pendingName then
		EZGuard.AutoTargetState.pendingName = L""
		EZGuard.AutoTargetState.pendingIndex = 0
		EZGuard.AutoTargetState.nextAllowedTime = 0
	end
	markTargetDirty()
end

function EZGuard.PLAYER_TARGET_HIT_POINTS_UPDATED()
	markTargetDirty()
end

function EZGuard.PLAYER_EFFECTS_UPDATED()
	markTargetDirty()
end

function EZGuard.PLAYER_TARGET_EFFECTS_UPDATED()
	markTargetDirty()
end

function EZGuard.GROUP_UPDATED()
	markPlayersDirty()
end

function EZGuard.PLAYER_HOT_BAR_UPDATED()
	EZGuard.RefreshGuardHotbarSlot()
end

function EZGuard.OnUpdate(elapsed)
	if not isTank then
		return
	end

	currentTime = currentTime + elapsed
	timeLeft = timeLeft - elapsed
	if timeLeft > 0 then
		return
	end
	timeLeft = TIME_DELAY

	if not isAddonActive() then
		return
	end

	if hasGuard then
		EZGuard.RefreshGuardButtonAppearance()
	end

	if EZGuard.RefreshState.targetDirty or currentTime >= EZGuard.RefreshState.nextTargetRefreshTime then
		refreshGuardTargetState()
	end

	if EZGuard.RefreshState.playersDirty
		or #EZGuard.Party == 0
		or currentTime >= EZGuard.RefreshState.nextPlayersSnapshotTime
	then
		EZGuard.RefreshPlayersSnapshot()
	end

	if EZGuard.RefreshState.transientDirty
		or currentTime >= EZGuard.RefreshState.nextTransientRefreshTime
	then
		EZGuard.RefreshPlayersTransientState()
	end

	if GetNumGroupmates() > 0 then
		EZGuard.SelectHurtPlayer()
	end

	EZGuard.UpdateButtonGlow()
	EZGuard.AutoTarget()
end

function EZGuard.RefreshGuardHotbarSlot()
	local abilityId = GuardAbilityID[GameData.Player.career.line]
	EZGuard.GuardButtonState.hotbarSlot = nil
	hasGuard = false

	if not abilityId then
		return
	end

	for slot = 1, 60 do
		local _, actionId = GetHotbarData(slot)
		if actionId == abilityId then
			EZGuard.GuardButtonState.hotbarSlot = slot
			hasGuard = true
			return
		end
	end
end

function EZGuard.CheckGuard(slot, actionType, actionId)
	if actionId == GuardAbilityID[GameData.Player.career.line] then
		hasGuard = true
		if slot then
			EZGuard.GuardButtonState.hotbarSlot = slot
		end
	end
end

function EZGuard.Slash(input)
	input = string.lower(input)
	if input == "" then
		EZGuard.Settings.enabled = not EZGuard.Settings.enabled
	elseif tonumber(input) then
		EZGuard.Settings.guardDistance = tonumber(input)
		EZGuard.Settings.enabled = true
	end
	if EZGuard.Settings.enabled then
		EZGuard.Enable()
	else
		EZGuard.Disable()
	end
end

function EZGuard.Print(message)
	local line = getChatPrefixWString(true) .. toWString(message)
	if EA_ChatWindow and type(EA_ChatWindow.Print) == "function" then
		EA_ChatWindow.Print(line, SystemData.SystemLogFilters.GENERAL)
	elseif type(TextLogAddEntry) == "function" then
		TextLogAddEntry("System", SystemData.SystemLogFilters.GENERAL, line)
	end
end

function EZGuard.PrintSettings()
	if EZGuard.Settings.enabled then
		EZGuard.Print(L"--- <icon57> Enabled")
	else
		EZGuard.Print(L"--- <icon58> Disabled")
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
	if EZGuard.Settings.enabled then
		EZGuard.RefreshGuardButtonAppearance()
		return
	end

	EZGuard.Settings.enabled = true
	EZGuard.RegisterEventHandlers(true)
	markAllDirty()
	EZGuard.RefreshGuardButtonAppearance()
	EZGuard.Print(L"--- <icon57> Enabled")
end

function EZGuard.Disable()
	if not EZGuard.Settings.enabled then
		EZGuard.RefreshGuardButtonAppearance()
		return
	end

	EZGuard.Settings.enabled = false
	EZGuard.RegisterEventHandlers(false)
	EZGuard.Print(L"--- <icon58> Disabled")
end

function EZGuard.UpdateButtonGlow()
	local shouldGlow = EZGuard.Settings.burnEffects
		and EZGuard.NewGuardTarget.index ~= 0
		and EZGuard.NewGuardTarget.name ~= L""
		and EZGuard.NewGuardTarget.name ~= EZGuard.CurrentGuardTarget.name

	local glowLevel = shouldGlow and 2 or 0
	if glowLevel == EZGuard.GuardButtonState.glowLevel then
		return
	end

	EZGuard.GuardButtonState.glowLevel = glowLevel
	EZGuard.RefreshGuardButtonAppearance()
end

function EZGuard.RefreshGuardButtonAppearance()
	local button = getGuardButton()
	if not button then
		return
	end

	local settingsEnabled = EZGuard.Settings and EZGuard.Settings.enabled
	setGuardButtonActiveOverlay(button, settingsEnabled)
	setGuardButtonGlow(button, settingsEnabled and EZGuard.GuardButtonState.glowLevel or 0)
	EZGuard.GuardButtonState.buttonActive = settingsEnabled
end

function EZGuard.AutoTarget()
	if not EZGuard.Settings.autoTarget
		or EZGuard.NewGuardTarget.index == 0
		or EZGuard.NewGuardTarget.name == L""
		or EZGuard.NewGuardTarget.name == EZGuard.CurrentGuardTarget.name
	then
		return
	end

	EZGuard.TryAutoTarget(EZGuard.NewGuardTarget)
end

function EZGuard.TryAutoTarget(player)
	local targetEvent = resolveTargetEvent(player)
	if not targetEvent then
		return
	end

	if EZGuard.AutoTargetState.pendingName == player.name
		and currentTime < EZGuard.AutoTargetState.nextAllowedTime
	then
		return
	end

	BroadcastEvent(targetEvent)
	EZGuard.AutoTargetState.pendingName = player.name
	EZGuard.AutoTargetState.pendingIndex = player.partyIndex or player.index or 0
	EZGuard.AutoTargetState.nextAllowedTime = currentTime + PARTY_AUTO_TARGET_THROTTLE
end

function refreshFriendlyTargetState()
	EZGuard.CurrentFriendlyTarget.name, EZGuard.CurrentFriendlyTarget.healthPercent = EZGuard.GetFriendlyTarget()
	EZGuard.RefreshState.targetDirty = false
	EZGuard.RefreshState.nextTargetRefreshTime = currentTime + TARGET_REFRESH_INTERVAL
end

function refreshGuardTargetState()
	if EZGuard.IsGuardingTarget(GameData.BuffTargetType.SELF) then
		if EZGuard.IsGuardingTarget(GameData.BuffTargetType.TARGET_FRIENDLY)
			and EZGuard.CurrentFriendlyTarget.name ~= fixString(LOCAL_PLAYER_NAME)
			and EZGuard.CurrentFriendlyTarget.name ~= L""
		then
			EZGuard.CurrentGuardTarget.name = EZGuard.CurrentFriendlyTarget.name
			EZGuard.CurrentGuardTarget.healthPercent = EZGuard.CurrentFriendlyTarget.healthPercent
		end
	else
		EZGuard.CurrentGuardTarget.index = 0
		EZGuard.CurrentGuardTarget.name = L""
		EZGuard.CurrentGuardTarget.healthPercent = 0
	end

	EZGuard.RefreshState.targetDirty = false
	EZGuard.RefreshState.nextTargetRefreshTime = currentTime + TARGET_REFRESH_INTERVAL
end

function EZGuard.IsGuardingTarget(targetType)
	local buffs = GetBuffs(targetType)
	local guardAbilityId = GuardAbilityID[GameData.Player.career.line]

	for _, v in pairs(buffs) do
		if v.abilityId == guardAbilityId and v.castByPlayer then
			return true
		end
	end
	return false
end

function EZGuard.GetFriendlyTarget()
	TargetInfo:UpdateFromClient()
	local target = TargetInfo.m_Units[TargetInfo.FRIENDLY_TARGET]
	if target and not target.isNPC and target.name ~= L"" then
		return fixString(target.name), clampHealthPercent(target.healthPercent)
	elseif target and target.entityid == 0 then
		return fixString(LOCAL_PLAYER_NAME), clampHealthPercent(GameData.Player.hitPoints.current)
	end
	return L"", 0
end

function EZGuard.BuildFriendlyPlayersSnapshot()
	local playersByName = {}
	local players = {}
	local ownPartyTargetEvents = getOwnPartyTargetEvents()

	EZGuard.OwnPartyTargetEvents = ownPartyTargetEvents
	EZGuard.Player.name = fixString(LOCAL_PLAYER_NAME)

	if (GameData.Player.isInScenario or GameData.Player.isInSiege) and GameData.GetScenarioPlayerGroups then
		local scenarioPlayers = GameData.GetScenarioPlayerGroups() or {}
		for _, playerData in ipairs(scenarioPlayers) do
			pushPlayer(
				playersByName,
				ownPartyTargetEvents,
				playerData.name,
				playerData.health,
				ArcheType[CareerIDsToLines[playerData.careerId]],
				nil
			)
		end
	elseif IsWarBandActive and IsWarBandActive() then
		local warbandData = PartyUtils.GetWarbandData() or {}
		for _, groupData in ipairs(warbandData) do
			for partyIndex, playerData in ipairs(groupData.players or {}) do
				pushPlayer(
					playersByName,
					ownPartyTargetEvents,
					playerData.name,
					playerData.healthPercent,
					playerData.careerLine,
					ownPartyTargetEvents[fixString(playerData.name)] and partyIndex or nil
				)
			end
		end
	else
		local partyData = PartyUtils.GetPartyData() or {}
		for index, playerData in ipairs(partyData) do
			pushPlayer(
				playersByName,
				ownPartyTargetEvents,
				playerData.name,
				playerData.healthPercent,
				playerData.careerLine,
				index
			)
		end
	end

	for _, player in pairs(playersByName) do
		if player.name == EZGuard.CurrentGuardTarget.name then
			EZGuard.CurrentGuardTarget.index = player.index or player.partyIndex or 0
		end
		players[#players + 1] = player
	end

	return players
end

function EZGuard.RefreshPlayersSnapshot()
	EZGuard.Party = EZGuard.BuildFriendlyPlayersSnapshot()
	EZGuard.RefreshState.playersDirty = false
	EZGuard.RefreshState.transientDirty = true
	EZGuard.RefreshState.nextPlayersSnapshotTime = currentTime + SNAPSHOT_FALLBACK_INTERVAL
end

function EZGuard.SetPlayersDistance(players)
	local defaultDistance = 999999
	local playerDistances = {}

	if not EZGuard.Settings.rangeCheck then
		for i = 1, #players do
			players[i].distance = 0
		end
		EZGuard.PlayerDistances = playerDistances
		return players
	end

	local pending = {}
	local pendingCount = 0
	for i = 1, #players do
		local name = players[i].name
		if name ~= nil and name ~= L"" and pending[name] == nil then
			pending[name] = true
			pendingCount = pendingCount + 1
		end
	end

	if pendingCount > 0 then
		for i = 1, MAX_MAP_POINTS do
			local mpd = GetMapPointData("EA_Window_OverheadMapMapDisplay", i)
			if mpd and MapPointTypeFilter[mpd.pointType] and mpd.name then
				local key = fixString(mpd.name)
				if key then
					playerDistances[key] = mathFloor((mpd.distance or defaultDistance) * DISTANCE_FIX_COEFFICIENT)
					if pending[key] then
						pending[key] = nil
						pendingCount = pendingCount - 1
						if pendingCount <= 0 then
							break
						end
					end
				end
			end
		end
	end

	for i = 1, #players do
		local name = players[i].name
		players[i].distance = (name and playerDistances[name]) or defaultDistance
	end

	EZGuard.PlayerDistances = playerDistances
	return players
end

function EZGuard.RefreshPlayersTransientState()
	local players = EZGuard.Party or {}
	if #players == 0 then
		EZGuard.PlayerDistances = {}
		EZGuard.RefreshState.transientDirty = false
		EZGuard.RefreshState.nextTransientRefreshTime = currentTime + TRANSIENT_REFRESH_INTERVAL
		return players
	end

	players = EZGuard.SetPlayersDistance(players)
	sortTrackedPlayers(players)
	EZGuard.Party = players
	EZGuard.RefreshState.transientDirty = false
	EZGuard.RefreshState.nextTransientRefreshTime = currentTime + TRANSIENT_REFRESH_INTERVAL
	return players
end

function EZGuard.SelectHurtPlayer()
	local players = EZGuard.Party
	local cmpPlayer = {
		index = 0,
		name = L"",
		health = 101,
		distance = 999999,
		weight = 1000,
		targetEvent = nil,
		partyIndex = 0,
	}

	EZGuard.NewGuardTarget.index = 0
	EZGuard.NewGuardTarget.name = L""
	EZGuard.NewGuardTarget.healthPercent = 0
	EZGuard.NewGuardTarget.distance = 999999
	EZGuard.NewGuardTarget.weight = 1000
	EZGuard.NewGuardTarget.targetEvent = nil
	EZGuard.NewGuardTarget.partyIndex = 0

	for i = 1, #players do
		local player = players[i]
		if player.name ~= fixString(LOCAL_PLAYER_NAME)
			and player.health > 0
			and player.distance <= EZGuard.Settings.guardDistance
			and player.health * player.weight < cmpPlayer.health * cmpPlayer.weight
		then
			cmpPlayer = player
		end
	end

	if (cmpPlayer.name ~= L"" and cmpPlayer.health < 100 and cmpPlayer.name ~= EZGuard.CurrentGuardTarget.name)
		or (cmpPlayer.name ~= L"" and cmpPlayer.health == 100 and EZGuard.CurrentGuardTarget.name == L"")
		or (cmpPlayer.name ~= L"" and cmpPlayer.health == 100 and EZGuard.CurrentGuardTarget.healthPercent == 0)
	then
		EZGuard.NewGuardTarget.index = cmpPlayer.index or cmpPlayer.partyIndex or 0
		EZGuard.NewGuardTarget.name = cmpPlayer.name
		EZGuard.NewGuardTarget.healthPercent = cmpPlayer.health
		EZGuard.NewGuardTarget.distance = cmpPlayer.distance
		EZGuard.NewGuardTarget.weight = cmpPlayer.weight
		EZGuard.NewGuardTarget.targetEvent = cmpPlayer.targetEvent
		EZGuard.NewGuardTarget.partyIndex = cmpPlayer.partyIndex or cmpPlayer.index or 0
	end
end

function installActionButtonHooks()
	if actionButtonHooksInstalled or not ActionButton or not isTank then
		return
	end

	orgActionButtonOnLButtonDown = ActionButton.OnLButtonDown
	function ActionButton.OnLButtonDown(self, flags, x, y)
		local guardAbilityId = GuardAbilityID[GameData.Player.career.line]
		if EZGuard.Settings
			and EZGuard.Settings.enabled
			and flags == SystemData.ButtonFlags.GAME_ACTION
			and not EZGuard.Settings.autoTarget
			and self.m_ActionId == guardAbilityId
			and GetHotbarCooldown(self:GetSlot()) == 0
			and resolveTargetEvent(EZGuard.NewGuardTarget)
		then
			EZGuard.TryAutoTarget(EZGuard.NewGuardTarget)
		elseif self.m_ActionId == guardAbilityId
			and flags == SystemData.ButtonFlags.CONTROL
		then
			EZGuard.ToggleEnabled()
		end
		orgActionButtonOnLButtonDown(self, flags, x, y)
	end

	orgActionButtonUpdateBurning = ActionButton.UpdateBurning
	function ActionButton.UpdateBurning(self, previousResource, currentResource)
		if self.m_ActionId ~= GuardAbilityID[GameData.Player.career.line] then
			orgActionButtonUpdateBurning(self, previousResource, currentResource)
		end
	end

	orgActionButtonUpdateInventory = ActionButton.UpdateInventory
	function ActionButton.UpdateInventory(self)
		if self.m_ActionId == GuardAbilityID[GameData.Player.career.line] then
			EZGuard.RefreshGuardButtonAppearance()
		else
			orgActionButtonUpdateInventory(self)
		end
	end

	actionButtonHooksInstalled = true
end

function uninstallActionButtonHooks()
	if not actionButtonHooksInstalled or not ActionButton then
		return
	end

	if orgActionButtonOnLButtonDown then
		ActionButton.OnLButtonDown = orgActionButtonOnLButtonDown
	end
	if orgActionButtonUpdateBurning then
		ActionButton.UpdateBurning = orgActionButtonUpdateBurning
	end
	if orgActionButtonUpdateInventory then
		ActionButton.UpdateInventory = orgActionButtonUpdateInventory
	end

	orgActionButtonOnLButtonDown = nil
	orgActionButtonUpdateBurning = nil
	orgActionButtonUpdateInventory = nil
	actionButtonHooksInstalled = false
end
