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

local HeadGallery = require("src/ui/head_gallery")

local Variants = {}

Variants.animFor = nil -- function() -> the animation id the NPC heads should play, or nil
Variants.animForPlayer = nil -- function() -> the animation id the player's own head should play, or nil
Variants.scaleFor = nil -- function() -> how many times larger than normal the heads are drawn (the head size setting)
Variants.PLAYER = -1 -- the id standing for the player's own head (as the game's, for the local player)
Variants.savedSize = nil -- { width, height } the window was last left at: it opens at that size
Variants.onResized = nil -- function(width, height): called when the window closes at a size

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

local state = nil -- { window, ids, page, pages, current, onPick, labelFor, cells, nav, layoutW, layoutH }

local function log(message)
    print("[make_me_a_monster] " .. message)
end

local function colour(c) return Vector4.new(c[1], c[2], c[3], c[4]) end

local function destroyCells()
    for _, cell in ipairs(state.cells) do
        pcall(function() cell.click:Destroy() end)
        pcall(function() cell.label:Destroy() end)
        pcall(function() cell.idLabel:Destroy() end)
        pcall(function() cell.model:Destroy() end)
        pcall(function() cell.background:Destroy() end)
    end
    state.cells = {}
end

-- A cell's background: the head in use gold, the others dark (lighter under the mouse).
local function paint(cell, hovered)
    local c = hovered and HOVER or (cell.id == state.current and CURRENT or BACKGROUND)
    pcall(function() cell.background.colour = colour(c) end)
end

-- A head clicked: it becomes the one in use, and the cells show which. (The window stays open.)
local function pick(npcID)
    if state == nil then return end
    state.current = npcID
    pcall(state.onPick, npcID)
    for _, cell in ipairs(state.cells) do paint(cell, cell.id == npcID) end
end

-- The window's size, handed on to Variants.onResized (to be remembered), if it can be read.
local function reportSize(shown)
    if Variants.onResized == nil or shown == nil or shown.window == nil then return end
    local ok, width, height = pcall(function() return shown.window.root.width, shown.window.root.height end)
    if ok and type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
        pcall(Variants.onResized, math.floor(width), math.floor(height))
    end
end

-- The size of a cell and where the grid starts, for the window's content as it is now.
local function geometry()
    local content = state.window.content
    local width, height = content.width, content.height
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
local function headScale()
    local scale = Variants.scaleFor and Variants.scaleFor() or 1
    return type(scale) == "number" and scale >= 1 and scale or 1
end

-- A cell's parts put in their places (and sized) for the geometry g.
local function placeCell(cell, g)
    local col, row = (cell.index - 1) % COLUMNS, math.floor((cell.index - 1) / COLUMNS)
    local x, y = g.originX + col * (g.cellW + GAP), g.originY + row * (g.cellH + GAP)
    local labels = cell.idLabel and 36 or 22
    local head = math.max(16, math.min(g.cellW - 8, g.cellH - labels - 8))
    cell.background:SetPos(x, y)
    cell.background:SetSize(g.cellW, g.cellH)
    cell.model:SetPos(x + math.floor((g.cellW - head) / 2), y + 4)
    cell.model:SetSize(head, head)
    cell.model.viewDistance = math.max(1, math.floor(BASE_VIEW * BASE_SIZE / head / headScale()))
    cell.label:SetPos(x, y + g.cellH - labels)
    cell.label:SetSize(g.cellW, 16)
    if cell.idLabel then
        cell.idLabel:SetPos(x, y + g.cellH - 20)
        cell.idLabel:SetSize(g.cellW, 16)
    end
    cell.click:SetPos(x, y)
    cell.click:SetSize(g.cellW, g.cellH)
end

-- The page label and the buttons put in their places for the geometry g.
local function placeNav(g)
    local y = g.originY + g.gridH + 4
    pcall(function()
        local labelX = PAD + NAV_BUTTON + 6
        state.nav.label:SetPos(labelX, y + 6)
        state.nav.label:SetSize(math.max(1, g.width - labelX * 2), 20)
    end)
    pcall(function() state.nav.buttons[1].root:SetPos(PAD, y) end)
    pcall(function() state.nav.buttons[2].root:SetPos(g.width - PAD - NAV_BUTTON, y) end)
end

