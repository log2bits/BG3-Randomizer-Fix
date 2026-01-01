ModuleUUID = "8f23afc7-2354-42e0-844f-80445bf72f36"

function Get(ID_name)
	return Mods.BG3MCM.MCMAPI:GetSettingValue(ID_name, ModuleUUID)
end

Mods.BG3MCM.IMGUIAPI:InsertModMenuTab(ModuleUUID, "Optional contents", function(tabHeader)
    local ResetButton = tabHeader:AddButton("Reset Loot List")
    local ResetDescription = tabHeader:AddText("Reset the current loot pool back to its original state (when you wake up in the Nautiloid).")
    ResetButton.OnClick = function()
        Ext.ClientNet.PostMessageToServer("REL_SE_Reset","")
    end
end)

Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]:Subscribe(function(payload)
	if not payload or payload.modUUID ~= ModuleUUID or not payload.settingId then
        return
	elseif payload.settingId == "LevelBasedVisible" and payload.value  then
		Mods.BG3MCM.IMGUIAPI:InsertModMenuTab(ModuleUUID, "Level-based loot settings", function(tabHeader)
            local ResetButton = tabHeader:AddButton("Show current rates")
            local ResetDescription = tabHeader:AddText("Display the current spawn rates of items for the character in control")
            ResetButton.OnClick = function()
                Ext.ClientNet.PostMessageToServer("REL_SE_ShowRate","")
            end
        end)
    end
end)

if Get("LB_Enabled") then
    Mods.BG3MCM.IMGUIAPI:InsertModMenuTab(ModuleUUID, "Level-based loot settings", function(tabHeader)
        local ResetButton = tabHeader:AddButton("Show current rates")
        local ResetDescription = tabHeader:AddText("Display the current spawn rates of items for the character in control")
        ResetButton.OnClick = function()
            Ext.ClientNet.PostMessageToServer("REL_SE_ShowRate","")
        end
    end)
end
