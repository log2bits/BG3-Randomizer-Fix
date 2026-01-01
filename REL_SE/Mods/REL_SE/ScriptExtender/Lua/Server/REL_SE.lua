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
Mods.REL_SE.PersistentVars.Trader.Generated = Mods.REL_SE.PersistentVars.Trader.Generated or {}
Mods.REL_SE.PersistentVars.Trader.ItemsAdded = Mods.REL_SE.PersistentVars.Trader.ItemsAdded or {}
Mods.REL_SE.PersistentVars.Trader.ProcessedThisSession = Mods.REL_SE.PersistentVars.Trader.ProcessedThisSession or {}

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
-- containerName parameter is used to check if common container (for spawn chance)
function GenerateConsumable(targetGuid, targetName, consumableType, containerName)
    -- Check if common container and apply per-item spawn chance
    if containerName and IsCommonContainer(containerName) then
        local spawnChance = Get("commonContainerSpawnChance") or 20
        local roll = math.random(1, 100)
        if roll > spawnChance then
            print("[REL_SE] Common container consumable - failed spawn roll (" .. roll .. "/" .. spawnChance .. "%), skipping this " .. consumableType)
            return nil
        end
        print("[REL_SE] Common container consumable - passed spawn roll (" .. roll .. "/" .. spawnChance .. "%)")
    end

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
-- containerName parameter is passed to GenerateConsumable for spawn chance check
function GenerateConsumables(targetGuid, targetName, containerName)
    local scrollCount = Get("scrollCount") or 0
    local potionCount = Get("potionCount") or 0
    local arrowCount = Get("arrowCount") or 0

    if scrollCount > 0 or potionCount > 0 or arrowCount > 0 then
        print("[REL_SE] --- Generating Consumables ---")
    end

    -- Generate scrolls
    for i = 1, scrollCount do
        print("[REL_SE] Generating scroll " .. i .. "/" .. scrollCount)
        GenerateConsumable(targetGuid, targetName, "scroll", containerName)
    end

    -- Generate potions
    for i = 1, potionCount do
        print("[REL_SE] Generating potion " .. i .. "/" .. potionCount)
        GenerateConsumable(targetGuid, targetName, "potion", containerName)
    end

    -- Generate arrows
    for i = 1, arrowCount do
        print("[REL_SE] Generating arrow " .. i .. "/" .. arrowCount)
        GenerateConsumable(targetGuid, targetName, "arrow", containerName)
    end
end

-- Clear ALL items from a trader's inventory using TemplateRemoveFrom
function ClearTraderItems(traderGuid, traderName)
    print("[REL_SE] Clearing ALL items from trader: " .. traderName)

    local entity = Ext.Entity.Get(traderGuid)
    if not entity or not entity.InventoryOwner then
        print("[REL_SE] ERROR: Trader has no InventoryOwner component")
        return
    end

    local templatesCleared = {}
    local itemsCleared = 0

    -- Collect all item templates from primary inventory
    if entity.InventoryOwner.PrimaryInventory and entity.InventoryOwner.PrimaryInventory.InventoryContainer then
        local items = entity.InventoryOwner.PrimaryInventory.InventoryContainer.Items
        if items then
            for _, p in pairs(items) do
                if p.Item and p.Item.Uuid and p.Item.Uuid.EntityUuid then
                    local template = Osi.GetTemplate(p.Item.Uuid.EntityUuid)
                    if template and not templatesCleared[template] then
                        templatesCleared[template] = true
                    end
                end
            end
        end
    end

    -- Collect templates from all other inventories
    if entity.InventoryOwner.Inventories then
        for _, inventory in pairs(entity.InventoryOwner.Inventories) do
            local invEntity = Ext.Entity.Get(inventory)
            if invEntity and invEntity.InventoryContainer and invEntity.InventoryContainer.Items then
                for _, p in pairs(invEntity.InventoryContainer.Items) do
                    if p.Item and p.Item.Uuid and p.Item.Uuid.EntityUuid then
                        local template = Osi.GetTemplate(p.Item.Uuid.EntityUuid)
                        if template and not templatesCleared[template] then
                            templatesCleared[template] = true
                        end
                    end
                end
            end
        end
    end

    -- Now remove all collected templates
    for template, _ in pairs(templatesCleared) do
        Osi.TemplateRemoveFrom(template, traderGuid, 9999)
        itemsCleared = itemsCleared + 1
        print("[REL_SE] Removed template: " .. template)
    end

    print("[REL_SE] Successfully cleared " .. itemsCleared .. " template types from trader")
end

