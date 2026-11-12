-- The NPCs the plugin lists, from the saved list in src/data/listed_heads.lua. Only their ids are looked up in the
-- current game build (in id.NPC).

local GameIds = require("src/game/game_ids")

local NpcDirectory = {}

-- One group per dropdown entry, in dropdown order: { name, members, idCount, shownID }, where shownID is the head shown
-- for the group. A member is one name in the group with its ids: { name, id, id... }. nameHasDigit marks a name that
-- contains a digit, since only those names are searched for a word made of digits.
NpcDirectory.groups = {}
local groupByNpcID = {}      -- id -> the smallest group it is in
local shownGroupByNpcID = {} -- id -> the group it is shown for
local groupsByNpcID = {}     -- id -> every group it is in, smallest first (only for heads in several groups)
local memberByNpcID = {}     -- id -> its member (a head in several groups still has one name)
NpcDirectory.isLoaded = false

-- Non-ASCII letters and the plain letters closest to each, so that a search for "e" finds "é".
local PLAIN_LETTERS = {}

local function addPlainLetters(letters, ...)
    for character in letters:gmatch("[\194-\244][\128-\191]*") do PLAIN_LETTERS[character] = { ... } end
end

-- Not all of these are in the game's names yet, but they are included for completeness.
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
addPlainLetters("ß", "ss", "s", "b") -- ß is also read as a b
addPlainLetters("ţťŧŢŤŦ", "t")
addPlainLetters("þÞ", "th")
addPlainLetters("ùúûüũūŭůűųÙÚÛÜŨŪŬŮŰŲ", "u")
addPlainLetters("ŵŴ", "w")
addPlainLetters("ýÿŷÝŸŶ", "y")
addPlainLetters("źżžŹŻŽ", "z")

-- The text with each non-ASCII letter replaced by its plain letter number `choice`, or by its last one if it has fewer.
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

-- Under some locales string.lower can change bytes inside a non-ASCII UTF-8 letter, so only A to Z are lowered.
function NpcDirectory.lowerCaseAscii(inputText)
    return (inputText:gsub("[A-Z]", function(character) return character:lower() end))
end

-- Cleans a text the way the list's names were cleaned: "50% Luke" becomes "50 Luke" and "Tz-Kih" becomes "Tz Kih".
-- Both names and queries are cleaned, because a few listed names still contain a symbol, such as "Dagon'hai".
local function cleaned(text)
    text = text:gsub("<[^>]*>", ""):gsub("\194\160", " "):gsub("[_%-]", " ")
    return (text:gsub("[^%w%s\128-\255]", ""))
end

