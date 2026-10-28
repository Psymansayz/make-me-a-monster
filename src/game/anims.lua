-- The animations the plugin lists (config.Seq) as { id, name, label, search }, for finding one by name: just the
-- whitelisted ones (src/data/animation_whitelist.lua), looked up by id a few at a time. Their duplicates (longer
-- takes, loops) are kept apart in the whitelist and are not loaded.

local Whitelist = require("src/data/animation_whitelist")
local PlayerAnims = require("src/data/player_head_animations")
local Labels = require("src/data/animation_labels")

local Anims = {}

Anims.list = {}     -- in id order
Anims.done = false  -- every whitelisted animation looked up
Anims.scanned = 0   -- how many have been looked up

local PER_FRAME = 400
-- The whitelisted animations for NPC heads, then the player's own head's (marked own).
local wanted = {}
for _, animID in ipairs(Whitelist.ids or {}) do wanted[#wanted + 1] = animID end
local ownFrom = #wanted
for _, animID in ipairs(PlayerAnims.actors or {}) do wanted[#wanted + 1] = animID end

-- Looks up the next PER_FRAME whitelisted animations; call every frame until Anims.done.
function Anims.step()
    if Anims.done then return end
    for _ = 1, PER_FRAME do
        local animID = wanted[Anims.scanned + 1]
        if animID == nil then
            Anims.done = true
            return
        end
        Anims.scanned = Anims.scanned + 1
        local own = Anims.scanned > ownFrom
        -- (an id the game no longer has is skipped)
        local ok, name = pcall(function() return config.Seq.FromID(animID).configName end)
        if ok and type(name) == "string" and name ~= "" then
            local label = name .. " (" .. animID .. ")"
            Anims.list[#Anims.list + 1] = { id = animID, name = name, label = label, search = label:lower(), own = own }
        end
    end
end

-- The animation with this id, or nil.
function Anims.find(animID)
    for _, anim in ipairs(Anims.list) do
        if anim.id == animID then return anim end
    end
    return nil
end

-- The name of the animation with this id, or nil.
function Anims.nameOf(animID)
    local ok, name = pcall(function() return config.Seq.FromID(animID).configName end)
    return ok and type(name) == "string" and name or nil
end

-- The id of the animation with this name, or nil.
function Anims.idOf(name)
    local ok, animID = pcall(function() return config.Seq[name].id end)
    return ok and tonumber(animID) or nil
end

-- The chat head animations' names start with one of these (own head, NPC head).
Anims.PREFIX_OWN, Anims.PREFIX_NPC = "HUMAN_ACTOR_CHATHEAD", "HUMAN_UPDATE_CHATHEAD"

-- Words that mean the same in the two kinds' names (each is read as the one it maps to), as found in the
-- game's names: HUMAN_ACTOR_CHATHEAD_<EMOTION>[_<SUBTLE|STANDARD|EXTREME>] against
-- HUMAN_UPDATE_CHATHEAD_<EMOTION>[_<SUBTLE|NORMAL|EXTREME>][_LEN1..4 | _LEN_ALL | _LOOP].
local SAME_WORD = {
    SURPRISED = "SHOCK", DISGUSTED = "DISGUST", SCARED = "FEAR", SLEEPING = "SLEEP", NORMAL = "STANDARD",
}
-- Words left out: STANDARD is the intensity most animations have (those with none stand for it too: ACTOR
-- BORED_STANDARD is UPDATE BORED), TEMP marks an unfinished version (ACTOR HAPPY_SUBTLE_TEMP).
local DROPPED_WORD = { STANDARD = true, TEMP = true }
-- Whole names that differ (ACTOR IDLE_STANDARD is UPDATE NEUTRAL_IDLE; UPDATE NEUTRAL_TALK is read as NEUTRAL,
-- whose match is NEUTRAL_STANDARD).
local SAME_KEY = { IDLE = "NEUTRAL_IDLE", NEUTRAL_TALK = "NEUTRAL" }

-- A chat head animation's name after its prefix, without the endings _LEN<n>, _LEN_ALL and _LOOP (in any
-- order), and the number n of the _LEN<n> ending if it had one.
local function stripped(rest)
    rest = rest:gsub("^_", "")
    local length = nil
    local changed = true
    while changed do
        changed = false
        for _, ending in ipairs({ "_LEN_ALL", "_LOOP", "_LEN(%d+)" }) do
            for _, pattern in ipairs({ "_" .. ending:sub(2) .. "$", "^" .. ending:sub(2) .. "$" }) do
                local n = rest:match(pattern)
                if rest:find(pattern) then
                    if ending == "_LEN(%d+)" then length = length or tonumber(n) end
                    rest = rest:gsub(pattern, "")
                    changed = true
                end
            end
        end
    end
    return rest, length
end

-- What two animations' names have in common if they are the same expression in the two kinds: the name
-- after the prefix and without its endings, with the words that mean the same read as one (SAME_WORD,
-- DROPPED_WORD, SAME_KEY). Nil if the name isn't a chat head animation's (of either kind).
function Anims.keyOf(name)
    for _, prefix in ipairs({ Anims.PREFIX_OWN, Anims.PREFIX_NPC }) do
        if name:sub(1, #prefix) == prefix and (#name == #prefix or name:sub(#prefix + 1, #prefix + 1) == "_") then
            local rest = stripped(name:sub(#prefix + 1))
            local words = {}
            for word in rest:gmatch("[^_]+") do
                local same = SAME_WORD[word] or word
                if not DROPPED_WORD[same] then words[#words + 1] = same end
            end
            local key = table.concat(words, "_")
            return SAME_KEY[key] or key
        end
    end
    return nil
end

-- Which kind a chat head animation's name is of: the prefix it starts with, or nil.
function Anims.prefixOf(name)
    for _, prefix in ipairs({ Anims.PREFIX_OWN, Anims.PREFIX_NPC }) do
        if name:sub(1, #prefix) == prefix and (#name == #prefix or name:sub(#prefix + 1, #prefix + 1) == "_") then
            return prefix
        end
    end
    return nil
end

-- Of several animations with one label, the one used: the first take (_LEN1), else the plain name, else
-- the one for any length (_LEN_ALL), else a loop.
local function rank(name)
    if name:find("_LEN1$") then return 1 end
    if name:find("_LEN_ALL$") then return 3 end
    if name:find("_LOOP$") then return 4 end
    return 2
end

-- STANDARD and NORMAL are shown only where the animation has other intensities (SUBTLE or EXTREME): HAPPY
-- STANDARD stays beside HAPPY SUBTLE, but BORED STANDARD is shown as BORED.
local INTENSITY = { SUBTLE = true, EXTREME = true, STANDARD = true, NORMAL = true }

-- A name (words joined by underscores) split into the name without its intensity word and that word, or the
-- name and nil if it has none.
local function splitIntensity(text)
    local words, found = {}, nil
    for word in text:gmatch("[^_]+") do
        if found == nil and INTENSITY[word] then found = word else words[#words + 1] = word end
    end
    return table.concat(words, "_"), found
end

local intensities = { count = -1, set = {} } -- "<prefix or other>:<stem>" -> true, for the SUBTLE/EXTREME ones

-- Whether an animation of this kind (chat head prefix, or "other") and name without intensity has a SUBTLE or
-- EXTREME version.
local function hasOtherIntensity(kind, stem)
    if intensities.count ~= #Anims.list then
        intensities.count, intensities.set = #Anims.list, {}
        for _, anim in ipairs(Anims.list) do
            local name = anim.name
            if name:find("SUBTLE", 1, true) or name:find("EXTREME", 1, true) then
                local prefix = Anims.prefixOf(name)
                local rest = stripped(prefix and name:sub(#prefix + 1) or name)
                local other, word = splitIntensity(rest)
                if word == "SUBTLE" or word == "EXTREME" then intensities.set[(prefix or "other") .. ":" .. other] = true end
            end
        end
    end
    return intensities.set[kind .. ":" .. stem] == true
end

-- A label (underscores) of the given kind without STANDARD or NORMAL if the animation has no other
-- intensities; else as it is.
local function withoutPlainIntensity(kind, label)
    local stem, word = splitIntensity(label)
    if (word == "STANDARD" or word == "NORMAL") and stem ~= "" and not hasOtherIntensity(kind, stem) then
        return stem
    end
    return label
end

local chatheadCache = {} -- prefix -> { count = animations read when made, list }

-- The chat head animations: those whose names start with `prefix`, as { id, label, key } sorted by label.
-- The label is the name without the prefix and without the endings _LEN<n>, _LEN_ALL and _LOOP; names
-- ending _LEN2 or more (longer takes of the same animation) are left out.
function Anims.chatheads(prefix)
    local cached = chatheadCache[prefix]
    if cached ~= nil and cached.count == #Anims.list then return cached.list end
    local found, byLabel = {}, {}
    for _, anim in ipairs(Anims.list) do
        local name = anim.name
        if Anims.prefixOf(name) == prefix then
            local label, length = stripped(name:sub(#prefix + 1))
            if length == nil or length <= 1 then
                if label == "" then label = prefix:match("[^_]+$") end
                local entry = byLabel[label]
                if entry == nil then
                    entry = { id = anim.id, label = label, key = Anims.keyOf(name), rank = rank(name) }
                    byLabel[label] = entry
                    found[#found + 1] = entry
                elseif rank(name) < entry.rank then
                    entry.id, entry.rank = anim.id, rank(name)
                end
            end
        end
    end
    -- (STANDARD/NORMAL hidden last, unless that would give two the same label)
    local taken = {}
    for _, entry in ipairs(found) do taken[entry.label] = true end
    for _, entry in ipairs(found) do
        local shorter = withoutPlainIntensity(prefix, entry.label)
        if shorter ~= entry.label and not taken[shorter] then
            taken[shorter] = true
            entry.label = shorter
        end
    end
    table.sort(found, function(a, b) return a.label < b.label end)
    chatheadCache[prefix] = { count = #Anims.list, list = found }
    return found
end

-- The chat head animation of this kind (prefix) for the same expression as `key` (Anims.keyOf), or nil.
function Anims.matching(prefix, key)
    local best = nil
    for _, anim in ipairs(Anims.chatheads(prefix)) do
        if anim.key == key and (best == nil or anim.rank < best.rank) then best = anim end
    end
    return best
end

-- What the searchable list shows for an animation, worked out once and kept on it: base (the name without
-- the endings _LEN<n>, _LEN_ALL and _LOOP), length (the n of a _LEN<n> ending), text (the name without a chat
-- head prefix, underscores as spaces) and kind ("player" or "npc" for a chat head animation).
local function describe(anim)
    if anim.base ~= nil then return end
    local base, length = stripped(anim.name)
    anim.base, anim.length = base, length
    local text = base
    local prefix = Anims.prefixOf(base)
    if prefix ~= nil then
        text = base:sub(#prefix + 1):gsub("^_", "")
        if text == "" then text = prefix:match("[^_]+$") end
        anim.kind = prefix == Anims.PREFIX_OWN and "player" or "npc"
    end
    text = withoutPlainIntensity(prefix or "other", text)
    anim.text = text:gsub("_", " ")
    if anim.id ~= nil and Labels[anim.id] ~= nil then anim.text = Labels[anim.id] end
end

-- The name of the animation with this id as the lists show it (see Anims.search, without the kind added to
-- tell two apart), or nil if it has no name.
function Anims.displayName(animID)
    local name = Anims.nameOf(animID)
    if name == nil then return nil end
    local anim = { name = name, id = animID }
    describe(anim)
    return anim.text
end

-- Up to `limit` animations whose name or id contains every word of the query (spaces and underscores both
-- separate words, so "chat happy" finds CHAT_HAPPY), as { id, label }. Of those for the player's own head if
-- `own`, else of those for NPC heads. The same hiding as the chat head
-- animations: no chat head prefix, no _LEN<n>, _LEN_ALL or _LOOP endings, names ending _LEN2 or more left
-- out, one of the animations that differ only by those endings (the first take, see rank), and underscores
-- as spaces. Where a chat head animation for the player's head and one for an NPC's would read the same, the
-- kind is added: "(player)" or "(npc)".
function Anims.search(query, limit, own)
    local words = {}
    for word in tostring(query or ""):lower():gmatch("[^%s_]+") do words[#words + 1] = word end
    local found, byBase = {}, {}
    for _, anim in ipairs(Anims.list) do
        local matches = (anim.own == true) == (own == true)
        for _, word in ipairs(words) do
            if not anim.search:find(word, 1, true) then matches = false break end
        end
        if matches then
            describe(anim)
            if anim.length == nil or anim.length <= 1 then
                local entry = byBase[anim.base]
                if entry == nil then
                    if #found >= limit then break end
                    entry = { id = anim.id, rank = rank(anim.name), anim = anim }
                    byBase[anim.base] = entry
                    found[#found + 1] = entry
                elseif rank(anim.name) < entry.rank then
                    entry.id, entry.rank = anim.id, rank(anim.name)
                end
            end
        end
    end
    local count = {}
    for _, entry in ipairs(found) do count[entry.anim.text] = (count[entry.anim.text] or 0) + 1 end
    for _, entry in ipairs(found) do
        local anim = entry.anim
        entry.label = anim.text
        if count[anim.text] > 1 and anim.kind ~= nil then entry.label = anim.text .. " (" .. anim.kind .. ")" end
    end
    return found
end

return Anims
