-- Debug only: for each race or character with chat animations of its own (src/data/dedicated_animations.lua), one
-- of its heads twice: the human animation for an emotion on the left, its own animation on the right. Every few
-- seconds the next animation plays, on the next of the set's heads. A page per set. A model number entered holds
-- that head (the animations go on) until "Cycle models". Clicking a head logs it (DEDICATED|head|), for tracking
-- broken heads in a set that works.

local HeadGrid = require("src/ui/head_grid")
local Blacklist = require("src/data/head_blacklist")
local DedicatedAnimations = require("src/data/dedicated_animations")

local DedicatedAnimationsWindow = {}

local grid = nil -- the HeadGrid while the window is open
HeadGrid.addWindowFunctions(DedicatedAnimationsWindow, function() return grid end)

-- The client has no clock: so the animations change on server ticks (0.6 s each), 3 of them about every 2 seconds.
local TICKS_PER_ANIMATION = 3
local TICK_SUBSCRIPTION = "make_me_a_monster_dedicated_tick"
local CELL_W, CELL_H = 300, 330 -- (room for the longest animation name under a head)

-- { name, page, heads = { npc id... }, pairs = { { humanID, ownID, humanName, ownName }... } }, once read
local sets = nil
local headIDs = nil -- the grid's ids: each set's head shown, twice
local shownSet, step, headIndex, ticks = nil, 1, 1, 0
local headHeld = false -- a model was jumped to: the heads stop cycling
local RESUME_TEXT = "Cycle models"
local placement = {} -- the window's size and position, kept while the plugin runs
local blacklisted = {} -- npc id -> the blacklist's group holding it
local BLANK = "blank"
local NO_HUMAN = "(no human match)" -- the left head's label when the emotion has no human animation

local function readBlacklist()
    for _, groupName in ipairs({ BLANK, "identical", "manual" }) do
        for _, npcID in ipairs(Blacklist[groupName]) do blacklisted[npcID] = groupName end
    end
end

