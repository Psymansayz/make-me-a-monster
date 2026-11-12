-- Picks which of an NPC's variants are worth showing: those whose chat head has a model, one per look.
--
-- The lists on a customisation are engine collections, so they are read inside pcall with ipairs, or pairs if that
-- fails. The recolour and rematerial targets aren't compared, because heads that differ only in those look alike.

local Blacklist = require("src/data/head_blacklist")

local HeadFilter = {}

-- The blacklisted ids, which are hidden without being checked.
local listed = {}
for _, group in ipairs({ Blacklist.blank or {}, Blacklist.identical or {}, Blacklist.manual or {} }) do
    for _, npcID in ipairs(group) do listed[npcID] = true end
end

-- An engine list or map as text. Equal contents give equal text.
local function describe(value, depth)
    depth = depth or 0
    if value == nil then return "" end
    local kind = type(value)
    if kind == "number" or kind == "string" or kind == "boolean" then return tostring(value) end
    if depth > 3 then return "?" end
    local items = {}
    local succeeded = pcall(function()
        for key, item in ipairs(value) do items[#items + 1] = { key, item } end
    end)
    if not succeeded or #items == 0 then
        pcall(function()
            for key, item in pairs(value) do items[#items + 1] = { key, item } end
        end)
        table.sort(items, function(a, b) return tostring(a[1]) < tostring(b[1]) end)
    end
    local parts = {}
    for _, pair in ipairs(items) do parts[#parts + 1] = tostring(pair[1]) .. "=" .. describe(pair[2], depth + 1) end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function count(value)
    local n = 0
    pcall(function() for _ in ipairs(value) do n = n + 1 end end)
    if n == 0 then pcall(function() for _ in pairs(value) do n = n + 1 end end) end
    return n
end

local cache = {} -- npc id -> signature text, false if it has no head model, or nil if it couldn't be read
local read = {}  -- npc id -> true once it has been read

local function signature(npcID)
    if read[npcID] then return cache[npcID] end
    read[npcID] = true
    local succeeded, result = pcall(function()
        local custom = ui.NPCCustomisation.new(npcID, false)
        if custom == nil then return nil end
        if custom.isPlayerClone == true then return "player clone" end
        if count(custom.modelList) == 0 then return false end
        return table.concat({
            describe(custom.modelList), describe(custom.modelRecolourList), describe(custom.modelRematerialList),
        }, "|")
    end)
    if succeeded then cache[npcID] = result end
    return cache[npcID]
end

-- For telling apart heads that have the same signature.
function HeadFilter.describeHead(npcID)
    local succeeded, text = pcall(function()
        local custom = ui.NPCCustomisation.new(npcID, false)
        if custom == nil then return "no customisation" end
        local parts = {}
        for _, field in ipairs({ "isPlayerClone", "modelList", "modelScaleList", "modelRecolourList", "modelRematerialList",
            "recolourDest", "rematerialDest", "playerIdkColour" }) do
            parts[#parts + 1] = field .. "=" .. describe(custom[field])
        end
        return table.concat(parts, " ")
    end)
    return succeeded and text or ("unreadable: " .. tostring(text))
end

function HeadFilter.headModels(npcID)
    local models = {}
    pcall(function()
        local custom = ui.NPCCustomisation.new(npcID, false)
        local function note(modelID)
            if type(modelID) == "number" then models[#models + 1] = modelID end
        end
        local listed = pcall(function() for _, modelID in ipairs(custom.modelList) do note(modelID) end end)
        if not listed or #models == 0 then
            pcall(function() for _, modelID in pairs(custom.modelList) do note(modelID) end end)
        end
    end)
    return models
end

-- Model ids are given out in order, so the highest tells roughly how new the head is.
function HeadFilter.newestModel(npcID)
    local highest = 0
    for _, modelID in ipairs(HeadFilter.headModels(npcID)) do
        if modelID > highest then highest = modelID end
    end
    return highest
end

-- The ids worth showing from `ids`, in order.
function HeadFilter.variants(ids)
    local shown, seen = {}, {}
    local canTell = ui ~= nil and ui.NPCCustomisation ~= nil
    for _, npcID in ipairs(ids) do
        if not listed[npcID] then
            local sig = signature(npcID)
            if sig == false then
                -- no head model, so it is left out
            elseif sig == nil then
                if not canTell then shown[#shown + 1] = npcID end -- shown only if the client has no customisation type
            elseif seen[sig] ~= nil then
                -- looks like one already shown, so it is left out
            else
                seen[sig] = npcID
                shown[#shown + 1] = npcID
            end
        end
    end
    return shown
end

return HeadFilter
