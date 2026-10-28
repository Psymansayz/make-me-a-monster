-- The NPCs the plugin lists: their entries and heads come from the saved list (src/data/heads.lua), and nothing is
-- read from the game.

local Npcs = {}

Npcs.groups = {}   -- one per entry of the dropdown, in its order: { name, ids = { id... }, members, search }
local groupOfID = {}   -- id -> group
local idName = {}      -- id -> name
Npcs.loaded = false

-- Letters beyond ASCII and the plain letter closest to each, for searching: a search for "e" finds "é",
-- and a search for "é" finds it too (and "e").
local FOLD = {}

-- A letter can have several plain ones (a search for any of them finds it): the first is the main one.
local function addFold(chars, ...)
    for char in chars:gmatch("[\194-\244][\128-\191]*") do FOLD[char] = { ... } end
end

addFold("àáâãäåāăąǎÀÁÂÃÄÅĀĂĄǍ", "a")
addFold("æÆ", "ae")
addFold("çćĉċčÇĆĈĊČ", "c")
addFold("ďđðĎĐÐ", "d")
addFold("èéêëēĕėęěÈÉÊËĒĔĖĘĚ", "e")
addFold("ĝğġģĜĞĠĢ", "g")
addFold("ĥħĤĦ", "h")
addFold("ìíîïĩīĭįıÌÍÎÏĨĪĬĮİ", "i")
addFold("ĵĴ", "j")
addFold("ķĶ", "k")
addFold("ĺļľŀłĹĻĽĿŁ", "l")
addFold("ñńņňŉÑŃŅŇ", "n")
addFold("òóôõöøōŏőÒÓÔÕÖØŌŎŐ", "o")
addFold("œŒ", "oe")
addFold("ŕŗřŔŖŘ", "r")
addFold("śŝşšŚŜŞŠ", "s")
addFold("ß", "ss", "s", "b") -- (the ß is also read as a b)
addFold("ţťŧŢŤŦ", "t")
addFold("þÞ", "th")
addFold("ùúûüũūŭůűųÙÚÛÜŨŪŬŮŰŲ", "u")
addFold("ŵŴ", "w")
addFold("ýÿŷÝŸŶ", "y")
addFold("źżžŹŻŽ", "z")

-- The text with each letter beyond ASCII (that has a plain one) replaced by its plain letter number `choice`
-- (the last one it has if it has fewer; the first if not given).
function Npcs.fold(text, choice)
    choice = choice or 1
    return (text:gsub("[\194-\244][\128-\191]*", function(char)
        local plain = FOLD[char]
        return plain and (plain[choice] or plain[#plain]) or nil
    end))
end

local MOST_CHOICES = 3

-- The different ways the text reads with its letters made plain (one if none has several).
function Npcs.foldAll(text)
    local all, seen = {}, {}
    for choice = 1, MOST_CHOICES do
        local folded = Npcs.fold(text, choice)
        if not seen[folded] then
            seen[folded] = true
            all[#all + 1] = folded
        end
    end
    return all
end

-- The text in lower case, as it is, followed by each way it reads made plain: what searches look in.
function Npcs.searchText(text)
    return Npcs.lower(text) .. " " .. Npcs.lower(table.concat(Npcs.foldAll(text), " "))
end

-- Lower case for the letters A to Z only.
-- Workaround: string.lower can change bytes of a UTF-8 letter beyond ASCII under some locales, so names and
-- queries are lowered by this.
function Npcs.lower(text)
    return (text:gsub("[A-Z]", function(char) return char:lower() end))
end

-- The entries and heads listed, as saved in src/data/heads.lua. NPCs added to the game later are not listed until
-- that file is made again.
-- data.groups = { { name, members = { { name, { id... } }... } }... }. Nothing is looked up in the game.
function Npcs.load(data)
    Npcs.groups, groupOfID, idName = {}, {}, {}
    for _, saved in ipairs(data.groups or {}) do
        local ids, members = {}, {}
        for _, member in ipairs(saved.members) do
            members[#members + 1] = { name = member[1], ids = member[2] }
            for _, npcID in ipairs(member[2]) do
                ids[#ids + 1] = npcID
                idName[npcID] = member[1]
            end
        end
        table.sort(ids)
        local group = { name = saved.name, ids = ids, members = members } -- (its search text is made when searched)
        Npcs.groups[#Npcs.groups + 1] = group
        for _, npcID in ipairs(ids) do groupOfID[npcID] = group end
    end
    Npcs.loaded = true
end

-- The text a search looks in for a group: its names (as they are and with plain letters) and ids.
local function searchOf(group)
    if group.search == nil then
        local parts = {}
        for _, member in ipairs(group.members) do
            parts[#parts + 1] = Npcs.searchText(member.name) .. " " .. table.concat(member.ids, " ")
        end
        group.search = table.concat(parts, " ")
    end
    return group.search
end

-- The name of the NPC with this id (as listed), or nil.
function Npcs.nameOf(npcID)
    return idName[npcID]
end

-- The group (the entry of the dropdown) that this id belongs to, or nil.
function Npcs.groupOf(npcID)
    return groupOfID[npcID]
end

-- The dropdown's label for a group: its name, and how many variants it has if more than one (`count`: the ones
-- listed; all of them if not given).
function Npcs.groupLabel(group, count)
    count = count or #group.ids
    return count > 1 and (group.name .. " (" .. count .. " variants)") or group.name
end

-- Up to `limit` groups whose name or ids contain every word of the query (all of them, in order, if the
-- query is blank); letters beyond ASCII match themselves and their plain letters, ignoring case.
function Npcs.search(query, limit)
    local words = {}
    for word in Npcs.lower(tostring(query or "")):gmatch("%S+") do words[#words + 1] = word end
    local found = {}
    for _, group in ipairs(Npcs.groups) do
        local matches = true
        for _, word in ipairs(words) do
            -- (the group's search text holds the name as it is and with its letters beyond ASCII made plain: a
            -- plain word finds either, one with such a letter only the name that has it)
            if not searchOf(group):find(word, 1, true) then matches = false break end
        end
        if matches then
            found[#found + 1] = group
            if #found >= limit then break end
        end
    end
    return found
end

return Npcs
