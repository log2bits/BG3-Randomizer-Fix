-- ====================================================================
-- BG3 Randomizer - Simplified Version
-- Randomly spawns items from LootList.txt into containers and traders
-- ====================================================================

ModuleUUID = "8f23afc7-2354-42e0-844f-80445bf72f36"

-- MCM Integration
function Get(settingName)
    return Mods.BG3MCM.MCMAPI:GetSettingValue(settingName, ModuleUUID)
end

-- Persistent storage for per-save data
Mods.REL_SE = Mods.REL_SE or {}
Mods.REL_SE.PersistentVars = Mods.REL_SE.PersistentVars or {}

-- Ensure Trader table exists (for saves that don't have it yet)
Mods.REL_SE.PersistentVars.Trader = Mods.REL_SE.PersistentVars.Trader or {}
Mods.REL_SE.PersistentVars.Trader.StatusRemoved = Mods.REL_SE.PersistentVars.Trader.StatusRemoved or {}
Mods.REL_SE.PersistentVars.Trader.Shuffled = Mods.REL_SE.PersistentVars.Trader.Shuffled or {}
Mods.REL_SE.PersistentVars.Trader.Generated = Mods.REL_SE.PersistentVars.Trader.Generated or {}

-- ====================================================================
-- LOOTLIST READING
-- ====================================================================

-- Path to LootList.txt
local LootListPath = "LootList.txt"

-- Extract strings from file using pattern
function ExtractStrings(filename, criteria)
    local file = Ext.IO.LoadFile(filename)
    local lines = {}
    if not file then
        print("[REL_SE] ERROR: Could not load " .. filename)
        return lines
    end
    for line in string.gmatch(file, criteria) do
        table.insert(lines, line)
    end
    return lines
end

-- Build the main loot list from LootList.txt
-- Format: --ItemName--++UUID++<rarity>#type#!act!
function LoadLootList()
    print("[REL_SE] ======================================")
    print("[REL_SE] Loading LootList.txt...")

    local names = ExtractStrings(LootListPath, "%-%-(.-)%-%-")
    local uuids = ExtractStrings(LootListPath, "%+%+(.-)%+%+")
    local rarities = ExtractStrings(LootListPath, "<(.-)>")
    local types = ExtractStrings(LootListPath, "#(.-)#")
    local acts = ExtractStrings(LootListPath, "!(.-)!")

    local bigList = {}
    for i = 1, #names do
        if not acts[i] then
            acts[i] = " "
        end
        table.insert(bigList, {
            item_name = names[i],
            item_uuid = uuids[i],
            item_rarity = rarities[i],
            item_type = types[i],
            item_act = acts[i]
        })
    end

    print("[REL_SE] Loaded " .. #bigList .. " items from LootList.txt")
    print("[REL_SE] ======================================")

    return bigList
end

-- Global loot list
BigList = LoadLootList()

-- ====================================================================
-- LOOT GENERATION
-- ====================================================================

-- Roll for a rarity based on configured percentages
-- Only rolls for uncommon, rare, very rare, and legendary (no common)
function RollRarity()
    local uncommonChance = Get("uncommonChance") or 25
    local rareChance = Get("rareChance") or 15
    local veryRareChance = Get("veryRareChance") or 8
    local legendaryChance = Get("legendaryChance") or 3

    local roll = math.random(1, 100)

    if roll <= legendaryChance then
        return "legendary"
    elseif roll <= legendaryChance + veryRareChance then
        return "very rare"
    elseif roll <= legendaryChance + veryRareChance + rareChance then
        return "rare"
    else
        return "uncommon"  -- Default to uncommon, no common rarity
    end
end

-- Get all items of a specific rarity
function GetItemsByRarity(rarity)
    local items = {}
    for i, item in ipairs(BigList) do
        if item.item_rarity == rarity then
            table.insert(items, i)
        end
    end
    return items
end

-- Get all items of a specific type and rarity
function GetItemsByTypeAndRarity(itemType, rarity)
    local items = {}
    for i, item in ipairs(BigList) do
        if item.item_type == itemType and item.item_rarity == rarity then
            table.insert(items, i)
        end
    end
    return items
end

-- Generate a random consumable of a specific type using rarity distribution
-- Returns the item UUID if successful, nil otherwise
function GenerateConsumable(targetGuid, targetName, consumableType)
    -- Roll for rarity using same distribution as regular items
    local rarity = RollRarity()
    print("[REL_SE] Rolled rarity for " .. consumableType .. ": " .. rarity)

    -- Get consumables of this type and rarity
    local itemsOfTypeAndRarity = GetItemsByTypeAndRarity(consumableType, rarity)

    -- If no items of that rarity, try next lower rarity
    while #itemsOfTypeAndRarity == 0 and rarity ~= "uncommon" do
        print("[REL_SE] No " .. consumableType .. "s found for rarity: " .. rarity .. ", trying lower rarity...")
        if rarity == "legendary" then
            rarity = "very rare"
        elseif rarity == "very rare" then
            rarity = "rare"
        elseif rarity == "rare" then
            rarity = "uncommon"
        end
        itemsOfTypeAndRarity = GetItemsByTypeAndRarity(consumableType, rarity)
    end

    -- If still no items found, skip this consumable
    if #itemsOfTypeAndRarity == 0 then
        print("[REL_SE] No " .. consumableType .. "s found in loot list for any rarity, skipping")
        return nil
    end

    -- Pick a random item from the filtered list
    local randomIndex = itemsOfTypeAndRarity[math.random(1, #itemsOfTypeAndRarity)]
    local item = BigList[randomIndex]

    print("[REL_SE] Adding " .. consumableType .. ": " .. item.item_name .. " (" .. rarity .. ") to " .. targetName)
    Osi.TemplateAddTo(item.item_uuid, targetGuid, 1, 0)
    return item.item_uuid
end

-- Generate multiple consumables
function GenerateConsumables(targetGuid, targetName)
    local scrollCount = Get("scrollCount") or 0
    local potionCount = Get("potionCount") or 0
    local arrowCount = Get("arrowCount") or 0

    if scrollCount > 0 or potionCount > 0 or arrowCount > 0 then
        print("[REL_SE] --- Generating Consumables ---")
    end

    -- Generate scrolls
    for i = 1, scrollCount do
        print("[REL_SE] Generating scroll " .. i .. "/" .. scrollCount)
        GenerateConsumable(targetGuid, targetName, "scroll")
    end

    -- Generate potions
    for i = 1, potionCount do
        print("[REL_SE] Generating potion " .. i .. "/" .. potionCount)
        GenerateConsumable(targetGuid, targetName, "potion")
    end

    -- Generate arrows
    for i = 1, arrowCount do
        print("[REL_SE] Generating arrow " .. i .. "/" .. arrowCount)
        GenerateConsumable(targetGuid, targetName, "arrow")
    end
end

-- Generate items for trader and track them for later removal
function GenerateTraderItems(traderGuid, traderName)
    local addedItems = {}

    -- Generate regular items
    local itemCount = Get("traderItemCount") or 5
    print("[REL_SE] Generating " .. itemCount .. " items for: " .. traderName)
    for i = 1, itemCount do
        print("[REL_SE] Generating item " .. i .. "/" .. itemCount)
        local uuid = GenerateRandomItem(traderGuid, traderName)
        if uuid then
            table.insert(addedItems, uuid)
        end
    end

    -- Generate consumables using trader-specific settings
    local scrollCount = Get("traderScrollCount") or 2
    local potionCount = Get("traderPotionCount") or 3
    local arrowCount = Get("traderArrowCount") or 1

    if scrollCount > 0 or potionCount > 0 or arrowCount > 0 then
        print("[REL_SE] --- Generating Consumables ---")
    end

    for i = 1, scrollCount do
        print("[REL_SE] Generating scroll " .. i .. "/" .. scrollCount)
        local uuid = GenerateConsumable(traderGuid, traderName, "scroll")
        if uuid then
            table.insert(addedItems, uuid)
        end
    end

    for i = 1, potionCount do
        print("[REL_SE] Generating potion " .. i .. "/" .. potionCount)
        local uuid = GenerateConsumable(traderGuid, traderName, "potion")
        if uuid then
            table.insert(addedItems, uuid)
        end
    end

    for i = 1, arrowCount do
        print("[REL_SE] Generating arrow " .. i .. "/" .. arrowCount)
        local uuid = GenerateConsumable(traderGuid, traderName, "arrow")
        if uuid then
            table.insert(addedItems, uuid)
        end
    end

    print("[REL_SE] Finished generating items for: " .. traderName)
    return addedItems
end

-- Remove previously generated items from trader
function ClearTraderItems(traderGuid, traderName)
    local generatedItems = Mods.REL_SE.PersistentVars.Trader.Generated[traderGuid]

    if not generatedItems or #generatedItems == 0 then
        print("[REL_SE] No previous items to clear for: " .. traderName)
        return
    end

    print("[REL_SE] Clearing " .. #generatedItems .. " previous items from: " .. traderName)

    for _, templateUuid in ipairs(generatedItems) do
        -- Remove all instances of this template from trader's inventory
        local removedCount = 0
        while Osi.TemplateIsInInventory(templateUuid, traderGuid) == 1 do
            Osi.TemplateRemoveFrom(templateUuid, traderGuid, 1)
            removedCount = removedCount + 1
        end
        if removedCount > 0 then
            print("[REL_SE] Removed " .. removedCount .. " x " .. templateUuid)
        end
    end

    print("[REL_SE] Finished clearing items from: " .. traderName)
end

-- Generate a random item and add it to container/trader
-- Returns the item UUID if successful, nil otherwise
function GenerateRandomItem(targetGuid, targetName)
    if #BigList == 0 then
        print("[REL_SE] ERROR: BigList is empty! Cannot generate loot.")
        return nil
    end

    -- Roll for rarity
    local rarity = RollRarity()
    print("[REL_SE] Rolled rarity: " .. rarity)

    -- Get items of that rarity
    local itemsOfRarity = GetItemsByRarity(rarity)

    -- If no items of that rarity, try next lower rarity
    while #itemsOfRarity == 0 and rarity ~= "uncommon" do
        print("[REL_SE] No items found for rarity: " .. rarity .. ", trying lower rarity...")
        if rarity == "legendary" then
            rarity = "very rare"
        elseif rarity == "very rare" then
            rarity = "rare"
        elseif rarity == "rare" then
            rarity = "uncommon"
        end
        itemsOfRarity = GetItemsByRarity(rarity)
    end

    -- If still no items found, skip this item
    if #itemsOfRarity == 0 then
        print("[REL_SE] No items found in loot list for any rarity, skipping this item")
        return nil
    end

    -- Pick random item from the rarity list
    local randomIndex = itemsOfRarity[math.random(1, #itemsOfRarity)]
    local item = BigList[randomIndex]

    print("[REL_SE] Adding item: " .. item.item_name .. " (" .. rarity .. ") to " .. targetName)
    Osi.TemplateAddTo(item.item_uuid, targetGuid, 1, 0)
    return item.item_uuid
end

-- Generate multiple items for a container/trader
function GenerateMultipleItems(targetGuid, targetName, count)
    print("[REL_SE] ======================================")
    print("[REL_SE] Generating " .. count .. " items for: " .. targetName)

    for i = 1, count do
        print("[REL_SE] Generating item " .. i .. "/" .. count)
        GenerateRandomItem(targetGuid, targetName)
    end

    print("[REL_SE] Finished generating items for: " .. targetName)
    print("[REL_SE] ======================================")
end

-- ====================================================================
-- BLACKLIST CHECKING
-- ====================================================================

function IsBlacklisted(name)
    local blacklist = Get("BlackList")
    if not blacklist or not blacklist.elements then
        return false
    end

    for _, v in pairs(blacklist.elements) do
        if v.enabled and v.name == name then
            print("[REL_SE] " .. name .. " is blacklisted, skipping")
            return true
        end
    end

    return false
end

-- ====================================================================
-- CONTAINER LOOT DISTRIBUTION
-- ====================================================================

Ext.Osiris.RegisterListener("UseStarted", 2, "before", function(_, containerGuid)
    -- Only process containers
    if Osi.IsContainer(containerGuid) ~= 1 then
        return
    end

    -- Check if already looted (has LOOT_DISTRIBUTED_OBJECT status)
    if Osi.HasActiveStatus(containerGuid, "LOOT_DISTRIBUTED_OBJECT") == 1 then
        return
    end

    local name = Osi.ResolveTranslatedString(Ext.Entity.Get(containerGuid).DisplayName.NameKey.Handle.Handle)

    print("[REL_SE] ======================================")
    print("[REL_SE] Container opened: " .. name)

    -- Check blacklist
    if IsBlacklisted(name) then
        Osi.ApplyStatus(containerGuid, "LOOT_DISTRIBUTED_OBJECT", -1)
        return
    end

    -- Get item count from config
    local itemCount = Get("containerItemCount") or 1

    -- Generate items
    GenerateMultipleItems(containerGuid, name, itemCount)

    -- Generate consumables
    GenerateConsumables(containerGuid, name)

    -- Apply LOOT_DISTRIBUTED status so it won't be looted again
    Osi.ApplyStatus(containerGuid, "LOOT_DISTRIBUTED_OBJECT", -1)
    print("[REL_SE] Applied LOOT_DISTRIBUTED_OBJECT status to: " .. name)
    print("[REL_SE] ======================================")
end)

-- ====================================================================
-- DEAD CHARACTER LOOT DISTRIBUTION
-- ====================================================================

Ext.Osiris.RegisterListener("RequestCanLoot", 2, "before", function(looter, targetGuid)
    -- Only process dead characters that are not in the party (enemies and neutrals)
    if Osi.IsDead(targetGuid) ~= 1 or Osi.IsInPartyWith(looter, targetGuid) == 1 then
        return
    end

    -- Check if already looted
    if Osi.HasActiveStatus(targetGuid, "LOOT_DISTRIBUTED_OBJECT") == 1 then
        return
    end

    local name = Osi.ResolveTranslatedString(Ext.Entity.Get(targetGuid).DisplayName.NameKey.Handle.Handle)

    print("[REL_SE] ======================================")
    print("[REL_SE] Dead character looted: " .. name)
    print("[REL_SE] Looter: " .. Osi.GetDisplayName(looter))

    -- Check blacklist
    if IsBlacklisted(name) then
        Osi.ApplyStatus(targetGuid, "LOOT_DISTRIBUTED_OBJECT", -1)
        print("[REL_SE] Blacklisted, skipping")
        return
    end

    -- Check if boss or normal enemy
    local isBoss = Osi.IsBoss(targetGuid) == 1
    local itemCount = 0

    if isBoss then
        itemCount = Get("bossItemCount") or 10
        print("[REL_SE] Target is a BOSS, generating " .. itemCount .. " items")
    else
        itemCount = Get("enemyItemCount") or 1
        print("[REL_SE] Target is a normal enemy/neutral, generating " .. itemCount .. " items")
    end

    -- Generate items
    GenerateMultipleItems(targetGuid, name, itemCount)

    -- Generate consumables
    GenerateConsumables(targetGuid, name)

    -- Apply LOOT_DISTRIBUTED status
    Osi.ApplyStatus(targetGuid, "LOOT_DISTRIBUTED_OBJECT", -1)
    print("[REL_SE] Applied LOOT_DISTRIBUTED_OBJECT status to: " .. name)
    print("[REL_SE] ======================================")
end)

-- ====================================================================
-- TRADER SUPPORT
-- ====================================================================

Ext.Osiris.RegisterListener("RequestTrade", 4, "before", function(_, traderGuid, _, _)
    -- Ensure Trader table exists (for saves that loaded before this was added)
    Mods.REL_SE.PersistentVars = Mods.REL_SE.PersistentVars or {}
    Mods.REL_SE.PersistentVars.Trader = Mods.REL_SE.PersistentVars.Trader or {}
    Mods.REL_SE.PersistentVars.Trader.StatusRemoved = Mods.REL_SE.PersistentVars.Trader.StatusRemoved or {}
    Mods.REL_SE.PersistentVars.Trader.Shuffled = Mods.REL_SE.PersistentVars.Trader.Shuffled or {}
    Mods.REL_SE.PersistentVars.Trader.Generated = Mods.REL_SE.PersistentVars.Trader.Generated or {}

    -- Check if trader support is enabled
    if not Get("traderEnabled") then
        return
    end

    -- Check if can trade
    if Osi.CanTrade(traderGuid) ~= 1 then
        return
    end

    local name = Osi.ResolveTranslatedString(Ext.Entity.Get(traderGuid).DisplayName.NameKey.Handle.Handle)

    -- Check blacklist
    if IsBlacklisted(name) then
        return
    end

    -- Check if trader has status and already rolled this long rest
    if Osi.HasActiveStatus(traderGuid, "LOOT_DISTRIBUTED_TRADER") == 1 then
        -- Check if already processed this long rest
        for _, processedTrader in ipairs(Mods.REL_SE.PersistentVars.Trader.StatusRemoved) do
            if processedTrader == traderGuid then
                print("[REL_SE] Trader " .. name .. " already rolled this long rest")
                return
            end
        end

        -- Remove status to allow re-rolling (after long rest)
        Osi.RemoveStatus(traderGuid, "LOOT_DISTRIBUTED_TRADER")
        table.insert(Mods.REL_SE.PersistentVars.Trader.StatusRemoved, traderGuid)
        print("[REL_SE] Removed LOOT_DISTRIBUTED_TRADER status from: " .. name .. " (preparing for reshuffle)")
    end

    -- Check if not already processed
    if Osi.HasActiveStatus(traderGuid, "LOOT_DISTRIBUTED_TRADER") == 0 then
        print("[REL_SE] ======================================")
        print("[REL_SE] Trader opened: " .. name)

        -- Clear old items from previous long rest
        ClearTraderItems(traderGuid, name)

        -- Generate new items and track them
        local addedItems = GenerateTraderItems(traderGuid, name)

        -- Store the generated items for next reshuffle
        Mods.REL_SE.PersistentVars.Trader.Generated[traderGuid] = addedItems

        -- Apply LOOT_DISTRIBUTED status
        Osi.ApplyStatus(traderGuid, "LOOT_DISTRIBUTED_TRADER", -1)
        print("[REL_SE] Applied LOOT_DISTRIBUTED_TRADER status to: " .. name)
        print("[REL_SE] ======================================")
    end
end)

-- ====================================================================
-- LONG REST RESET FOR TRADERS
-- ====================================================================

Ext.Osiris.RegisterListener("LongRestFinished", 0, "before", function()
    print("[REL_SE] ======================================")
    print("[REL_SE] Long rest finished, resetting trader status tracking")
    Mods.REL_SE.PersistentVars.Trader.StatusRemoved = {}
    Mods.REL_SE.PersistentVars.Trader.Shuffled = {}
    print("[REL_SE] ======================================")
end)

-- ====================================================================
-- FORCE SHUFFLE ALL TRADERS (FOR TESTING)
-- ====================================================================

-- Function to force shuffle all traders
function ForceShuffleAllTraders()
    print("[REL_SE] ======================================")
    print("[REL_SE] FORCE SHUFFLING ALL TRADERS")

    -- Ensure Trader tables exist
    Mods.REL_SE.PersistentVars = Mods.REL_SE.PersistentVars or {}
    Mods.REL_SE.PersistentVars.Trader = Mods.REL_SE.PersistentVars.Trader or {}
    Mods.REL_SE.PersistentVars.Trader.StatusRemoved = Mods.REL_SE.PersistentVars.Trader.StatusRemoved or {}
    Mods.REL_SE.PersistentVars.Trader.Shuffled = Mods.REL_SE.PersistentVars.Trader.Shuffled or {}
    Mods.REL_SE.PersistentVars.Trader.Generated = Mods.REL_SE.PersistentVars.Trader.Generated or {}

    -- Clear the tracking tables to allow reshuffling
    Mods.REL_SE.PersistentVars.Trader.StatusRemoved = {}
    Mods.REL_SE.PersistentVars.Trader.Shuffled = {}

    -- Remove LOOT_DISTRIBUTED_TRADER from all traders that have it
    local tradersShuffled = 0
    for traderGuid, _ in pairs(Mods.REL_SE.PersistentVars.Trader.Generated) do
        if Osi.HasActiveStatus(traderGuid, "LOOT_DISTRIBUTED_TRADER") == 1 then
            Osi.RemoveStatus(traderGuid, "LOOT_DISTRIBUTED_TRADER")
            tradersShuffled = tradersShuffled + 1
            local name = Osi.ResolveTranslatedString(Ext.Entity.Get(traderGuid).DisplayName.NameKey.Handle.Handle)
            print("[REL_SE] Removed status from trader: " .. name)
        end
    end

    print("[REL_SE] Reset " .. tradersShuffled .. " traders - they will reshuffle when next opened")
    print("[REL_SE] ======================================")
end

-- Network message handler for force shuffle
Ext.RegisterNetListener("REL_SE_ForceShuffleTraders", function(channel, payload)
    print("[REL_SE] Received force shuffle request from client")
    ForceShuffleAllTraders()
end)

-- ====================================================================
-- INITIALIZATION
-- ====================================================================

print("[REL_SE] ======================================")
print("[REL_SE] BG3 Randomizer Simplified - Loaded!")
print("[REL_SE] Total items in loot pool: " .. #BigList)
print("[REL_SE] ======================================")
