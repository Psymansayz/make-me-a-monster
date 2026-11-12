-- TEMPORARY debug window for grouping heads by hand. It shows the listed heads sorted by their models, and logs
-- these lines, which tools/apply_grouping_log.py saves in src/data/head_groups.lua:
-- HEADGROUP|group|line/lines|id=Name@CONSTANT~id=Name@CONSTANT...
-- HEADDUPLICATES|batch|line/lines|id=Name@CONSTANT~id=Name@CONSTANT...
-- HEADDUPLICATEOF|batch|id=Name@CONSTANT

local HeadFilter = require("src/game/head_filter")
local HeadFlaggingWindow = require("src/debug/head_flagging_window")
local HeadGroups = require("src/data/head_groups")
local Animations = require("src/game/animations")

local HeadGroupingWindow = {}

local LINE_LENGTH = 860 -- a long selection is split into lines of this length
local MIN_WIDTH = 980 -- room for both log buttons and the page label in the bottom row
local LINES_PER_PRESS = 800 -- the console keeps about 1000 lines, so the duplicates may take several presses

local timesLogged = { HEADGROUP = HeadGroups.groupsLogged, HEADDUPLICATES = HeadGroups.batchesLogged }
local isLogged = {} -- npc id -> true if left out of the window: logged, or in a saved group but not its shown head
local isGrouped = {} -- npc id -> true when in a saved group
local isGroupShownHead = {} -- npc id -> true when it is the head shown for a group
for _, group in ipairs(HeadGroups.groups) do
    isGroupShownHead[group[1][1]] = true
    for _, record in ipairs(group) do isGrouped[record[1]] = true end
end
-- A head can be in several groups, and it leaves the window only if none of them shows it.
for npcID in pairs(isGrouped) do
    if not isGroupShownHead[npcID] then isLogged[npcID] = true end
end
local exactDuplicateBatches, nextExactBatch = nil, 1 -- found on the first press, once per reload
local batchAwaitingOriginal = nil -- the batch whose original the next click picks; kept if the window closes

local function recordOf(npcID, nameOf)
    return ("%d=%s@%s"):format(npcID, nameOf(npcID) or "?", config.NPC.FromID(npcID).configName)
end

