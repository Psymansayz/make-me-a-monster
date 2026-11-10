-- The "variants" window: the heads of a group of the NPC chosen, in a 3x3 grid, and a button to its next group if it is
-- in several; with the player's own head in use, just that head.

local Settings = require("src/data/settings")
local AnimationChoice = require("src/game/animation_choice")
local HeadGrid = require("src/ui/head_grid")

local VariantsWindow = {}

VariantsWindow.PLAYER_HEAD_ID = -1 -- the id standing for the player's own head (as the game's, for the local player)

local grid = nil -- the HeadGrid while the window is open
HeadGrid.addWindowFunctions(VariantsWindow, function() return grid end)
local onButton = nil -- what the button under the heads does
local groupJustSelected = false -- a head was selected under a group's name: the page last open no longer counts

local MIN_WIDTH = 640 -- (room for Previous, Next, the longest button text and the page label in the bottom row)

-- A group as saved: several can have one name, which of the head's groups it is then goes by its size too.
local function savedGroupOf(npcGroup)
    return npcGroup.name .. "|" .. npcGroup.idCount
end

-- What the window opens on for this NPC: the group it was just selected under; else the group and page last open if it
-- was the one chosen then; else its smallest group.
function VariantsWindow.firstView(npcID, groups)
    local justSelected = groupJustSelected
    groupJustSelected = false
    if npcID == Settings.variantsNpcID then
        for _, npcGroup in ipairs(groups) do
            if savedGroupOf(npcGroup) == Settings.variantsGroup then
                if justSelected then return npcGroup, nil end
                return npcGroup, grid and grid.page or Settings.variantsPage
            end
        end
    end
    return groups[1], nil
end

-- This NPC was selected under this group's name: the window opens on it next.
function VariantsWindow.selectGroup(npcID, npcGroup)
    VariantsWindow.remember(npcID, npcGroup)
    Settings.variantsPage, groupJustSelected = nil, true
end

function VariantsWindow.remember(npcID, npcGroup)
    Settings.variantsNpcID, Settings.variantsGroup = npcID, savedGroupOf(npcGroup)
end

-- No text, no button.
function VariantsWindow.setButton(text)
    if VariantsWindow.isOpen() then grid:setExtraButton(text) end
end

local function isPlayerHead(npcID)
    return npcID == VariantsWindow.PLAYER_HEAD_ID
end

local function animationFor(npcID)
    if isPlayerHead(npcID) then return AnimationChoice.playerHeadAnimation(true) end
    return AnimationChoice.npcHeadAnimation(npcID)
end

-- options: title, ids, current, onPick(id), nameOf(id) (or none), page (else that of current), buttonText and
-- onButton() (the button under the heads; no text, no button).
function VariantsWindow.open(PrettyUI, parent, options)
    onButton = options.onButton
    local nameOf = options.nameOf or function() return nil end
    -- Already open: its cells are reused, as for a page change.
    if VariantsWindow.isOpen() then
        grid.onPick, grid.nameOf = options.onPick, nameOf
        grid:setHeads(options.ids, options.current, options.title, options.page)
        grid:setExtraButton(options.buttonText)
        return
    end
    grid = HeadGrid.open(PrettyUI, parent, {
        title = options.title, columns = 3, rows = 3, minWidth = MIN_WIDTH,
        ids = options.ids, current = options.current, page = options.page,
        extraButton = { text = options.buttonText, onClick = function() if onButton then onButton() end end },
        placement = Settings.windows.variants,
        nameOf = nameOf, isPlayerHead = isPlayerHead, animationFor = animationFor,
        pageLabel = function(page, pages, shown)
            return ("Page %d of %d (%d variants)"):format(page, pages, shown)
        end,
        onPick = options.onPick,
        onClosed = function()
            -- (with the player's own head in use, the page is not that of the NPC remembered)
            if Settings.chosenNpcID ~= nil then Settings.variantsPage = grid.page end
            grid = nil
        end,
    })
end

return VariantsWindow
