# ModPresets
Allows you to create mod configuration presets for Don't Starve Together server and client mods.

## Klei's Preset System
`ServerCreationScreen` creates `WorldSettingsTab` creates `WorldSettingsMenu` creates `PresetBox`

### `PresetBox` Buttons

* **Revert**
* **Update**
    * *OnEditPreset* opens `NamePresetScreen` which calls *EditPreset*
    * If you have selected a custom preset, this button will allow you to update the settings, name, and description associated with that preset.
* **Choose settings preset**
    * Opens `PresetPopupScreen`
    * This button allows you to select a preset from a list of presets. (There may be built-in presets that you cannot alter or delete.)
* **Save as new preset**
    * *OnSavePreset* opens `NamePresetScreen` which calls *SavePreset*
    * This opens up a screen that allows you to provide a name and description for a new preset that stores the current state of the configuration options.

### `PresetPopupScreen` Buttons

* **Update**
    * *EditPreset* opens `NamePresetScreen` which calls *oneditfn*
        * *oneditfn*, *ondeletefn*, and *onconfirmfn* are functions that are passed into the `PresetPopupScreen` constructor by `PresetBox`.
    * This button allows you to change the name or description of a preset, but it DOES NOT update the preset's mod configurations, unlike the `PresetBox` edit/update button.
* **Delete**
    * *DeletePreset* calls *ondeletefn*
    * This shows a confirmation screen and will delete the associated preset from the stored presets upon approval.

* **Apply**
    * *OnConfirmPreset* calls *onconfirmfn* which calls the `PresetBox` *OnPresetChosen*  function.
    * This button will apply the configuration options of the selected preset. The applied preset will then become the "currentpreset".

> **PresetPopupScreen Note:** If a currentpreset exists, that preset will be the default item selected and highlighted with a darker color. Otherwise, the first item in the list will be selected and no item will be highlighted.

---

## Roadmap

1. We'd eventually like to add an easier way to import and export mod presets, that way two friends can easily share their mod setup.
2. What happens if someone gives you a mod preset that references mods you don't have? (Use Klei's *TheSim:StartDownloadTempMods* or *TheSim:SubscribeToMod(mod.mod_name)* or GLOBAL.DownloadMods? All found in networking.lua)
3. Potentially make this mod compatible with our In-Game Mod Manager that allows you to change client mods while you're in-game.

---

## Summary

The following screens are modified or used by this mod

* `ServerCreationScreen` (class post construct creates a modified `PresetBox` on `ModsTab`)
* `PresetPopupScreen` (lists available presets)
    * OnPresetButton (for highlighting/selecting a preset in the list)
    * EditPreset (edits only name and description of a preset)
    * DeletePreset (asks for confirmation, then calls `PresetBox.DeletePreset`)
* `NamePresetScreen` (confirmation popup for editing preset details)

The following widgets are modified or used by this mod

* `ModsTab` (`PresetBox` is added as a child)
* `PresetBox`
    * OnSavePreset (save new preset while on `ModsTab`)
    * OnPresetButton (creates and modifies `PresetPopupScreen`)
    * OnPresetChosen (asks for confirmation, then applies a mod preset)
    * OnEditPreset (updates a preset while on `ModsTab`)
    * DeletePreset (deletes a preset from `presets` table and *mod_presets* file)

---

## Implementation

