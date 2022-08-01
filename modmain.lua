local PresetBox = require "widgets/redux/worldsettings/presetbox"
local PopupDialogScreen = require "screens/redux/popupdialog"
local NamePresetScreen = require "screens/redux/namepresetscreen"
local PresetPopupScreen = require "screens/redux/presetpopupscreen"
local Levels = require "map/levels"
local Text = require "widgets/text"
local Image = require "widgets/image"
local Widget = require "widgets/widget"
local TEMPLATES = require "widgets/redux/templates"

local MOD_PRESETS_FILE = "mod_presets"
local USE_FIRST_PRESET = "USE_FIRST_PRESET"

local presets = {}
local presetsList = {}

--This is terrible. We just didn't want to copy ScrollWidgetsCtor and ApplyDataToWidget twice, one for the server presets PresetBox and a second time for the client presets PresetBox.
--This allows us to define ScrollWidgetsCtor and ApplyDataToWidget outside of PresetBox's OnPresetButton override.
local presetpopupscreen

local vanilla = {
    description="Ole' reliable Constant.",
    id="VANILLA",
    mods={},
    name="Vanilla",
    version=2,
	is_client_preset=false,
}

local disableAll = {
    description="Removes all excitement.",
    id="CLEAN_SLATE",
    mods={},
    name="Clean Slate",
    version=2,
	is_client_preset=true,
}

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

--First check if the file is empty. If so, just write. If not, then don't tamper with it.
GLOBAL.TheSim:GetPersistentString(MOD_PRESETS_FILE, function(load_success, data)
	local presetsTemp = {}
	local success
	if not load_success or data == nil then
		-- If load failed or file empty, save the vanilla preset
		presetsTemp[vanilla.id] = vanilla
		presetsTemp[disableAll.id] = disableAll
	else
		-- Add 'is_client_preset' property to presets stored using save-data-format version 1
		success, presetsTemp = GLOBAL.RunInSandbox(data)
		if success and presetsTemp then
			for k,preset in pairs(presetsTemp) do
				if preset.version == 1 then
					preset.is_client_preset = false
					preset.version = 2
				end
			end
			-- Add 'Disable All' preset for preset files created before mod version 1.1
			if not presetsTemp[disableAll.id] then
				presetsTemp[disableAll.id] = disableAll
			end
		end
	end
	GLOBAL.SavePersistentString(MOD_PRESETS_FILE, GLOBAL.DataDumper(presetsTemp, nil, false), false)
end)

local function IsBuiltinPreset(presetid)
	return presetid == vanilla.id or presetid == disableAll.id
end

local function getEnabledClientModNames()
	local enabledClientMods = {}
	for k,v in pairs(GLOBAL.KnownModIndex:GetClientModNames()) do
		if GLOBAL.KnownModIndex:IsModEnabled(v) then
			table.insert(enabledClientMods, v)
		end
	end
	return enabledClientMods
end

local function sortByPresetName(a, b)
	return string.lower(a.name) < string.lower(b.name)
end

-- Creates an array with certain presets, to be used by a scrolling list (see presetpopupscreen.lua)
local function getPresetsArrayByType(is_client_preset)
	local presetsListArray = {}
	local customPresets = {}
	
	for k,v in pairs(presets) do
		if IsBuiltinPreset(v.id) and v.is_client_preset == is_client_preset then
			table.insert(presetsListArray, v)
		end
	end
	-- Alphabetize built-in presets, add to top
	table.sort(presetsListArray, sortByPresetName)
	
	for k, v in pairs(presets) do
		if not IsBuiltinPreset(v.id) and v.is_client_preset == is_client_preset then
			table.insert(customPresets, v)
		end
	end
	-- Alphabetize custom presets, append after built-in presets
	table.sort(customPresets, sortByPresetName)
	
	for k,v in pairs(customPresets) do
		table.insert(presetsListArray, v)
	end
	
	return presetsListArray
end

---- LOADING ----
local function loadModPresets()
	GLOBAL.TheSim:GetPersistentString(MOD_PRESETS_FILE, function(load_success, data)
		if load_success and data ~= nil then
			local success, custompresets = GLOBAL.RunInSandbox(data)
			if success and custompresets then
				presets = custompresets
			end
		end
	end)
end

