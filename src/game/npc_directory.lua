-- The NPCs the plugin lists: their entries and heads come from the saved list (src/data/listed_heads.lua); only their
-- ids in this game build are looked up (id.NPC).

local GameIds = require("src/game/game_ids")

local NpcDirectory = {}

-- One per entry of the dropdown, in its order: { name, ids = { id... }, members = { { name, ids }... } }. Groups and
-- members also keep what a search looks in, made when first searched.
NpcDirectory.groups = {}
local groupByNpcID = {}      -- id -> group (the smallest it is in: a head can be in several)
local shownGroupByNpcID = {} -- id -> the group it is the head shown for
local groupsByNpcID = {}     -- id -> every group it is in, the smallest first, for a head in several only
local memberByNpcID = {}     -- id -> the member it is in (by its name: a head in several groups has one name)
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
local function withPlainLetters(inputText, choice)
    return (inputText:gsub("[\194-\244][\128-\191]*", function(character)
        local plainLetters = PLAIN_LETTERS[character]
        return plainLetters and (plainLetters[choice] or plainLetters[#plainLetters]) or nil
    end))
end

local MOST_CHOICES = 3

local function allPlainReadings(inputText)
    local readings, alreadySeenReadings = {}, {}
    for choice = 1, MOST_CHOICES do
        local folded = withPlainLetters(inputText, choice)
        if not alreadySeenReadings[folded] then
            alreadySeenReadings[folded] = true
            readings[#readings + 1] = folded
        end
    end
    return readings
end

-- string.lower can change bytes of a UTF-8 letter beyond ASCII under some locales: so the letters A to Z only.
function NpcDirectory.lowerCaseAscii(inputText)
    return (inputText:gsub("[A-Z]", function(character) return character:lower() end))
end

-- What searches look in: the text in lower case, followed by each way it reads made plain if it has letters beyond
-- ASCII.
local function searchableText(inputText)
    local lowered = NpcDirectory.lowerCaseAscii(inputText)
    if not inputText:find("[\128-\255]") then return lowered end
    return lowered .. " " .. NpcDirectory.lowerCaseAscii(table.concat(allPlainReadings(inputText), " "))
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
    local groupsToChoose = {}
    for _, savedGroup in ipairs(listedHeadsData.groups) do
        local npcIDs, members, firstIsKnown = {}, {}, false
        for memberIndex, savedMember in ipairs(savedGroup.members) do
            local member = { name = savedMember[1], ids = {} }
            for nameIndex, npcName in ipairs(savedMember[2]) do
                local npcID = GameIds.resolve("NPC", npcName)
                if npcID ~= nil then
                    member.ids[#member.ids + 1], npcIDs[#npcIDs + 1] = npcID, npcID
                    memberByNpcID[npcID] = member
                    if memberIndex == 1 and nameIndex == 1 then firstIsKnown = true end
                end
            end
            if #member.ids > 0 then members[#members + 1] = member end
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
                local firstGroup = groupByNpcID[npcID]
                if firstGroup == nil then
                    groupByNpcID[npcID] = npcGroup
                else
                    groupsByNpcID[npcID] = groupsByNpcID[npcID] or { firstGroup }
                    table.insert(groupsByNpcID[npcID], npcGroup)
                end
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
    for npcID, groups in pairs(groupsByNpcID) do
        table.sort(groups, function(a, b)
            if #a.ids ~= #b.ids then return #a.ids < #b.ids end
            return a.ids[1] < b.ids[1]
        end)
        groupByNpcID[npcID] = groups[1]
    end
    NpcDirectory.isLoaded = true
end

-- A query's words never hold a space: so a word is found in one of a name's texts or another, never across them.

local function searchNameOf(named) -- a group or a member
    if named.searchName == nil then named.searchName = searchableText(named.name) end
    return named.searchName
end

local function nameHolds(named, queryWords)
    for _, queryWord in ipairs(queryWords) do
        if not searchNameOf(named):find(queryWord, 1, true) then return false end
    end
    return true
end

local function idsTextOf(member)
    if member.idsText == nil then member.idsText = table.concat(member.ids, " ") end
    return member.idsText
end

local function memberHoldsWord(member, queryWord)
    return searchNameOf(member):find(queryWord, 1, true) ~= nil or idsTextOf(member):find(queryWord, 1, true) ~= nil
end

local function memberHolds(member, queryWords)
    for _, queryWord in ipairs(queryWords) do
        if not memberHoldsWord(member, queryWord) then return false end
    end
    return true
end

-- A group's own name is searched too: no member may have it.
local function groupHoldsWord(npcGroup, queryWord)
    if searchNameOf(npcGroup):find(queryWord, 1, true) then return true end
    for _, member in ipairs(npcGroup.members) do
        if memberHoldsWord(member, queryWord) then return true end
    end
    return false
end

local function groupHolds(npcGroup, queryWords)
    for _, queryWord in ipairs(queryWords) do
        if not groupHoldsWord(npcGroup, queryWord) then return false end
    end
    return true
end

-- One head of a member: by the member's name or that head's own id.
local function headHolds(member, npcID, queryWords)
    local idText = tostring(npcID)
    for _, queryWord in ipairs(queryWords) do
        if not searchNameOf(member):find(queryWord, 1, true) and not idText:find(queryWord, 1, true) then
            return false
        end
    end
    return true
end

function NpcDirectory.wordsOfQuery(query)
    local queryWords = {}
    for queryWord in NpcDirectory.lowerCaseAscii(query):gmatch("%S+") do queryWords[#queryWords + 1] = queryWord end
    return queryWords
end

-- The members holding every word, the shortest names first: "Goblin" before "Goblin guard".
local function membersHolding(npcGroup, queryWords)
    local members = {}
    for _, member in ipairs(npcGroup.members) do
        if memberHolds(member, queryWords) then members[#members + 1] = member end
    end
    table.sort(members, function(a, b) return #a.name < #b.name end)
    return members
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
        if nameHolds(npcGroup, queryWords) then
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
    local sortName = {}
    for _, npcID in ipairs(heads) do sortName[npcID] = NpcDirectory.lowerCaseAscii(nameOfHead[npcID]) end
    table.sort(heads, function(a, b)
        if sortName[a] ~= sortName[b] then return sortName[a] < sortName[b] end
        return a < b
    end)
    return heads, nameOfHead
end

-- The heads, each with its own name and id, holding every word.
function NpcDirectory.headsHolding(heads, queryWords)
    local matching = {}
    for _, npcID in ipairs(heads) do
        if headHolds(memberByNpcID[npcID], npcID, queryWords) then matching[#matching + 1] = npcID end
    end
    return matching
end

-- The shortest member holding every word of the query, for the dropdown to show, and how many NPCs match in all.
function NpcDirectory.memberMatching(npcGroup, query)
    local queryWords = NpcDirectory.wordsOfQuery(query)
    if #queryWords == 0 then return nil end
    if table.concat(queryWords, " ") == NpcDirectory.lowerCaseAscii(npcGroup.name) then return nil end
    local best, matchingNpcCount = nil, 0
    for _, member in ipairs(npcGroup.members) do
        if memberHolds(member, queryWords) then
            matchingNpcCount = matchingNpcCount + #member.ids
            if best == nil or #member.name < #best.name then best = member end
        end
    end
    return best, matchingNpcCount
end

function NpcDirectory.nameOfNpc(npcID)
    local member = memberByNpcID[npcID]
    return member and member.name
end

-- A head standing for its group goes by the group's name: a race or job group's head has its own (Andil, in Goblin).
function NpcDirectory.nameForGroupOfNpc(npcID)
    local npcGroup = shownGroupByNpcID[npcID]
    return npcGroup and npcGroup.name or NpcDirectory.nameOfNpc(npcID)
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

-- The dropdown's label for a group or a member: its name, and how many variants it has if more than one.
function NpcDirectory.labelOf(name, variantCount)
    return variantCount > 1 and (name .. " (" .. variantCount .. " variants)") or name
end

-- Up to `maxResults` groups whose name or ids contain every word of the query.
function NpcDirectory.searchGroups(query, maxResults)
    local queryWords = NpcDirectory.wordsOfQuery(query)
    local matchingGroups = {}
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        if #queryWords == 0 or groupHolds(npcGroup, queryWords) then
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
