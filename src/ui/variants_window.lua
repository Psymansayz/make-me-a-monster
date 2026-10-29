-- The "variants" window: every NPC sharing the chosen NPC's name, as a 3x3 grid of their heads, a page at a
-- time. Clicking one picks it and closes the window. The window can be resized: the cells and the heads in
-- them grow and shrink with it.
--
-- Workaround: pages instead of scrolling: models in a scroll area aren't clipped by it, so they would draw
-- outside it.
-- Workaround: the window is closed from the next frame, not from the click that picked: a component isn't
-- destroyed inside its own click handler.
-- Workaround: a window's content size changes a moment after it is resized, so it is read every frame and the
-- cells are placed again when it differs.

local AllHeadsWindow = require("src/ui/all_heads_window")
local Settings = require("src/data/settings")

local VariantsWindow = {}

VariantsWindow.animationForNpcHeads = nil -- function() -> the animation id the NPC heads should play, or nil
VariantsWindow.animationForPlayerHead = nil -- function() -> the animation id the player's own head should play, or nil
VariantsWindow.PLAYER_HEAD_ID = -1 -- the id standing for the player's own head (as the game's, for the local player)

local COLUMNS, ROWS = 3, 3
local PAGE_SIZE = COLUMNS * ROWS
local PAD, GAP = 8, 6
local NAV_HEIGHT = 34
local NAV_BUTTON = 90 -- the width of the Previous and Next buttons
local MIN_CELL_W, MIN_CELL_H = 80, 100      -- and the least the window can be resized to
local BORDERS = 16                           -- the window's 8-wide borders, both sides
local TITLE_AND_BOTTOM = 40                  -- its title bar and bottom border
local BASE_VIEW = 2150 -- the game's usual view distance for a chat head, at BASE_SIZE units across
local BASE_SIZE = 160

local BACKGROUND = { 0.12, 0.09, 0.06, 1 }
local HOVER = { 0.30, 0.24, 0.14, 1 }
local CURRENT = { 0.55, 0.42, 0.14, 1 }
local TEXT_LIGHT = 0xE9E5DDFF

local windowState = nil -- { window, ids, page, pages, current, onPick, labelFor, cells, nav, layoutW, layoutH }

local function toColour(colourValues) return Vector4.new(colourValues[1], colourValues[2], colourValues[3], colourValues[4]) end

local function destroyCells()
    for _, headCell in ipairs(windowState.cells) do
        pcall(function() headCell.click:Destroy() end)
        pcall(function() headCell.label:Destroy() end)
        pcall(function() headCell.idLabel:Destroy() end)
        pcall(function() headCell.model:Destroy() end)
        pcall(function() headCell.background:Destroy() end)
    end
    windowState.cells = {}
end

-- A cell's background: the head in use gold, the others dark (lighter under the mouse).
local function paintCell(headCell, hovered)
    local colourValues = hovered and HOVER or (headCell.id == windowState.current and CURRENT or BACKGROUND)
    pcall(function() headCell.background.colour = toColour(colourValues) end)
end

-- A head clicked: it becomes the one in use, and the cells show which. (The window stays open.)
local function pickHead(npcID)
    if windowState == nil then return end
    windowState.current = npcID
    pcall(windowState.onPick, npcID)
    for _, headCell in ipairs(windowState.cells) do paintCell(headCell, headCell.id == npcID) end
end

-- The window's size, handed to the settings (to be remembered), if it can be read.
local function reportWindowPlacement(reportedState)
    if reportedState == nil or reportedState.window == nil then return end
    local root = reportedState.window.root
    local succeeded, width, height, x, y = pcall(function() return root.width, root.height, root.x, root.y end)
    if not succeeded then return end
    if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
        Settings.setVariantsSize(math.floor(width), math.floor(height))
    end
    if type(x) == "number" and type(y) == "number" then
        Settings.setVariantsPosition(math.max(0, math.floor(x)), math.max(0, math.floor(y)))
    end
end

