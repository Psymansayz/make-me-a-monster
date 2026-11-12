-- The settings, saved in PersistentDB, which all clients in this install share.

local Animations = require("src/game/animations")
local GameIds = require("src/game/game_ids")

local Settings = {}

Settings.chosenNpcID = nil
Settings.lastSeenNpcAnimationID = nil -- seen on a real NPC's head, not a swapped one
Settings.chosenAnimationID = nil -- set it with chooseAnimation
-- The last human animation picked. Heads outside the sets play it when the picked set animation has no human match.
Settings.humanAnimationID = nil
Settings.DEFAULT_HEAD_VIEW_DISTANCE = 2150
Settings.headViewDistance = Settings.DEFAULT_HEAD_VIEW_DISTANCE
Settings.HEAD_SIZE_PERCENT = { min = 50, max = 300, step = 5 }
-- Each is { x, y, width, height }, where x and y are the top left corner. They stay nil until the window first closes.
Settings.windows = { variants = {}, allHeads = {}, settings = {} }
-- Not saved. The settings window closes when the plugin unloads, so the settings always start on the page.
Settings.settingsPoppedOut = false
Settings.oneHeadPerGroup = true
Settings.variantsNpcID = nil
Settings.variantsGroup = nil -- in the form VariantsWindow saves it
Settings.variantsPage = nil

-- A negative value means nothing was saved.
local function savedInteger(settingKey)
    local savedValue = PersistentDB:GetInt(settingKey)
    return savedValue ~= nil and savedValue >= 0 and savedValue or nil
end

-- The all-heads window's keys still use its old name, "gallery".
local WINDOW_KEY_PREFIXES = { variants = "variants", allHeads = "gallery", settings = "settings" }
local PLACEMENT_KEY_SUFFIXES = { x = "X", y = "Y", width = "Width", height = "Height" }

local function savedConfig(kind, settingKey)
    local configName = PersistentDB:GetString(settingKey)
    return configName ~= nil and configName ~= "" and GameIds.resolve(kind, configName) or nil
end

-- A saved animation choice, where an empty string means the game's own animation, or unsaved if there is none.
local function savedAnimation(settingKey, unsaved)
    local animationName = PersistentDB:GetString(settingKey)
    if animationName == nil then return unsaved end
    return animationName ~= "" and Animations.idOf(animationName) or nil
end

-- Choosing a human animation also remembers it as the last human one.
function Settings.chooseAnimation(animationID)
    Settings.chosenAnimationID = animationID
    if Animations.setOf(animationID) == nil then Settings.humanAnimationID = animationID end
end

function Settings.load()
    Settings.chosenNpcID = savedConfig("NPC", "npcName")
    Settings.lastSeenNpcAnimationID = savedConfig("Seq", "lastSeenAnimName")
    Settings.chosenAnimationID = savedAnimation("animName", Animations.fallback)
    local chosenHuman = Animations.setOf(Settings.chosenAnimationID) == nil and Settings.chosenAnimationID or nil
    Settings.humanAnimationID = savedAnimation("humanAnimName", chosenHuman)
    Settings.headViewDistance = savedInteger("headViewDistance") or Settings.DEFAULT_HEAD_VIEW_DISTANCE
    for window, prefix in pairs(WINDOW_KEY_PREFIXES) do
        local placement = Settings.windows[window]
        for field, suffix in pairs(PLACEMENT_KEY_SUFFIXES) do placement[field] = savedInteger(prefix .. suffix) end
    end
    Settings.oneHeadPerGroup = savedInteger("oneHeadPerGroup") ~= 0
    Settings.variantsNpcID = savedConfig("NPC", "variantsNpcName")
    Settings.variantsGroup = PersistentDB:GetString("variantsGroup")
    Settings.variantsPage = savedInteger("variantsPage")
end

local function npcNameOf(npcID)
    return npcID and GameIds.nameOf("NPC", npcID) or ""
end

local function animationNameOf(animationID)
    return animationID and Animations.nameOf(animationID) or ""
end

-- Forgets saved NPCs that the list no longer has. Called once, after the list loads.
function Settings.forgetUnlistedNpcs(isListed)
    if Settings.chosenNpcID ~= nil and not isListed(Settings.chosenNpcID) then Settings.chosenNpcID = nil end
    if Settings.variantsNpcID ~= nil and not isListed(Settings.variantsNpcID) then Settings.variantsNpcID = nil end
end

-- The settings live in memory and are only written when the plugin shuts down.
function Settings.save()
    PersistentDB:SetString("npcName", npcNameOf(Settings.chosenNpcID))
    PersistentDB:SetString("lastSeenAnimName", animationNameOf(Settings.lastSeenNpcAnimationID))
    PersistentDB:SetString("animName", animationNameOf(Settings.chosenAnimationID))
    PersistentDB:SetString("humanAnimName", animationNameOf(Settings.humanAnimationID))
    PersistentDB:SetInt("headViewDistance", Settings.headViewDistance)
    for window, prefix in pairs(WINDOW_KEY_PREFIXES) do
        local placement = Settings.windows[window]
        for field, suffix in pairs(PLACEMENT_KEY_SUFFIXES) do
            PersistentDB:SetInt(prefix .. suffix, placement[field] or -1)
        end
    end
    PersistentDB:SetInt("oneHeadPerGroup", Settings.oneHeadPerGroup and 1 or 0)
    PersistentDB:SetString("variantsNpcName", npcNameOf(Settings.variantsNpcID))
    PersistentDB:SetString("variantsGroup", Settings.variantsGroup or "")
    PersistentDB:SetInt("variantsPage", Settings.variantsPage or -1)
end

function Settings.headSizePercent()
    return math.floor(Settings.DEFAULT_HEAD_VIEW_DISTANCE / Settings.headViewDistance * 100 + 0.5)
end

function Settings.setHeadSizePercent(sliderValue)
    local limits = Settings.HEAD_SIZE_PERCENT
    local percent = math.floor(sliderValue / limits.step + 0.5) * limits.step
    percent = math.max(limits.min, math.min(limits.max, percent))
    Settings.headViewDistance = math.max(1, math.floor(Settings.DEFAULT_HEAD_VIEW_DISTANCE * 100 / percent + 0.5))
    return percent
end

return Settings