local function logLines(tag, selected, nameOf)
    if #selected == 0 then return {} end
    timesLogged[tag] = timesLogged[tag] + 1
    local packedLines, current, length = {}, {}, 0
    for _, npcID in ipairs(selected) do
        isLogged[npcID] = true
        local record = recordOf(npcID, nameOf)
        if length + #record + 1 > LINE_LENGTH then
            packedLines[#packedLines + 1] = table.concat(current, "~")
            current, length = {}, 0
        end
        current[#current + 1], length = record, length + #record + 1
    end
    packedLines[#packedLines + 1] = table.concat(current, "~")
    local lines = {}
    for position, packedLine in ipairs(packedLines) do
        lines[position] = ("%s|%d|%d/%d|%s"):format(tag, timesLogged[tag], position, #packedLines, packedLine)
    end
    return lines
end

-- Which head of a sorted selection stays in the window, so that logging more heads for a group keeps its head.
local function headToKeep(selected)
    for _, npcID in ipairs(selected) do
        if isGroupShownHead[npcID] then return npcID end
    end
    return selected[1]
end

-- Which head of a look to keep: first one on the player's rig, since it has its own animations, then one in a saved
-- group, then the lowest id.
local function keepRank(npcID)
    return Animations.headsOnPlayerRig[npcID] and 1 or isGrouped[npcID] and 2 or 3
end

-- Every look shared by more than one head, sorted by the original's id: { { original, duplicates = { id... } }... }.
local function findExactDuplicates(heads)
    local headsOfLook, looks, unread, withRecolourTargets = {}, {}, 0, 0
    for _, npcID in ipairs(heads) do
        local look = HeadFilter.describeHead(npcID)
        -- Unreadable heads all get the same description, so they must not count as one look.
        if look:find("^unreadable") or look == "no customisation" or look:find("modelList=[]", 1, true) then
            unread = unread + 1
        else
            if look:find("recolourDest=[1=", 1, true) then withRecolourTargets = withRecolourTargets + 1 end
            if headsOfLook[look] == nil then
                headsOfLook[look] = {}
                looks[#looks + 1] = look
            end
            table.insert(headsOfLook[look], npcID)
        end
    end
    local batches, duplicateCount = {}, 0
    for _, look in ipairs(looks) do
        local sameLook = headsOfLook[look]
        if #sameLook > 1 then
            table.sort(sameLook, function(firstHead, secondHead)
                local firstRank, secondRank = keepRank(firstHead), keepRank(secondHead)
                if firstRank ~= secondRank then return firstRank < secondRank end
                return firstHead < secondHead
            end)
            local duplicates = { table.unpack(sameLook, 2) }
            table.sort(duplicates)
            batches[#batches + 1] = { original = sameLook[1], duplicates = duplicates }
            duplicateCount = duplicateCount + #duplicates
        end
    end
    table.sort(batches, function(firstBatch, secondBatch) return firstBatch.original < secondBatch.original end)
    print(("[make_me_a_monster] EXACTDUPLICATES|%d heads, %d not read, %d with recolour targets, %d looks, "
        .. "%d duplicates in %d batches"):format(#heads, unread, withRecolourTargets, #looks, duplicateCount, #batches))
    return batches
end

function HeadGroupingWindow.logExactDuplicates(heads, nameOf)
    if exactDuplicateBatches == nil then exactDuplicateBatches = findExactDuplicates(heads) end
    local linesLogged = 0
    while nextExactBatch <= #exactDuplicateBatches and linesLogged < LINES_PER_PRESS do
        local batch = exactDuplicateBatches[nextExactBatch]
        nextExactBatch = nextExactBatch + 1
        local lines = logLines("HEADDUPLICATES", batch.duplicates, nameOf)
        lines[#lines + 1] = ("HEADDUPLICATEOF|%d|%s"):format(timesLogged.HEADDUPLICATES,
            recordOf(batch.original, nameOf))
        for _, line in ipairs(lines) do print("[make_me_a_monster] " .. line) end
        linesLogged = linesLogged + #lines
    end
    return nextExactBatch - 1, #exactDuplicateBatches
end

function HeadGroupingWindow.open(PrettyUI, parent, heads, nameOf, animationFor)
    local sortedHeads, modelsOf = {}, {}
    for _, npcID in ipairs(heads) do
        if not isLogged[npcID] then
            sortedHeads[#sortedHeads + 1], modelsOf[npcID] = npcID, HeadFilter.headModels(npcID)
        end
    end
    -- Compares the model lists in order, which keeps heads built from the same models together.
    table.sort(sortedHeads, function(firstHead, secondHead)
        local firstModels, secondModels = modelsOf[firstHead], modelsOf[secondHead]
        for position = 1, math.max(#firstModels, #secondModels) do
            local firstModel, secondModel = firstModels[position] or -1, secondModels[position] or -1
            if firstModel ~= secondModel then return firstModel < secondModel end
        end
        return firstHead < secondHead
    end)
    -- TEMPORARY: shows in the console whether the saved groups reach the window.
    print(("[make_me_a_monster] HEADGROUPS|%d saved groups, showing %d of %d heads"):format(#HeadGroups.groups,
        #sortedHeads, #heads))
    return HeadFlaggingWindow.open(PrettyUI, parent, sortedHeads, nameOf, animationFor, {
        title = "Debug: all heads by model (select heads, then Log group or Log duplicates)",
        minWidth = MIN_WIDTH,
        logButton = "Log group",
        removeOnLog = true,
        quietClicks = true, -- the console keeps about 1000 lines, so they are saved for the groups
        idText = function(npcID) return ("ID %d, model %s"):format(npcID, modelsOf[npcID][1] or "?") end,
        firstLogKeeps = headToKeep,
        flaggedLines = function(selected)
            local lines = logLines("HEADGROUP", selected, nameOf)
            if #selected > 0 then
                local keptHead = headToKeep(selected)
                isLogged[keptHead], isGroupShownHead[keptHead] = nil, true
            end
            return lines
        end,
        secondLogButton = "Log duplicates",
        secondFlaggedLines = function(selected)
            if #selected > 0 then batchAwaitingOriginal = timesLogged.HEADDUPLICATES + 1 end
            return logLines("HEADDUPLICATES", selected, nameOf)
        end,
        headClicked = function(npcID)
            if batchAwaitingOriginal == nil then return false end
            print(("[make_me_a_monster] HEADDUPLICATEOF|%d|%s"):format(batchAwaitingOriginal, recordOf(npcID, nameOf)))
            batchAwaitingOriginal = nil
            return true
        end,
        labelNote = function() return batchAwaitingOriginal and "Click the original" or nil end,
    })
end

return HeadGroupingWindow
