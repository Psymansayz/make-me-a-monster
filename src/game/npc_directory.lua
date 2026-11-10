-- The NPCs the plugin lists: their entries and heads come from the saved list (src/data/listed_heads.lua); only their
-- ids in this game build are looked up (id.NPC). On dev, without the saved list, they come from a scan of the game's
-- NPCs over several frames instead (NpcDirectory.step, then NpcDirectory.regroup).

local GameIds = require("src/game/game_ids")

local NpcDirectory = {}

-- One per entry of the dropdown, in its order: { name, members, idCount, shownID (the head shown for it) }. A member
-- is one name of the group, its ids in its own list part: { name, id, id... } (most have one). The group's ids in
-- order: NpcDirectory.idsOf. A group or member whose name holds a digit has nameHasDigit (only those names are
-- searched for a word of digits).
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

-- Not all of these are in the game's names yet.
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

-- A text cleaned as the list's names were when it was made: "50% Luke" is listed as "50 Luke", "Bob's" as "Bobs",
-- "Tz-Kih" as "Tz Kih". (The names and the queries both: a few listed names still hold a symbol, as "Dagon'hai".)
local function cleaned(text)
    text = text:gsub("<[^>]*>", ""):gsub("\194\160", " "):gsub("[_%-]", " ")
    return (text:gsub("[^%w%s\128-\255]", ""))
end

-- A text's words, cleaned and in lower case.
local function cleanedWords(text)
    local words = {}
    for word in NpcDirectory.lowerCaseAscii(cleaned(text)):gmatch("%S+") do words[#words + 1] = word end
    return words
end

-- What searches look in: the name cleaned and in lower case, followed by each way it reads made plain if it has
-- letters beyond ASCII.
local function searchableText(name)
    local plain = cleaned(name)
    local lowered = NpcDirectory.lowerCaseAscii(plain)
    if not plain:find("[\128-\255]") then return lowered end
    return lowered .. " " .. NpcDirectory.lowerCaseAscii(table.concat(allPlainReadings(plain), " "))
end

-- Selects a head to represent each group: one no other group shows, moving another group's to one of its others.
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

-- Loads groups of { name, members = { { name, { entry... } }... } }, each entry made an id by idOf.
local function loadGroups(savedGroups, idOf)
    local groupsToChoose = {}
    for _, savedGroup in ipairs(savedGroups) do
        local npcIDs, members, firstIsKnown = {}, {}, false
        for memberIndex, savedMember in ipairs(savedGroup.members) do
            local member = { name = savedMember[1], nameHasDigit = savedMember[1]:find("%d") ~= nil or nil }
            for nameIndex, entry in ipairs(savedMember[2]) do
                local npcID = idOf(entry)
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
    -- A group no head was free for shows its smallest id (for it alone: not in shownGroupByNpcID).
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

local function npcIDOfName(npcName)
    return GameIds.resolve("NPC", npcName)
end

-- Loads the saved list (src/data/listed_heads.lua). NPCs added to the game later are not listed until it is made again.
function NpcDirectory.loadListedHeads(listedHeadsData)
    loadGroups(listedHeadsData.groups, npcIDOfName)
end

-- A search word of digits only is looked for in the ids, and in the few names holding a digit ("man 3", "50% luke").
local function isIdWord(queryWord)
    return queryWord:find("^%d+$") ~= nil
end

local function idHoldsWord(npcID, queryWord)
    return tostring(npcID):find(queryWord, 1, true) ~= nil
end

-- What searches and the heads window use, made when first needed and let go after five minutes without a use: the
-- names' searched texts (searchableText), and the heads in name order (both lists). The client has no clock: so the
-- time is counted in server ticks, subscribed to only while something is kept.
local searchTexts = {} -- group or member -> its text
local headsInNameOrder, headsOfEachGroup = nil, nil
local CACHE_TICKS = 500 -- (0.6 s each: five minutes)
local CACHE_SUBSCRIPTION = "make_me_a_monster_directory_caches"
local ticksToKeepCaches = 0
local countingDown = false

local function countDownCaches()
    ticksToKeepCaches = ticksToKeepCaches - 1
    if ticksToKeepCaches <= 0 then NpcDirectory.forgetCaches() end
end

-- Lets the caches go: when they expire, and at shutdown.
function NpcDirectory.forgetCaches()
    if countingDown then Event.ServerLogic.Unsubscribe(CACHE_SUBSCRIPTION) end
    searchTexts, headsInNameOrder, headsOfEachGroup = {}, nil, nil
    ticksToKeepCaches, countingDown = 0, false
end

-- Each use keeps them five minutes more.
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

-- A query's words never hold a space: so a word is found in one name or another, never across two.
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

-- A group's own name is searched too: no member may have it.
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

-- One head of a member: by the member's name, or that head's own id.
local function headHolds(member, npcID, queryWords)
    for _, queryWord in ipairs(queryWords) do
        if not nameHoldsWord(member, queryWord) and not (isIdWord(queryWord) and idHoldsWord(npcID, queryWord)) then
            return false
        end
    end
    return true
end

-- A query's words, cleaned and in lower case; .text: the words joined by single spaces; .blank: nothing was typed (a
-- query of symbols only has no words, but is not blank: it matches nothing). Each search starts here: the caches are
-- kept five minutes more.
function NpcDirectory.wordsOfQuery(query)
    local queryWords = cleanedWords(query)
    queryWords.text = table.concat(queryWords, " ")
    queryWords.blank = not query:find("%S")
    if #queryWords > 0 then keepCaches() end
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