-- Generate items for trader and track them for clearing
function GenerateTraderItems(traderGuid, traderName)
    -- Initialize tracking table for this trader
    Mods.REL_SE.PersistentVars.Trader.ItemsAdded[traderGuid] = Mods.REL_SE.PersistentVars.Trader.ItemsAdded[traderGuid] or {}

    -- Generate regular items (no container name for traders, so no spawn chance reduction)
    local itemCount = Get("traderItemCount") or 5
    print("[REL_SE] Generating " .. itemCount .. " items for: " .. traderName)
    for i = 1, itemCount do
        print("[REL_SE] Generating item " .. i .. "/" .. itemCount)
        local itemUuid = GenerateRandomItem(traderGuid, traderName, nil)
        if itemUuid then
            table.insert(Mods.REL_SE.PersistentVars.Trader.ItemsAdded[traderGuid], itemUuid)
        end
    end

    -- Generate consumables using trader-specific settings (no spawn chance reduction)
    local scrollCount = Get("traderScrollCount") or 2
    local potionCount = Get("traderPotionCount") or 3
    local arrowCount = Get("traderArrowCount") or 1

    if scrollCount > 0 or potionCount > 0 or arrowCount > 0 then
        print("[REL_SE] --- Generating Consumables ---")
    end

    for i = 1, scrollCount do
        print("[REL_SE] Generating scroll " .. i .. "/" .. scrollCount)
        local itemUuid = GenerateConsumable(traderGuid, traderName, "scroll", nil)
        if itemUuid then
            table.insert(Mods.REL_SE.PersistentVars.Trader.ItemsAdded[traderGuid], itemUuid)
        end
    end

    for i = 1, potionCount do
        print("[REL_SE] Generating potion " .. i .. "/" .. potionCount)
        local itemUuid = GenerateConsumable(traderGuid, traderName, "potion", nil)
        if itemUuid then
            table.insert(Mods.REL_SE.PersistentVars.Trader.ItemsAdded[traderGuid], itemUuid)
        end
    end

    for i = 1, arrowCount do
        print("[REL_SE] Generating arrow " .. i .. "/" .. arrowCount)
        local itemUuid = GenerateConsumable(traderGuid, traderName, "arrow", nil)
        if itemUuid then
            table.insert(Mods.REL_SE.PersistentVars.Trader.ItemsAdded[traderGuid], itemUuid)
        end
    end

    print("[REL_SE] Finished generating items for: " .. traderName)
end

-- Generate a random item and add it to container/trader
-- Returns the item UUID if successful, nil otherwise
-- containerName parameter is used to check if common container (for spawn chance)
function GenerateRandomItem(targetGuid, targetName, containerName)
    if #BigList == 0 then
        print("[REL_SE] ERROR: BigList is empty! Cannot generate loot.")
        return nil
    end

    -- Check if common container and apply per-item spawn chance
    if containerName and IsCommonContainer(containerName) then
        local spawnChance = Get("commonContainerSpawnChance") or 20
        local roll = math.random(1, 100)
        if roll > spawnChance then
            print("[REL_SE] Common container item - failed spawn roll (" .. roll .. "/" .. spawnChance .. "%), skipping this item")
            return nil
        end
        print("[REL_SE] Common container item - passed spawn roll (" .. roll .. "/" .. spawnChance .. "%)")
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
-- containerName parameter is passed to GenerateRandomItem for spawn chance check
function GenerateMultipleItems(targetGuid, targetName, count, containerName)
    print("[REL_SE] ======================================")
    print("[REL_SE] Generating " .. count .. " items for: " .. targetName)

    for i = 1, count do
        print("[REL_SE] Generating item " .. i .. "/" .. count)
        GenerateRandomItem(targetGuid, targetName, containerName)
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
-- COMMON CONTAINER CHECK
-- ====================================================================

-- Common containers (barrels, crates, trunks, etc.) have lower spawn chance
local commonContainerPatterns = {
    "Barrel", "Crate", "Trunk", "Vase",
    "Pile of Books", "Row of Books", "Stack of Books", "Shelf",
    "Table", "Desk", "Bottle Rack", "Fish Barrel",
    "Loose Plank", "Open Crate", "Wardrobe"
}

function IsCommonContainer(name)
    for _, pattern in ipairs(commonContainerPatterns) do
        if string.find(name, pattern) then
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

    -- Check if container is in someone's inventory (being opened from trade window)
    local entity = Ext.Entity.Get(containerGuid)
    if entity and entity.InventoryMember and entity.InventoryMember.Inventory then
        local parentInventory = Ext.Entity.Get(entity.InventoryMember.Inventory)
        if parentInventory and parentInventory.InventoryOwner then
            print("[REL_SE] Container is in someone's inventory, skipping loot generation")
            Osi.ApplyStatus(containerGuid, "LOOT_DISTRIBUTED_OBJECT", -1)
            return
        end
    end

    -- Get item count from config
    local itemCount = Get("containerItemCount") or 1

    -- Generate items (each item will check spawn chance individually if common container)
    GenerateMultipleItems(containerGuid, name, itemCount, name)

    -- Generate consumables (each consumable will check spawn chance individually if common container)
    GenerateConsumables(containerGuid, name, name)

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

    -- Generate items (no container name for enemies, so no spawn chance reduction)
    GenerateMultipleItems(targetGuid, name, itemCount, nil)

    -- Generate consumables (no container name for enemies, so no spawn chance reduction)
    GenerateConsumables(targetGuid, name, nil)

    -- Apply LOOT_DISTRIBUTED status
    Osi.ApplyStatus(targetGuid, "LOOT_DISTRIBUTED_OBJECT", -1)
    print("[REL_SE] Applied LOOT_DISTRIBUTED_OBJECT status to: " .. name)
    print("[REL_SE] ======================================")
