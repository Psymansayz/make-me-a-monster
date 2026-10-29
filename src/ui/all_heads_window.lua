-- The "all heads" window: every chat head the plugin lists, as a paged grid with their names. Clicking one makes it
-- the head used in dialogue (the window stays open, the head in use highlighted, so another can be tried). A search
-- box narrows the heads by name or id, and a page box jumps to a page; the window can be resized, the cells and
-- heads in them growing and shrinking with it, and its size is remembered.
--
-- Workaround: pages instead of scrolling: models in a scroll area aren't clipped by it, so they would draw
-- outside it.
-- Workaround: the page is changed from the next frame, not from the button or box that asked: a component isn't
-- destroyed inside its own handler.
-- Workaround: a window's content size changes a moment after it is resized, so it is read every frame and the cells
-- are placed again when it differs.
--
-- AllHeadsWindow.open(PrettyUI, parent, heads, current, onPick, nameOf): heads = { id... } in the order shown;
-- current = the id used now (highlighted, and its page shown first); onPick(id) is called when a head is clicked
-- (the highlight then moves to it);
-- nameOf(id) is the name shown under each head. AllHeadsWindow.tick(): every frame. AllHeadsWindow.close().

local Settings = require("src/data/settings")

local AllHeadsWindow = {}

AllHeadsWindow.animationForNpcHeads = nil -- function() -> the animation id the heads should play, or nil
AllHeadsWindow.onClosed = nil -- function(): called when the window has closed, however it was closed

local COLUMNS, ROWS = 5, 4
local PAGE_SIZE = COLUMNS * ROWS
local PAD, GAP = 8, 6
local NAV_HEIGHT = 36
local START_CELL_W, START_CELL_H = 150, 170
local MIN_CELL_W, MIN_CELL_H = 90, 110
local MIN_WIDTH = 640 -- room for the buttons and boxes in the bottom row
local BORDERS, TITLE_AND_BOTTOM = 16, 40
local BASE_VIEW, BASE_SIZE = 2150, 160

local BACKGROUND = { 0.12, 0.09, 0.06, 1 }
local HOVER = { 0.30, 0.24, 0.14, 1 }
local CURRENT = { 0.55, 0.42, 0.14, 1 }
local TEXT_LIGHT = 0xE9E5DDFF

local windowState = nil -- { window, current, onPick, nameOf, all, shown, page, pages, cells, nav, lowered, query, layoutW, ... }

local function toColour(colourValues) return Vector4.new(colourValues[1], colourValues[2], colourValues[3], colourValues[4]) end

-- The head size setting: how many times larger than normal the heads are drawn (1: normal).
local function currentHeadScale()
    return Settings.headScale
end

local function destroyCells()
    for _, headCell in ipairs(windowState.cells) do
        pcall(function() headCell.click:Destroy() end)
        pcall(function() headCell.name:Destroy() end)
        pcall(function() headCell.idLabel:Destroy() end)
        pcall(function() headCell.model:Destroy() end)
        pcall(function() headCell.background:Destroy() end)
    end
    windowState.cells = {}
end

-- The window's size, handed to the settings (to be remembered), if it can be read.
local function reportWindowPlacement(reportedState)
    if reportedState == nil or reportedState.window == nil then return end
    local root = reportedState.window.root
    local succeeded, width, height, x, y = pcall(function() return root.width, root.height, root.x, root.y end)
    if not succeeded then return end
    if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
        Settings.setGallerySize(math.floor(width), math.floor(height))
    end
    if type(x) == "number" and type(y) == "number" then
        Settings.setGalleryPosition(math.max(0, math.floor(x)), math.max(0, math.floor(y)))
    end
end

-- A cell's background: the head in use gold, the others dark (lighter under the mouse).
local function paintCell(headCell, hovered)
    local colourValues = hovered and HOVER or (headCell.id == windowState.current and CURRENT or BACKGROUND)
    pcall(function() headCell.background.colour = toColour(colourValues) end)
end

-- A head clicked: it becomes the one in use, and the cells show which.
local function pickHead(npcID)
    if windowState == nil then return end
    windowState.current = npcID
    pcall(windowState.onPick, npcID)
    for _, headCell in ipairs(windowState.cells) do paintCell(headCell, headCell.id == npcID) end
