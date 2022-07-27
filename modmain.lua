local PresetBox = require "widgets/redux/worldsettings/presetbox"
local PopupDialogScreen = require "screens/redux/popupdialog"
local NamePresetScreen = require "screens/redux/namepresetscreen"
local PresetPopupScreen = require "screens/redux/presetpopupscreen"
local Levels = require "map/levels"
local Text = require "widgets/text"
local Image = require "widgets/image"
local Widget = require "widgets/widget"
local TEMPLATES = require "widgets/redux/templates"

local mod_preset_file = "mod_presets"
local USE_FIRST_PRESET = "USE_FIRST_PRESET"

local vanilla = {
    description="Ole' reliable Constant.",
    id="VANILLA",
    mods={},
    name="Vanilla",
    version=1 
}

--First check if the file is empty. If so, just write. If not, then don't tamper with it.
GLOBAL.TheSim:GetPersistentString(mod_preset_file, function(load_success, data)
	if not load_success or data == nil then
		local presets = {}
		presets[vanilla.id] = vanilla
		GLOBAL.SavePersistentString(mod_preset_file, GLOBAL.DataDumper(presets, nil, false), false)
	end
end)

local function IsBuiltinPreset(presetid)
	return presetid == vanilla.id
end

AddClassPostConstruct("screens/redux/servercreationscreen", function(scs)
	local presetbox = scs.mods_tab:AddChild(PresetBox(scs.world_tabs[1].settings_widget, LEVELCATEGORY.SETTINGS, 430))
	presetbox:SetPosition(-525, 30)
	presetbox:SetScale(0.55)
	presetbox.changepresetmode:Hide()
	presetbox.horizontal_line:Hide()
	presetbox.presets:SetString("Mod Presets")
	presetbox.presetdesc:Nudge(GLOBAL.Vector3(0, -40, 0)) -- For some reason the description of the current preset was too high and right under the preset name, so we move it down a little with this.
	presetbox.presetbutton:SetText("Choose Mod Preset")
	
	presetbox:SetPresetEditable(false)
	
	local presets = {}
	-- Get list of all other presets
	GLOBAL.TheSim:GetPersistentString(mod_preset_file, function(load_success, data)
		if load_success and data ~= nil then
			local success, custompresets = GLOBAL.RunInSandbox(data)
			if success and custompresets then
				presets = custompresets
			end
		end
	end)
	
	local onsavepreset = function(id, name, description)
		local enabledServerMods = GLOBAL.ModManager:GetEnabledServerModNames()
		local preset = {
			id = id,
			name = name,
			description = description,
			version = 1,
			mods = {},
		}
		for k, mod in ipairs(enabledServerMods) do
			local config = GLOBAL.KnownModIndex:LoadModConfigurationOptions(mod, false)
			preset.mods[mod] = config
		end
		
		-- Save/Update preset
		presets[id] = preset
		
		GLOBAL.SavePersistentString(mod_preset_file, GLOBAL.DataDumper(presets, nil, false), false)
		return true
	end
	
	local oneditpresetdetails = function(presetid, name, description)
		-- Update details
		presets[presetid].name = name
		presets[presetid].description = description
		
		-- Save presets
		GLOBAL.SavePersistentString(mod_preset_file, GLOBAL.DataDumper(presets, nil, false), false)
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
	
	-- Make preset list look pretty (see presetpopupscreen.lua)
	local widget_width = 400
	local widget_height = 80
	
	local padded_width = widget_width + 10
	local padded_height = widget_height + 10
	
	local num_rows = math.floor(500 / padded_height)
	local peek_height = math.abs(num_rows * padded_height - 500)
	
	local normal_list_item_bg_tint = {1, 1, 1, 0.4}
    local focus_list_item_bg_tint  = {1, 1, 1, 0.6}
    local current_list_item_bg_tint = {1, 1, 1, 0.8}
    local focus_current_list_item_bg_tint  = {1, 1, 1, 1}

    local hover_config = {
        offset_x = 0,
        offset_y = 48,
    }
	
	presetbox.OnPresetButton = function(self)
		--self.currentpreset = presetsList[1].id --this is a test. remove this or set it to nil unless you know from startup what preset they had last chosen.
		if self.parent_widget:GetParentScreen() then self.parent_widget:GetParentScreen().last_focus = GLOBAL.TheFrontEnd:GetFocusWidget() end
		local presetpopupscreen = PresetPopupScreen(
			self.currentpreset or USE_FIRST_PRESET, --TERRIBLE. This USE_FIRST_PRESET string is used instead of nil in order to bypass a nil check in presetpopupscreen's constructor
			function(levelcategory, presetid)
				-- When users confirm which preset to load from PresetPopupScreen
				self:OnPresetChosen(presetid)
			end,
			function(levelcategory, originalid, presetid, name, desc)
				-- When users confirm they want to edit the name/desc of a preset from PresetPopupScreen
				oneditpresetdetails(originalid, name, desc)
				
				-- If user changed details for current preset, update text on presetbox
				if originalid == self.currentpreset then
					self:SetTextAndDesc(name, desc)
				end
				return true
			end,
			function(levelcategory, presetid)
				-- When users confirm they want to delete a preset from PresetPopupScreen
				self:DeletePreset(presetid)
			end,
			self.levelcategory,
			GLOBAL.GetLevelType(self.parent_widget:GetGameMode()),
			self.parent_widget:GetLocation()
		)
		
		-- Yes, we copied this... (see presetpopupscreen.lua)
		local function ScrollWidgetsCtor(context, i)
			local preset = Widget("preset-"..i)
			preset:SetOnGainFocus(function() presetpopupscreen.scroll_list:OnWidgetFocus(preset) end)

			preset.backing = preset:AddChild(TEMPLATES.ListItemBackground(padded_width, padded_height, function() presetpopupscreen:OnPresetButton(preset.data.id) end))
			preset.backing.move_on_click = true

			preset.name = preset.backing:AddChild(Text(GLOBAL.CHATFONT, 26))
			preset.name:SetHAlign(GLOBAL.ANCHOR_LEFT)
			preset.name:SetRegionSize(padded_width - 40, 30)
			preset.name:SetPosition(0, padded_height/2 - 20)

			preset.desc = preset.backing:AddChild(Text(GLOBAL.CHATFONT, 16))
			preset.desc:SetVAlign(GLOBAL.ANCHOR_MIDDLE)
			preset.desc:SetHAlign(GLOBAL.ANCHOR_LEFT)
			preset.desc:SetPosition(0, padded_height/2 -(20 + 26 + 10))

			preset.edit = preset.backing:AddChild(TEMPLATES.IconButton("images/button_icons.xml", "mods.tex", GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.EDITPRESET, false, false, function() presetpopupscreen:EditPreset(preset.data.id) end, hover_config))
			preset.edit:SetScale(0.5)
			preset.edit:SetPosition(140, padded_height/2 - 22.5)

			preset.delete = preset.backing:AddChild(TEMPLATES.IconButton("images/button_icons.xml", "delete.tex", GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.DELETEPRESET, false, false, function() presetpopupscreen:DeletePreset(preset.data.id) end, hover_config))
			preset.delete:SetScale(0.5)
			preset.delete:SetPosition(175, padded_height/2 - 22.5)

			preset.modded = preset.backing:AddChild(Image("images/button_icons2.xml", "workshop_filter.tex"))
			preset.modded:SetScale(.1)
			preset.modded:SetClickable(false)
			preset.modded:Hide()

			local _OnControl = preset.backing.OnControl
			preset.backing.OnControl = function(_, control, down)
				if preset.edit.focus and preset.edit:OnControl(control, down) then return true end
				if preset.delete.focus and preset.delete:OnControl(control, down) then return true end

				--Normal button logic
				if _OnControl(_, control, down) then return true end

				if not down and preset.data then
					if control == GLOBAL.CONTROL_MENU_MISC_1 then
						if preset.data then
							presetpopupscreen:EditPreset(preset.data.id)
							GLOBAL.TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
							return true
						end
					elseif control == GLOBAL.CONTROL_MENU_MISC_2 then
						if preset.data then
							presetpopupscreen:DeletePreset(preset.data.id)
							GLOBAL.TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
							return true
						end
					end
				end
			end

			preset.GetHelpText = function()
				local controller_id = GLOBAL.TheInput:GetControllerID()
				local t = {}

				if preset.data then
					table.insert(t, GLOBAL.TheInput:GetLocalizedControl(controller_id, GLOBAL.CONTROL_MENU_MISC_1) .. " " .. GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.EDITPRESET)
					table.insert(t, GLOBAL.TheInput:GetLocalizedControl(controller_id, GLOBAL.CONTROL_MENU_MISC_2) .. " " .. GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.DELETEPRESET)
				end

				return table.concat(t, "  ")
			end

			preset.focus_forward = preset.backing

			return preset
		end
		
		-- See presetpopupscreen.lua
		local function ApplyDataToWidget(context, preset, data, index)
			if not data then
				preset.backing:Hide()
				preset.data = nil
				return
			end

			if presetpopupscreen.selectedpreset == data.id then
				preset.backing:Select()
				preset.name:SetColour(GLOBAL.UICOLOURS.GOLD_SELECTED)
			else
				preset.backing:Unselect()
				preset.name:SetColour(GLOBAL.UICOLOURS.GOLD_CLICKABLE)
			end

			preset.name:SetString(data.name)
			preset.desc:SetMultilineTruncatedString(data.description, 3, padded_width - 40, nil, "...")
			if preset.data ~= data then
				preset.data = data
				preset.backing:Show()
				
				--self.originalpreset is initialized to be presetbox's currentPrest which we passed in earlier to presetpopupscreen's constructor
				if data.id == presetpopupscreen.originalpreset then --this highlights the last applied preset. I think every time a user opens this FOR THE FIRST TIME that none of the presets will be the "original" or "last applied" preset since they haven't selected one yet, EVEN if they've applied a preset to a server in the past. We can't save the "last applied" preset to a speciifc cluster and load it into currentpreset at the moment.
					preset.backing:SetImageNormalColour(GLOBAL.unpack(current_list_item_bg_tint))
					preset.backing:SetImageFocusColour(GLOBAL.unpack(focus_current_list_item_bg_tint))
					preset.backing:SetImageSelectedColour(GLOBAL.unpack(current_list_item_bg_tint))
					preset.backing:SetImageDisabledColour(GLOBAL.unpack(current_list_item_bg_tint))
				else
					preset.backing:SetImageNormalColour(GLOBAL.unpack(normal_list_item_bg_tint))
					preset.backing:SetImageFocusColour(GLOBAL.unpack(focus_list_item_bg_tint))
					preset.backing:SetImageSelectedColour(GLOBAL.unpack(normal_list_item_bg_tint))
					preset.backing:SetImageDisabledColour(GLOBAL.unpack(normal_list_item_bg_tint))
				end
				
				if IsBuiltinPreset(data.id) then
					preset.edit:Hide()
					preset.delete:Hide()
				else
					preset.edit:Show()
					preset.delete:Show()
				end
			end
		end
		
		presetpopupscreen.scroll_list:Kill()
		
		-- Recreate scrolling list of presets (see presetpopupscreen.lua)
		local presetsList = {}
		for k, v in pairs(presets) do
			if not IsBuiltinPreset(v.id) then
				table.insert(presetsList, v)
			end
		end
		table.sort(presetsList, function(a, b)
			return string.lower(a.name) < string.lower(b.name)
		end)
		table.insert(presetsList, 1, presets[vanilla.id])
		
		--TODO: Sort this array. If we have builtin presets and we want them to show first,
		--sort here according to maybe a new order property? or just alphabetically (excluding builtin presets)
		presetpopupscreen.scroll_list = presetpopupscreen.root:AddChild(TEMPLATES.ScrollingGrid(
			presetsList,
			{
				context = {},
				widget_width  = padded_width,
				widget_height = padded_height,
				num_visible_rows = num_rows,
				num_columns      = 1,
				item_ctor_fn = ScrollWidgetsCtor,
				apply_fn     = ApplyDataToWidget,
				scrollbar_offset = 10,
				scrollbar_height_offset = -50,
				peek_height = peek_height,
				force_peek = true,
				end_offset = 1 - peek_height/padded_height,
			}
		))
		presetpopupscreen.scroll_list:SetPosition(0 + (presetpopupscreen.scroll_list:CanScroll() and -10 or 0), -25)
		
		presetpopupscreen.OnPresetButton = function(self, presetinfo)
			self:OnSelectPreset(presetinfo)
			self:Refresh()
		end
		
		-- Select first preset if currentpreset is nil
		if presetpopupscreen.selectedpreset == USE_FIRST_PRESET then
			presetpopupscreen:OnPresetButton(presetsList[1].id)
		end
		
		presetpopupscreen.EditPreset = function(self, presetid)
			GLOBAL.TheFrontEnd:PushScreen(
				NamePresetScreen(
					self.levelcategory,
					GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.EDITPRESET,
					GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.SAVEPRESETCHANGES,
					function(newid, name, description)
						if not self.oneditfn(self.levelcategory, presetid, newid, name, description) then
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
							return
						end
						for i, v in ipairs(presetsList) do
							if v.id == presetid then
								presetsList[i] = presets[presetid]
							end
						end
						self:Refresh()
					end,
					presetid,
					presets[presetid].name,
					presets[presetid].description
				)
			)
		end
		
		presetpopupscreen.DeletePreset = function(self, presetid)
			GLOBAL.TheFrontEnd:PushScreen(
				PopupDialogScreen(string.format(GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.DELETEPRESET_TITLE, presets[presetid].name), GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.DELETEPRESET_BODY,
				{
					{
						text = GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.CANCEL,
						cb = function()
							GLOBAL.TheFrontEnd:PopScreen()
						end,
					},
					{
						text = GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.DELETE,
						cb = function()
							self.ondeletefn(self.levelcategory, presetid)
							for k, v in pairs(presetsList) do
								if v.id == presetid then
									table.remove(presetsList, k)
									break
								end
							end
							--TODO: Sort again here!
							
							-- Select first preset if selected preset was just deleted
							if presetid == self.selectedpreset then
								self:OnPresetButton(presetsList[1].id)
							else
								self:Refresh()
							end
							GLOBAL.TheFrontEnd:PopScreen()
						end,
					},
				})
			)
		end
		
		GLOBAL.TheFrontEnd:PushScreen(presetpopupscreen)
	end
	
	presetbox.OnPresetChosen = function(self, presetid)
		-- TODO: Push info screen asking user to select a preset if none is chosen
		if presetid == USE_FIRST_PRESET then
			return
		end
	
		local onpresetchosen = function()
			-- Disable all mods
			for k, modname in pairs(GLOBAL.ModManager:GetEnabledServerModNames()) do
				scs.mods_tab:OnConfirmEnable(false, modname)
			end
			
			-- Load the selected preset
			for modname, configs in pairs(presets[presetid].mods) do --First enable the mods and then set the configuration options
				scs.mods_tab:OnConfirmEnable(false, modname)
				GLOBAL.KnownModIndex:SaveConfigurationOptions(function() end, modname, configs, false)
			end
			
			self.currentpreset = presetid
			
			if IsBuiltinPreset(presetid) then
				self:SetPresetEditable(false)
			else
				self:SetPresetEditable(true)
			end
			self:SetTextAndDesc(presets[presetid].name, presets[presetid].description)
		end
		
		-- Confirmation popup, inform changes will be lost
		GLOBAL.TheFrontEnd:PushScreen(PopupDialogScreen(GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.LOSECHANGESTITLE, GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.LOSECHANGESBODY,
            {
                {
                    text = GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.YES,
                    cb = function()
                        GLOBAL.TheFrontEnd:PopScreen() --This PopScreen must come first. Otherwise, if a non-workshop mod is enabled by the preset, this confirmation screen will stay on top and prevent users from clicking "Ok" on the non-workshop mod warning.
                        onpresetchosen()
                    end
                },
                {
                    text = GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.NO,
                    cb = function()
                        GLOBAL.TheFrontEnd:PopScreen()
                    end
                }
            })
        )
	end
	
	presetbox.OnEditPreset = function(self)
		GLOBAL.TheFrontEnd:PushScreen(
			NamePresetScreen(
				self.levelcategory,
				GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.EDITPRESET,
				GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.SAVEPRESETCHANGES,
				function(id, name, description)
					if self:EditPreset(self.currentpreset, id, name, description, true) then return end
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
				end,
				self.currentpreset,
				presets[self.currentpreset].name,
				presets[self.currentpreset].description
			)
		)
	end
	
	presetbox.EditPreset = function(self, originalid, presetid, name, desc, updateoverrides)
		-- Save the edited preset
		if onsavepreset(originalid, name, desc) then
			if originalid == self.currentpreset then
				self:SetTextAndDesc(name, desc)
			end
			return true
		end
	end
	
	presetbox.DeletePreset = function(self, presetid)
		presets[presetid] = nil
		GLOBAL.SavePersistentString(mod_preset_file, GLOBAL.DataDumper(presets, nil, false), false)
		
		-- Clear current preset and update displayed preset details
		if presetid == self.currentpreset then
			self.currentpreset = nil
			self:SetTextAndDesc("", "")
			self:SetPresetEditable(false)
		end
	end
end)
