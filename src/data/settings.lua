-- The chosen NPC, saved in PersistentDB (shared by every character on this PC).

local Settings = {}

local KEY = "chosen_npc"

Settings.npcID = nil -- the NPC whose head replaces the player's, or nil for none
Settings.animID = nil     -- the chat animation last seen on a real NPC's head (learned), or nil
Settings.animOverride = nil -- the animation picked from the animation dropdown, or nil
Settings.headScale = 100      -- how large the head is drawn in dialogue, as a percentage of normal (100 to 300)
Settings.variantsWidth = nil  -- the size the variants window was left at, or nil
Settings.variantsHeight = nil
Settings.galleryWidth = nil   -- the size the all-heads window was left at, or nil
Settings.galleryHeight = nil

-- Workaround: PersistentDB keeps numbers as 32-bit floats; NPC ids are far below 2^24, so they are exact.
function Settings.load()
    local ok, data = pcall(function() return PersistentDB:GetStructuredData(KEY) end)
    local id = ok and type(data) == "table" and tonumber(data.npcID) or nil
    Settings.npcID = id and id >= 0 and math.floor(id) or nil
    local anim = ok and type(data) == "table" and tonumber(data.animID) or nil
    Settings.animID = anim and anim >= 0 and math.floor(anim) or nil
    local override = ok and type(data) == "table" and tonumber(data.animOverride) or nil
    Settings.animOverride = override and override >= 0 and math.floor(override) or nil
    -- (an animation saved by the older searchable list stands in if there is no other)
    local search = ok and type(data) == "table" and tonumber(data.animSearch) or nil
    if Settings.animOverride == nil and search and search >= 0 then Settings.animOverride = math.floor(search) end
    local scale = ok and type(data) == "table" and tonumber(data.headScale) or nil
    Settings.headScale = scale and math.max(100, math.min(300, math.floor(scale + 0.5))) or 100
    local width = ok and type(data) == "table" and tonumber(data.variantsWidth) or nil
    local height = ok and type(data) == "table" and tonumber(data.variantsHeight) or nil
    if width and height and width > 0 and height > 0 then
        Settings.variantsWidth, Settings.variantsHeight = math.floor(width), math.floor(height)
    else
        Settings.variantsWidth, Settings.variantsHeight = nil, nil
    end
    local galleryWidth = ok and type(data) == "table" and tonumber(data.galleryWidth) or nil
    local galleryHeight = ok and type(data) == "table" and tonumber(data.galleryHeight) or nil
    if galleryWidth and galleryHeight and galleryWidth > 0 and galleryHeight > 0 then
        Settings.galleryWidth, Settings.galleryHeight = math.floor(galleryWidth), math.floor(galleryHeight)
    else
        Settings.galleryWidth, Settings.galleryHeight = nil, nil
    end
    return ok and type(data) == "table" -- whether anything was saved
end

local function save()
    local ok, err = pcall(function()
        PersistentDB:SetStructuredData(KEY, {
            npcID = Settings.npcID or -1, animID = Settings.animID or -1, animOverride = Settings.animOverride or -1,
            headScale = Settings.headScale,
            variantsWidth = Settings.variantsWidth or -1, variantsHeight = Settings.variantsHeight or -1,
            galleryWidth = Settings.galleryWidth or -1, galleryHeight = Settings.galleryHeight or -1,
        })
    end)
    if not ok then print("[make_me_a_monster] could not save the settings: " .. tostring(err)) end
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
