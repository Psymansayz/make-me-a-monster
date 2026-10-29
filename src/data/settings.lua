-- The settings, saved in PersistentDB (shared by every character on this PC), each as an integer entry under its
-- own key. An entry that isn't there reads as nil, which is the default; a setting with nothing chosen is saved as -1.

local Animations = require("src/data/animations")

local Settings = {}

Settings.chosenNpcID = nil -- the NPC whose head replaces the player's, or nil for none
Settings.lastSeenNpcAnimationID = nil     -- the chat animation last seen on a real NPC's head (learned), or nil
Settings.chosenAnimationID = nil -- the animation picked from the animation dropdown, or nil
Settings.headScale = 1  -- how many times larger than the game draws it the head is drawn (1 to 3; saved as a percentage)
Settings.variantsWidth = nil  -- the size the variants window was left at, or nil
Settings.variantsHeight = nil
Settings.galleryWidth = nil   -- the size the all-heads window was left at, or nil
Settings.galleryHeight = nil

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
        animationID = Settings.chosenNpcID and Animations.npcFallback or Animations.fallback
    elseif animationID < 0 then
        animationID = nil
    end
    Settings.chosenAnimationID = animationID
    local percent = savedInteger("headScale")
    Settings.headScale = percent and percent / 100 or 1
    Settings.variantsWidth, Settings.variantsHeight = savedInteger("variantsWidth"), savedInteger("variantsHeight")
    Settings.galleryWidth, Settings.galleryHeight = savedInteger("galleryWidth"), savedInteger("galleryHeight")
end

-- Written when the plugin shuts down (the settings are only kept in memory until then).
function Settings.save()
    PersistentDB:SetInt("npcID", Settings.chosenNpcID or -1)
    PersistentDB:SetInt("animID", Settings.lastSeenNpcAnimationID or -1)
    PersistentDB:SetInt("animOverride", Settings.chosenAnimationID or -1)
    PersistentDB:SetInt("headScale", math.floor(Settings.headScale * 100 + 0.5))
    PersistentDB:SetInt("variantsWidth", Settings.variantsWidth or -1)
    PersistentDB:SetInt("variantsHeight", Settings.variantsHeight or -1)
    PersistentDB:SetInt("galleryWidth", Settings.galleryWidth or -1)
    PersistentDB:SetInt("galleryHeight", Settings.galleryHeight or -1)
end

function Settings.setLastSeenNpcAnimation(animID)
    Settings.lastSeenNpcAnimationID = animID
end

function Settings.setChosenAnimation(animID)
    Settings.chosenAnimationID = animID
end

function Settings.setHeadScale(scale)
    Settings.headScale = scale
end

function Settings.setGallerySize(width, height)
    Settings.galleryWidth, Settings.galleryHeight = width, height
end

function Settings.setVariantsSize(width, height)
    Settings.variantsWidth, Settings.variantsHeight = width, height
end

function Settings.setChosenNpc(npcID)
    Settings.chosenNpcID = npcID
end

return Settings