### **Notes**
* **currentpreset**: This refers to the most recently applied preset on the configuration options. This mod does not remember the preset last applied for each save slot, so this variable will always be initialized to a dummy value ([see "Choose Mod Preset" section](#changing-presetbox-choose-mod-preset)).
* **selectedpreset**: Only applies to `PresetPopupScreen` and refers to the item in the list that was last clicked. There MUST be a selected preset at all times. Clicking the Apply button with no selected preset will cause a crash.

To start, since Klei already provided a lot of functionality for us (such as the preset box and the preset list and all their corresponding buttons) this mod is really just comprised of a TON of overrides (what mod isn't?). 

### **Saving Presets**

Before I start making a detailed outline of the code, I'll describe how we SAVE the presets first so the mod's structure will make sense.

We started by trying to figure out how to retrieve a list of enabled mods and their respective configuration options for a specific save slot. We learned that `KnownModIndex` contains many functions that allow us to not only get information about enabled mods and configs, but also to set them. We figured out how to get a list of enabled mods (with `ModManager:GetEnabledServerModNames()`) and their config choices (with `KnownModIndex:LoadModConfigurationOptions(modname, is_client_mod)`). These loaded configuration options must be deep copied since the config object returned can still be altered elsewhere.

Once we learned how to collect the mod information, we figured we could use Klei's *SavePersistentString* function to store the data to a file somewhere on the disk. By default, *SavePersistentString* saves files in here: `C:\Users\...\Documents\Klei\DoNotStarveTogether\254404980\client_save`

We originally wanted to store the individual presets in their own folder (e.g. `\client_save\mod_presets\`) in separate files. However, since file manipulation is only really possible in the DST *data* folder, and we couldn't create a folder in *client_save* from *modmain*, and we wanted to use *SavePersistentString* to save inside the *client_save* folder, we settled for storing all the presets in one object stored in one file called *mod_presets*.

When the mod first loads up, it checks if *mod_presets* exists and has data. If it is empty or nil, then we create the file for the first time and initialize it with our built-in "Vanilla" preset.

> **Remember:** One of the first things the mod does is read the file and store the table in a variable called `presets`. As people add and change and delete presets, you can safely assume that the `presets` table and the *mod_presets* file will be in sync.

### **Creating the PresetBox**

We first added a `PresetBox` "child" on the `ModsTab` (`ModsTab` being a child of `ServerCreationScreen`), and we set its position with a bunch of magic numbers. Since the `PresetBox` won't start up with a currentpreset, we have to disable the "Update" button because there is nothing to update if no preset is selected. Also, the box that displays the name and description of the current preset will start up empty.

### **Modding PresetBox's "Save As New Preset" Button**

After this, we got the "Save as new preset" button working. This is simply done by overriding `PresetBox`'s *OnSavePreset* function. We still push a screen to ask for the new name and description of the preset, and then we just run OUR save function instead.

### **Modding PresetBox's "Choose Mod Preset" Button**

Now, the biggest part of this mod is the override to `PresetBox`'s *OnPresetButton*. This is the on-click function for the "Choose Mod Preset" button. This button is what calls the `PresetPopupScreen` into existence, which means it is the only place where we will ever have a reference to the screen object and be able to change its properties.

When "Choose Mod Preset" is clicked, it creates a `PresetPopupScreen` and its constructor requires:

1. The current preset
    * We pass currentpreset or something else that is NOT nil (i.e. *USE_FIRST_PRESET*) in order to bypass a nil check inside the constructor. We need control over this to make sure that our `PresetPopupScreen` had SOMETHING selected when it opens. When it opens, we check if currentpreset is *USE_FIRST_PRESET* and then we can change it from there.
2. An onconfirmfn that will run when "Apply" is selected
3. An oneditfn that will run when an "Update Preset" button is clicked on one of the items in the preset list. This will update JUST THE NAME AND DESCRIPTION of a preset
4. An ondeletefn that will run when the "Delete" button is clicked on one of the items in the preset list
5. The levelcategory (Not used by us, so we just pass in whatever was passed into `PresetBox`'s constructor. We passed in *LEVELCATEGORY.SETTINGS*)
6. Some other level-related parameter
7. The location (Not used by us, so we just pass in `presetbox.parent_widget:GetLocation()`)

Now prepare for something quite programmatically horrifying. In order to generate the list of presets on the `PresetPopupScreen` the way we needed, we were forced to **copy** the *ScrollWidgetsCtor* (ctor for each scroll widget) and *ApplyDataToWidget* functions pretty much one-for-one from `presetpopupscreen.lua`. This also means we had to copy all the magic numbers and variables they defined into our class post construct. *Sigh... (If Klei touches these files at all in future updates this mod might be shattered into a million pieces...)

After copying these two functions, we kill the original *scroll_list*. We generate an array of items (using an array version of the `presets` object, indexable with numbers instead of ID's) in alphabetical order (except for built-in presets which go on top), and then we re-create the scroll_list widget with this new array and the *ScrollWidgetsCtor* and *ApplyDataToWidget* functions.

After we create scroll_list again, we eventually check for the whole currentpreset issue. If selectedpreset is still our *USE_FIRST_PRESET* placeholder, then just select the first preset from OUR list and not some other junk data that will cause a crash like mentioned earlier.

**Overrides for our `PresetPopupScreen`**

* *OnPresetButton*
    * This is the on-click function for each item in the preset list (as specified in *ScrollWidgetsCtor*). It just updates the selectedpreset and refreshes the list to show an outline around the selected preset. Our override is pretty much the same as the original function, but we had to make sure the presetid was passed into `self:OnSelectPreset(presetid)` correctly.
* *EditPreset*
    * This function is called when someone wants to update ONLY the name and description of a preset from the preset list. Our override prevents the game from calling more functions related to WORLD presets. It calls the *oneditfn* we passed earlier which eventually calls oneditpresetdetails which updates the file and the `presets` table. If they confirm their changes, it will update presetsList (array version) and refresh the list view. And if the updated preset happens to be the current preset, *oneditfn* will update the `PresetBox` text to immediately reflect the change.
* *DeletePreset*
    * Always shows a confirmation screen. Again, our override prevents the game from calling more "Level" functions related to world settings that will cause a crash. Upon confirmation, our *ondeletefn* is called which updates the `presets` table and the *mod_presets* file. (If the deleted preset was the current preset, then clear the text on the `PresetBox` and disable the update button.) Then update presetsList (array). If the deleted preset was the selected preset, then select the first item in the list and refresh the list view.

**The following point partially belongs to `PresetBox` since it is an override of the  `PresetBox` *OnPresetChosen* function, but it is only called by *PresetPopupScreen*'s "Apply" button.**
* *The "Apply" button* / `PresetBox` *OnPresetChosen* - (The fun part)
    * When "Apply" is clicked, it will always show a confirmation screen before running the *onconfirmfn* we passed earlier. In order to apply the changes, we need to first disable all mods. We use *GetEnabledServerModNames* again, and then run a `ModsTab` function `mods_tab:OnConfirmEnable(restart_required, modname)` to toggle them into a disabled state one by one. Next, we go through `presets` and call the same function to enable the preset's mods. Next we use a wonderful function `KnownModIndex:SaveConfigurationOptions(callback, modname, configs, is_client_mod)` to apply the individual configurations to the newly enabled mods. Then we set currentpreset to the preset that was just applied. If the preset is a built-in preset, we disable the update button. Lastly update the text on the `PresetBox`.

> **Note:** Something that is very nice about all these `ModManager` and `KnownModIndex` and `ModsTab` functions is that they do not permanently edit the mod settings and configurations. You can simply click the back button on the `ServerCreationScreen` to undo all the changes. (This is something we can eventually add to the "Revert Changes" button. Right now it's always disabled.)

### **Modding PresetBox's "Update Preset" Button**

Updating a preset from `PresetBox` will allow you to update the name and description AND the config choices for the currentpreset. Overriding *OnEditPreset* was pretty straightforward. We just create a `NamePresetScreen` and run the same function we use to save a new preset. If an entry already exists in the `presets` table, it will simply overwrite the existing data (see Lua note). After the changes to the preset are saved to the *mod_presets* file, we update the `PresetBox` text to immediately reflect the changes if they changed the name or description.

> **Lua Note:** If I assign a new value in a lua table like this: `myTable["keyHere"] = value`, I can just run the same code to update the value: `myTable["keyHere"] = newValue`.

---

## More
Be sure to check out the code itself in modmain.lua for more notes!

And make sure to check out the GitHub repository: [ModPresets - GitHub - rawii22 and albertoromañach](https://github.com/rawii22/ModPresets)

And the Steam Workshop: [Mod Presets - Steam](https://steamcommunity.com/sharedfiles/filedetails/?id=2840651706)