LibConfig = LibStub("LibConfig")

EZGuard_Config = {}

local GUI

local function slashInputText(input)
	if input == nil then
		return ""
	end
	if type(input) ~= "string" then
		input = tostring(input) or ""
	end
	input = string.lower(input)
	return (input:match("^%s*(.-)%s*$")) or ""
end

function EZGuard_Config.Slash(input)
	local text = slashInputText(input)
	if text == "toggle" then
		EZGuard.ToggleEnabled()
		return
	end
	if text == "on" or text == "enable" then
		EZGuard.Enable()
		return
	end
	if text == "off" or text == "disable" then
		EZGuard.Disable()
		return
	end
	local distance = tonumber(text)
	if distance then
		EZGuard.Settings.guardDistance = distance
		EZGuard.NormalizeSettings(EZGuard.Settings)
		EZGuard.Print(L"Guard distance: " .. towstring(tostring(EZGuard.Settings.guardDistance)))
		return
	end

	if (not GUI) then
		GUI = LibConfig("EZGuard v" .. tostring(EZGuard.Settings.version), EZGuard.Settings, true, EZGuard_Config.SettingsChanged)

		GUI:AddTab("Info")
		local infoText
		infoText = GUI("label", "EZGuard makes your guard ability select a group member and set guard to it when clicked. It will only select alive players within guard range (default 50ft).")
		infoText.label:Font("font_default_text_small")
		infoText.label:Align("left")

		infoText = GUI("label", "When EZGuard is enabled your guard ability will have an active check mark. Ctrl-clicking your guard ability toggles EZGuard on and off.")
		infoText.label:Font("font_default_text_small")
		infoText.label:Align("left")

		infoText = GUI("label", "When Auto Target is enabled, party members are selected automatically. You then manually click your guard ability.")
		infoText.label:Font("font_default_text_small")
		infoText.label:Align("left")

		infoText = GUI("label", "Enabling Burn Effect makes your guard ability glow when a group member in range needs guard.")
		infoText.label:Font("font_default_text_small")
		infoText.label:Align("left")

		GUI:AddTab("Settings")
		local checkbox
		checkbox = GUI("checkbox", "Enabled", "enabled")
		checkbox.label:Font("font_default_text_small")

		checkbox = GUI("checkbox", "Auto Target", "autoTarget")
		checkbox.label:Font("font_default_text_small")

		checkbox = GUI("checkbox", "Burn Effect", "burnEffects")
		checkbox.label:Font("font_default_text_small")

		checkbox = GUI("checkbox", "Range Check (map distance)", "rangeCheck")
		checkbox.label:Font("font_default_text_small")

		local textbox
		textbox = GUI("textbox", "Guard Distance:", "guardDistance")
		textbox.label:Font("font_default_text_small")
		textbox.label:AnchorTo(textbox, "left", "left", 48, -5)
		textbox.label:Align("left")
		textbox.edit:AnchorTo(textbox.label, "right", "right", -48)
		textbox.edit:Resize(50)

		GUI:AddTab("Hitpoints Factors")
		infoText = GUI("label", "Sets the hitpoints factor when selecting a player to guard. Lower factor is targeted before higher.")
		infoText.label:Font("font_default_text_small")
		infoText.label:Align("left")

		textbox = GUI("textbox", "Healers Hitpoints factor:", "healerWeight")
		textbox.label:Font("font_default_text_small")
		textbox.label:AnchorTo(textbox, "left", "left", 48, -5)
		textbox.label:Align("left")
		textbox.edit:AnchorTo(textbox.label, "right", "right", -48)
		textbox.edit:Resize(50)

		textbox = GUI("textbox", "DPS Hitpoints factor:", "dpsWeight")
		textbox.label:Font("font_default_text_small")
		textbox.label:AnchorTo(textbox, "left", "left", 48, -5)
		textbox.label:Align("left")
		textbox.edit:AnchorTo(textbox.label, "right", "right", -48)
		textbox.edit:Resize(50)

		textbox = GUI("textbox", "Tanks Hitpoints factor:", "tankWeight")
		textbox.label:Font("font_default_text_small")
		textbox.label:AnchorTo(textbox, "left", "left", 48, -5)
		textbox.label:Align("left")
		textbox.edit:AnchorTo(textbox.label, "right", "right", -48)
		textbox.edit:Resize(50)
	end
	GUI:Show()
end

function EZGuard_Config.SettingsChanged()
	GUI:Hide()
	EZGuard.Settings = EZGuard.Settings or {}
	EZGuard.NormalizeSettings(EZGuard.Settings)
	if EZGuard.RefreshState then
		EZGuard.RefreshState.playersDirty = true
		EZGuard.RefreshState.transientDirty = true
		EZGuard.RefreshState.targetDirty = true
		EZGuard.RefreshState.nextPlayersSnapshotTime = 0
		EZGuard.RefreshState.nextTransientRefreshTime = 0
		EZGuard.RefreshState.nextTargetRefreshTime = 0
	end
	EZGuard.ApplyEnabledState()
end
