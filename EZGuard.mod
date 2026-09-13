<?xml version="1.0" encoding="UTF-8"?>
<ModuleFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
	<UiMod name="EZGuard" version="1.22" date="22/08/2026" >
		<Author name="Talladego" email="" />
		<Description text="EZGuard" />
		<VersionSettings gameVersion="1.4.8" windowsVersion="1.0" savedVariablesVersion="1.0" />

		<Dependencies>
			<Dependency name="EA_ActionBars" />
			<Dependency name="LibSlash" />
		</Dependencies>
			
		<Files>
			<File name="libs\LibStub.lua" />
			<File name="libs\LibGUI.lua" />
			<File name="libs\LibConfig.lua" />		

			<File name="EZGuard_Config.lua" />		
			<File name="EZGuard.lua" />			
		</Files>

		<SavedVariables>
			<SavedVariable name="EZGuard.Settings" />
		</SavedVariables>

		<OnInitialize>
			<CallFunction name="EZGuard.Initialize" />
		</OnInitialize>

		<OnUpdate>
			<CallFunction name="EZGuard.OnUpdate" />
		</OnUpdate>

		<OnShutdown>
			<CallFunction name="EZGuard.OnShutdown" />
		</OnShutdown>
	</UiMod>
</ModuleFile>
