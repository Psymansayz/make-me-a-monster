-- The NPCs the plugin lists, from the saved list in src/data/listed_heads.lua. Only their ids are looked up in the
-- current game build (in id.NPC). On dev, if there is no saved list, the game's NPCs are scanned instead, over several
-- frames (NpcDirectory.step, then NpcDirectory.regroup).

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

-- Loads groups of { name, members = { { name, { entry... } }... } }, turning each entry into an id with idOf.
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

local function npcIDOfName(npcName)
    return GameIds.resolve("NPC", npcName)
end

-- Loads the saved list (src/data/listed_heads.lua). NPCs added to the game later aren't listed until it is remade.
function NpcDirectory.loadListedHeads(listedHeadsData)
    loadGroups(listedHeadsData.groups, npcIDOfName)
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

-- Dev scan -------------------------------------------------------------------------------------------------

NpcDirectory.list = {}    -- { id, name, label }, in id order
NpcDirectory.done = false -- true once every config has been read
NpcDirectory.scanned = 0  -- ids tried so far
local scannedEntries = {} -- one per distinct name, in order of first appearance: { name, ids = { id... } }
local entryByName = {}    -- lower-case name -> entry

function NpcDirectory.scannedEntries()
    return scannedEntries
end

local PER_FRAME = 400
local MAX_ID = 200000
-- config.NPC has no length or iterator, so the scan stops after this many missing ids in a row. The low ids have
-- gaps, so this only applies past MIN_ID.
local MISS_LIMIT = 3000
local MIN_ID = 5000
local misses = 0

-- The form of a name used for listing and merging, so that "Bob's_Axes" and "Bobs Axes" are the same entry.
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
                -- Names that differ only by case are one entry, listed under the first one read.
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

-- Words for an NPC's state or form. Names that differ only by these are one entry.
local MODIFIERS = {}
for queryWord in ("false fabricated unnatural abnormal imitation malignant hydra champion baby adolescent adolecent "
    .. "adult elder egg sick undead figure corpse well dead elite expert ghastly big grand zombie consumer"):gmatch("%S+") do
    MODIFIERS[queryWord] = true
end

-- Filler words that never link names. Numbers don't either.
local FILLER = {}
for queryWord in ("the of and a an in at to de la no mk mr mrs von van i ii iii iv v"):gmatch("%S+") do FILLER[queryWord] = true end

-- A word in more than this many entries is too common to group names by (guard, captain, sir...)...
local MOST_IN_A_GROUP = 25
-- ...except these.
local ALWAYS_GROUP = {}
for queryWord in ("tzhaar dragon man gnome"):gmatch("%S+") do ALWAYS_GROUP[queryWord] = true end

-- Words that never group names: titles, ranks, adjectives and words too broad to mean one NPC's variants.
local NO_GROUP = {}
for queryWord in ("black king commander general guardian giant claus lord brother lady master hunter sergeant jack ranger "
    .. "armour chaos dark evil father head magic pete queen varrock ambassador blood death director dwarven "
    .. "lumbridge rex abyssal hat tiny lieutenant instructor prince sentinel bobbled trainer dr fire chosen "
    .. "class creature ice major mayor pet red royal snow strange war ali "
    -- adjectives, and the gods' followers:
    .. "saradominist bandosian armadylean menaphite crassian shadow local skeletal young desert crystal elven "
    .. "ethereal forgotten green blue imperial jungle light shady spectral chief ancient carnillean deceased "
    .. "fledgling ghostly gold lil meiyerditch mini mysterious not sand summer violet bloated fat fungal godless "
    .. "grey guthixian kharidian mighty proud wandering warming bronze fremennik masterwork nature water mystic "
    .. "silk my very white new rabid prehistoric decaying colonised supreme silver ranged melee halloween combat colonel count private void stone twin present zombie al foo ur ded akh haz pi ist kgp"):gmatch("%S+") do
    NO_GROUP[queryWord] = true
end

-- The name for a group made around one of these words, instead of the words its names share.
local GROUP_NAMES = { ham = "HAM member", loot = "Loot beam" }

local function wordsOf(name)
    local list = {}
    for queryWord in NpcDirectory.lowerCaseAscii(name):gmatch("%S+") do list[#list + 1] = queryWord end
    return list
end

local function capital(inputText)
    return (inputText:gsub("^[a-z]", function(character) return character:upper() end))
end

-- The longest run of words that all these names share, or the shortest name if they share none.
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

-- Merges the scan's entries into groups and loads them. Names that differ only by MODIFIERS become one entry, then
-- entries sharing a word are grouped, starting with the word most of them share. Every member holds its group's word,
-- so groups never chain. visibleIdsOf(entry) gives the entry's heads worth showing; an entry with none is left out.
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
    table.sort(candidates) -- the same result each time

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

    -- Each group in the saved list's form, by id. Its members are the merged entries and their heads worth showing.
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

-- The log lines src/data/listed_heads.lua is made from, once a scan has been merged into groups.
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
