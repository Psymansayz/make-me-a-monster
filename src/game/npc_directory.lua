-- The NPCs the plugin lists: their entries and heads come from the saved list (src/data/listed_heads.lua); only their
-- ids in this game build are looked up (id.NPC).

local GameIds = require("src/game/game_ids")

local NpcDirectory = {}

NpcDirectory.groups = {}   -- one per entry of the dropdown, in its order: { name, ids = { id... }, members, search }
local groupByNpcID = {}   -- id -> group (the smallest it is in: a head can be in several)
local shownGroupByNpcID = {} -- id -> the group it is the head shown for
local groupsByNpcID = {} -- id -> every group it is in, the smallest first
local nameByNpcID = {}      -- id -> name
NpcDirectory.isLoaded = false

-- Letters beyond ASCII and the plain letters closest to each: a search for "e" finds "é".
local PLAIN_LETTERS = {}

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

-- The text with each letter beyond ASCII replaced by its plain letter number `choice` (the last if it has fewer).
function NpcDirectory.withPlainLetters(inputText, choice)
    choice = choice or 1
    return (inputText:gsub("[\194-\244][\128-\191]*", function(character)
        local plainLetters = PLAIN_LETTERS[character]
        return plainLetters and (plainLetters[choice] or plainLetters[#plainLetters]) or nil
    end))
end

local MOST_CHOICES = 3

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

-- string.lower can change bytes of a UTF-8 letter beyond ASCII under some locales: so the letters A to Z only.
function NpcDirectory.lowerCaseAscii(inputText)
    return (inputText:gsub("[A-Z]", function(character) return character:lower() end))
end

-- Selects a head to represent each group
local function placeGroup(npcGroup, triedIDs)
    for _, npcID in ipairs(npcGroup.ids) do
        if shownGroupByNpcID[npcID] == nil then
            shownGroupByNpcID[npcID], npcGroup.shownID = npcGroup, npcID
            return true
        end
    end
    for _, npcID in ipairs(npcGroup.ids) do
        if not triedIDs[npcID] then
            triedIDs[npcID] = true
            if placeGroup(shownGroupByNpcID[npcID], triedIDs) then
                shownGroupByNpcID[npcID], npcGroup.shownID = npcGroup, npcID
                return true
            end
        end
    end
    return false
end

-- Loads the saved list (src/data/listed_heads.lua). NPCs added to the game later are not listed until it is made again.
function NpcDirectory.loadListedHeads(listedHeadsData)
    NpcDirectory.groups, groupByNpcID, shownGroupByNpcID, groupsByNpcID, nameByNpcID = {}, {}, {}, {}, {}
    local groupsToChoose = {}
    for _, savedGroup in ipairs(listedHeadsData.groups or {}) do
        local npcIDs, members, firstIsKnown = {}, {}, false
        for _, member in ipairs(savedGroup.members) do
            local memberIDs = {}
            for _, npcName in ipairs(member[2]) do
                local npcID = GameIds.resolve("NPC", npcName)
                if npcID ~= nil then
                    memberIDs[#memberIDs + 1], npcIDs[#npcIDs + 1] = npcID, npcID
                    nameByNpcID[npcID] = member[1]
                    firstIsKnown = firstIsKnown or npcName == savedGroup.members[1][2][1]
                end
            end
            if #memberIDs > 0 then members[#members + 1] = { name = member[1], ids = memberIDs } end
        end
        if #npcIDs > 0 then
            local npcGroup = { name = savedGroup.name, ids = npcIDs, members = members }
            NpcDirectory.groups[#NpcDirectory.groups + 1] = npcGroup
            if firstIsKnown and shownGroupByNpcID[npcIDs[1]] == nil then
                shownGroupByNpcID[npcIDs[1]], npcGroup.shownID = npcGroup, npcIDs[1]
            else
                groupsToChoose[#groupsToChoose + 1] = npcGroup
            end
            for _, npcID in ipairs(npcIDs) do
                local otherGroup = groupByNpcID[npcID]
                if otherGroup == nil or #npcIDs < #otherGroup.ids then groupByNpcID[npcID] = npcGroup end
                groupsByNpcID[npcID] = groupsByNpcID[npcID] or {}
                table.insert(groupsByNpcID[npcID], npcGroup)
            end
        end
    end
    table.sort(groupsToChoose, function(a, b) return #a.ids < #b.ids end)
    for _, npcGroup in ipairs(groupsToChoose) do placeGroup(npcGroup, {}) end
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        local shownID = npcGroup.shownID or npcGroup.ids[1]
        table.sort(npcGroup.ids, function(a, b)
            if (a == shownID) ~= (b == shownID) then return a == shownID end
            return a < b
        end)
    end
    for _, groups in pairs(groupsByNpcID) do
        table.sort(groups, function(a, b)
            if #a.ids ~= #b.ids then return #a.ids < #b.ids end
            return a.ids[1] < b.ids[1]
        end)
    end
    NpcDirectory.isLoaded = true
end

local function searchOfMember(member)
    if member.search == nil then
        member.search = NpcDirectory.searchableText(member.name) .. " " .. table.concat(member.ids, " ")
    end
    return member.search
end

-- A group's own name is searched too: no individual member may contain it.
local function searchOf(npcGroup)
    if npcGroup.search == nil then
        local searchParts = { NpcDirectory.searchableText(npcGroup.name) }
        for _, member in ipairs(npcGroup.members) do searchParts[#searchParts + 1] = searchOfMember(member) end
        npcGroup.search = table.concat(searchParts, " ")
    end
    return npcGroup.search
end

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

-- The members holding every word, the shortest names first: "Goblin" before "Goblin guard".
local function membersHolding(npcGroup, queryWords)
    local members = {}
    for _, member in ipairs(npcGroup.members) do
        if containsEveryWord(searchOfMember(member), queryWords) then members[#members + 1] = member end
    end
    table.sort(members, function(a, b) return #a.name < #b.name end)
    return members
end

local function headHolds(member, npcID, queryWords)
    return containsEveryWord(NpcDirectory.searchableText(member.name) .. " " .. npcID, queryWords)
end

-- A head of these members that nothing shows yet, one that holds the words if there is one; or nil.
local function freeHeadOf(members, queryWords, isTaken)
    for _, member in ipairs(members) do
        for _, npcID in ipairs(member.ids) do
            if not isTaken[npcID] and headHolds(member, npcID, queryWords) then return npcID, member.name end
        end
    end
    for _, member in ipairs(members) do
        for _, npcID in ipairs(member.ids) do
            if not isTaken[npcID] then return npcID, member.name end
        end
    end
    return nil
end

-- The heads to show for a search, one per matching group, and { id -> name }. A group whose name or shown head matches
-- keeps that head. Any other shows the variant that matched, avoiding showing duplicates if possible.
function NpcDirectory.headsMatching(shownHeads, queryWords)
    local heads, nameOfHead, groupsToChoose = {}, {}, {}
    for _, shownID in ipairs(shownHeads) do
        local npcGroup = NpcDirectory.groupOfNpc(shownID)
        local member = NpcDirectory.memberOfNpc(shownID, npcGroup)
        if containsEveryWord(NpcDirectory.lowerCaseAscii(npcGroup.name), queryWords) then
            heads[#heads + 1], nameOfHead[shownID] = shownID, npcGroup.name
        elseif headHolds(member, shownID, queryWords) then
            heads[#heads + 1], nameOfHead[shownID] = shownID, member.name
        else
            local members = membersHolding(npcGroup, queryWords)
            if #members > 0 then groupsToChoose[#groupsToChoose + 1] = members end
        end
    end
    for _, members in ipairs(groupsToChoose) do
        local npcID, name = freeHeadOf(members, queryWords, nameOfHead)
        if npcID ~= nil then heads[#heads + 1], nameOfHead[npcID] = npcID, name end
    end
    table.sort(heads, function(a, b)
        local nameA, nameB = NpcDirectory.lowerCaseAscii(nameOfHead[a]), NpcDirectory.lowerCaseAscii(nameOfHead[b])
        if nameA ~= nameB then return nameA < nameB end
        return a < b
    end)
    return heads, nameOfHead
end

-- The shortest member holding every word of the query, for the dropdown to show, and how many NPCs match in all.
function NpcDirectory.memberMatching(npcGroup, query)
    local queryWords = wordsOfQuery(query)
    if #queryWords == 0 then return nil end
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

function NpcDirectory.nameOfNpc(npcID)
    return nameByNpcID[npcID]
end

-- A head standing for its group goes by the group's name: a race or job group's head has its own (Andil, in Goblin).
function NpcDirectory.nameForGroupOfNpc(npcID)
    local npcGroup = shownGroupByNpcID[npcID]
    return npcGroup and npcGroup.name or nameByNpcID[npcID]
end

-- A head in several groups belongs to the one it is the head shown for, else the smallest.
function NpcDirectory.groupOfNpc(npcID)
    return shownGroupByNpcID[npcID] or groupByNpcID[npcID]
end

-- Every group this id is in, the smallest first.
function NpcDirectory.groupsOfNpc(npcID)
    return groupsByNpcID[npcID] or { groupByNpcID[npcID] }
end

-- Two groups can have one name: the one it is the head shown for wins, else the smallest.
function NpcDirectory.groupLabelled(npcID, label)
    local shownGroup = shownGroupByNpcID[npcID]
    if shownGroup and shownGroup.name == label then return shownGroup end
    for _, npcGroup in ipairs(NpcDirectory.groupsOfNpc(npcID)) do
        if npcGroup.name == label then return npcGroup end
    end
    return nil
end

-- The next group this id is in, or nil if it is in no other.
function NpcDirectory.nextGroupOfNpc(npcID, npcGroup)
    local groups = NpcDirectory.groupsOfNpc(npcID)
    if #groups < 2 then return nil end
    for position, group in ipairs(groups) do
        if group == npcGroup then return groups[position % #groups + 1] end
    end
    return groups[1]
end

-- The member (one name of a group) this NPC is in, or nil.
function NpcDirectory.memberOfNpc(npcID, npcGroup)
    npcGroup = npcGroup or NpcDirectory.groupOfNpc(npcID)
    if npcGroup == nil then return nil end
    for _, member in ipairs(npcGroup.members) do
        for _, memberNpcID in ipairs(member.ids) do
            if memberNpcID == npcID then return member end
        end
    end
    return nil
end

-- The dropdown's label for a group: its name, and how many variants it has if more than one.
function NpcDirectory.labelOfGroup(npcGroup, variantCount)
    variantCount = variantCount or #npcGroup.ids
    return variantCount > 1 and (npcGroup.name .. " (" .. variantCount .. " variants)") or npcGroup.name
end

-- The same for one name of a group (a member).
function NpcDirectory.labelOfMember(member, variantCount)
    variantCount = variantCount or #member.ids
    return variantCount > 1 and (member.name .. " (" .. variantCount .. " variants)") or member.name
end

-- Up to `maxResults` groups whose name or ids contain every word of the query.
function NpcDirectory.searchGroups(query, maxResults)
    local queryWords = wordsOfQuery(query)
    local matchingGroups = {}
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        if containsEveryWord(searchOf(npcGroup), queryWords) then
            matchingGroups[#matchingGroups + 1] = npcGroup
            if #matchingGroups >= maxResults then break end
        end
    end
    return matchingGroups
end

-- The heads the plugin lists, one per id, in name order. Made once: the list does not change while the plugin runs.
local headsInNameOrder, headsOfEachGroup = nil, nil

local function headsByName(headsOfGroup, nameOf)
    local heads, lowered = {}, {}
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        for _, npcID in ipairs(headsOfGroup(npcGroup)) do
            if lowered[npcID] == nil then
                heads[#heads + 1] = npcID
                lowered[npcID] = NpcDirectory.lowerCaseAscii(nameOf(npcID) or "")
            end
        end
    end
    table.sort(heads, function(a, b)
        if lowered[a] ~= lowered[b] then return lowered[a] < lowered[b] end
        return a < b
    end)
    return heads
end

function NpcDirectory.headsInNameOrder()
    if headsInNameOrder == nil then
        headsInNameOrder = headsByName(function(npcGroup) return npcGroup.ids end, NpcDirectory.nameOfNpc)
    end
    return headsInNameOrder
end

-- The head shown for each group, in order of the groups' names.
function NpcDirectory.headsOfEachGroup()
    if headsOfEachGroup == nil then
        headsOfEachGroup = headsByName(function(npcGroup) return { npcGroup.ids[1] } end,
            NpcDirectory.nameForGroupOfNpc)
    end
    return headsOfEachGroup
end

return NpcDirectory
