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
    local scale = saved("headScale")
    Settings.headScale = scale and math.max(100, math.min(300, scale)) or 100
    local width, height = saved("variantsWidth"), saved("variantsHeight")
    if width and height and width > 0 and height > 0 then
        Settings.variantsWidth, Settings.variantsHeight = width, height
    else
        Settings.variantsWidth, Settings.variantsHeight = nil, nil
    end
    local galleryWidth, galleryHeight = saved("galleryWidth"), saved("galleryHeight")
    if galleryWidth and galleryHeight and galleryWidth > 0 and galleryHeight > 0 then
        Settings.galleryWidth, Settings.galleryHeight = galleryWidth, galleryHeight
    else
        Settings.galleryWidth, Settings.galleryHeight = nil, nil
    end
end

local function save()
    PersistentDB:SetInt("npcID", Settings.npcID or -1)
    PersistentDB:SetInt("animID", Settings.animID or -1)
    PersistentDB:SetInt("animOverride", Settings.animOverride or -1)
    PersistentDB:SetInt("headScale", Settings.headScale)
    PersistentDB:SetInt("variantsWidth", Settings.variantsWidth or -1)
    PersistentDB:SetInt("variantsHeight", Settings.variantsHeight or -1)
    PersistentDB:SetInt("galleryWidth", Settings.galleryWidth or -1)
    PersistentDB:SetInt("galleryHeight", Settings.galleryHeight or -1)
end

-- Written again as it stands (when the game screen is left and on shutdown), in case a write was lost.
function Settings.save()
    save()
end

function Settings.setAnim(animID)
    if animID == Settings.animID then return end
    Settings.animID = animID
    save()
end

function Settings.setAnimOverride(animID)
    Settings.animOverride = animID
    save()
end

function Settings.setHeadScale(percent)
    if percent == Settings.headScale then return end
    Settings.headScale = percent
    save()
end

function Settings.setGallerySize(width, height)
    if width == Settings.galleryWidth and height == Settings.galleryHeight then return end
    Settings.galleryWidth, Settings.galleryHeight = width, height
    save()
end

function Settings.setVariantsSize(width, height)
    if width == Settings.variantsWidth and height == Settings.variantsHeight then return end
    Settings.variantsWidth, Settings.variantsHeight = width, height
    save()
end

function Settings.setNpc(npcID)
    Settings.npcID = npcID
    save()
end

return Settings