-- The shortest member holding every word of the query (NpcDirectory.wordsOfQuery), for the dropdown to show, and how
-- many NPCs match in all.
function NpcDirectory.memberMatching(npcGroup, queryWords)
    if #queryWords == 0 then return nil end
    if queryWords.text == table.concat(cleanedWords(npcGroup.name), " ") then return nil end
    -- A name holding every word wins over a match by id ("man 3": Man 3, not Man with an id holding 3).
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
        for _, memberNpcID in ipairs(member) do
            if memberNpcID == npcID then return member end
        end
    end
    return nil
end

-- A group's ids in order: the head shown for it first, then the rest by id. Made when asked (the variants window).
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

-- The dropdown's label for a group or a member: its name, and how many variants it has if more than one.
function NpcDirectory.labelOf(name, variantCount)
    return variantCount > 1 and (name .. " (" .. variantCount .. " variants)") or name
end

-- Up to `maxResults` groups whose name or ids contain every word of the query (NpcDirectory.wordsOfQuery).
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

-- The heads headsOfGroup gives for each group, once each, sorted by the names nameOf gives them (then by id).
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

-- The heads the plugin lists, one per id, in name order (kept as a cache, above).
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


-- Dev scan -------------------------------------------------------------------------------------------------

NpcDirectory.list = {}    -- { id, name, label }, in id order
NpcDirectory.done = false -- every config read
NpcDirectory.scanned = 0  -- ids tried so far
local scannedEntries = {} -- one per distinct name, in order of first appearance: { name, ids = { id... } }
local entryByName = {}    -- lower-case name -> entry

function NpcDirectory.scannedEntries()
    return scannedEntries
end

local PER_FRAME = 400
local MAX_ID = 200000
-- Workaround: config.NPC has no length or iterator, so the scan ends after this many ids in a row that
-- don't exist (past the first MIN_ID, which may contain gaps).
local MISS_LIMIT = 3000
local MIN_ID = 5000
local misses = 0