end

-- The grid for the window's content as it is now.
local function computeGeometry()
    local windowContent = windowState.window.content
    local width, height = windowContent.width, windowContent.height
    local cellW = math.max(40, math.floor((width - PAD * 2 - (COLUMNS - 1) * GAP) / COLUMNS))
    local cellH = math.max(60, math.floor((height - PAD * 2 - NAV_HEIGHT - 4 - (ROWS - 1) * GAP) / ROWS))
    local gridW = COLUMNS * cellW + (COLUMNS - 1) * GAP
    return {
        width = width, height = height, cellW = cellW, cellH = cellH,
        originX = math.max(0, math.floor((width - gridW) / 2)), originY = PAD,
        gridH = ROWS * cellH + (ROWS - 1) * GAP,
    }
end

local function placeCell(headCell, grid)
    local column, row = (headCell.index - 1) % COLUMNS, math.floor((headCell.index - 1) / COLUMNS)
    local x, y = grid.originX + column * (grid.cellW + GAP), grid.originY + row * (grid.cellH + GAP)
    local headSize = math.max(16, math.min(grid.cellW - 8, grid.cellH - 44))
    headCell.background:SetPos(x, y)
    headCell.background:SetSize(grid.cellW, grid.cellH)
    headCell.model:SetPos(x + math.floor((grid.cellW - headSize) / 2), y + 4)
    headCell.model:SetSize(headSize, headSize)
    headCell.model.viewDistance = math.max(1, math.floor(BASE_VIEW * BASE_SIZE / headSize / currentHeadScale()))
    headCell.name:SetPos(x, y + grid.cellH - 38)
    headCell.name:SetSize(grid.cellW, 16)
    headCell.idLabel:SetPos(x, y + grid.cellH - 20)
    headCell.idLabel:SetSize(grid.cellW, 16)
    headCell.click:SetPos(x, y)
    headCell.click:SetSize(grid.cellW, grid.cellH)
end

local function placeNavigation(grid)
    local y = grid.originY + grid.gridH + 4
    local navigation = windowState.nav
    pcall(function() navigation.previous.root:SetPos(PAD, y + 2) end)
    pcall(function() navigation.after.root:SetPos(PAD + 86, y + 2) end)
    pcall(function() navigation.search.root:SetPos(PAD + 180, y + 2) end)
    pcall(function() navigation.jump.root:SetPos(PAD + 392, y + 2) end)
    pcall(function()
        navigation.label:SetPos(PAD + 470, y + 8)
        navigation.label:SetSize(math.max(1, grid.width - PAD * 2 - 470), 20)
    end)
end

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

-- One of the window's PAGE_SIZE cells, made once when the window opens and used for every page (a page change
-- gives the cells other heads, it doesn't make and destroy components: that built up while paging, and the
-- client was slow to let go of them). Empty until fillCell.
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
    headCell.name = makeTextLabel("")
    headCell.idLabel = makeTextLabel("")

    -- Over the rest, taking the click. (One handler per hook: a second default Subscribe replaces the first.)
    headCell.click = ui.Layer.new(windowContent)
    headCell.click.clickthrough = false
    headCell.click:Subscribe(ui.Hook.ONMOUSEOVER, function() paintCell(headCell, true) end)
    headCell.click:Subscribe(ui.Hook.ONMOUSELEAVE, function() paintCell(headCell, false) end)
    headCell.click:Subscribe(ui.Hook.ONCLICK, function() if headCell.id ~= nil then pickHead(headCell.id) end end)
    setCellHidden(headCell, true)
end

-- The cell showing this head.
local function fillCell(headCell, npcID)
    headCell.id = npcID
    headCell.model:SetModel(ui.ModelType.NPC_HEAD, npcID)
    local animationID = AllHeadsWindow.animationForNpcHeads and AllHeadsWindow.animationForNpcHeads() or nil
    if animationID ~= nil then headCell.model.animID = animationID end
    headCell.name.content = windowState.nameOf(npcID) or "?"
    headCell.idLabel.content = "ID " .. npcID
    setCellHidden(headCell, false)
    paintCell(headCell, false)
end

