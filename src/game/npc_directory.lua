-- The game's NPCs as { id, name, label } for the picker, read from config.NPC over several frames
-- (there are tens of thousands of configs; reading them all in one frame would stall the client).

local GameIds = require("src/game/game_ids")

local NpcDirectory = {}

NpcDirectory.list = {}      -- { id, name, label, search }, in id order
NpcDirectory.groups = {}    -- one per distinct name, in order of first appearance: { name, ids = { id... }, search }
local groupByName = {} -- name -> group
local groupByNpcID = {}   -- id -> group (the smallest it is in: a head can be in several)
local shownGroupByNpcID = {} -- id -> the group it is the head shown for
local groupsByNpcID = {} -- id -> every group it is in, the smallest first
local nameByNpcID = {}      -- id -> name
NpcDirectory.done = false   -- every config read
NpcDirectory.scanned = 0    -- ids tried so far

local PER_FRAME = 400
local MAX_ID = 200000
-- Workaround: config.NPC has no length or iterator, so the scan ends after this many ids in a row that
-- don't exist (past the first MIN_ID, which may contain gaps).
local MISS_LIMIT = 3000
local MIN_ID = 5000
local misses = 0

-- The name as it is listed and merged by: the game's markup taken out, underscores and hyphens made spaces,
-- everything else that isn't a letter, digit or space removed (letters beyond ASCII are kept), runs of space
-- made one. "Bob's_Axes" and "Bobs Axes" are the same entry, and so are "Wise-Old Man" and "Wise Old Man".
function NpcDirectory.normalise(name)
    name = name:gsub("<[^>]*>", ""):gsub("\194\160", " "):gsub("[_%-]", " ")
    name = name:gsub("[^%w%s\128-\255]", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return name
end

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

-- The display name as plain text, or nil if the NPC has none.
-- Workaround: NPCs without a real name (some quest stand-ins) carry the placeholder "null".
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
                local label = name .. " (" .. npcID .. ")"
                local lower = NpcDirectory.lowerCaseAscii(name)
                nameByNpcID[npcID] = name
                list[#list + 1] = { id = npcID, name = name, label = label,
                    search = NpcDirectory.searchableText(label) }
                -- Names that differ only by case are one entry (listed as the first one read).
                local npcGroup = groupByName[lower]
                if npcGroup == nil then
                    npcGroup = { name = name, ids = {}, search = NpcDirectory.searchableText(name) }
                    groupByName[lower] = npcGroup
                    NpcDirectory.groups[#NpcDirectory.groups + 1] = npcGroup
                end
                npcGroup.ids[#npcGroup.ids + 1] = npcID
                npcGroup.search = npcGroup.search .. " " .. npcID
                groupByNpcID[npcID] = npcGroup
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

-- Gives the group a head to stand for: one that no group shows, else one whose group can move to another. False if
-- there is neither.
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

-- The entries and heads listed, as saved in src/data/listed_heads.lua (made from a scan by NpcDirectory.exportLines): no scan, no
-- head checks. NPCs added to the game later are not listed until that file is made again.
-- data.groups = { { name, members = { { name, { NPC name... } }... } }... }: the names in the game (id.NPC) are turned
-- into this build's ids here; an NPC the game does not know by its name is left out. A group's ids start with its head
-- shown, then go by id. A group whose first NPC is left out takes another (placeGroup), the smallest such group first,
-- so that every group keeps a place of its own in the list of one head per group.
function NpcDirectory.loadBaked(listedHeadsData)
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
            local npcGroup = { name = savedGroup.name, ids = npcIDs, members = members } -- (its search text is made when searched)
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
    NpcDirectory.baked, NpcDirectory.done, NpcDirectory.regrouped = true, true, true
end

-- The names of a group (members). A name read from the game that has not been merged yet (while the NPCs are being read, in
-- the dev scan) has none: it is its own one name.
local function membersOf(npcGroup)
    return npcGroup.members or { npcGroup }
end

-- The text a search looks in for one name of a group: the name (as it is and with plain letters) and its ids.
local function searchOfMember(member)
    if member.search == nil then
        member.search = NpcDirectory.searchableText(member.name) .. " " .. table.concat(member.ids, " ")
    end
    return member.search
end

-- The text a search looks in for a group: its own name (which no member may have: Gorajo), all its members' and ids.
local function searchOf(npcGroup)
    if npcGroup.search == nil then
        local searchParts = { NpcDirectory.searchableText(npcGroup.name) }
        for _, member in ipairs(membersOf(npcGroup)) do searchParts[#searchParts + 1] = searchOfMember(member) end
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

-- The members of a group holding every word (in a name or ids), the shortest names first: "Goblin" before
-- "Goblin guard".
local function membersHolding(npcGroup, queryWords)
    local members = {}
    for _, member in ipairs(membersOf(npcGroup)) do
        if containsEveryWord(searchOfMember(member), queryWords) then members[#members + 1] = member end
    end
    table.sort(members, function(a, b) return #a.name < #b.name end)
    return members
end

-- Whether this head of the member holds every word: its id can be what was searched for.
local function headHolds(member, npcID, queryWords)
    return containsEveryWord(NpcDirectory.searchableText(member.name) .. " " .. npcID, queryWords)
end

-- A head of these members to show that nothing shows yet, one that holds the words if there is one; or nil.
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

-- The heads to show for a search (lower case words), one for each group that it matches, in order of their names, and
-- { id -> name }. shownHeads: the head shown for each group. A group whose name matches, or whose head shown does,
-- keeps it. Any other shows the variant that matched, after those so that it takes no head from them, and no head
-- twice.
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
    for _, member in ipairs(membersOf(npcGroup)) do
        if containsEveryWord(searchOfMember(member), queryWords) then
            matchingNpcCount = matchingNpcCount + #member.ids
            if best == nil or #member.name < #best.name then best = member end
        end
    end
    return best, matchingNpcCount
end

-- Development: the lines to log once a scan has been merged into entries (visibleIds(group) = the ids worth showing),
-- from which src/data/listed_heads.lua is made: "HEADS|<n>/<of>|<records>", a record being
-- "<entry name>=<member name>:<id>,<id>;<member name>:..." and records joined by "~". (Names hold no | ~ = : ; ,.)
function NpcDirectory.exportLines(visibleIds, maxLength)
    maxLength = maxLength or 900
    local chunks, current, length, heads = {}, {}, 0, 0
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        local shown = {}
        for _, npcID in ipairs(visibleIds(npcGroup)) do shown[npcID] = true end
        local members = {}
        for _, member in ipairs(npcGroup.members or { { name = npcGroup.name, ids = npcGroup.ids } }) do
            local npcIDs = {}
            for _, npcID in ipairs(member.ids) do
                if shown[npcID] then npcIDs[#npcIDs + 1] = npcID end
            end
            if #npcIDs > 0 then
                heads = heads + #npcIDs
                members[#members + 1] = member.name .. ":" .. table.concat(npcIDs, ",")
            end
        end
        if #members > 0 then
            local record = npcGroup.name .. "=" .. table.concat(members, ";")
            if length > 0 and length + #record > maxLength then
                chunks[#chunks + 1] = table.concat(current, "~")
                current, length = {}, 0
            end
            current[#current + 1] = record
            length = length + #record + 1
        end
    end
    if #current > 0 then chunks[#chunks + 1] = table.concat(current, "~") end
    local lines = {}
    for index, chunk in ipairs(chunks) do lines[index] = ("HEADS|%d/%d|%s"):format(index, #chunks, chunk) end
    return lines, heads
end

-- The NPC with this id, or nil.
function NpcDirectory.find(npcID)
    for _, npc in ipairs(NpcDirectory.list) do
        if npc.id == npcID then return npc end
    end
    return nil
end

-- The name of the NPC with this id (as listed: see NpcDirectory.normalise), or nil.
function NpcDirectory.nameOfNpc(npcID)
    return nameByNpcID[npcID]
end

-- The name of a head standing for its group: a race or job group's head has a name of its own (Andil, in Goblin), so
-- it goes by the group's. A head no group shows has its own name.
function NpcDirectory.nameForGroupOfNpc(npcID)
    local npcGroup = shownGroupByNpcID[npcID]
    return npcGroup and npcGroup.name or nameByNpcID[npcID]
end

-- The group (every NPC of one name, or after NpcDirectory.regroup of several) that this id belongs to, or nil. A head
-- in several: the one it is the head shown for, else the smallest.
function NpcDirectory.groupOfNpc(npcID)
    return shownGroupByNpcID[npcID] or groupByNpcID[npcID]
end

-- Every group this id is in, the smallest first.
function NpcDirectory.groupsOfNpc(npcID)
    return groupsByNpcID[npcID] or { groupByNpcID[npcID] }
end

-- The group of this id that this label names, or nil: the one it is the head shown for, else the smallest (two groups
-- can have one name).
function NpcDirectory.groupLabelled(npcID, label)
    local shownGroup = shownGroupByNpcID[npcID]
    if shownGroup and shownGroup.name == label then return shownGroup end
    for _, npcGroup in ipairs(NpcDirectory.groupsOfNpc(npcID)) do
        if npcGroup.name == label then return npcGroup end
    end
    return nil
end

-- The group after this one, of those this id is in (back to the first after the last), or nil if it is in no other.
function NpcDirectory.nextGroupOfNpc(npcID, npcGroup)
    local groups = NpcDirectory.groupsOfNpc(npcID)
    if #groups < 2 then return nil end
    for position, group in ipairs(groups) do
        if group == npcGroup then return groups[position % #groups + 1] end
    end
    return groups[1]
end

-- The name of the group (a member) that this NPC has, or nil: in npcGroup, else in NpcDirectory.groupOfNpc. (A group
-- holds several names; the NPC chosen can be of any.)
function NpcDirectory.memberOfNpc(npcID, npcGroup)
    npcGroup = npcGroup or NpcDirectory.groupOfNpc(npcID)
    if npcGroup == nil then return nil end
    for _, member in ipairs(membersOf(npcGroup)) do
        for _, memberNpcID in ipairs(member.ids) do
            if memberNpcID == npcID then return member end
        end
    end
    return nil
end

-- The dropdown's label for a group: its name, and how many variants it has if more than one (`count`:
-- the ones worth showing; all of them if not given).
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

-- Merging names into entries -------------------------------------------------------------------------------

-- Words that say what state or form of an NPC it is, not what it is: names that differ only by these are
-- one entry (the NPCs look the same).
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

-- Words that never put names together: titles and ranks, words that name a kind of thing too wide to be one
-- NPC's variants, and adjectives (which describe an NPC, or say whose side it is on, instead of saying what it
-- is).
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

-- The longest run of words that all of these names hold (as written in the shortest name), first letter
-- capital; the shortest name if they hold none.
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

-- The groups made again, fewer and larger. keep(group) says whether a group stays at all (the dropdown
-- leaves out names with no head worth showing). Two steps:
--   1. names that differ only by MODIFIERS are one entry ("Abnormal golem hydra" is "Golem");
--   2. entries holding a word in common are put together: repeatedly the word holding the most entries
--      not yet put in a group is taken, and those entries become a group. Every member of a group holds its
--      word (so groups never chain), and a word in more than MOST_IN_A_GROUP entries is passed over.
-- A group is named by the longest run of words all its names share. Each group has `members` (the groups it
-- was made of), all their `ids` and their `search` text.
function NpcDirectory.regroup(keep)
    local items, byKey = {}, {}
    for _, entry in ipairs(NpcDirectory.groups) do
        if keep(entry) then
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

    local final = {}
    for _, made in ipairs(grouped) do
        local npcIDs, names, entries, search = {}, {}, {}, {}
        for _, index in ipairs(made.members) do
            for _, entry in ipairs(items[index].members) do
                entries[#entries + 1] = entry
                names[#names + 1] = entry.name
                search[#search + 1] = entry.search
                for _, npcID in ipairs(entry.ids) do npcIDs[#npcIDs + 1] = npcID end
            end
        end
        table.sort(npcIDs)
        final[#final + 1] = {
            name = (made.word and GROUP_NAMES[made.word]) or (#names == 1 and names[1]) or sharedName(names),
            ids = npcIDs, members = entries, search = table.concat(search, " "), anchor = made.word,
        }
    end
    table.sort(final, function(a, b) return a.ids[1] < b.ids[1] end)

    NpcDirectory.groups = final
    groupByNpcID = {}
    for _, npcGroup in ipairs(final) do
        for _, npcID in ipairs(npcGroup.ids) do groupByNpcID[npcID] = npcGroup end
    end
    NpcDirectory.regrouped = true
end

-- Up to `limit` groups whose name or ids contain every word of the query (all of them, in order, if the
-- query is blank); letters beyond ASCII match themselves and their plain letters, ignoring case. visibleIds(group), if given, returns the group's ids worth showing; a group with none is
-- left out.
function NpcDirectory.searchGroups(query, maxResults, visibleIds)
    local queryWords = wordsOfQuery(query)
    local matchingGroups = {}
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        -- (the group's search text holds the name as it is and with its letters beyond ASCII made plain: a plain word
        -- finds either, one with such a letter only the name that has it)
        if containsEveryWord(searchOf(npcGroup), queryWords) and (visibleIds == nil or #visibleIds(npcGroup) > 0) then
            matchingGroups[#matchingGroups + 1] = npcGroup
            if #matchingGroups >= maxResults then break end
        end
    end
    return matchingGroups
end

-- The heads the plugin lists, one per id, in name order; idsOf(group) -> the ids of a group worth showing (all of them
-- if not given). Made once: the list does not change while the plugin runs.
local headsInNameOrder, headsOfEachGroup = nil, nil

-- The heads that headsOfGroup(group) gives for the groups, each once (a head can be in several), in order of nameOf.
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

function NpcDirectory.headsInNameOrder(idsOf)
    if headsInNameOrder == nil then
        headsInNameOrder = headsByName(function(npcGroup) return idsOf and idsOf(npcGroup) or npcGroup.ids end,
            NpcDirectory.nameOfNpc)
    end
    return headsInNameOrder
end

-- The head shown for each group, in order of the groups' names.
function NpcDirectory.headsOfEachGroup(idsOf)
    if headsOfEachGroup == nil then
        headsOfEachGroup = headsByName(function(npcGroup)
            return { (idsOf and idsOf(npcGroup) or npcGroup.ids)[1] }
        end, NpcDirectory.nameForGroupOfNpc)
    end
    return headsOfEachGroup
end

return NpcDirectory
