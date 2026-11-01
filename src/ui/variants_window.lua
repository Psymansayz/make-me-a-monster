-- The "variants" window: the heads of every NPC sharing the chosen one's name, in a 3x3 grid (src/ui/head_grid.lua);
-- with the player's own head in use, just that head (VariantsWindow.PLAYER_HEAD_ID).
-- VariantsWindow.open(PrettyUI, parent, title, variantIDs, current, onPick, labelFor) opens the window or gives the
-- open one these heads; close(); isOpen(); updateAnimations(); refreshHeadSize().

local Settings = require("src/data/settings")
local HeadGrid = require("src/ui/head_grid")

local VariantsWindow = {}

VariantsWindow.animationForNpcHeads = nil -- function(npcID) -> the animation id this NPC head should play, or nil
VariantsWindow.animationForPlayerHead = nil -- function() -> the animation id the player's own head should play, or nil
VariantsWindow.PLAYER_HEAD_ID = -1 -- the id standing for the player's own head (as the game's, for the local player)

local grid = nil -- the HeadGrid while the window is open

local function isPlayerHead(npcID)
    return npcID == VariantsWindow.PLAYER_HEAD_ID
end

local function animationFor(npcID)
    local animFor = isPlayerHead(npcID) and VariantsWindow.animationForPlayerHead or VariantsWindow.animationForNpcHeads
    return animFor and animFor(npcID) or nil
end

function VariantsWindow.isOpen()
    return grid ~= nil
end

function VariantsWindow.updateAnimations()
    if grid then grid:updateAnimations() end
end

function VariantsWindow.refreshHeadSize()
    if grid then grid:refreshHeadSize() end
end

function VariantsWindow.close()
    if grid then grid:close() end
end

function VariantsWindow.open(PrettyUI, parent, title, variantIDs, current, onPick, labelFor)
    local function nameOf(npcID) return labelFor and labelFor(npcID) or nil end
    -- Already open: the window shows these variants instead (its cells are reused, as for a page change).
    if grid then
        grid.onPick, grid.nameOf = onPick, nameOf
        grid:setHeads(variantIDs, current, title)
        return true
    end
    grid = HeadGrid.open(PrettyUI, parent, {
        title = title, columns = 3, rows = 3,
        ids = variantIDs, current = current,
        savedWidth = Settings.variantsWidth, savedHeight = Settings.variantsHeight,
        savedX = Settings.variantsX, savedY = Settings.variantsY,
        nameOf = nameOf, isPlayerHead = isPlayerHead, animationFor = animationFor,
        pageLabel = function(page, pages, shown)
            return ("Page %d of %d (%d variants)"):format(page, pages, shown)
        end,
        onPick = onPick,
        onPlacement = function(width, height, x, y)
            Settings.variantsWidth, Settings.variantsHeight = width, height
            Settings.variantsX, Settings.variantsY = x, y
        end,
        onClosed = function() grid = nil end,
    })
    return grid ~= nil
end

return VariantsWindow
