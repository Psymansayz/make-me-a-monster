-- The settings, saved in PersistentDB (shared by all clients in this install)

local Animations = require("src/game/animations")
local GameIds = require("src/game/game_ids")

local Settings = {}

Settings.chosenNpcID = nil -- the NPC whose head replaces the player's
Settings.lastSeenNpcAnimationID = nil     -- the chat animation last seen on a real NPC's head (learned)
Settings.chosenAnimationID = nil -- the animation picked from the animation dropdown
Settings.DEFAULT_HEAD_VIEW_DISTANCE = 2150
Settings.headViewDistance = Settings.DEFAULT_HEAD_VIEW_DISTANCE
Settings.variantsWidth = nil  -- the size the variants window was left at
Settings.variantsHeight = nil
Settings.galleryWidth = nil   -- the size the all-heads window was left at
Settings.galleryHeight = nil
Settings.variantsX = nil      -- where the variants window was left (its top left corner)
Settings.variantsY = nil
Settings.galleryX = nil       -- where the all-heads window was left
Settings.galleryY = nil
Settings.settingsX = nil      -- where the settings window was left
Settings.settingsY = nil
Settings.settingsPoppedOut = false -- the settings are in their own window, else on the plugin's page
Settings.oneHeadPerGroup = true -- the all-heads window shows one head of each group, else every head
Settings.variantsNpcID = nil -- the NPC chosen when the variants window was last open
Settings.variantsGroup = nil -- which group of it the window showed (VariantsWindow's text for it)
Settings.variantsPage = nil  -- the page it was left on

-- A saved integer that isn't negative
local function savedInteger(settingKey)
    local savedValue = PersistentDB:GetInt(settingKey)
    return savedValue ~= nil and savedValue >= 0 and savedValue or nil
end

-- An NPC saved by its name in the game, or nil.
local function savedNpc(settingKey)
    local npcName = PersistentDB:GetString(settingKey)
    return npcName ~= nil and npcName ~= "" and GameIds.resolve("NPC", npcName) or nil
end

-- The animation chosen: an empty string for the game's own animation, nothing saved yet for evil laugh.
local function savedAnimation()
    local animationName = PersistentDB:GetString("animName")
    if animationName == nil then return Animations.fallback end
    return animationName ~= "" and Animations.idOf(animationName) or nil
end

function Settings.load()
    Settings.chosenNpcID = savedNpc("npcName")
    Settings.lastSeenNpcAnimationID = savedInteger("animID")
    Settings.chosenAnimationID = savedAnimation()
    Settings.headViewDistance = savedInteger("headViewDistance") or Settings.DEFAULT_HEAD_VIEW_DISTANCE
    Settings.variantsWidth, Settings.variantsHeight = savedInteger("variantsWidth"), savedInteger("variantsHeight")
    Settings.galleryWidth, Settings.galleryHeight = savedInteger("galleryWidth"), savedInteger("galleryHeight")
    Settings.variantsX, Settings.variantsY = savedInteger("variantsX"), savedInteger("variantsY")
    Settings.galleryX, Settings.galleryY = savedInteger("galleryX"), savedInteger("galleryY")
    Settings.settingsX, Settings.settingsY = savedInteger("settingsX"), savedInteger("settingsY")
    Settings.settingsPoppedOut = savedInteger("settingsPoppedOut") == 1
    Settings.oneHeadPerGroup = savedInteger("oneHeadPerGroup") ~= 0
    Settings.variantsNpcID = savedNpc("variantsNpcName")
    Settings.variantsGroup = PersistentDB:GetString("variantsGroup")
    Settings.variantsPage = savedInteger("variantsPage")
end

local function npcNameOf(npcID)
    return npcID and GameIds.nameOf("NPC", npcID) or ""
end

-- The settings are only kept in memory until the plugin shuts down.
function Settings.save()
    PersistentDB:SetString("npcName", npcNameOf(Settings.chosenNpcID))
    PersistentDB:SetInt("animID", Settings.lastSeenNpcAnimationID or -1)
    local animationName = Settings.chosenAnimationID and Animations.nameOf(Settings.chosenAnimationID) or ""
    PersistentDB:SetString("animName", animationName)
    PersistentDB:SetInt("headViewDistance", Settings.headViewDistance)
    PersistentDB:SetInt("variantsWidth", Settings.variantsWidth or -1)
    PersistentDB:SetInt("variantsHeight", Settings.variantsHeight or -1)
    PersistentDB:SetInt("galleryWidth", Settings.galleryWidth or -1)
    PersistentDB:SetInt("galleryHeight", Settings.galleryHeight or -1)
    PersistentDB:SetInt("variantsX", Settings.variantsX or -1)
    PersistentDB:SetInt("variantsY", Settings.variantsY or -1)
    PersistentDB:SetInt("galleryX", Settings.galleryX or -1)
    PersistentDB:SetInt("galleryY", Settings.galleryY or -1)
    PersistentDB:SetInt("settingsX", Settings.settingsX or -1)
    PersistentDB:SetInt("settingsY", Settings.settingsY or -1)
    PersistentDB:SetInt("settingsPoppedOut", Settings.settingsPoppedOut and 1 or 0)
    PersistentDB:SetInt("oneHeadPerGroup", Settings.oneHeadPerGroup and 1 or 0)
    PersistentDB:SetString("variantsNpcName", npcNameOf(Settings.variantsNpcID))
    PersistentDB:SetString("variantsGroup", Settings.variantsGroup or "")
    PersistentDB:SetInt("variantsPage", Settings.variantsPage or -1)
end

-- The head size as the slider shows it: 50 to 300 percent of the normal size.
function Settings.headSizePercent()
    return math.floor(Settings.DEFAULT_HEAD_VIEW_DISTANCE / Settings.headViewDistance * 100 + 0.5)
end

function Settings.setHeadSizePercent(percent)
    Settings.headViewDistance = math.max(1, math.floor(Settings.DEFAULT_HEAD_VIEW_DISTANCE * 100 / percent + 0.5))
end

-- How many times larger than normal the windows' heads are drawn.
function Settings.headScaleMultiplier()
    return Settings.DEFAULT_HEAD_VIEW_DISTANCE / Settings.headViewDistance
end

return Settings
