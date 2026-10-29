-- The NPCs the plugin lists: their entries and heads come from the saved list (src/data/listed_heads.lua), and nothing is
-- read from the game.

local NpcDirectory = {}

NpcDirectory.groups = {}   -- one per entry of the dropdown, in its order: { name, ids = { id... }, members, search }
local groupByNpcID = {}   -- id -> group
local nameByNpcID = {}      -- id -> name
NpcDirectory.isLoaded = false

-- Letters beyond ASCII and the plain letter closest to each, for searching: a search for "e" finds "é",
-- and a search for "é" finds it too (and "e").
local PLAIN_LETTERS = {}

-- A letter can have several plain ones (a search for any of them finds it): the first is the main one.
local function addPlainLetters(letters, ...)
    for character in letters:gmatch("[\194-\244][\128-\191]*") do PLAIN_LETTERS[character] = { ... } end
end

addPlainLetters("àáâãäåāăąǎÀÁÂÃÄÅĀĂĄǍ", "a")
addPlainLetters("æÆ", "ae")
addPlainLetters("çćĉċčÇĆĈĊČ", "c")
addPlainLetters("ďđðĎĐÐ", "d")
addPlainLetters("èéêëēĕėęěÈÉÊËĒĔĖĘĚ", "e")
addPlainLetters("ĝğġģĜĞĠĢ", "g")
addPlainLetters("ĥħĤĦ", "h")
addPlainLetters("ìíîïĩīĭįıÌÍÎÏĨĪĬĮİ", "i")
addPlainLetters("ĵĴ", "j")
addPlainLetters("ķĶ", "k")
addPlainLetters("ĺļľŀłĹĻĽĿŁ", "l")
addPlainLetters("ñńņňŉÑŃŅŇ", "n")
addPlainLetters("òóôõöøōŏőÒÓÔÕÖØŌŎŐ", "o")
addPlainLetters("œŒ", "oe")
addPlainLetters("ŕŗřŔŖŘ", "r")
addPlainLetters("śŝşšŚŜŞŠ", "s")
addPlainLetters("ß", "ss", "s", "b") -- (the ß is also read as a b)
addPlainLetters("ţťŧŢŤŦ", "t")
addPlainLetters("þÞ", "th")
addPlainLetters("ùúûüũūŭůűųÙÚÛÜŨŪŬŮŰŲ", "u")
addPlainLetters("ŵŴ", "w")
addPlainLetters("ýÿŷÝŸŶ", "y")
addPlainLetters("źżžŹŻŽ", "z")

-- The text with each letter beyond ASCII (that has a plain one) replaced by its plain letter number `choice`
-- (the last one it has if it has fewer; the first if not given).
function NpcDirectory.withPlainLetters(inputText, choice)
    choice = choice or 1
    return (inputText:gsub("[\194-\244][\128-\191]*", function(character)
        local plainLetters = PLAIN_LETTERS[character]
        return plainLetters and (plainLetters[choice] or plainLetters[#plainLetters]) or nil
    end))
end

local MOST_CHOICES = 3

-- The different ways the text reads with its letters made plain (one if none has several).
function NpcDirectory.allPlainReadings(inputText)
    local readings, alreadySeenReadings = {}, {}
    for choice = 1, MOST_CHOICES do
        local folded = NpcDirectory.withPlainLetters(inputText, choice)
        if not alreadySeenReadings[folded] then
            alreadySeenReadings[folded] = true
            readings[#readings + 1] = folded
        end
    end
    return readings
end

-- The text in lower case, as it is, followed by each way it reads made plain: what searches look in.
function NpcDirectory.searchableText(inputText)
    return NpcDirectory.lowerCaseAscii(inputText) .. " " .. NpcDirectory.lowerCaseAscii(table.concat(NpcDirectory.allPlainReadings(inputText), " "))
end

-- Lower case for the letters A to Z only.
-- Workaround: string.lower can change bytes of a UTF-8 letter beyond ASCII under some locales, so names and
-- queries are lowered by this.
function NpcDirectory.lowerCaseAscii(inputText)
    return (inputText:gsub("[A-Z]", function(character) return character:lower() end))
end

-- The entries and heads listed, as saved in src/data/listed_heads.lua. NPCs added to the game later are not listed until
-- that file is made again.
-- data.groups = { { name, members = { { name, { id... } }... } }... }. Nothing is looked up in the game.
function NpcDirectory.loadListedHeads(listedHeadsData)
    NpcDirectory.groups, groupByNpcID, nameByNpcID = {}, {}, {}
    for _, savedGroup in ipairs(listedHeadsData.groups or {}) do
        local npcIDs, members = {}, {}
        for _, member in ipairs(savedGroup.members) do
            members[#members + 1] = { name = member[1], ids = member[2] }
            for _, npcID in ipairs(member[2]) do
                npcIDs[#npcIDs + 1] = npcID
                nameByNpcID[npcID] = member[1]
            end
        end
        table.sort(npcIDs)
        local npcGroup = { name = savedGroup.name, ids = npcIDs, members = members } -- (its search text is made when searched)
        NpcDirectory.groups[#NpcDirectory.groups + 1] = npcGroup
        for _, npcID in ipairs(npcIDs) do groupByNpcID[npcID] = npcGroup end
    end
    NpcDirectory.isLoaded = true
end

-- The text a search looks in for a group: its names (as they are and with plain letters) and ids.
local function searchOf(npcGroup)
    if npcGroup.search == nil then
        local searchParts = {}
        for _, member in ipairs(npcGroup.members) do
            searchParts[#searchParts + 1] = NpcDirectory.searchableText(member.name) .. " " .. table.concat(member.ids, " ")
        end
        npcGroup.search = table.concat(searchParts, " ")
    end
    return npcGroup.search
end

-- The name of the NPC with this id (as listed), or nil.
function NpcDirectory.nameOfNpc(npcID)
    return nameByNpcID[npcID]
end

-- The group (the entry of the dropdown) that this id belongs to, or nil.
function NpcDirectory.groupOfNpc(npcID)
    return groupByNpcID[npcID]
end

-- The dropdown's label for a group: its name, and how many variants it has if more than one (`count`: the ones
-- listed; all of them if not given).
function NpcDirectory.labelOfGroup(npcGroup, variantCount)
    variantCount = variantCount or #npcGroup.ids
    return variantCount > 1 and (npcGroup.name .. " (" .. variantCount .. " variants)") or npcGroup.name
end

-- Up to `limit` groups whose name or ids contain every word of the query (all of them, in order, if the
-- query is blank); letters beyond ASCII match themselves and their plain letters, ignoring case.
function NpcDirectory.searchGroups(query, maxResults)
    local queryWords = {}
    for queryWord in NpcDirectory.lowerCaseAscii(tostring(query or "")):gmatch("%S+") do queryWords[#queryWords + 1] = queryWord end
    local matchingGroups = {}
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        local matchesEveryWord = true
        for _, queryWord in ipairs(queryWords) do
            -- (the group's search text holds the name as it is and with its letters beyond ASCII made plain: a
            -- plain word finds either, one with such a letter only the name that has it)
            if not searchOf(npcGroup):find(queryWord, 1, true) then matchesEveryWord = false break end
        end
        if matchesEveryWord then
            matchingGroups[#matchingGroups + 1] = npcGroup
            if #matchingGroups >= maxResults then break end
        end
    end
    return matchingGroups
end

return NpcDirectory
