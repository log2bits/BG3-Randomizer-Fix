-- ====================================================================
-- BG3 Randomizer - Simplified Client
-- MCM Integration for client-side functionality
-- ====================================================================

ModuleUUID = "8f23afc7-2354-42e0-844f-80445bf72f36"

-- Get MCM setting value
function Get(ID_name)
    return Mods.BG3MCM.MCMAPI:GetSettingValue(ID_name, ModuleUUID)
end

-- Add custom MCM tab with utility buttons
Mods.BG3MCM.IMGUIAPI:InsertModMenuTab(ModuleUUID, "Utilities", function(tabHeader)
    local ShuffleButton = tabHeader:AddButton("Force Shuffle All Traders")
    local ShuffleDescription = tabHeader:AddText("Immediately resets all trader inventories. They will get new random items when you next open them. Use this for testing without long resting.")
    ShuffleButton.OnClick = function()
        print("[REL_SE Client] Sending force shuffle request to server")
        Ext.Net.PostMessageToServer("REL_SE_ForceShuffleTraders", "")
    end
end)