-- The size of a cell and where the grid starts, for the window's content as it is now.
local function computeGeometry()
    local windowContent = windowState.window.content
    local width, height = windowContent.width, windowContent.height
    local cellW = math.max(40, math.floor((width - PAD * 2 - (COLUMNS - 1) * GAP) / COLUMNS))
    local cellH = math.max(60, math.floor((height - PAD * 2 - NAV_HEIGHT - 4 - (ROWS - 1) * GAP) / ROWS))
    local gridW = COLUMNS * cellW + (COLUMNS - 1) * GAP
    local gridH = ROWS * cellH + (ROWS - 1) * GAP
    return {
        width = width, height = height, cellW = cellW, cellH = cellH,
        originX = math.max(0, math.floor((width - gridW) / 2)), originY = PAD, gridH = gridH,
    }
end

-- The head size setting: how many times larger than normal the heads are drawn (1: normal).
local function currentHeadScale()
    return Settings.headScale
end

-- A cell's parts put in their places (and sized) for the geometry g.
local function placeCell(headCell, grid)
    local column, row = (headCell.index - 1) % COLUMNS, math.floor((headCell.index - 1) / COLUMNS)
    local x, y = grid.originX + column * (grid.cellW + GAP), grid.originY + row * (grid.cellH + GAP)
    local labels = headCell.idLabel and 36 or 22
    local headSize = math.max(16, math.min(grid.cellW - 8, grid.cellH - labels - 8))
    headCell.background:SetPos(x, y)
    headCell.background:SetSize(grid.cellW, grid.cellH)
    headCell.model:SetPos(x + math.floor((grid.cellW - headSize) / 2), y + 4)
    headCell.model:SetSize(headSize, headSize)
    headCell.model.viewDistance = math.max(1, math.floor(BASE_VIEW * BASE_SIZE / headSize / currentHeadScale()))
    headCell.label:SetPos(x, y + grid.cellH - labels)
    headCell.label:SetSize(grid.cellW, 16)
    if headCell.idLabel then
        headCell.idLabel:SetPos(x, y + grid.cellH - 20)
        headCell.idLabel:SetSize(grid.cellW, 16)
    end
    headCell.click:SetPos(x, y)
    headCell.click:SetSize(grid.cellW, grid.cellH)
end

-- The page label and the buttons put in their places for the geometry g.
local function placeNavigation(grid)
    local y = grid.originY + grid.gridH + 4
    pcall(function()
        local labelX = PAD + NAV_BUTTON + 6
        windowState.nav.label:SetPos(labelX, y + 6)
        windowState.nav.label:SetSize(math.max(1, grid.width - labelX * 2), 20)
    end)
    pcall(function() windowState.nav.buttons[1].root:SetPos(PAD, y) end)
    pcall(function() windowState.nav.buttons[2].root:SetPos(grid.width - PAD - NAV_BUTTON, y) end)
end

-- Everything put in its place for the window's size now.
local function layoutWindow()
    local succeeded, grid = pcall(computeGeometry)
    if not succeeded then return end
    windowState.layoutW, windowState.layoutH, windowState.layoutScale = grid.width, grid.height, currentHeadScale()
    for _, headCell in ipairs(windowState.cells) do pcall(placeCell, headCell, grid) end
    placeNavigation(grid)
end

-- A cell shown or hidden (all its parts).
local function setCellHidden(headCell, hidden)
    for _, cellPart in ipairs({ headCell.background, headCell.model, headCell.name, headCell.idLabel, headCell.click }) do
        pcall(function() cellPart.hidden = hidden end)
    end
end