end)

-- ====================================================================
-- TRADER SUPPORT
-- ====================================================================

Ext.Osiris.RegisterListener("RequestTrade", 4, "after", function(_, traderGuid, _, _)
    -- Ensure Trader table exists (for saves that loaded before this was added)
    Mods.REL_SE.PersistentVars = Mods.REL_SE.PersistentVars or {}
    Mods.REL_SE.PersistentVars.Trader = Mods.REL_SE.PersistentVars.Trader or {}
    Mods.REL_SE.PersistentVars.Trader.Generated = Mods.REL_SE.PersistentVars.Trader.Generated or {}
    Mods.REL_SE.PersistentVars.Trader.ItemsAdded = Mods.REL_SE.PersistentVars.Trader.ItemsAdded or {}
    Mods.REL_SE.PersistentVars.Trader.ProcessedThisSession = Mods.REL_SE.PersistentVars.Trader.ProcessedThisSession or {}

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

    -- Check if already processed this session
    if Mods.REL_SE.PersistentVars.Trader.ProcessedThisSession[traderGuid] then
        print("[REL_SE] Trader " .. name .. " already processed this session, skipping")
        return
    end

    print("[REL_SE] ======================================")
    print("[REL_SE] Processing trader: " .. name)

    -- Check if this is a reshuffle (they were generated before) or first time
    if Mods.REL_SE.PersistentVars.Trader.Generated[traderGuid] then
        print("[REL_SE] Reshuffling trader (long rest or force shuffle)")
    else
        print("[REL_SE] First time encountering trader")
    end

    -- Clear ALL items from trader
    ClearTraderItems(traderGuid, name)

    -- Add 10,000 gold to trader
    print("[REL_SE] Adding 10,000 gold to: " .. name)
    Osi.AddGold(traderGuid, 10000)

    -- Generate new items
    GenerateTraderItems(traderGuid, name)

    -- Mark as processed
    Mods.REL_SE.PersistentVars.Trader.Generated[traderGuid] = true
    Mods.REL_SE.PersistentVars.Trader.ProcessedThisSession[traderGuid] = true

    -- Apply LOOT_DISTRIBUTED status (for tracking, though we mainly use ProcessedThisSession now)
    Osi.ApplyStatus(traderGuid, "LOOT_DISTRIBUTED_TRADER", -1)
    print("[REL_SE] Applied LOOT_DISTRIBUTED_TRADER status to: " .. name)
    print("[REL_SE] Trader inventory will refresh after long rest")
    print("[REL_SE] ======================================")
end)

-- ====================================================================
-- LONG REST RESET FOR TRADERS
-- ====================================================================

Ext.Osiris.RegisterListener("LongRestFinished", 0, "after", function()
    print("[REL_SE] ======================================")
    print("[REL_SE] Long rest finished - clearing session tracking")

    -- Clear the session tracking so traders can be reshuffled
    Mods.REL_SE.PersistentVars = Mods.REL_SE.PersistentVars or {}
    Mods.REL_SE.PersistentVars.Trader = Mods.REL_SE.PersistentVars.Trader or {}
    Mods.REL_SE.PersistentVars.Trader.ProcessedThisSession = {}

    print("[REL_SE] Traders will be reshuffled on next interaction")
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
    Mods.REL_SE.PersistentVars.Trader.Generated = Mods.REL_SE.PersistentVars.Trader.Generated or {}
    Mods.REL_SE.PersistentVars.Trader.ItemsAdded = Mods.REL_SE.PersistentVars.Trader.ItemsAdded or {}
    Mods.REL_SE.PersistentVars.Trader.ProcessedThisSession = Mods.REL_SE.PersistentVars.Trader.ProcessedThisSession or {}

    -- Clear session tracking to allow reshuffling
    Mods.REL_SE.PersistentVars.Trader.ProcessedThisSession = {}

    local tradersReset = 0
    for traderGuid, _ in pairs(Mods.REL_SE.PersistentVars.Trader.Generated) do
        tradersReset = tradersReset + 1
        local name = Osi.ResolveTranslatedString(Ext.Entity.Get(traderGuid).DisplayName.NameKey.Handle.Handle)
        print("[REL_SE] Reset trader: " .. name)
    end

    print("[REL_SE] Reset " .. tradersReset .. " traders - they will be reshuffled when next opened")
    print("[REL_SE] Old items will be cleared and replaced with new random items")
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
