-- The "variants" window: the heads in one group of the chosen NPC, in a 3x3 grid, with a button to the NPC's next
-- group if it is in several. With the player's own head in use, it shows just that head.

local Settings = require("src/data/settings")
local AnimationChoice = require("src/game/animation_choice")
local HeadGrid = require("src/ui/head_grid")

local VariantsWindow = {}

VariantsWindow.PLAYER_HEAD_ID = -1 -- stands for the player's own head; it is the game's id for the local player

local grid = nil
HeadGrid.addWindowFunctions(VariantsWindow, function() return grid end)
local onButton = nil
local groupJustSelected = false -- a head was just selected under a group's name, so the last page doesn't apply

local MIN_WIDTH = 640 -- room for Previous, Next, the longest button text and the page label in the bottom row

-- How a group is saved. Several groups can share a name, so its size tells them apart.
local function savedGroupOf(npcGroup)
    return npcGroup.name .. "|" .. npcGroup.idCount
end

-- The group and page the window opens on for this NPC: the group it was just selected under, or the group and page
-- last open if this NPC was chosen then, or its smallest group.
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

-- Called when this NPC is selected under this group's name, so that the window opens on that group next.
function VariantsWindow.selectGroup(npcID, npcGroup)
    VariantsWindow.remember(npcID, npcGroup)
    Settings.variantsPage, groupJustSelected = nil, true
end

function VariantsWindow.remember(npcID, npcGroup)
    Settings.variantsNpcID, Settings.variantsGroup = npcID, savedGroupOf(npcGroup)
end

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

-- options: title, ids, current, onPick(id) and an optional nameOf(id). page is the page to show, or nil for the one
-- holding current. buttonText and onButton() make a button under the heads, which is hidden while buttonText is nil.
function VariantsWindow.open(PrettyUI, parent, options)
    onButton = options.onButton
    local nameOf = options.nameOf or function() return nil end
    -- If the window is already open, its cells are reused, as they are for a page change.
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
            -- With the player's own head in use, the page shown isn't the remembered NPC's page.
            if Settings.chosenNpcID ~= nil then Settings.variantsPage = grid.page end
            grid = nil
        end,
    })
end

return VariantsWindow
