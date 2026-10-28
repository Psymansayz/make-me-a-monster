-- The game's NPCs as { id, name, label } for the picker, read from config.NPC over several frames
-- (there are tens of thousands of configs; reading them all in one frame would stall the client).

local Npcs = {}

Npcs.list = {}      -- { id, name, label, search }, in id order
Npcs.groups = {}    -- one per distinct name, in order of first appearance: { name, ids = { id... }, search }
local groupByName = {} -- name -> group
local groupOfID = {}   -- id -> group
local idName = {}      -- id -> name
Npcs.done = false   -- every config read
Npcs.scanned = 0    -- ids tried so far

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
function Npcs.normalise(name)
    name = name:gsub("<[^>]*>", ""):gsub("\194\160", " "):gsub("[_%-]", " ")
    name = name:gsub("[^%w%s\128-\255]", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return name
end

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

-- The display name as plain text, or nil if the NPC has none.
-- Workaround: NPCs without a real name (some quest stand-ins) carry the placeholder "null".
local function plainName(config)
    local ok, name = pcall(function() return config.name end)
    if not ok or type(name) ~= "string" then return nil end
    name = Npcs.normalise(name)
    if name == "" or Npcs.lower(name) == "null" then return nil end
    return name
end

-- Reads the next PER_FRAME ids; call every frame until Npcs.done.
function Npcs.step()
    if Npcs.done then return end
    local list = Npcs.list
    for _ = 1, PER_FRAME do
        local npcID = Npcs.scanned
        Npcs.scanned = npcID + 1
        local ok, config = pcall(function() return config.NPC.FromID(npcID) end)
        if ok and config ~= nil then
            misses = 0
            local name = plainName(config)
            if name ~= nil then
                local label = name .. " (" .. npcID .. ")"
                local lower = Npcs.lower(name)
                idName[npcID] = name
                list[#list + 1] = { id = npcID, name = name, label = label,
                    search = Npcs.searchText(label) }
                -- Names that differ only by case are one entry (listed as the first one read).
                local group = groupByName[lower]
                if group == nil then
                    group = { name = name, ids = {}, search = Npcs.searchText(name) }
                    groupByName[lower] = group
                    Npcs.groups[#Npcs.groups + 1] = group
                end
                group.ids[#group.ids + 1] = npcID
                group.search = group.search .. " " .. npcID
                groupOfID[npcID] = group
            end
        else
            misses = misses + 1
        end
        if npcID >= MAX_ID or (npcID >= MIN_ID and misses >= MISS_LIMIT) then
            Npcs.done = true
            return
        end
    end
end

-- The NPC with this id, or nil.
function Npcs.find(npcID)
    for _, npc in ipairs(Npcs.list) do
        if npc.id == npcID then return npc end
    end
    return nil
end

-- The name of the NPC with this id (as listed: see Npcs.normalise), or nil.
function Npcs.nameOf(npcID)
    return idName[npcID]
end

-- The group (every NPC of one name, or after Npcs.regroup of several) that this id belongs to, or nil.
function Npcs.groupOf(npcID)
    return groupOfID[npcID]
end

-- The dropdown's label for a group: its name, and how many variants it has if more than one (`count`:
-- the ones worth showing; all of them if not given).
function Npcs.groupLabel(group, count)
    count = count or #group.ids
    return count > 1 and (group.name .. " (" .. count .. " variants)") or group.name
end

-- Merging names into entries -------------------------------------------------------------------------------

-- Words that say what state or form of an NPC it is, not what it is: names that differ only by these are
-- one entry (the NPCs look the same).
local MODIFIERS = {}
for word in ("false fabricated unnatural abnormal imitation malignant hydra champion baby adolescent adolecent "
    .. "adult elder egg sick undead figure corpse well dead elite expert ghastly big grand zombie consumer"):gmatch("%S+") do
    MODIFIERS[word] = true
end

-- Words that link no names (and numbers).
local FILLER = {}
for word in ("the of and a an in at to de la no mk mr mrs von van i ii iii iv v"):gmatch("%S+") do FILLER[word] = true end

-- A word in more than this many entries is too common to put names together (guard, captain, sir...)...
local MOST_IN_A_GROUP = 25
-- ...except these.
local ALWAYS_GROUP = {}
for word in ("tzhaar dragon man gnome"):gmatch("%S+") do ALWAYS_GROUP[word] = true end

-- Words that never put names together: titles and ranks, words that name a kind of thing too wide to be one
-- NPC's variants, and adjectives (which describe an NPC, or say whose side it is on, instead of saying what it
-- is).
local NO_GROUP = {}
for word in ("king commander general guardian giant claus lord brother lady master hunter sergeant jack ranger "
    .. "armour chaos dark evil father head magic pete queen varrock ambassador blood death director dwarven "
    .. "lumbridge rex abyssal hat tiny lieutenant instructor prince sentinel bobbled trainer dr fire chosen "
    .. "class creature ice major mayor pet red royal snow strange war ali "
    -- adjectives, and the sides of the gods:
    .. "saradominist bandosian armadylean menaphite crassian shadow local skeletal young desert crystal elven "
    .. "ethereal forgotten green blue imperial jungle light shady spectral chief ancient carnillean deceased "
    .. "fledgling ghostly gold lil meiyerditch mini mysterious not sand summer violet bloated fat fungal godless "
    .. "grey guthixian kharidian mighty proud wandering warming bronze fremennik masterwork nature water mystic "
    .. "silk my very white new rabid prehistoric decaying colonised supreme silver ranged melee halloween combat colonel count private void stone twin present zombie al foo ur ded akh haz pi ist kgp"):gmatch("%S+") do
    NO_GROUP[word] = true
end

-- What a group made around one of these words is called (instead of the words its names share).
local GROUP_NAMES = { ham = "HAM member", loot = "Loot beam" }

local function wordsOf(name)
    local list = {}
    for word in Npcs.lower(name):gmatch("%S+") do list[#list + 1] = word end
    return list
end

local function capital(text)
    return (text:gsub("^[a-z]", function(char) return char:upper() end))
end

-- The longest run of words that all of these names hold (as written in the shortest name), first letter
-- capital; the shortest name if they hold none.
local function sharedName(names)
    local originals, lowered, base = {}, {}, 1
    for index, name in ipairs(names) do
        local words, lower = {}, {}
        for word in name:gmatch("%S+") do
            words[#words + 1] = word
            lower[#lower + 1] = Npcs.lower(word)
        end
        originals[index], lowered[index] = words, lower
        if #words < #originals[base] then base = index end
    end
    local words = lowered[base]
    for length = #words, 1, -1 do
        for start = 1, #words - length + 1 do
            local run = " " .. table.concat(words, " ", start, start + length - 1) .. " "
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
function Npcs.regroup(keep)
    local items, byKey = {}, {}
    for _, entry in ipairs(Npcs.groups) do
        if keep(entry) then
            local core = {}
            for _, word in ipairs(wordsOf(entry.name)) do
                if not MODIFIERS[word] then core[#core + 1] = word end
            end
            local key = #core > 0 and table.concat(core, " ") or Npcs.lower(entry.name)
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
        for word in item.key:gmatch("%S+") do
            if not FILLER[word] and not word:find("^%d+$") and not item.words[word] then
                item.words[word] = true
                local list = byWord[word]
                if list == nil then
                    list = {}
                    byWord[word] = list
                end
                list[#list + 1] = index
            end
        end
    end

    local count, candidates = {}, {}
    for word, list in pairs(byWord) do
        if #list >= 2 and not NO_GROUP[word] and (#list <= MOST_IN_A_GROUP or ALWAYS_GROUP[word]) then
            count[word] = #list
            candidates[#candidates + 1] = word
        end
    end
    table.sort(candidates) -- (the same result each time)

    local claimed, grouped = {}, {}
    while true do
        local bestWord = nil
        for _, word in ipairs(candidates) do
            local unclaimed = count[word]
            if unclaimed ~= nil and unclaimed >= 2 then
                if bestWord == nil or unclaimed > count[bestWord]
                    or (unclaimed == count[bestWord] and #byWord[word] < #byWord[bestWord]) then
                    bestWord = word
                end
            end
        end
        if bestWord == nil then break end
        local members = {}
        for _, index in ipairs(byWord[bestWord]) do
            if not claimed[index] then
                claimed[index] = true
                members[#members + 1] = index
                for word in pairs(items[index].words) do
                    if count[word] ~= nil then count[word] = count[word] - 1 end
                end
            end
        end
        count[bestWord] = nil
        grouped[#grouped + 1] = { members = members, word = bestWord }
    end
    for index = 1, #items do
        if not claimed[index] then grouped[#grouped + 1] = { members = { index } } end
    end

    local final = {}
    for _, made in ipairs(grouped) do
        local ids, names, entries, search = {}, {}, {}, {}
        for _, index in ipairs(made.members) do
            for _, entry in ipairs(items[index].members) do
                entries[#entries + 1] = entry
                names[#names + 1] = entry.name
                search[#search + 1] = entry.search
                for _, npcID in ipairs(entry.ids) do ids[#ids + 1] = npcID end
            end
        end
        table.sort(ids)
        final[#final + 1] = {
            name = (made.word and GROUP_NAMES[made.word]) or (#names == 1 and names[1]) or sharedName(names),
            ids = ids, members = entries, search = table.concat(search, " "), anchor = made.word,
        }
    end
    table.sort(final, function(a, b) return a.ids[1] < b.ids[1] end)

    Npcs.groups = final
    groupOfID = {}
    for _, group in ipairs(final) do
        for _, npcID in ipairs(group.ids) do groupOfID[npcID] = group end
    end
    Npcs.regrouped = true
end

-- Up to `limit` groups whose name or ids contain every word of the query (all of them, in order, if the
-- query is blank); letters beyond ASCII match themselves and their plain letters, ignoring case. visibleIds(group), if given, returns the group's ids worth showing; a group with none is
-- left out.
function Npcs.search(query, limit, visibleIds)
    local words = {}
    for word in Npcs.lower(tostring(query or "")):gmatch("%S+") do words[#words + 1] = word end
    local found = {}
    for _, group in ipairs(Npcs.groups) do
        local matches = true
        for _, word in ipairs(words) do
            -- (the group's search text holds the name as it is and with its letters beyond ASCII made plain: a
            -- plain word finds either, one with such a letter only the name that has it)
            if not group.search:find(word, 1, true) then matches = false break end
        end
        if matches and (visibleIds == nil or #visibleIds(group) > 0) then
            found[#found + 1] = group
            if #found >= limit then break end
        end
    end
    return found
end

return Npcs
