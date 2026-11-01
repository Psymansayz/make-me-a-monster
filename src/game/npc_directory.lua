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

-- The game does not use all of these letters at the moment, but they are included for completeness and future use.
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

-- The text a search looks in for one name of a group: the name (as it is and with plain letters) and its ids.
local function searchOfMember(member)
    if member.search == nil then
        member.search = NpcDirectory.searchableText(member.name) .. " " .. table.concat(member.ids, " ")
    end
    return member.search
end

-- The text a search looks in for a group: all its names and ids.
local function searchOf(npcGroup)
    if npcGroup.search == nil then
        local searchParts = {}
        for _, member in ipairs(npcGroup.members) do searchParts[#searchParts + 1] = searchOfMember(member) end
        npcGroup.search = table.concat(searchParts, " ")
    end
    return npcGroup.search
end

-- The lower case words of a query.
local function wordsOfQuery(query)
    local queryWords = {}
    for queryWord in NpcDirectory.lowerCaseAscii(tostring(query or "")):gmatch("%S+") do queryWords[#queryWords + 1] = queryWord end
    return queryWords
end

local function containsEveryWord(text, queryWords)
    for _, queryWord in ipairs(queryWords) do
        if not text:find(queryWord, 1, true) then return false end
    end
    return true
end

-- The name of the group (a member) that matched the query, for the dropdown to show: of the names whose own text and ids hold
-- every word of the query, the shortest (the most general: "Goblin" before "Goblin guard"), the first if equal. Also how
-- many NPCs the matching names have in all. Nil if the query is blank, is exactly the name of the group, or its words
-- are spread over different names.
function NpcDirectory.memberMatching(npcGroup, query)
    local queryWords = wordsOfQuery(query)
    if #queryWords == 0 then return nil end
    -- A query that is exactly the name of the group needs no other name shown: the group's own label says it.
    if table.concat(queryWords, " ") == NpcDirectory.lowerCaseAscii(npcGroup.name) then return nil end
    local best, matchingNpcCount = nil, 0
    for _, member in ipairs(npcGroup.members) do
        if containsEveryWord(searchOfMember(member), queryWords) then
            matchingNpcCount = matchingNpcCount + #member.ids
            if best == nil or #member.name < #best.name then best = member end
        end
    end
    return best, matchingNpcCount
end

-- The name of the NPC with this id (as listed), or nil.
function NpcDirectory.nameOfNpc(npcID)
    return nameByNpcID[npcID]
end

-- The group (the entry of the dropdown) that this id belongs to, or nil.
function NpcDirectory.groupOfNpc(npcID)
    return groupByNpcID[npcID]
end

-- The name of the group (a member) that this NPC has, or nil. (A group holds several names; the NPC chosen can be of any.)
function NpcDirectory.memberOfNpc(npcID)
    local npcGroup = NpcDirectory.groupOfNpc(npcID)
    if npcGroup == nil then return nil end
    for _, member in ipairs(npcGroup.members) do
        for _, memberNpcID in ipairs(member.ids) do
            if memberNpcID == npcID then return member end
        end
    end
    return nil
end

-- The dropdown's label for a group: its name, and how many variants it has if more than one (`count`: the ones
-- listed; all of them if not given).
function NpcDirectory.labelOfGroup(npcGroup, variantCount)
    variantCount = variantCount or #npcGroup.ids
    return variantCount > 1 and (npcGroup.name .. " (" .. variantCount .. " variants)") or npcGroup.name
end

-- The same for one name of a group (a member): its name, and how many NPCs there are if more than one (`variantCount`: the
-- NPCs that matched a search; all the NPCs with this name if not given).
function NpcDirectory.labelOfMember(member, variantCount)
    variantCount = variantCount or #member.ids
    return variantCount > 1 and (member.name .. " (" .. variantCount .. " variants)") or member.name
end

-- Up to `limit` groups whose name or ids contain every word of the query (all of them, in order, if the
-- query is blank); letters beyond ASCII match themselves and their plain letters, ignoring case.
function NpcDirectory.searchGroups(query, maxResults)
    local queryWords = wordsOfQuery(query)
    local matchingGroups = {}
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        -- (the group's search text holds the name as it is and with its letters beyond ASCII made plain: a plain word
        -- finds either, one with such a letter only the name that has it)
        if containsEveryWord(searchOf(npcGroup), queryWords) then
            matchingGroups[#matchingGroups + 1] = npcGroup
            if #matchingGroups >= maxResults then break end
        end
    end
    return matchingGroups
end

-- The heads the plugin lists, one per id, in name order. Made once: the list does not change while the plugin runs.
local headsInNameOrder = nil

function NpcDirectory.headsInNameOrder()
    if headsInNameOrder ~= nil then return headsInNameOrder end
    local heads, lowered = {}, {}
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        for _, npcID in ipairs(npcGroup.ids) do
            heads[#heads + 1] = npcID
            lowered[npcID] = NpcDirectory.lowerCaseAscii(NpcDirectory.nameOfNpc(npcID) or "")
        end
    end
    table.sort(heads, function(a, b)
        if lowered[a] ~= lowered[b] then return lowered[a] < lowered[b] end
        return a < b
    end)
    headsInNameOrder = heads
    return heads
end

return NpcDirectory
