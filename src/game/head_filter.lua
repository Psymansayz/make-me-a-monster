-- Which of an NPC's variants are worth showing: those whose chat head has a model, one of each look.
--
-- The head's data comes from ui.NPCCustomisation.new(npcID, false) (the head customisation of that NPC): a
-- variant with no head models is blank, and variants with the same models and the same recolours and
-- rematerials (the source lists) look the same. The recolour and rematerial targets (recolourDest and
-- rematerialDest) are left out of the comparison: the source lists are empty for every NPC, and heads that
-- differ only in the targets look alike. Nothing is drawn to find this out.
--
-- Workaround: the lists on a customisation are engine collections, so they are read with pcall, with
-- ipairs and, failing that, pairs.
-- An NPC whose head data can't be read at all (the game refuses to make a head customisation for it) has no
-- head to show, like a blank one: it is left out. (Unless the customisation type is missing altogether in
-- this client: then nothing can be told, and every variant is kept.)

local Blacklist = require("src/data/head_blacklist")

local HeadFilter = {}

-- The blacklisted ids, hidden without being checked.
local listed = {}
for _, group in ipairs({ Blacklist.blank or {}, Blacklist.identical or {}, Blacklist.manual or {} }) do
    for _, npcID in ipairs(group) do listed[npcID] = true end
end

-- A list or map from the engine as text, the same for the same contents: arrays by position, maps by key.
local function describe(value, depth)
    depth = depth or 0
    if value == nil then return "" end
    local kind = type(value)
    if kind == "number" or kind == "string" or kind == "boolean" then return tostring(value) end
    if depth > 3 then return "?" end
    local items = {}
    local ok = pcall(function()
        for key, item in ipairs(value) do items[#items + 1] = { key, item } end
    end)
    if not ok or #items == 0 then
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

local cache = {} -- npc id -> signature text, false (no head model), or nil (couldn't be read)
local read = {}  -- npc id -> true once looked at

-- The head of an NPC as text (equal for equal looks), false if it has no model, nil if it can't be read.
local function signature(npcID)
    if read[npcID] then return cache[npcID] end
    read[npcID] = true
    local ok, result = pcall(function()
        local custom = ui.NPCCustomisation.new(npcID, false)
        if custom == nil then return nil end
        if custom.isPlayerClone == true then return "player clone" end
        if count(custom.modelList) == 0 then return false end
        return table.concat({
            describe(custom.modelList), describe(custom.modelRecolourList), describe(custom.modelRematerialList),
        }, "|")
    end)
    if ok then cache[npcID] = result end
    return cache[npcID]
end

-- The ids worth showing from `ids` (in order): those with a head model, the first of each look. Only these
-- can be made the active head, so the active one is never a hidden one. Blacklisted ids are left out without
-- being checked.
function HeadFilter.variants(ids)
    local shown, seen = {}, {}
    local canTell = ui ~= nil and ui.NPCCustomisation ~= nil
    for _, npcID in ipairs(ids) do
        if not listed[npcID] then
            local sig = signature(npcID)
            if sig == false then
                -- (no head model: left out)
            elseif sig == nil then
                if not canTell then shown[#shown + 1] = npcID end -- (no head data: left out)
            elseif seen[sig] ~= nil then
                -- (looks like one already shown: left out)
            else
                seen[sig] = npcID
                shown[#shown + 1] = npcID
            end
        end
    end
    return shown
end

return HeadFilter