-- Each set's heads: those the game knows, without blank ones (the blacklist may have grown since the data was made);
-- a set whose heads are all blank keeps its first.
local function readSets()
    readBlacklist()
    local missing = {}
    sets = {}
    for _, saved in ipairs(DedicatedAnimations) do
        local heads, firstKnown = {}, nil
        for _, npcName in ipairs(saved.heads) do
            local npcID = id.NPC[npcName]
            if npcID >= 0 then
                firstKnown = firstKnown or npcID
                if blacklisted[npcID] ~= BLANK then heads[#heads + 1] = npcID end
            else
                missing[#missing + 1] = npcName
            end
        end
        if #heads == 0 then heads[1] = firstKnown end
        local animationPairs = {}
        -- Every dedicated animation is shown: one without a human animation for its emotion has none on the left.
        for _, entry in ipairs(saved.animations) do
            local humanName, ownName = entry[3], entry[1]
            local humanID, ownID = humanName and id.Seq[humanName], id.Seq[ownName]
            if humanID ~= nil and humanID < 0 then
                missing[#missing + 1] = humanName
                humanID = nil
            end
            if ownID >= 0 then
                animationPairs[#animationPairs + 1] = { humanID, ownID, humanID and humanName or NO_HUMAN, ownName }
            else
                missing[#missing + 1] = ownName
            end
        end
        if #heads > 0 and #animationPairs > 0 then
            sets[#sets + 1] = { name = saved.name, page = #sets + 1, heads = heads, pairs = animationPairs }
        else
            missing[#missing + 1] = "(set " .. saved.name .. ")"
        end
    end
    if #missing > 0 then print("[make_me_a_monster] DEDICATED|unknown|" .. table.concat(missing, " ")) end
end

-- The set's page shows this head of it.
local function showHead(set, index)
    headIDs[set.page * 2 - 1], headIDs[set.page * 2] = set.heads[index], set.heads[index]
end

local function titleOf(set)
    local npcID = set.heads[headIndex]
    return ("Debug: dedicated animations - %s - model %d of %d%s: %s (ID %d%s)"):format(set.name, headIndex,
        #set.heads, headHeld and " (held)" or "", tostring(id.NPC.FromID(npcID)), npcID,
        blacklisted[npcID] and (", " .. blacklisted[npcID]) or "")
end

-- Two heads a set: the left one plays the human animation. A set shown again starts from its first animation and
-- head; the set left goes back to its first head, so its page is filled with it when it comes back.
local function pairAt(position)
    local set, isHuman = sets[math.ceil(position / 2)], position % 2 == 1
    if set ~= shownSet then
        if shownSet ~= nil then showHead(shownSet, 1) end
        shownSet, step, headIndex, ticks, headHeld = set, 1, 1, 0, false
        if grid then
            grid.window:SetTitle(titleOf(set))
            grid:setExtraButton(nil)
        end
    end
    return set.pairs[step], isHuman
end

local function onTick()
    ticks = ticks + 1
    if ticks < TICKS_PER_ANIMATION then return end
    ticks = 0
    step = step % #shownSet.pairs + 1
    if not headHeld then headIndex = headIndex % #shownSet.heads + 1 end
    showHead(shownSet, headIndex)
    grid.window:SetTitle(titleOf(shownSet))
    grid:showPage()
    grid:updateAnimations()
end

-- Holds the set's head with this number (kept within the set); the animations go on cycling.
local function jumpToModel(number)
    headIndex, headHeld = math.max(1, math.min(#shownSet.heads, number)), true
    showHead(shownSet, headIndex)
    grid.window:SetTitle(titleOf(shownSet))
    grid:setExtraButton(RESUME_TEXT)
    grid:showPage()
    grid:updateAnimations()
end

-- The heads cycle again, on from the one held.
local function resumeCycling()
    headHeld = false
    grid.window:SetTitle(titleOf(shownSet))
    grid:setExtraButton(nil)
end

local function logHead(npcID)
    local pair = shownSet.pairs[step]
    print(("[make_me_a_monster] DEDICATED|head|%s|%d|%s|model %d of %d|%s|%s|%s"):format(shownSet.name, npcID,
        tostring(id.NPC.FromID(npcID)), headIndex, #shownSet.heads, blacklisted[npcID] or "listed", pair[3], pair[4]))
end

function DedicatedAnimationsWindow.open(PrettyUI, parent)
    if grid then
        grid.window:Show()
        return true
    end
    if sets == nil then readSets() end
    if #sets == 0 then return false end
    headIDs = {}
    for _, set in ipairs(sets) do showHead(set, 1) end
    shownSet = nil
    grid = HeadGrid.open(PrettyUI, parent, {
        title = "Debug: dedicated animations", columns = 2, rows = 1, ids = headIDs, page = placement.page,
        minWidth = 2 * 260, -- (room for Previous, Next, the model box, the button and the label)
        numberBox = { placeholder = "Model", onSubmit = jumpToModel },
        extraButton = { text = nil, onClick = resumeCycling },
        savedWidth = placement.width or (2 * CELL_W + 38), savedHeight = placement.height or (CELL_H + 96),
        savedX = placement.x, savedY = placement.y,
        nameOf = function(_, position)
            local pair, isHuman = pairAt(position)
            return isHuman and pair[3] or pair[4]
        end,
        animationFor = function(_, position)
            local pair, isHuman = pairAt(position)
            if isHuman then return pair[1] end -- (nil without a human animation: the head plays nothing)
            return pair[2]
        end,
        pageLabel = function(page, pages)
            return ("Set %d of %d, animation %d of %d"):format(page, pages, step, #shownSet.pairs)
        end,
        onPick = logHead,
        onPlacement = function(width, height, x, y)
            placement.width, placement.height, placement.x, placement.y = width, height, x, y
        end,
        onClosed = function()
            Event.ServerLogic.Unsubscribe(TICK_SUBSCRIPTION)
            placement.page = grid.page
            grid = nil
        end,
    })
    if grid == nil then return false end
    grid.window:SetTitle(titleOf(shownSet))
    Event.ServerLogic.Subscribe(TICK_SUBSCRIPTION, onTick)
    return true
end

return DedicatedAnimationsWindow