-- The name as it is listed and merged by: "Bob's_Axes" and "Bobs Axes" are the same entry.
function NpcDirectory.normalise(name)
    name = name:gsub("<[^>]*>", ""):gsub("\194\160", " "):gsub("[_%-]", " ")
    name = name:gsub("[^%w%s\128-\255]", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return name
end

-- NPCs without a real name (some quest stand-ins) carry the placeholder "null".
local function plainName(config)
    local succeeded, name = pcall(function() return config.name end)
    if not succeeded or type(name) ~= "string" then return nil end
    name = NpcDirectory.normalise(name)
    if name == "" or NpcDirectory.lowerCaseAscii(name) == "null" then return nil end
    return name
end

-- Reads the next PER_FRAME ids; call every frame until NpcDirectory.done.
function NpcDirectory.step()
    if NpcDirectory.done then return end
    local list = NpcDirectory.list
    for _ = 1, PER_FRAME do
        local npcID = NpcDirectory.scanned
        NpcDirectory.scanned = npcID + 1
        local succeeded, config = pcall(function() return config.NPC.FromID(npcID) end)
        if succeeded and config ~= nil then
            misses = 0
            local name = plainName(config)
            if name ~= nil then
                list[#list + 1] = { id = npcID, name = name, label = name .. " (" .. npcID .. ")" }
                -- Names that differ only by case are one entry (listed as the first one read).
                local lower = NpcDirectory.lowerCaseAscii(name)
                local entry = entryByName[lower]
                if entry == nil then
                    entry = { name = name, ids = {} }
                    entryByName[lower] = entry
                    scannedEntries[#scannedEntries + 1] = entry
                end
                entry.ids[#entry.ids + 1] = npcID
            end
        else
            misses = misses + 1
        end
        if npcID >= MAX_ID or (npcID >= MIN_ID and misses >= MISS_LIMIT) then
            NpcDirectory.done = true
            return
        end
    end
end

function NpcDirectory.find(npcID)
    for _, npc in ipairs(NpcDirectory.list) do
        if npc.id == npcID then return npc end
    end
    return nil
end

-- Merging names into entries -------------------------------------------------------------------------------

-- Words for an NPC's state or form: names that differ only by these are one entry.
local MODIFIERS = {}
for queryWord in ("false fabricated unnatural abnormal imitation malignant hydra champion baby adolescent adolecent "
    .. "adult elder egg sick undead figure corpse well dead elite expert ghastly big grand zombie consumer"):gmatch("%S+") do
    MODIFIERS[queryWord] = true
end

-- Words that link no names (and numbers).
local FILLER = {}
for queryWord in ("the of and a an in at to de la no mk mr mrs von van i ii iii iv v"):gmatch("%S+") do FILLER[queryWord] = true end

-- A word in more than this many entries is too common to put names together (guard, captain, sir...)...
local MOST_IN_A_GROUP = 25
-- ...except these.
local ALWAYS_GROUP = {}
for queryWord in ("tzhaar dragon man gnome"):gmatch("%S+") do ALWAYS_GROUP[queryWord] = true end

-- Words that never put names together: titles, ranks, adjectives and words too wide to be one NPC's variants.
local NO_GROUP = {}
for queryWord in ("black king commander general guardian giant claus lord brother lady master hunter sergeant jack ranger "
    .. "armour chaos dark evil father head magic pete queen varrock ambassador blood death director dwarven "
    .. "lumbridge rex abyssal hat tiny lieutenant instructor prince sentinel bobbled trainer dr fire chosen "
    .. "class creature ice major mayor pet red royal snow strange war ali "
    -- adjectives, and the sides of the gods:
    .. "saradominist bandosian armadylean menaphite crassian shadow local skeletal young desert crystal elven "
    .. "ethereal forgotten green blue imperial jungle light shady spectral chief ancient carnillean deceased "
    .. "fledgling ghostly gold lil meiyerditch mini mysterious not sand summer violet bloated fat fungal godless "
    .. "grey guthixian kharidian mighty proud wandering warming bronze fremennik masterwork nature water mystic "
    .. "silk my very white new rabid prehistoric decaying colonised supreme silver ranged melee halloween combat colonel count private void stone twin present zombie al foo ur ded akh haz pi ist kgp"):gmatch("%S+") do
    NO_GROUP[queryWord] = true
end

-- What a group made around one of these words is called (instead of the words its names share).
local GROUP_NAMES = { ham = "HAM member", loot = "Loot beam" }

local function wordsOf(name)
    local list = {}
    for queryWord in NpcDirectory.lowerCaseAscii(name):gmatch("%S+") do list[#list + 1] = queryWord end
    return list
end

local function capital(inputText)
    return (inputText:gsub("^[a-z]", function(character) return character:upper() end))
end

-- The longest run of words that all of these names hold; the shortest name if they hold none.
local function sharedName(names)
    local originals, lowered, base = {}, {}, 1
    for index, name in ipairs(names) do
        local queryWords, lower = {}, {}
        for queryWord in name:gmatch("%S+") do
            queryWords[#queryWords + 1] = queryWord
            lower[#lower + 1] = NpcDirectory.lowerCaseAscii(queryWord)
        end
        originals[index], lowered[index] = queryWords, lower
        if #queryWords < #originals[base] then base = index end
    end
    local queryWords = lowered[base]
    for length = #queryWords, 1, -1 do
        for start = 1, #queryWords - length + 1 do
            local run = " " .. table.concat(queryWords, " ", start, start + length - 1) .. " "
            local inAll = true
            for index, other in ipairs(lowered) do
                if index ~= base and not (" " .. table.concat(other, " ") .. " "):find(run, 1, true) then
                    inAll = false
                    break
                end
            end
            if inAll then return capital(table.concat(originals[base], " ", start, start + length - 1)) end
        end
    end
    return names[base]
end

-- Merges the scan's entries into groups, and loads them. Names that differ only by MODIFIERS become one entry, then
-- entries sharing a word are put together, the word holding the most first. Every member holds its group's word, so
-- groups never chain. visibleIdsOf(entry): the entry's heads worth showing; an entry with none is left out.
function NpcDirectory.regroup(visibleIdsOf)
    local items, byKey = {}, {}
    for _, entry in ipairs(scannedEntries) do
        if #visibleIdsOf(entry) > 0 then
            local core = {}
            for _, queryWord in ipairs(wordsOf(entry.name)) do
                if not MODIFIERS[queryWord] then core[#core + 1] = queryWord end
            end
            local key = #core > 0 and table.concat(core, " ") or NpcDirectory.lowerCaseAscii(entry.name)
            local item = byKey[key]
            if item == nil then
                item = { key = key, members = {}, words = {} }
                byKey[key] = item
                items[#items + 1] = item
            end
            item.members[#item.members + 1] = entry
        end
    end

    local byWord = {}
    for index, item in ipairs(items) do
        for queryWord in item.key:gmatch("%S+") do
            if not FILLER[queryWord] and not queryWord:find("^%d+$") and not item.words[queryWord] then
                item.words[queryWord] = true
                local list = byWord[queryWord]
                if list == nil then
                    list = {}
                    byWord[queryWord] = list
                end
                list[#list + 1] = index
            end
        end
    end

    local variantCount, candidates = {}, {}
    for queryWord, list in pairs(byWord) do
        if #list >= 2 and not NO_GROUP[queryWord] and (#list <= MOST_IN_A_GROUP or ALWAYS_GROUP[queryWord]) then
            variantCount[queryWord] = #list
            candidates[#candidates + 1] = queryWord
        end
    end
    table.sort(candidates) -- (the same result each time)

    local claimed, grouped = {}, {}
    while true do
        local bestWord = nil
        for _, queryWord in ipairs(candidates) do
            local unclaimed = variantCount[queryWord]
            if unclaimed ~= nil and unclaimed >= 2 then
                if bestWord == nil or unclaimed > variantCount[bestWord]
                    or (unclaimed == variantCount[bestWord] and #byWord[queryWord] < #byWord[bestWord]) then
                    bestWord = queryWord
                end
            end
        end
        if bestWord == nil then break end
        local members = {}
        for _, index in ipairs(byWord[bestWord]) do
            if not claimed[index] then
                claimed[index] = true
                members[#members + 1] = index
                for queryWord in pairs(items[index].words) do
                    if variantCount[queryWord] ~= nil then variantCount[queryWord] = variantCount[queryWord] - 1 end
                end
            end
        end
        variantCount[bestWord] = nil
        grouped[#grouped + 1] = { members = members, word = bestWord }
    end
    for index = 1, #items do
        if not claimed[index] then grouped[#grouped + 1] = { members = { index } } end
    end

    -- Each group as the saved list has it, by id: its members are the merged entries, with the heads worth showing.
    local savedGroups = {}
    for _, made in ipairs(grouped) do
        local members, names, firstID = {}, {}, nil
        for _, index in ipairs(made.members) do
            for _, entry in ipairs(items[index].members) do
                local visible = visibleIdsOf(entry)
                members[#members + 1] = { entry.name, visible }
                names[#names + 1] = entry.name
                for _, npcID in ipairs(visible) do
                    if firstID == nil or npcID < firstID then firstID = npcID end
                end
            end
        end
        savedGroups[#savedGroups + 1] = {
            name = (made.word and GROUP_NAMES[made.word]) or (#names == 1 and names[1]) or sharedName(names),
            members = members, firstID = firstID,
        }
    end
    table.sort(savedGroups, function(a, b) return a.firstID < b.firstID end)
    loadGroups(savedGroups, function(npcID) return npcID end)
end

-- Development: the log lines src/data/listed_heads.lua is made from, once a scan has been merged into groups.
function NpcDirectory.exportLines(maxLength)
    maxLength = maxLength or 900
    local chunks, current, length, heads = {}, {}, 0, 0
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        local members = {}
        for _, member in ipairs(npcGroup.members) do
            heads = heads + #member
            members[#members + 1] = member.name .. ":" .. table.concat(member, ",")
        end
        local record = npcGroup.name .. "=" .. table.concat(members, ";")
        if length > 0 and length + #record > maxLength then
            chunks[#chunks + 1] = table.concat(current, "~")
            current, length = {}, 0
        end
        current[#current + 1] = record
        length = length + #record + 1
    end
    if #current > 0 then chunks[#chunks + 1] = table.concat(current, "~") end
    local lines = {}
    for index, chunk in ipairs(chunks) do lines[index] = ("HEADS|%d/%d|%s"):format(index, #chunks, chunk) end
    return lines, heads
end

return NpcDirectory
