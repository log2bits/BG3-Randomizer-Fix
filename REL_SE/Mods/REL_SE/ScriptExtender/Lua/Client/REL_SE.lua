-- ====================================================================
-- BG3 Randomizer - Simplified Client
-- MCM Integration for client-side functionality
-- ====================================================================

ModuleUUID = "8f23afc7-2354-42e0-844f-80445bf72f36"

-- Get MCM setting value
function Get(ID_name)
    return Mods.BG3MCM.MCMAPI:GetSettingValue(ID_name, ModuleUUID)
end
