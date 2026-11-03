-- The settings, saved in PersistentDB (shared by every character on this PC), each as an integer entry under its
-- own key. An entry that isn't there reads as nil, which is the default; a setting with nothing chosen is saved as -1.
-- The head and the animation chosen are saved by their names in the game too (ids can differ between game builds).
-- The fields are set directly; only the head size has a setter (it works out the view distance).

local Animations = require("src/game/animations")
local GameIds = require("src/game/game_ids")

local Settings = {}

Settings.chosenNpcID = nil -- the NPC whose head replaces the player's, or nil for none
Settings.lastSeenNpcAnimationID = nil     -- the chat animation last seen on a real NPC's head (learned), or nil
Settings.chosenAnimationID = nil -- the animation picked from the animation dropdown, or nil
-- The view distance the heads in the dialogue boxes are drawn at: the game's own, divided by how many times larger
-- the head is wanted (the slider's 50% to 300%). The game's distance is taken to be this constant (2150 in every log
-- seen) for every box. The distance itself is kept, so nothing is worked out when a dialogue box opens.
Settings.DEFAULT_HEAD_VIEW_DISTANCE = 2150
Settings.headViewDistance = Settings.DEFAULT_HEAD_VIEW_DISTANCE
Settings.variantsWidth = nil  -- the size the variants window was left at, or nil
Settings.variantsHeight = nil
Settings.galleryWidth = nil   -- the size the all-heads window was left at, or nil
Settings.galleryHeight = nil
Settings.variantsX = nil      -- where the variants window was left (its top left corner), or nil
Settings.variantsY = nil
Settings.galleryX = nil       -- where the all-heads window was left, or nil
Settings.galleryY = nil

-- A saved integer that isn't negative, or nil.
local function savedInteger(settingKey)
    local savedValue = PersistentDB:GetInt(settingKey)
    return savedValue ~= nil and savedValue >= 0 and savedValue or nil
end

-- The NPC whose head was chosen, or nil. Saved by name, and by id for a head whose name is not known yet (one saved by
-- id only, and not chosen again before the plugin's page was opened); "" with -1 for none.
local function savedNpc()
    local npcName = PersistentDB:GetString("npcName")
    if npcName ~= nil and npcName ~= "" then return GameIds.resolve("NPC", npcName) end
    return savedInteger("npcID")
end

-- The animation chosen, or nil for the default one. Saved as "": the player chose the default animation; a name this
-- game build does not list reads as the default too.
local function savedAnimation()
    local animationName = PersistentDB:GetString("animName")
    if animationName ~= nil then return animationName ~= "" and Animations.idOf(animationName) or nil end
    -- (saved by its id by an earlier build; -1 for the default animation)
    local savedID = PersistentDB:GetInt("animOverride")
    if savedID ~= nil then return Animations.isListed(savedID) and savedID or nil end
    -- Nothing saved at all: evil laugh, the player's or the NPC's kind by the head in use.
    return Settings.chosenNpcID and Animations.npcFallback or Animations.fallback
end

function Settings.load()
    Settings.chosenNpcID = savedNpc()
    Settings.lastSeenNpcAnimationID = savedInteger("animID")
    Settings.chosenAnimationID = savedAnimation()
    Settings.headViewDistance = savedInteger("headViewDistance") or Settings.DEFAULT_HEAD_VIEW_DISTANCE
    Settings.variantsWidth, Settings.variantsHeight = savedInteger("variantsWidth"), savedInteger("variantsHeight")
    Settings.galleryWidth, Settings.galleryHeight = savedInteger("galleryWidth"), savedInteger("galleryHeight")
    Settings.variantsX, Settings.variantsY = savedInteger("variantsX"), savedInteger("variantsY")
    Settings.galleryX, Settings.galleryY = savedInteger("galleryX"), savedInteger("galleryY")
end

-- Written when the plugin shuts down (the settings are only kept in memory until then).
function Settings.save()
    PersistentDB:SetString("npcName", Settings.chosenNpcID and GameIds.nameOf("NPC", Settings.chosenNpcID) or "")
    PersistentDB:SetInt("npcID", Settings.chosenNpcID or -1)
    PersistentDB:SetInt("animID", Settings.lastSeenNpcAnimationID or -1)
    PersistentDB:SetString("animName", Settings.chosenAnimationID and Animations.nameOf(Settings.chosenAnimationID) or "")
    PersistentDB:SetInt("headViewDistance", Settings.headViewDistance)
    PersistentDB:SetInt("variantsWidth", Settings.variantsWidth or -1)
    PersistentDB:SetInt("variantsHeight", Settings.variantsHeight or -1)
    PersistentDB:SetInt("galleryWidth", Settings.galleryWidth or -1)
    PersistentDB:SetInt("galleryHeight", Settings.galleryHeight or -1)
    PersistentDB:SetInt("variantsX", Settings.variantsX or -1)
    PersistentDB:SetInt("variantsY", Settings.variantsY or -1)
    PersistentDB:SetInt("galleryX", Settings.galleryX or -1)
    PersistentDB:SetInt("galleryY", Settings.galleryY or -1)
end

-- The head size as the slider shows it (50 to 300, how many percent of the normal size), and its setter, which works
-- out the view distance to keep.
function Settings.headSizePercent()
    return math.floor(Settings.DEFAULT_HEAD_VIEW_DISTANCE / Settings.headViewDistance * 100 + 0.5)
end

function Settings.setHeadSizePercent(percent)
    Settings.headViewDistance = math.max(1, math.floor(Settings.DEFAULT_HEAD_VIEW_DISTANCE * 100 / percent + 0.5))
end

-- How many times larger than normal the heads are drawn (1 to 3), for the windows' heads.
function Settings.headScaleMultiplier()
    return Settings.DEFAULT_HEAD_VIEW_DISTANCE / Settings.headViewDistance
end

return Settings