---- SAVING ----
local onsavepreset_server = function(id, name, description)
	local enabledServerMods = GLOBAL.ModManager:GetEnabledServerModNames()
	local preset = {
		id = id,
		name = name,
		description = description,
		version = 2,
		mods = {},
		is_client_preset = false,
	}
	for k, mod in ipairs(enabledServerMods) do
		local config = GLOBAL.KnownModIndex:LoadModConfigurationOptions(mod, false)
		preset.mods[mod] = GLOBAL.deepcopy(config) -- Deep copy since the config object returned can still be altered elsewhere.
	end
	
	-- Save/Update preset
	presets[id] = preset
	
	GLOBAL.SavePersistentString(MOD_PRESETS_FILE, GLOBAL.DataDumper(presets, nil, false), false)
	return true
end

local onsavepreset_client = function(id, name, description)
	local enabledClientMods = getEnabledClientModNames()
	local preset = {
		id = id,
		name = name,
		description = description,
		version = 2,
		mods = {},
		is_client_preset = true,
	}
	
	for k, mod in ipairs(enabledClientMods) do
		local config = GLOBAL.KnownModIndex:LoadModConfigurationOptions(mod, true)
		preset.mods[mod] = GLOBAL.deepcopy(config)
	end
	
	-- Save/Update preset
	presets[id] = preset
	
	GLOBAL.SavePersistentString(MOD_PRESETS_FILE, GLOBAL.DataDumper(presets, nil, false), false)
	return true
end

---- EDITING ----
local oneditpresetdetails = function(presetid, name, description)
	-- Update details
	presets[presetid].name = name
	presets[presetid].description = description
	
	-- Save presets
	GLOBAL.SavePersistentString(MOD_PRESETS_FILE, GLOBAL.DataDumper(presets, nil, false), false)
end

local function pb_OnEditPreset(self)
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

---- DELETING ----
local function pb_DeletePreset(self, presetid)
	presets[presetid] = nil
	GLOBAL.SavePersistentString(MOD_PRESETS_FILE, GLOBAL.DataDumper(presets, nil, false), false)
	
	-- Clear current preset and update displayed preset details
	if presetid == self.currentpreset then
		self.currentpreset = nil
		self:SetTextAndDesc("", "")
		self:SetPresetEditable(false)
	end
end

--====================
-- PRESETPOPUPSCREEN
--====================
---- SCROLL_LIST ----
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

local function pps_OnPresetButton(self, presetinfo)
	self:OnSelectPreset(presetinfo)
	self:Refresh()
end

local function pps_EditPreset(self, presetid)
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

local function pps_DeletePreset(self, presetid)
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