-- Everything put in its place for the window's size now.
local function layout()
    local ok, g = pcall(geometry)
    if not ok then return end
    state.layoutW, state.layoutH, state.layoutScale = g.width, g.height, headScale()
    for _, cell in ipairs(state.cells) do pcall(placeCell, cell, g) end
    placeNav(g)
end

-- A cell shown or hidden (all its parts).
local function setHidden(cell, hidden)
    for _, part in ipairs({ cell.background, cell.model, cell.name, cell.idLabel, cell.click }) do
        pcall(function() part.hidden = hidden end)
    end
end

-- One of the window's PAGE_SIZE cells, made once when the window opens and used for every page (see
-- src/ui/head_gallery.lua). Empty until fillCell.
local function makeCell(index)
    local content = state.window.content
    local cell = { index = index }
    state.cells[#state.cells + 1] = cell

    cell.background = ui.Rectangle.new(content)
    cell.background.fill = true
    cell.background.clickthrough = true

    cell.model = ui.Model.new(content)
    cell.model.clickthrough = true

    local function text(line)
        local label = ui.Text.new(content)
        label.maxLines = 1
        label.font = id.Font.MUSEO_SANS_11PT_REGULAR
        label.rgba = TEXT_LIGHT
        label.alignHorizontal = ui.AlignMode.CENTRE
        label.clickthrough = true
        label.content = line
        return label
    end
    cell.label = text("")
    cell.idLabel = text("")

    -- Over the rest, taking the click. (One handler per hook: a second default Subscribe replaces the first.)
    cell.click = ui.Layer.new(content)
    cell.click.clickthrough = false
    cell.click:Subscribe(ui.Hook.ONMOUSEOVER, function() paint(cell, true) end)
    cell.click:Subscribe(ui.Hook.ONMOUSELEAVE, function() paint(cell, false) end)
    cell.click:Subscribe(ui.Hook.ONCLICK, function() if cell.id ~= nil then pick(cell.id) end end)
    setHidden(cell, true)
end

-- The cell showing this head (npcID, or Variants.PLAYER for the player's own).
local function fillCell(cell, npcID)
    cell.id = npcID
    local isPlayer = npcID == Variants.PLAYER
    cell.model:SetModel(isPlayer and ui.ModelType.PLAYER_HEAD or ui.ModelType.NPC_HEAD, npcID)
    local animFor = isPlayer and Variants.animForPlayer or Variants.animFor
    local anim = animFor and animFor() or nil
    if anim ~= nil then cell.model.animID = anim end
    -- The NPC's name, if it is told (an entry can hold several names), above its id.
    local nameText = (not isPlayer and state.labelFor) and state.labelFor(npcID) or nil
    cell.label.content = isPlayer and "My head" or (nameText or ("ID " .. npcID))
    cell.idLabel.content = nameText and ("ID " .. npcID) or ""
    setHidden(cell, false)
    paint(cell, false)
end

local function emptyCell(cell)
    cell.id = nil
    setHidden(cell, true)
end

local function showPage()
    if not state.cellsMade then
        state.cellsMade = true
        for index = 1, PAGE_SIZE do
            local ok, err = pcall(makeCell, index)
            if not ok then log("could not make a variant cell: " .. tostring(err)) end
        end
    end
    local first = (state.page - 1) * PAGE_SIZE
    for _, cell in ipairs(state.cells) do
        local npcID = state.ids[first + cell.index]
        if npcID == nil then
            emptyCell(cell)
        else
            local ok, err = pcall(fillCell, cell, npcID)
            if not ok then log("could not fill a variant cell: " .. tostring(err)) end
        end
    end
    pcall(function()
        state.nav.label.content = "Page " .. state.page .. " of " .. state.pages .. " (" .. #state.ids .. " variants)"
    end)
    layout()
    -- Previous and Next only where there is a page to go to; the others stay above the heads.
    local wanted = { state.page > 1, state.page < state.pages }
    for index, button in ipairs(state.nav.buttons) do
        pcall(function()
            button.root.hidden = not wanted[index]
            button.root:MoveToFront()
        end)
    end
end

-- Workaround: the page is changed from the next frame: the buttons that ask are not destroyed or rebuilt
-- during their own click.
local turnBy = 0

local function applyTurn()
    local delta = turnBy
    turnBy = 0
    if state == nil or delta == 0 then return end
    local page = math.max(1, math.min(state.pages, state.page + delta))
    if page == state.page then return end
    state.page = page
    showPage()
end

-- The heads shown play the animation now wanted (it was changed while the window is open).
function Variants.updateAnimations()
    if state == nil then return end
    for _, cell in ipairs(state.cells) do
        if cell.id ~= nil then
            pcall(function()
                local isPlayer = cell.id == Variants.PLAYER
                local animFor = isPlayer and Variants.animForPlayer or Variants.animFor
                local anim = animFor and animFor() or nil
                if anim ~= nil then
                    cell.model.animID = anim
                else
                    cell.model:SetModel(isPlayer and ui.ModelType.PLAYER_HEAD or ui.ModelType.NPC_HEAD, cell.id)
                end
            end)
        end
    end
end

function Variants.isOpen()
    return state ~= nil
end

-- Opens the window in `parent` for these NPC ids. current: the id active now (highlighted).
-- onPick(npcID) is called when a head is clicked (the window stays open, the head in use highlighted). labelFor(npcID), if given,
-- is the name shown under each head.
function Variants.open(PrettyUI, parent, title, ids, current, onPick, labelFor)
    if state ~= nil then Variants.close() end
    local width, height = 0, 0
    local minWidth = COLUMNS * MIN_CELL_W + (COLUMNS - 1) * GAP + PAD * 2 + BORDERS
    local minHeight = ROWS * MIN_CELL_H + (ROWS - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
    -- As it was left, else the size the all-heads window opens at.
    if Variants.savedSize ~= nil then
        width, height = Variants.savedSize.width, Variants.savedSize.height
    else
        width, height = HeadGallery.defaultSize()
    end
    -- (kept on the screen, and no smaller than it can be resized to)
    width = math.max(math.min(minWidth, parent.width), math.min(width, parent.width))
    height = math.max(math.min(minHeight, parent.height), math.min(height, parent.height))
    local x = math.max(0, math.floor((parent.width - width) / 2))
    local y = math.max(0, math.floor((parent.height - height) / 2))
    state = { ids = ids, page = 1, pages = math.max(1, math.ceil(#ids / PAGE_SIZE)), current = current,
        onPick = onPick, labelFor = labelFor, cells = {}, nav = { buttons = {} } }
    turnBy = 0
    local mine = state
    local ok, err = pcall(function()
        mine.window = PrettyUI.Window.new(parent, {
            title = title, x = x, y = y, width = width, height = height,
            minWidth = math.min(minWidth, width), minHeight = math.min(minHeight, height),
            resizable = true, scrollable = false, destroyOnClose = true,
            -- Closed with its X: the window destroys itself; the heads (models) in it are destroyed here, and what
            -- the window held is let go.
            onClose = function()
                if state == mine then
                    reportSize(mine)
                    destroyCells()
                    state, turnBy = nil, 0
                end
            end,
        })
    end)
    if not ok then
        state = nil
        print("[make_me_a_monster] could not open the variants window: " .. tostring(err))
        return false
    end
    local content = mine.window.content
    local okNav, errNav = pcall(function()
        mine.nav.label = ui.Text.new(content)
        mine.nav.label.maxLines = 1
        mine.nav.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
        mine.nav.label.rgba = TEXT_LIGHT
        mine.nav.label.alignHorizontal = ui.AlignMode.CENTRE
        -- (no angle brackets in the button text: the game reads "<" as the start of a markup tag)
        local previous = PrettyUI.SimpleButton.new(content, "Previous", function() turnBy = -1 end,
            { x = PAD, y = 0, width = NAV_BUTTON })
        local after = PrettyUI.SimpleButton.new(content, "Next", function() turnBy = 1 end,
            { x = PAD, y = 0, width = NAV_BUTTON })
        mine.nav.buttons = { previous, after }
    end)
    if not okNav then log("could not make the page buttons: " .. tostring(errNav)) end
    showPage()
    return true
end

function Variants.close()
    if state == nil then return end
    local window = state.window
    reportSize(state)
    destroyCells()
    state, turnBy = nil, 0
    pcall(function() window:Destroy() end)
end

-- Every frame: turns the page, and fits the cells to the window's size.
function Variants.tick()
    applyTurn()
    if state ~= nil and state.window ~= nil then
        local ok, width, height = pcall(function()
            return state.window.content.width, state.window.content.height
        end)
        if ok and (width ~= state.layoutW or height ~= state.layoutH or headScale() ~= state.layoutScale) then
            layout()
        end
    end
end

return Variants
