-- The settings, saved in PersistentDB (shared by all clients in this install)

local Animations = require("src/game/animations")
local GameIds = require("src/game/game_ids")

local Settings = {}

Settings.chosenNpcID = nil -- the NPC whose head replaces the player's
Settings.lastSeenNpcAnimationID = nil     -- the chat animation last seen on a real NPC's head (learned)
Settings.chosenAnimationID = nil -- the animation picked from the animation dropdown (set with chooseAnimation)
-- The last human animation picked: a head outside the sets plays it when a set's animation picked has no human match.
Settings.humanAnimationID = nil
Settings.DEFAULT_HEAD_VIEW_DISTANCE = 2150
Settings.headViewDistance = Settings.DEFAULT_HEAD_VIEW_DISTANCE
Settings.HEAD_SIZE_PERCENT = { min = 50, max = 300, step = 5 } -- the head size slider
-- Where each window was left: { x, y, width, height } (its top left corner; nil until it has been closed once).
Settings.windows = { variants = {}, allHeads = {}, settings = {} }
-- The settings are in their own window, else on the plugin's page. Not saved: the window closes when the plugin
-- unloads, so the settings start on the page.
Settings.settingsPoppedOut = false
Settings.oneHeadPerGroup = true -- the all-heads window shows one head of each group, else every head
Settings.variantsNpcID = nil -- the NPC chosen when the variants window was last open
Settings.variantsGroup = nil -- which group of it the window showed (VariantsWindow's text for it)
Settings.variantsPage = nil  -- the page it was left on

-- A saved integer that isn't negative
local function savedInteger(settingKey)
    local savedValue = PersistentDB:GetInt(settingKey)
    return savedValue ~= nil and savedValue >= 0 and savedValue or nil
end

-- The saved keys of each window's placement (the all-heads window's are still named "gallery").
local WINDOW_KEY_PREFIXES = { variants = "variants", allHeads = "gallery", settings = "settings" }
local PLACEMENT_KEY_SUFFIXES = { x = "X", y = "Y", width = "Width", height = "Height" }

-- An NPC saved by its name in the game, or nil.
local function savedNpc(settingKey)
    local npcName = PersistentDB:GetString(settingKey)
    return npcName ~= nil and npcName ~= "" and GameIds.resolve("NPC", npcName) or nil
end

-- An animation saved by its name in the game, or nil.
local function savedSeq(settingKey)
    local animationName = PersistentDB:GetString(settingKey)
    return animationName ~= nil and animationName ~= "" and GameIds.resolve("Seq", animationName) or nil
end

-- An animation chosen: an empty string for the game's own animation, nothing saved yet for unsaved.
local function savedAnimation(settingKey, unsaved)
    local animationName = PersistentDB:GetString(settingKey)
    if animationName == nil then return unsaved end
    return animationName ~= "" and Animations.idOf(animationName) or nil
end

-- A human animation chosen is also remembered as the last human one.
function Settings.chooseAnimation(animationID)
    Settings.chosenAnimationID = animationID
    if Animations.setOf(animationID) == nil then Settings.humanAnimationID = animationID end
end

function Settings.load()
    Settings.chosenNpcID = savedNpc("npcName")
    Settings.lastSeenNpcAnimationID = savedSeq("lastSeenAnimName")
    Settings.chosenAnimationID = savedAnimation("animName", Animations.fallback)
    local chosenHuman = Animations.setOf(Settings.chosenAnimationID) == nil and Settings.chosenAnimationID or nil
    Settings.humanAnimationID = savedAnimation("humanAnimName", chosenHuman)
    Settings.headViewDistance = savedInteger("headViewDistance") or Settings.DEFAULT_HEAD_VIEW_DISTANCE
    for window, prefix in pairs(WINDOW_KEY_PREFIXES) do
        local placement = Settings.windows[window]
        for field, suffix in pairs(PLACEMENT_KEY_SUFFIXES) do placement[field] = savedInteger(prefix .. suffix) end
    end
    Settings.oneHeadPerGroup = savedInteger("oneHeadPerGroup") ~= 0
    Settings.variantsNpcID = savedNpc("variantsNpcName")
    Settings.variantsGroup = PersistentDB:GetString("variantsGroup")
    Settings.variantsPage = savedInteger("variantsPage")
end

local function npcNameOf(npcID)
    return npcID and GameIds.nameOf("NPC", npcID) or ""
end

local function animationNameOf(animationID)
    return animationID and Animations.nameOf(animationID) or ""
end

-- The settings are only kept in memory until the plugin shuts down.
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

-- The head size as the slider shows it: a percent of the normal size.
function Settings.headSizePercent()
    return math.floor(Settings.DEFAULT_HEAD_VIEW_DISTANCE / Settings.headViewDistance * 100 + 0.5)
end

-- The head size from the slider's value, kept to its steps and bounds: the percent set.
function Settings.setHeadSizePercent(sliderValue)
    local limits = Settings.HEAD_SIZE_PERCENT
    local percent = math.floor(sliderValue / limits.step + 0.5) * limits.step
    percent = math.max(limits.min, math.min(limits.max, percent))
    Settings.headViewDistance = math.max(1, math.floor(Settings.DEFAULT_HEAD_VIEW_DISTANCE * 100 / percent + 0.5))
    return percent
end

-- How many times larger than normal the heads are drawn (used by dev's debug windows).
function Settings.headScaleMultiplier()
    return Settings.DEFAULT_HEAD_VIEW_DISTANCE / Settings.headViewDistance
end

return Settings