--==============================================
-- SERVER MOD PRESETS FOR SERVERCREATIONSCREEN
--==============================================

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
	
	
	-- Get list of all other presets
	loadModPresets()
	
	presetbox.OnSavePreset = function(self)
		if self.parent_widget:GetParentScreen() then self.parent_widget:GetParentScreen().last_focus = GLOBAL.TheFrontEnd:GetFocusWidget() end
		GLOBAL.TheFrontEnd:PushScreen(
			NamePresetScreen(
				self.levelcategory,
				GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.NEWPRESET,
				GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.SAVEPRESET,
				function(id, name, description)
					if onsavepreset_server(id, name, description) then return end
					
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
	
	presetbox.OnPresetButton = function(self)
		--self.currentpreset = presetsList[1].id --this is a test. remove this or set it to nil unless you know from startup what preset they had last chosen.
		if self.parent_widget:GetParentScreen() then self.parent_widget:GetParentScreen().last_focus = GLOBAL.TheFrontEnd:GetFocusWidget() end
		presetpopupscreen = PresetPopupScreen(
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
		
		presetpopupscreen.scroll_list:Kill()
		
		-- Get array of presets for scrolling list
		presetsList = getPresetsArrayByType(false)
		
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
		
		presetpopupscreen.OnPresetButton = pps_OnPresetButton
		
		-- Select first preset if currentpreset is nil
		if presetpopupscreen.selectedpreset == USE_FIRST_PRESET then
			presetpopupscreen:OnPresetButton(presetsList[1].id)
		end
		
		presetpopupscreen.EditPreset = pps_EditPreset
		
		presetpopupscreen.DeletePreset = pps_DeletePreset
		
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
	
	presetbox.OnEditPreset = pb_OnEditPreset
	
	presetbox.EditPreset = function(self, originalid, presetid, name, desc, updateoverrides)
		-- Save the edited preset
		if onsavepreset_server(originalid, name, desc) then
			if originalid == self.currentpreset then
				self:SetTextAndDesc(name, desc)
			end
			return true
		end
	end
	
	presetbox.DeletePreset = pb_DeletePreset
	
	-- Hide the preset box when a menu button other than "server" is selected. This is because the preset box on the mods_tab is only for server mods.
	local OnMenuButtonSelected_original = scs.mods_tab.subscreener.OnMenuButtonSelected
	scs.mods_tab.subscreener.OnMenuButtonSelected = function(self, selection)
		OnMenuButtonSelected_original(self, selection)
		if selection == "server" then
			presetbox:Show()
		else
			presetbox:Hide()
		end
	end
end)

--====================================
-- CLIENT MOD PRESETS FOR MODSSCREEN
--====================================

AddClassPostConstruct("screens/redux/modsscreen", function(ms)
	--THIS IS TERRIBLE PLEASE DON'T LOOK...
	--PresetBox calls DoFocusHookups at the end of the ctor and calls a function that doesn't exist on OUR parent widget. We defined it here to bypass it.
	ms.mods_page.IsNewShard = function(self)
		return false
	end
	
	local presetbox = ms.mods_page:AddChild(PresetBox(ms.mods_page, LEVELCATEGORY.SETTINGS, 430))
	presetbox:SetPosition(-640, 120)
	presetbox:SetScale(0.6)
	presetbox.changepresetmode:Hide()
	presetbox.horizontal_line:Hide()
	presetbox.presets:SetString("Mod Presets")
	presetbox.presetdesc:Nudge(GLOBAL.Vector3(0, -40, 0)) -- For some reason the description of the current preset was too high and right under the preset name, so we move it down a little with this.
	presetbox.presetbutton:SetText("Choose Mod Preset")
	
	presetbox:SetPresetEditable(false)
	
	
	-- Get list of all other presets
	loadModPresets()
	
	presetbox.OnSavePreset = function(self)
		GLOBAL.TheFrontEnd:PushScreen(
			NamePresetScreen(
				self.levelcategory,
				GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.NEWPRESET,
				GLOBAL.STRINGS.UI.CUSTOMIZATIONSCREEN.SAVEPRESET,
				function(id, name, description)
					if onsavepreset_client(id, name, description) then return end
					
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
	
	presetbox.OnPresetButton = function(self)
		--self.currentpreset = presetsList[1].id --this is a test. remove this or set it to nil unless you know from startup what preset they had last chosen.
		
		presetpopupscreen = PresetPopupScreen(
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
			"SURVIVAL",
			"SURVIVAL"
		)
		
		presetpopupscreen.scroll_list:Kill()
		
		-- Get array of presets for scrolling list
		presetsList = getPresetsArrayByType(true)
		
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
		
		presetpopupscreen.OnPresetButton = pps_OnPresetButton
		
		-- Select first preset if currentpreset is nil
		if presetpopupscreen.selectedpreset == USE_FIRST_PRESET then
			presetpopupscreen:OnPresetButton(presetsList[1].id)
		end
		
		presetpopupscreen.EditPreset = pps_EditPreset
		
		presetpopupscreen.DeletePreset = pps_DeletePreset
		
		GLOBAL.TheFrontEnd:PushScreen(presetpopupscreen)
	end
	
	presetbox.OnPresetChosen = function(self, presetid)
		-- TODO: Push info screen asking user to select a preset if none is chosen
		if presetid == USE_FIRST_PRESET then
			return
		end
	
		local onpresetchosen = function()
			-- Disable all mods
			for k, modname in pairs(getEnabledClientModNames()) do
				ms.mods_page:OnConfirmEnable(false, modname)
			end
			
			-- Load the selected preset
			for modname, configs in pairs(presets[presetid].mods) do --First enable the mods and then set the configuration options
				ms.mods_page:OnConfirmEnable(false, modname)
				GLOBAL.KnownModIndex:SaveConfigurationOptions(function() end, modname, configs, true)
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
	
	presetbox.OnEditPreset = pb_OnEditPreset
	
	presetbox.EditPreset = function(self, originalid, presetid, name, desc, updateoverrides)
		-- Save the edited preset
		if onsavepreset_client(originalid, name, desc) then
			if originalid == self.currentpreset then
				self:SetTextAndDesc(name, desc)
			end
			return true
		end
	end
	
	presetbox.DeletePreset = pb_DeletePreset
	
	-- Hide the preset box when a menu button other than "client" is selected. This is because the preset box in this ModsTab is only for client mods.
	local OnMenuButtonSelected_original = ms.mods_page.subscreener.OnMenuButtonSelected
	ms.mods_page.subscreener.OnMenuButtonSelected = function(self, selection)
		OnMenuButtonSelected_original(self, selection)
		if selection == "client" then
			presetbox:Show()
		else
			presetbox:Hide()
		end
	end
end)
