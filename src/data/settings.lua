-- The settings, saved in PersistentDB (shared by every character on this PC), each as an integer entry under its
-- own key. An entry that isn't there reads as nil, which is the default; a setting with nothing chosen is saved as -1.

local Settings = {}

Settings.npcID = nil -- the NPC whose head replaces the player's, or nil for none
Settings.animID = nil     -- the chat animation last seen on a real NPC's head (learned), or nil
Settings.animOverride = nil -- the animation picked from the animation dropdown, or nil
Settings.headScale = 100      -- how large the head is drawn in dialogue, as a percentage of normal (100 to 300)
Settings.variantsWidth = nil  -- the size the variants window was left at, or nil
Settings.variantsHeight = nil
Settings.galleryWidth = nil   -- the size the all-heads window was left at, or nil
Settings.galleryHeight = nil

-- A saved integer that isn't negative, or nil.
local function saved(key)
    local value = PersistentDB:GetInt(key)
    return value ~= nil and value >= 0 and value or nil
end

function Settings.load()
    Settings.npcID = saved("npcID")
    Settings.animID = saved("animID")
    Settings.animOverride = saved("animOverride")
    Settings.headScale = saved("headScale") or 100
    Settings.variantsWidth, Settings.variantsHeight = saved("variantsWidth"), saved("variantsHeight")
    Settings.galleryWidth, Settings.galleryHeight = saved("galleryWidth"), saved("galleryHeight")
end

-- Written when the plugin shuts down (the settings are only kept in memory until then).
function Settings.save()
    PersistentDB:SetInt("npcID", Settings.npcID or -1)
    PersistentDB:SetInt("animID", Settings.animID or -1)
    PersistentDB:SetInt("animOverride", Settings.animOverride or -1)
    PersistentDB:SetInt("headScale", Settings.headScale)
    PersistentDB:SetInt("variantsWidth", Settings.variantsWidth or -1)
    PersistentDB:SetInt("variantsHeight", Settings.variantsHeight or -1)
    PersistentDB:SetInt("galleryWidth", Settings.galleryWidth or -1)
    PersistentDB:SetInt("galleryHeight", Settings.galleryHeight or -1)
end

function Settings.setAnim(animID)
    Settings.animID = animID
end

function Settings.setAnimOverride(animID)
    Settings.animOverride = animID
end

function Settings.setHeadScale(percent)
    Settings.headScale = percent
end

function Settings.setGallerySize(width, height)
    Settings.galleryWidth, Settings.galleryHeight = width, height
end

function Settings.setVariantsSize(width, height)
    Settings.variantsWidth, Settings.variantsHeight = width, height
end

function Settings.setNpc(npcID)
    Settings.npcID = npcID
end

return Settings