local function cleanedWords(text)
    local words = {}
    for word in NpcDirectory.lowerCaseAscii(cleaned(text)):gmatch("%S+") do words[#words + 1] = word end
    return words
end

-- The text searches look in: the cleaned, lower-case name, followed by its plain readings if it has non-ASCII letters.
local function searchableText(name)
    local plain = cleaned(name)
    local lowered = NpcDirectory.lowerCaseAscii(plain)
    if not plain:find("[\128-\255]") then return lowered end
    return lowered .. " " .. NpcDirectory.lowerCaseAscii(table.concat(allPlainReadings(plain), " "))
end

-- Gives a group a head no other group shows, moving another group to one of its other heads if needed.
local function placeGroup(npcGroup, triedIDs)
    for _, member in ipairs(npcGroup.members) do
        for _, npcID in ipairs(member) do
            if shownGroupByNpcID[npcID] == nil then
                shownGroupByNpcID[npcID], npcGroup.shownID = npcGroup, npcID
                return true
            end
        end
    end
    for _, member in ipairs(npcGroup.members) do
        for _, npcID in ipairs(member) do
            if not triedIDs[npcID] then
                triedIDs[npcID] = true
                if placeGroup(shownGroupByNpcID[npcID], triedIDs) then
                    shownGroupByNpcID[npcID], npcGroup.shownID = npcGroup, npcID
                    return true
                end
            end
        end
    end
    return false
end

-- Loads the saved list (src/data/listed_heads.lua). NPCs added to the game later aren't listed until it is remade.
function NpcDirectory.loadListedHeads(listedHeadsData)
    local groupsToChoose = {}
    for _, savedGroup in ipairs(listedHeadsData.groups) do
        local npcIDs, members, firstIsKnown = {}, {}, false
        for memberIndex, savedMember in ipairs(savedGroup.members) do
            local member = { name = savedMember[1], nameHasDigit = savedMember[1]:find("%d") ~= nil or nil }
            for nameIndex, npcName in ipairs(savedMember[2]) do
                local npcID = GameIds.resolve("NPC", npcName)
                if npcID ~= nil then
                    member[#member + 1], npcIDs[#npcIDs + 1] = npcID, npcID
                    memberByNpcID[npcID] = member
                    if memberIndex == 1 and nameIndex == 1 then firstIsKnown = true end
                end
            end
            if #member > 0 then members[#members + 1] = member end
        end
        if #npcIDs > 0 then
            local npcGroup = { name = savedGroup.name, members = members, idCount = #npcIDs,
                nameHasDigit = savedGroup.name:find("%d") ~= nil or nil }
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
    table.sort(groupsToChoose, function(a, b) return a.idCount < b.idCount end)
    for _, npcGroup in ipairs(groupsToChoose) do placeGroup(npcGroup, {}) end
    -- A group with no free head left shows its smallest id, but isn't entered in shownGroupByNpcID.
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        if npcGroup.shownID == nil then
            for _, member in ipairs(npcGroup.members) do
                for _, npcID in ipairs(member) do
                    if npcGroup.shownID == nil or npcID < npcGroup.shownID then npcGroup.shownID = npcID end
                end
            end
        end
    end
    for npcID, groups in pairs(groupsByNpcID) do
        table.sort(groups, function(a, b)
            if a.idCount ~= b.idCount then return a.idCount < b.idCount end
            return a.shownID < b.shownID
        end)
        groupByNpcID[npcID] = groups[1]
    end
    NpcDirectory.isLoaded = true
end

-- A search word of only digits is matched against the ids and the few names that contain a digit ("man 3", "50% luke").
local function isIdWord(queryWord)
    return queryWord:find("^%d+$") ~= nil
end

local function idHoldsWord(npcID, queryWord)
    return tostring(npcID):find(queryWord, 1, true) ~= nil
end

-- Caches for searches and the heads window, built when first needed and dropped after five minutes without use.
local searchTexts = {} -- group or member -> its text
local headsInNameOrder, headsOfEachGroup = nil, nil
local CACHE_TICKS = 500 -- five minutes of 0.6 s ticks
local CACHE_SUBSCRIPTION = "make_me_a_monster_directory_caches"
local ticksToKeepCaches = 0
local countingDown = false

local function countDownCaches()
    ticksToKeepCaches = ticksToKeepCaches - 1
    if ticksToKeepCaches <= 0 then NpcDirectory.forgetCaches() end
end

function NpcDirectory.forgetCaches()
    if countingDown then Event.ServerLogic.Unsubscribe(CACHE_SUBSCRIPTION) end
    searchTexts, headsInNameOrder, headsOfEachGroup = {}, nil, nil
    ticksToKeepCaches, countingDown = 0, false
end

-- Each use keeps them for another five minutes.
local function keepCaches()
    if not countingDown then Event.ServerLogic.Subscribe(CACHE_SUBSCRIPTION, countDownCaches) end
    ticksToKeepCaches, countingDown = CACHE_TICKS, true
end

local function searchTextOf(named) -- a group or a member
    local text = searchTexts[named]
    if text == nil then
        text = searchableText(named.name)
        searchTexts[named] = text
    end
    return text
end

-- A query word never contains a space, so it is found within one name, never across two.
local function nameHoldsWord(named, queryWord)
    if not named.nameHasDigit and isIdWord(queryWord) then return false end
    return searchTextOf(named):find(queryWord, 1, true) ~= nil
end

local function nameHolds(named, queryWords)
    for _, queryWord in ipairs(queryWords) do
        if not nameHoldsWord(named, queryWord) then return false end
    end
    return true
end

local function memberHoldsWord(member, queryWord)
    if nameHoldsWord(member, queryWord) then return true end
    if not isIdWord(queryWord) then return false end
    for _, npcID in ipairs(member) do
        if idHoldsWord(npcID, queryWord) then return true end
    end
    return false
end

local function memberHolds(member, queryWords)
    for _, queryWord in ipairs(queryWords) do
        if not memberHoldsWord(member, queryWord) then return false end
    end
    return true
end

-- The group's own name is searched too, since no member may have it.
local function groupHoldsWord(npcGroup, queryWord)
    if nameHoldsWord(npcGroup, queryWord) then return true end
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

-- Whether one head of a member matches every word, by the member's name or by that head's own id.
local function headHolds(member, npcID, queryWords)
    for _, queryWord in ipairs(queryWords) do
        if not nameHoldsWord(member, queryWord) and not (isIdWord(queryWord) and idHoldsWord(npcID, queryWord)) then
            return false
        end
    end
    return true
end

-- A query's words, cleaned and in lower case. .text is the words joined by spaces; .blank means nothing was typed.
-- A query of only symbols has no words but isn't blank, so it matches nothing. Every search starts here, so this is
-- where the caches are kept alive.
function NpcDirectory.wordsOfQuery(query)
    local queryWords = cleanedWords(query)
    queryWords.text = table.concat(queryWords, " ")
    queryWords.blank = not query:find("%S")
    if #queryWords > 0 then keepCaches() end
    return queryWords
end

-- The members matching every word, shortest names first: "Goblin" before "Goblin guard".
local function membersHolding(npcGroup, queryWords)
    local members = {}
    for _, member in ipairs(npcGroup.members) do
        if memberHolds(member, queryWords) then members[#members + 1] = member end
    end
    table.sort(members, function(a, b) return #a.name < #b.name end)
    return members
end

-- A head of these members that isn't shown yet, preferring one that matches the words, or nil if there is none.
local function freeHeadOf(members, queryWords, isTaken)
    for _, member in ipairs(members) do
        for _, npcID in ipairs(member) do
            if not isTaken[npcID] and headHolds(member, npcID, queryWords) then return npcID, member.name end
        end
    end
    for _, member in ipairs(members) do
        for _, npcID in ipairs(member) do
            if not isTaken[npcID] then return npcID, member.name end
        end
    end
    return nil
end

-- The heads to show for a search, one per matching group, and { id -> name }. A group whose name or shown head matches
-- keeps that head. Any other group shows the variant that matched, avoiding duplicates where possible.
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

-- The heads that match every word by their own name or id.
function NpcDirectory.headsHolding(heads, queryWords)
    local matching = {}
    for _, npcID in ipairs(heads) do
        if headHolds(memberByNpcID[npcID], npcID, queryWords) then matching[#matching + 1] = npcID end
    end
    return matching
end

-- The shortest member matching every word, for the dropdown to show, and how many NPCs match in all.
function NpcDirectory.memberMatching(npcGroup, queryWords)
    if #queryWords == 0 then return nil end
    if queryWords.text == table.concat(cleanedWords(npcGroup.name), " ") then return nil end
    -- A name containing every word wins over a match by id: "man 3" finds Man 3, not a Man whose id contains 3.
    local bestByName, best, matchingNpcCount = nil, nil, 0
    for _, member in ipairs(npcGroup.members) do
        if memberHolds(member, queryWords) then
            matchingNpcCount = matchingNpcCount + #member
            if best == nil or #member.name < #best.name then best = member end
            if nameHolds(member, queryWords) and (bestByName == nil or #member.name < #bestByName.name) then
                bestByName = member
            end
        end
    end
    return bestByName or best, matchingNpcCount
end

function NpcDirectory.nameOfNpc(npcID)
    local member = memberByNpcID[npcID]
    return member and member.name
end

-- A head shown for its group goes by the group's name, since the head of a race or job group has a name of its own
-- (Andil, in Goblin).
function NpcDirectory.nameForGroupOfNpc(npcID)
    local npcGroup = shownGroupByNpcID[npcID]
    return npcGroup and npcGroup.name or NpcDirectory.nameOfNpc(npcID)
end

-- A head in several groups belongs to the group it is shown for, or to the smallest one otherwise.
function NpcDirectory.groupOfNpc(npcID)
    return shownGroupByNpcID[npcID] or groupByNpcID[npcID]
end

-- Every group this id is in, the smallest first.
function NpcDirectory.groupsOfNpc(npcID)
    return groupsByNpcID[npcID] or { groupByNpcID[npcID] }
end

-- Two groups can share a name. The group the head is shown for wins, otherwise the smallest.
function NpcDirectory.groupLabelled(npcID, label)
    local shownGroup = shownGroupByNpcID[npcID]
    if shownGroup and shownGroup.name == label then return shownGroup end
    for _, npcGroup in ipairs(NpcDirectory.groupsOfNpc(npcID)) do
        if npcGroup.name == label then return npcGroup end
    end
    return nil
end

function NpcDirectory.nextGroupOfNpc(npcID, npcGroup)
    local groups = NpcDirectory.groupsOfNpc(npcID)
    if #groups < 2 then return nil end
    for position, group in ipairs(groups) do
        if group == npcGroup then return groups[position % #groups + 1] end
    end
    return groups[1]
end

function NpcDirectory.memberOfNpc(npcID, npcGroup)
    npcGroup = npcGroup or NpcDirectory.groupOfNpc(npcID)
    if npcGroup == nil then return nil end
    for _, member in ipairs(npcGroup.members) do
        for _, memberNpcID in ipairs(member) do
            if memberNpcID == npcID then return member end
        end
    end
    return nil
end

-- A group's ids, with its shown head first and the rest in id order.
function NpcDirectory.idsOf(npcGroup)
    local shownID, ids = npcGroup.shownID, {}
    for _, member in ipairs(npcGroup.members) do
        for _, npcID in ipairs(member) do ids[#ids + 1] = npcID end
    end
    table.sort(ids, function(a, b)
        if (a == shownID) ~= (b == shownID) then return a == shownID end
        return a < b
    end)
    return ids
end

function NpcDirectory.labelOf(name, variantCount)
    return variantCount > 1 and (name .. " (" .. variantCount .. " variants)") or name
end

function NpcDirectory.searchGroups(queryWords, maxResults)
    local matchingGroups = {}
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        if queryWords.blank or (#queryWords > 0 and groupHolds(npcGroup, queryWords)) then
            matchingGroups[#matchingGroups + 1] = npcGroup
            if #matchingGroups >= maxResults then break end
        end
    end
    return matchingGroups
end

-- The heads that headsOfGroup returns for each group, without repeats, sorted by the names nameOf gives (then by id).
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
    keepCaches()
    if headsInNameOrder == nil then
        headsInNameOrder = headsByName(function(npcGroup)
            local ids = {}
            for _, member in ipairs(npcGroup.members) do
                for _, npcID in ipairs(member) do ids[#ids + 1] = npcID end
            end
            return ids
        end, NpcDirectory.nameOfNpc)
    end
    return headsInNameOrder
end

-- The head shown for each group, in order of the groups' names.
function NpcDirectory.headsOfEachGroup()
    keepCaches()
    if headsOfEachGroup == nil then
        headsOfEachGroup = headsByName(function(npcGroup) return { npcGroup.shownID } end,
            NpcDirectory.nameForGroupOfNpc)
    end
    return headsOfEachGroup
end

return NpcDirectory