-- The cell with nothing in it (past the last head of the last page).
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
    windowState.page = math.max(1, math.min(windowState.pages, windowState.page))
    local firstHeadIndex = (windowState.page - 1) * PAGE_SIZE
    for position, headCell in ipairs(windowState.cells) do
        local npcID = windowState.shown[firstHeadIndex + headCell.index]
        if npcID == nil then
            emptyCell(headCell)
        else
            pcall(fillCell, headCell, npcID)
        end
    end
    pcall(function()
        windowState.nav.label.content = ("Page %d of %d (%d heads%s)"):format(
            windowState.page, windowState.pages, #windowState.shown, #windowState.shown < #windowState.all and " found" or "")
    end)
    layoutWindow()
    -- Previous and Next only where there is a page to go to; they stay above the heads.
    local wanted = { windowState.page > 1, windowState.page < windowState.pages }
    for position, button in ipairs({ windowState.nav.previous, windowState.nav.after }) do
        pcall(function()
            button.root.hidden = not wanted[position]
            button.root:MoveToFront()
        end)
    end
end

-- The heads whose name or id holds every word of the search text (all of them if it is blank).
local function applySearch()
    local searchWords = {}
    for searchWord in (windowState.query or ""):lower():gmatch("%S+") do searchWords[#searchWords + 1] = searchWord end
    if #searchWords == 0 then
        windowState.shown = windowState.all
    else
        local matchingHeadIDs = {}
        for _, npcID in ipairs(windowState.all) do
            local haystack = (windowState.lowered[npcID] or "") .. " " .. npcID
            local matches = true
            for _, searchWord in ipairs(searchWords) do
                if not haystack:find(searchWord, 1, true) then
                    matches = false
                    break
                end
            end
            if matches then matchingHeadIDs[#matchingHeadIDs + 1] = npcID end
        end
        windowState.shown = matchingHeadIDs
    end
    windowState.pages = math.max(1, math.ceil(#windowState.shown / PAGE_SIZE))
    windowState.page = 1
end

-- The size the window opens at when it has no saved size: five cells across and four down, at their starting size.
-- The window's size scales with the game window (`parent`): that cell size, made larger or smaller to take up about
-- WIDTH_SHARE of its width or HEIGHT_SHARE of its height, whichever comes first.
local WIDTH_SHARE, HEIGHT_SHARE = 0.45, 0.75

function AllHeadsWindow.defaultSize(parent)
    local width = COLUMNS * START_CELL_W + (COLUMNS - 1) * GAP + PAD * 2 + BORDERS
    local height = ROWS * START_CELL_H + (ROWS - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
    local scale = math.min(parent.width * WIDTH_SHARE / width, parent.height * HEIGHT_SHARE / height)
    return math.floor(width * scale), math.floor(height * scale)
end

-- The heads shown play the animation now wanted (it was changed while the window is open).
function AllHeadsWindow.updateAnimations()
    if windowState == nil then return end
    local animationID = AllHeadsWindow.animationForNpcHeads and AllHeadsWindow.animationForNpcHeads() or nil
    for _, headCell in ipairs(windowState.cells) do
        if headCell.id ~= nil then
            pcall(function()
                if animationID ~= nil then
                    headCell.model.animID = animationID
                else
                    headCell.model:SetModel(ui.ModelType.NPC_HEAD, headCell.id) -- (no animation: the head as it starts)
                end
            end)
        end
    end
end

function AllHeadsWindow.isOpen()
    return windowState ~= nil
end

function AllHeadsWindow.open(PrettyUI, parent, heads, current, onPick, nameOf)
    if windowState ~= nil then AllHeadsWindow.close() end
    local width, height = AllHeadsWindow.defaultSize(parent)
    local minWidth = math.max(MIN_WIDTH, COLUMNS * MIN_CELL_W + (COLUMNS - 1) * GAP + PAD * 2 + BORDERS)
    local minHeight = ROWS * MIN_CELL_H + (ROWS - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
    -- As it was left, if it was.
    if Settings.galleryWidth ~= nil then width, height = Settings.galleryWidth, Settings.galleryHeight end
    -- (kept on the screen, and no smaller than it can be resized to)
    width = math.max(math.min(minWidth, parent.width), math.min(width, parent.width))
    height = math.max(math.min(minHeight, parent.height), math.min(height, parent.height))
    local x = math.max(0, math.floor((parent.width - width) / 2))
    local y = math.max(0, math.floor((parent.height - height) / 2))
    -- Where it was left, if it was (kept on the screen).
    if Settings.galleryX ~= nil then
        x = math.max(0, math.min(Settings.galleryX, parent.width - width))
        y = math.max(0, math.min(Settings.galleryY, parent.height - height))
    end

    local lowered = {}
    local currentIndex = nil
    for position, npcID in ipairs(heads) do
        lowered[npcID] = (nameOf(npcID) or ""):lower()
        if npcID == current then currentIndex = position end
    end
    windowState = { all = heads, shown = heads, page = 1, pages = math.max(1, math.ceil(#heads / PAGE_SIZE)),
        current = current, onPick = onPick, nameOf = nameOf, cells = {}, nav = {}, lowered = lowered, query = "" }
    if currentIndex ~= nil then windowState.page = math.ceil(currentIndex / PAGE_SIZE) end -- (the head used now first)
    local openedState = windowState
    local succeeded, errorMessage = pcall(function()
        openedState.window = PrettyUI.Window.new(parent, {
            title = "All heads", x = x, y = y, width = width, height = height,
            minWidth = math.min(minWidth, width), minHeight = math.min(minHeight, height),
            resizable = true, scrollable = false, destroyOnClose = true,
            -- Closed with its X: the window destroys itself; the heads (models) in it are destroyed here, and what
            -- the window held is let go.
            onClose = function()
                if windowState == openedState then
                    reportWindowPlacement(openedState)
                    destroyCells()
                    windowState = nil
                    if AllHeadsWindow.onClosed then pcall(AllHeadsWindow.onClosed) end
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
        local navigation = openedState.nav
        navigation.turn = 0
        -- (no angle brackets in the button text: the game reads "<" as the start of a markup tag)
        navigation.previous = PrettyUI.SimpleButton.new(windowContent, "Previous", function() navigation.turn = -1 end, { width = 80 })
        navigation.after = PrettyUI.SimpleButton.new(windowContent, "Next", function() navigation.turn = 1 end, { width = 80 })
        navigation.search = PrettyUI.TextField.new(windowContent, {
            width = 204, height = 30, placeholder = "Search name or id",
            onChange = function(_, _, text) openedState.query, openedState.searchDirty = text, true end,
        })
        navigation.jump = PrettyUI.TextField.new(windowContent, {
            width = 70, height = 30, placeholder = "Page", filterMode = ui.InputFieldFilterMode.NUMERIC,
            onSubmit = function(_, text) navigation.jumpTo = tonumber(text) end,
        })
        navigation.label = ui.Text.new(windowContent)
        navigation.label.maxLines = 1
        navigation.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
        navigation.label.rgba = TEXT_LIGHT
    end)
    showPage()
    return true
end

function AllHeadsWindow.close()
    if windowState == nil then return end
    local window = windowState.window
    reportWindowPlacement(windowState)
    destroyCells()
    windowState = nil
    pcall(function() window:Destroy() end)
    if AllHeadsWindow.onClosed then pcall(AllHeadsWindow.onClosed) end
end

-- Every frame: does what the buttons and boxes asked for (not inside their own handlers), and fits the cells to the
-- window's size.
function AllHeadsWindow.tick()
    if windowState == nil or windowState.window == nil then return end
    local navigation = windowState.nav
    if windowState.searchDirty then
        windowState.searchDirty = false
        applySearch()
        showPage()
    end
    if navigation.turn ~= nil and navigation.turn ~= 0 then
        local pageChange = navigation.turn
        navigation.turn = 0
        local page = math.max(1, math.min(windowState.pages, windowState.page + pageChange))
        if page ~= windowState.page then
            windowState.page = page
            showPage()
        end
    end
    if navigation.jumpTo ~= nil then
        windowState.page, navigation.jumpTo = navigation.jumpTo, nil
        showPage()
    end
    local succeeded, width, height = pcall(function() return windowState.window.content.width, windowState.window.content.height end)
    if succeeded and (width ~= windowState.layoutW or height ~= windowState.layoutH or currentHeadScale() ~= windowState.layoutScale) then layoutWindow() end
end

return AllHeadsWindow