-- One of the window's PAGE_SIZE cells, made once when the window opens and used for every page (see
-- src/ui/all_heads_window.lua). Empty until fillCell.
local function makeCell(position)
    local windowContent = windowState.window.content
    local headCell = { index = position }
    windowState.cells[#windowState.cells + 1] = headCell

    headCell.background = ui.Rectangle.new(windowContent)
    headCell.background.fill = true
    headCell.background.clickthrough = true

    headCell.model = ui.Model.new(windowContent)
    headCell.model.clickthrough = true

    local function makeTextLabel(labelText)
        local textLabel = ui.Text.new(windowContent)
        textLabel.maxLines = 1
        textLabel.font = id.Font.MUSEO_SANS_11PT_REGULAR
        textLabel.rgba = TEXT_LIGHT
        textLabel.alignHorizontal = ui.AlignMode.CENTRE
        textLabel.clickthrough = true
        textLabel.content = labelText
        return textLabel
    end
    headCell.label = makeTextLabel("")
    headCell.idLabel = makeTextLabel("")

    -- Over the rest, taking the click. (One handler per hook: a second default Subscribe replaces the first.)
    headCell.click = ui.Layer.new(windowContent)
    headCell.click.clickthrough = false
    headCell.click:Subscribe(ui.Hook.ONMOUSEOVER, function() paintCell(headCell, true) end)
    headCell.click:Subscribe(ui.Hook.ONMOUSELEAVE, function() paintCell(headCell, false) end)
    headCell.click:Subscribe(ui.Hook.ONCLICK, function() if headCell.id ~= nil then pickHead(headCell.id) end end)
    setCellHidden(headCell, true)
end

-- The cell showing this head (npcID, or VariantsWindow.PLAYER for the player's own).
local function fillCell(headCell, npcID)
    headCell.id = npcID
    local isPlayer = npcID == VariantsWindow.PLAYER_HEAD_ID
    headCell.model:SetModel(isPlayer and ui.ModelType.PLAYER_HEAD or ui.ModelType.NPC_HEAD, npcID)
    local animFor = isPlayer and VariantsWindow.animationForPlayerHead or VariantsWindow.animationForNpcHeads
    local animationID = animFor and animFor() or nil
    if animationID ~= nil then headCell.model.animID = animationID end
    -- The NPC's name, if it is told (an entry can hold several names), above its id.
    local nameText = (not isPlayer and windowState.labelFor) and windowState.labelFor(npcID) or nil
    headCell.label.content = isPlayer and "My head" or (nameText or ("ID " .. npcID))
    headCell.idLabel.content = nameText and ("ID " .. npcID) or ""
    setCellHidden(headCell, false)
    paintCell(headCell, false)
end

local function emptyCell(headCell)
    headCell.id = nil
    setCellHidden(headCell, true)
end

local function showPage()
    if not windowState.cellsMade then
        windowState.cellsMade = true
        for position = 1, PAGE_SIZE do
            pcall(makeCell, position)
        end
    end
    local firstHeadIndex = (windowState.page - 1) * PAGE_SIZE
    for _, headCell in ipairs(windowState.cells) do
        local npcID = windowState.ids[firstHeadIndex + headCell.index]
        if npcID == nil then
            emptyCell(headCell)
        else
            pcall(fillCell, headCell, npcID)
        end
    end
    pcall(function()
        windowState.nav.label.content = "Page " .. windowState.page .. " of " .. windowState.pages .. " (" .. #windowState.ids .. " variants)"
    end)
    layoutWindow()
    -- Previous and Next only where there is a page to go to; the others stay above the heads.
    local wanted = { windowState.page > 1, windowState.page < windowState.pages }
    for position, button in ipairs(windowState.nav.buttons) do
        pcall(function()
            button.root.hidden = not wanted[position]
            button.root:MoveToFront()
        end)
    end
end

-- Workaround: the page is changed from the next frame: the buttons that ask are not destroyed or rebuilt
-- during their own click.
local pendingPageChange = 0

local function applyPageChange()
    local pageChange = pendingPageChange
    pendingPageChange = 0
    if windowState == nil or pageChange == 0 then return end
    local page = math.max(1, math.min(windowState.pages, windowState.page + pageChange))
    if page == windowState.page then return end
    windowState.page = page
    showPage()
end

-- The heads shown play the animation now wanted (it was changed while the window is open).
function VariantsWindow.updateAnimations()
    if windowState == nil then return end
    for _, headCell in ipairs(windowState.cells) do
        if headCell.id ~= nil then
            pcall(function()
                local isPlayer = headCell.id == VariantsWindow.PLAYER_HEAD_ID
                local animFor = isPlayer and VariantsWindow.animationForPlayerHead or VariantsWindow.animationForNpcHeads
                local animationID = animFor and animFor() or nil
                if animationID ~= nil then
                    headCell.model.animID = animationID
                else
                    headCell.model:SetModel(isPlayer and ui.ModelType.PLAYER_HEAD or ui.ModelType.NPC_HEAD, headCell.id)
                end
            end)
        end
    end
end

function VariantsWindow.isOpen()
    return windowState ~= nil
end

-- Opens the window in `parent` for these NPC ids. current: the id active now (highlighted).
-- onPick(npcID) is called when a head is clicked (the window stays open, the head in use highlighted). labelFor(npcID), if given,
-- is the name shown under each head.
function VariantsWindow.open(PrettyUI, parent, title, variantIDs, current, onPick, labelFor)
    if windowState ~= nil then VariantsWindow.close() end
    local width, height = 0, 0
    local minWidth = COLUMNS * MIN_CELL_W + (COLUMNS - 1) * GAP + PAD * 2 + BORDERS
    local minHeight = ROWS * MIN_CELL_H + (ROWS - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
    -- As it was left, else the size the all-heads window opens at.
    if Settings.variantsWidth ~= nil then
        width, height = Settings.variantsWidth, Settings.variantsHeight
    else
        width, height = AllHeadsWindow.defaultSize(parent)
    end
    -- (kept on the screen, and no smaller than it can be resized to)
    width = math.max(math.min(minWidth, parent.width), math.min(width, parent.width))
    height = math.max(math.min(minHeight, parent.height), math.min(height, parent.height))
    local x = math.max(0, math.floor((parent.width - width) / 2))
    local y = math.max(0, math.floor((parent.height - height) / 2))
    -- Where it was left, if it was (kept on the screen).
    if Settings.variantsX ~= nil then
        x = math.max(0, math.min(Settings.variantsX, parent.width - width))
        y = math.max(0, math.min(Settings.variantsY, parent.height - height))
    end
    windowState = { ids = variantIDs, page = 1, pages = math.max(1, math.ceil(#variantIDs / PAGE_SIZE)), current = current,
        onPick = onPick, labelFor = labelFor, cells = {}, nav = { buttons = {} } }
    pendingPageChange = 0
    local openedState = windowState
    local succeeded, errorMessage = pcall(function()
        openedState.window = PrettyUI.Window.new(parent, {
            title = title, x = x, y = y, width = width, height = height,
            minWidth = math.min(minWidth, width), minHeight = math.min(minHeight, height),
            resizable = true, scrollable = false, destroyOnClose = true,
            -- Closed with its X: the window destroys itself; the heads (models) in it are destroyed here, and what
            -- the window held is let go.
            onClose = function()
                if windowState == openedState then
                    reportWindowPlacement(openedState)
                    destroyCells()
                    Event.Draw.Unsubscribe("make_me_a_monster_variants_window")
                    windowState, pendingPageChange = nil, 0
                end
            end,
        })
    end)
    if not succeeded then
        windowState = nil
        return false
    end
    local windowContent = openedState.window.content
    pcall(function()
        openedState.nav.label = ui.Text.new(windowContent)
        openedState.nav.label.maxLines = 1
        openedState.nav.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
        openedState.nav.label.rgba = TEXT_LIGHT
        openedState.nav.label.alignHorizontal = ui.AlignMode.CENTRE
        -- (no angle brackets in the button text: the game reads "<" as the start of a markup tag)
        local previousButton = PrettyUI.SimpleButton.new(windowContent, "Previous", function() pendingPageChange = -1 end,
            { x = PAD, y = 0, width = NAV_BUTTON })
        local nextButton = PrettyUI.SimpleButton.new(windowContent, "Next", function() pendingPageChange = 1 end,
            { x = PAD, y = 0, width = NAV_BUTTON })
        openedState.nav.buttons = { previousButton, nextButton }
    end)
    showPage()
    Event.Draw.Subscribe("make_me_a_monster_variants_window", function() pcall(VariantsWindow.tick) end)
    return true
end

function VariantsWindow.close()
    if windowState == nil then return end
    local window = windowState.window
    reportWindowPlacement(windowState)
    destroyCells()
    Event.Draw.Unsubscribe("make_me_a_monster_variants_window")
    windowState, pendingPageChange = nil, 0
    pcall(function() window:Destroy() end)
end

-- Every frame while the window is open: turns the page, and fits the cells to the window's size.
function VariantsWindow.tick()
    applyPageChange()
    if windowState ~= nil and windowState.window ~= nil then
        local succeeded, width, height = pcall(function()
            return windowState.window.content.width, windowState.window.content.height
        end)
        if succeeded and (width ~= windowState.layoutW or height ~= windowState.layoutH or currentHeadScale() ~= windowState.layoutScale) then
            layoutWindow()
        end
    end
end

return VariantsWindow
