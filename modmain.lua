local PresetBox = require "widgets/redux/worldsettings/presetbox"
local PopupDialogScreen = require "screens/redux/popupdialog"
local NamePresetScreen = require "screens/redux/namepresetscreen"

local mod_preset_path = "mod_presets/"

--TODO: Create the mod_presets folder if it doesn't exist

AddClassPostConstruct("screens/redux/servercreationscreen", function(scs)
	local presetbox = scs.mods_tab:AddChild(PresetBox(scs.world_tabs[1].settings_widget, LEVELCATEGORY.SETTINGS, 430))
	presetbox:SetPosition(-525, 30)
	presetbox:SetScale(0.55)
	presetbox.changepresetmode:Hide()
	presetbox.horizontal_line:Hide()
	presetbox.presets:SetString("Mod Presets")
	
	local onsavepreset = function(id, name, description)
		local enabledServerMods = GLOBAL.ModManager:GetEnabledServerModNames()
		local preset = {
			name = name,
			description = description,
			version = 1,
			configs = {},
		}
		for k, mod in ipairs(enabledServerMods) do
			local config = GLOBAL.KnownModIndex:LoadModConfigurationOptions(mod, false)
			preset.configs[mod] = config
		end
		
		GLOBAL.SavePersistentString(mod_preset_path..string.gsub(name, "%s", "_"), GLOBAL.DataDumper(preset, nil, false), false)
		return true
	end
	
	presetbox.OnSavePreset = function(self)
		if self.parent_widget:GetParentScreen() then self.parent_widget:GetParentScreen().last_focus = GLOBAL.TheFrontEnd:GetFocusWidget() end
		GLOBAL.TheFrontEnd:PushScreen(
			NamePresetScreen(
				self.levelcategory,
				GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.NEWPRESET,
				GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.SAVEPRESET,
				function(id, name, description)
					if onsavepreset(id, name, description) then return end
					
					-- If save fails
					GLOBAL.TheFrontEnd:PushScreen(
						PopupDialogScreen(GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.SAVECHANGESFAILED_TITLE, GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.SAVECHANGESFAILED_BODY,
						{
							{
								text = GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.BACK,
								cb = function()
									GLOBAL.TheFrontEnd:PopScreen()
								end,
							},
						})
					)
				end
			)
		)
	end
end)

