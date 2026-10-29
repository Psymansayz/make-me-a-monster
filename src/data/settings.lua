-- The settings, saved in PersistentDB (shared by every character on this PC), each as an integer entry under its
-- own key. An entry that isn't there reads as nil, which is the default; a setting with nothing chosen is saved as -1.

local AnimationList = require("src/data/animation_list")

local Settings = {}

Settings.chosenNpcID = nil -- the NPC whose head replaces the player's, or nil for none
Settings.lastSeenNpcAnimationID = nil     -- the chat animation last seen on a real NPC's head (learned), or nil
Settings.chosenAnimationID = nil -- the animation picked from the animation dropdown, or nil
-- The view distance the heads in the dialogue boxes are drawn at: the game's own, divided by how many times larger
-- the head is wanted (the slider's 100% to 300%). The game's distance is taken to be this constant (2150 in every log
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

function Settings.load()
    Settings.chosenNpcID = savedInteger("npcID")
    Settings.lastSeenNpcAnimationID = savedInteger("animID")
    -- Nothing saved at all: evil laugh, the player's or the NPC's kind by the head in use. (Saved as -1: the player
    -- chose the default animation.)
    local animationID = PersistentDB:GetInt("animOverride")
    if animationID == nil then
        animationID = Settings.chosenNpcID and AnimationList.npcFallback or AnimationList.fallback
    elseif animationID < 0 then
        animationID = nil
    end
    Settings.chosenAnimationID = animationID
    Settings.headViewDistance = savedInteger("headViewDistance") or Settings.DEFAULT_HEAD_VIEW_DISTANCE
    Settings.variantsWidth, Settings.variantsHeight = savedInteger("variantsWidth"), savedInteger("variantsHeight")
    Settings.galleryWidth, Settings.galleryHeight = savedInteger("galleryWidth"), savedInteger("galleryHeight")
    Settings.variantsX, Settings.variantsY = savedInteger("variantsX"), savedInteger("variantsY")
    Settings.galleryX, Settings.galleryY = savedInteger("galleryX"), savedInteger("galleryY")
end

-- Written when the plugin shuts down (the settings are only kept in memory until then).
function Settings.save()
    PersistentDB:SetInt("npcID", Settings.chosenNpcID or -1)
    PersistentDB:SetInt("animID", Settings.lastSeenNpcAnimationID or -1)
    PersistentDB:SetInt("animOverride", Settings.chosenAnimationID or -1)
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

function Settings.setLastSeenNpcAnimation(animID)
    Settings.lastSeenNpcAnimationID = animID
end

function Settings.setChosenAnimation(animID)
    Settings.chosenAnimationID = animID
end

-- The head size as the slider shows it (100 to 300, how many percent of the normal size), and its setter, which works
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

function Settings.setGallerySize(width, height)
    Settings.galleryWidth, Settings.galleryHeight = width, height
end

function Settings.setVariantsSize(width, height)
    Settings.variantsWidth, Settings.variantsHeight = width, height
end

function Settings.setGalleryPosition(x, y)
    Settings.galleryX, Settings.galleryY = x, y
end

function Settings.setVariantsPosition(x, y)
    Settings.variantsX, Settings.variantsY = x, y
end

function Settings.setChosenNpc(npcID)
    Settings.chosenNpcID = npcID
end

return Settings
