-- A window of chat heads in a paged grid (the "all heads" and "variants" windows): a name and an id under each, a
-- click picks one. Nothing runs every frame; the cells are made once and reused for every page.
--
-- Models aren't clipped by a scroll area: so pages, not scrolling.
-- Models drawn in two regions of the tree (a window's content or root, a dialogue box) make the game flicker the
-- frames along their top and right edges (a viewport or scissor rectangle for the models' pass, it seems, with a
-- flipped y origin or an exclusive right edge, left stale between the regions). To work around this, the models are
-- drawn in a single layer, and are overlayed upon the windows as needed instead of within each window individually.
--
-- Components left to a parent's Destroy make the plugin pause for a moment when it unloads: so a closing window
-- destroys every part of every cell itself, one by one, the models first, before its layers and the window.
--
-- HeadGrid.open(PrettyUI, parent, options) -> the grid, or nil. options: title; columns, rows; ids; current;
--   minWidth; savedWidth/Height/X/Y; withSearch; nameOf(id); isPlayerHead(id); animationFor(id);
--   pageLabel(page, pages, shown); onPick(id); onSearch(text); onPlacement(width, height, x, y); onClosed().
-- grid:setHeads(ids, current, title); grid:updateAnimations(); grid:refreshHeadSize(); grid:close().

local Settings = require("src/data/settings")

local HeadGrid = {}
HeadGrid.__index = HeadGrid

local PAD, GAP = 8, 6
local NAV_HEIGHT = 36
local NAV_BUTTON = 80
local LABELS_HEIGHT = 40 -- the name and the id under a head: two 16-high lines, 38 and 20 up from the cell's bottom
local START_CELL_W, START_CELL_H = 150, 170 -- a cell when a window opens without a saved size
local MIN_CELL_W, MIN_CELL_H = 90, 110      -- and the least a window can be resized to
local BORDERS, TITLE_AND_BOTTOM = 16, 40     -- PrettyUI's 8-wide borders both sides; its 32-high title bar and bottom
local BASE_VIEW, BASE_SIZE = 2150, 160       -- the game's view distance for a chat head, at BASE_SIZE units across
local WINDOW_HEAD_SCALE = 1.5                -- the heads in the windows, this much larger than in the dialogue boxes

local BACKGROUND = Vector4.new(0.12, 0.09, 0.06, 1)
local HOVER = Vector4.new(0.30, 0.24, 0.14, 1)
local CURRENT = Vector4.new(0.55, 0.42, 0.14, 1)
local TEXT_LIGHT = 0xE9E5DDFF
local CELL_PARTS = { "background", "model", "name", "idLabel", "click" }
local raiseCount = 0 -- (for a Draw subscription id of each grid's own)

-- The size of a window whose cells are this size.
local function frameSize(columns, rows, cellW, cellH)
    return columns * cellW + (columns - 1) * GAP + PAD * 2 + BORDERS,
        rows * cellH + (rows - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
end

-- The size a window opens at with no saved size: five cells across and four down at their starting size, made larger
-- or smaller to take up about WIDTH_SHARE of the game window's width or HEIGHT_SHARE of its height, whichever comes
-- first.
local WIDTH_SHARE, HEIGHT_SHARE = 0.45, 0.75

function HeadGrid.defaultSize(parent)
    local width, height = frameSize(5, 4, START_CELL_W, START_CELL_H)
    local scale = math.min(parent.width * WIDTH_SHARE / width, parent.height * HEIGHT_SHARE / height)
    return math.floor(width * scale), math.floor(height * scale)
end

-- The size of the window's content for a window of this size: PrettyUI's borders and title bar taken off.
local function contentSizeOf(windowWidth, windowHeight)
    return windowWidth - BORDERS, windowHeight - TITLE_AND_BOTTOM
end

-- The page the head with this id is on (the first if it isn't listed).
local function pageOf(ids, current, pageSize)
    for position, npcID in ipairs(ids) do
        if npcID == current then return math.ceil(position / pageSize) end
    end
    return 1
end

-- The cell size and where the grid starts, for the content at its size.
function HeadGrid:geometry()
    local width, height = self.contentWidth, self.contentHeight
    local cellW = math.max(40, math.floor((width - PAD * 2 - (self.columns - 1) * GAP) / self.columns))
    local cellH = math.max(60, math.floor((height - PAD * 2 - NAV_HEIGHT - 4 - (self.rows - 1) * GAP) / self.rows))
    local gridW = self.columns * cellW + (self.columns - 1) * GAP
    return { width = width, cellW = cellW, cellH = cellH, originX = math.max(0, math.floor((width - gridW) / 2)),
        originY = PAD, gridH = self.rows * cellH + (self.rows - 1) * GAP }
end

-- A cell's parts put in their places (and sized) for the geometry g.
function HeadGrid:placeCell(cell, g)
    local column, row = (cell.index - 1) % self.columns, math.floor((cell.index - 1) / self.columns)
    local x, y = g.originX + column * (g.cellW + GAP), g.originY + row * (g.cellH + GAP)
    local headSize = math.max(16, math.min(g.cellW, g.cellH - LABELS_HEIGHT)) -- (square, over the labels)
    cell.background:SetPos(x, y)
    cell.background:SetSize(g.cellW, g.cellH)
    cell.model:SetPos(g.offsetX + x + math.floor((g.cellW - headSize) / 2), g.offsetY + y)
    -- (a model set again is drawn again from nothing, and a window being resized places its cells at every step: so
    -- the size and the view distance only when they change)
    if cell.headSize ~= headSize then
        cell.headSize = headSize
        cell.model:SetSize(headSize, headSize)
    end
    -- (the head is drawn larger by moving the camera closer: the windows' own scale, and the head size setting on top)
    local viewDistance = math.max(1,
        math.floor(BASE_VIEW * BASE_SIZE / headSize / WINDOW_HEAD_SCALE / Settings.headScaleMultiplier()))
    if cell.viewDistance ~= viewDistance then
        cell.viewDistance = viewDistance
        cell.model.viewDistance = viewDistance
    end
    cell.name:SetPos(g.offsetX + x, g.offsetY + y + g.cellH - 38)
    cell.name:SetSize(g.cellW, 16)
    cell.idLabel:SetPos(g.offsetX + x, g.offsetY + y + g.cellH - 20)
    cell.idLabel:SetSize(g.cellW, 16)
    cell.click:SetPos(x, y)
    cell.click:SetSize(g.cellW, g.cellH)
end

-- The bottom row put in its place. With a search: the buttons, the boxes and the label after them. Without: Previous
-- at the left, Next at the right, the label centred between them.
function HeadGrid:placeNavigation(g)
    local y = g.originY + g.gridH + 4
    local nav = self.nav
    nav.previous.root:SetPos(PAD, y + 2)
    if nav.search then
        nav.after.root:SetPos(PAD + NAV_BUTTON + 6, y + 2)
        nav.search.root:SetPos(PAD + 180, y + 2)
        nav.jump.root:SetPos(PAD + 392, y + 2)
        nav.label:SetPos(PAD + 470, y + 8)
        nav.label:SetSize(math.max(1, g.width - PAD * 2 - 470), 20)
    else
        nav.after.root:SetPos(g.width - PAD - NAV_BUTTON, y + 2)
        local labelX = PAD + NAV_BUTTON + 6
        nav.label:SetPos(labelX, y + 8)
        nav.label:SetSize(math.max(1, g.width - labelX * 2), 20)
    end
end

function HeadGrid:layout()
    local g = self:geometry()
    -- (where the content is on the plugin layer: the heads and the labels, in layers there, are placed from it)
    local root = self.window.root
    g.offsetX, g.offsetY = root.x + BORDERS / 2, root.y + TITLE_AND_BOTTOM - BORDERS / 2
    for _, cell in ipairs(self.cells) do self:placeCell(cell, g) end
    self:placeNavigation(g)
    self.headsLayer:MoveToFront()
    self.labelsLayer:MoveToFront()
end

local function setCellHidden(cell, hidden)
    for _, part in ipairs(CELL_PARTS) do cell[part].hidden = hidden end
end

-- A cell's background: the head in use gold, the others dark (lighter under the mouse).
function HeadGrid:paintCell(cell, hovered)
    cell.background.colour = hovered and HOVER or (cell.id == self.current and CURRENT or BACKGROUND)
end

-- A head clicked: it becomes the one in use, and the cells show which.
function HeadGrid:pick(npcID)
    self.current = npcID
    pcall(self.onPick, npcID)
    for _, cell in ipairs(self.cells) do self:paintCell(cell, cell.id == npcID) end
end

-- One of the cells, empty until filled.
function HeadGrid:makeCell(position)
    local content = self.window.content
    local cell = { index = position }
    self.cells[#self.cells + 1] = cell
    cell.background = ui.Rectangle.new(content)
    cell.background.fill = true
    cell.background.clickthrough = true
    cell.model = ui.Model.new(self.headsLayer)
    cell.model.clickthrough = true
    local function makeTextLabel()
        local text = ui.Text.new(self.labelsLayer)
        text.maxLines = 1
        text.font = id.Font.MUSEO_SANS_11PT_REGULAR
        text.rgba = TEXT_LIGHT
        text.alignHorizontal = ui.AlignMode.CENTRE
        text.clickthrough = true
        return text
    end
    cell.name = makeTextLabel()
    cell.idLabel = makeTextLabel()
    -- Over the rest, taking the click. (One handler per hook: a second default Subscribe replaces the first.)
    cell.click = ui.Layer.new(content)
    cell.click.clickthrough = false
    cell.click:Subscribe(ui.Hook.ONMOUSEOVER, function() self:paintCell(cell, true) end)
    cell.click:Subscribe(ui.Hook.ONMOUSELEAVE, function() self:paintCell(cell, false) end)
    cell.click:Subscribe(ui.Hook.ONCLICK, function() if cell.id ~= nil then self:pick(cell.id) end end)
    setCellHidden(cell, true)
end

local function modelTypeFor(self, npcID)
    return self.isPlayerHead(npcID) and ui.ModelType.PLAYER_HEAD or ui.ModelType.NPC_HEAD
end

-- The cell showing this head.
function HeadGrid:fillCell(cell, npcID)
    cell.id = npcID
    cell.model:SetModel(modelTypeFor(self, npcID), npcID)
    cell.viewDistance = nil -- (SetModel puts the view distance back to its default: placeCell sets it again)
    local animationID = self.animationFor(npcID)
    if animationID ~= nil then cell.model.animID = animationID end
    -- The name over the id; without a name the id alone; the player's own head says so.
    local isPlayer = self.isPlayerHead(npcID)
    local name = not isPlayer and self.nameOf(npcID) or nil
    cell.name.content = isPlayer and "My head" or name or ("ID " .. npcID)
    cell.idLabel.content = name and ("ID " .. npcID) or ""
    setCellHidden(cell, false)
    self:paintCell(cell, false)
end

-- The cell with nothing in it (past the last head of the last page): its model let go, not just hidden, so a page with
-- few heads keeps few loaded (what is loaded is released, all at once, when the plugin unloads).
local function emptyCell(cell)
    cell.id = nil
    cell.model:SetModel(ui.ModelType.NONE, -1)
    cell.name.content, cell.idLabel.content = "", ""
    setCellHidden(cell, true)
end

function HeadGrid:showPage()
    if #self.cells == 0 then
        for position = 1, self.pageSize do self:makeCell(position) end
    end
    self.page = math.max(1, math.min(self.pages, self.page))
    local first = (self.page - 1) * self.pageSize
    for _, cell in ipairs(self.cells) do
        local npcID = self.ids[first + cell.index]
        if npcID == nil then emptyCell(cell) else self:fillCell(cell, npcID) end
    end
    self.nav.label.content = self.pageLabel(self.page, self.pages, #self.ids)
    self:layout()
    -- (Previous and Next only where there is a page to go to)
    self.nav.previous.root.hidden = self.page <= 1
    self.nav.after.root.hidden = self.page >= self.pages
end

-- Other heads shown (the page of the one in use first), and a title if given.
function HeadGrid:setHeads(ids, current, title)
    self.ids, self.current = ids, current
    self.pages = math.max(1, math.ceil(#ids / self.pageSize))
    self.page = pageOf(ids, current, self.pageSize)
    if title ~= nil then self.window:SetTitle(title) end
    self:showPage()
end

function HeadGrid:changePage(pageChange)
    local page = math.max(1, math.min(self.pages, self.page + pageChange))
    if page ~= self.page then
        self.page = page
        self:showPage()
    end
end

-- The heads shown play the animation now wanted (it was changed while the window is open).
function HeadGrid:updateAnimations()
    for _, cell in ipairs(self.cells) do
        if cell.id ~= nil then
            local animationID = self.animationFor(cell.id)
            if animationID ~= nil then
                cell.model.animID = animationID
            else
                cell.model:SetModel(modelTypeFor(self, cell.id), cell.id) -- (no animation: the head as it starts)
                cell.model.viewDistance = cell.viewDistance
            end
        end
    end
end

-- The head size was changed (the slider): the heads are drawn at the new size.
function HeadGrid:refreshHeadSize()
    self:layout()
end

-- What the window leaves behind when it closes, however it was closed: its place reported, the heads let go.
function HeadGrid:release()
    if self.closed then return end
    self.closed = true
    local root = self.window.root
    self.onPlacement(math.floor(root.width), math.floor(root.height),
        math.max(0, math.floor(root.x)), math.max(0, math.floor(root.y)))
    Event.Draw.Unsubscribe(self.raiseSubscription)
    pcall(function() self.window:_UnregisterOverlay(self.labelsLayer) end) -- (the window may be going already)
    -- (components left to a parent's destruction make the plugin pause on unloading: so every part of every cell is
    -- destroyed one by one, the models first, before the layers and the window)
    for _, cell in ipairs(self.cells) do
        for _, part in ipairs(CELL_PARTS) do cell[part]:Destroy() end
    end
    self.cells = {}
    self.headsLayer:Destroy()
    self.labelsLayer:Destroy()
    self.onClosed()
end

function HeadGrid:close()
    if self.closed then return end
    self:release()
    self.window:Destroy()
end

function HeadGrid.open(PrettyUI, parent, options)
    local self = setmetatable({
        columns = options.columns, rows = options.rows, pageSize = options.columns * options.rows,
        nameOf = options.nameOf or function() return nil end,
        isPlayerHead = options.isPlayerHead or function() return false end,
        animationFor = options.animationFor or function() return nil end,
        pageLabel = options.pageLabel,
        onPick = options.onPick or function() end,
        onSearch = options.onSearch,
        onPlacement = options.onPlacement or function() end,
        onClosed = options.onClosed or function() end,
        cells = {}, nav = {}, closed = false,
    }, HeadGrid)
    -- The size: as it was left, else the default; kept on the screen and no smaller than it can be resized to.
    local minWidth, minHeight = frameSize(self.columns, self.rows, MIN_CELL_W, MIN_CELL_H)
    minWidth = math.max(minWidth, options.minWidth or 0)
    local width, height = options.savedWidth, options.savedHeight
    if width == nil then width, height = HeadGrid.defaultSize(parent) end
    width = math.max(math.min(minWidth, parent.width), math.min(width, parent.width))
    height = math.max(math.min(minHeight, parent.height), math.min(height, parent.height))
    -- Where it was left, else the middle (kept on the screen).
    local x, y = options.savedX, options.savedY
    if x == nil then x, y = math.floor((parent.width - width) / 2), math.floor((parent.height - height) / 2) end
    x = math.max(0, math.min(x, parent.width - width))
    y = math.max(0, math.min(y, parent.height - height))
    self.contentWidth, self.contentHeight = contentSizeOf(width, height)
    local made = pcall(function()
        self.window = PrettyUI.Window.new(parent, {
            title = options.title, x = x, y = y, width = width, height = height,
            minWidth = math.min(minWidth, width), minHeight = math.min(minHeight, height),
            resizable = true, scrollable = false, destroyOnClose = true,
            onClose = function() self:release() end, -- (closed with its X: the window destroys itself)
        })
    end)
    if not made then return nil end
    local window, content = self.window, self.window.content
    -- The heads' layer and the labels' layer, under the plugin layer beside the window: see the workarounds above.
    for _, layerName in ipairs({ "headsLayer", "labelsLayer" }) do
        local layer = ui.Layer.new(parent)
        layer.clickthrough = true
        layer:SetPos(0, 0)
        layer:SetSize(0, 0, 1.0, 1.0)
        self[layerName] = layer
    end
    -- Placed again when the window is shown, resized or dropped after a drag: the window's overlays. (The labels layer
    -- is the overlay: PrettyUI raises it after the layout, which raises the heads first, so the labels end up on top.)
    window:_RegisterOverlay(self.labelsLayer, nil, function() if not self.closed then self:layout() end end)
    -- At each step of a title-bar drag: PrettyUI notes the position through the window's drag bounds.
    local dragBounds = window.dragBounds
    local rememberPosition = dragBounds.RememberPosition
    dragBounds.RememberPosition = function(...)
        rememberPosition(...)
        if not self.closed then self:layout() end
    end
    -- One frame after a title-bar click, which raises the window over the layers: PrettyUI's click handler first
    -- disables the resize controller, which is caught here (the click's own hook stops later listeners).
    raiseCount = raiseCount + 1
    self.raiseSubscription = "make_me_a_monster_grid_raise_" .. raiseCount
    local resize = window.resize
    local setResizeEnabled = resize.SetEnabled
    resize.SetEnabled = function(controller, enabled)
        setResizeEnabled(controller, enabled)
        if enabled or self.closed then return end
        Event.Draw.Subscribe(self.raiseSubscription, function()
            Event.Draw.Unsubscribe(self.raiseSubscription)
            if not self.closed then
                self.headsLayer:MoveToFront()
                self.labelsLayer:MoveToFront()
            end
        end)
    end
    -- The bottom row. (No angle brackets in the button text: the game reads "<" as the start of a markup tag.)
    local nav = self.nav
    local buttonOptions = { width = NAV_BUTTON }
    nav.previous = PrettyUI.SimpleButton.new(content, "Previous", function() self:changePage(-1) end, buttonOptions)
    nav.after = PrettyUI.SimpleButton.new(content, "Next", function() self:changePage(1) end, buttonOptions)
    if options.withSearch then
        nav.search = PrettyUI.TextField.new(content, {
            width = 204, height = 30, placeholder = "Search name or id",
            onChange = function(_, _, text) if not self.closed then self.onSearch(text) end end,
        })
        nav.jump = PrettyUI.TextField.new(content, {
            width = 70, height = 30, placeholder = "Page", filterMode = ui.InputFieldFilterMode.NUMERIC,
            onSubmit = function(_, text)
                local page = tonumber(text)
                if page ~= nil and not self.closed then
                    self.page = page
                    self:showPage()
                end
            end,
        })
    end
    nav.label = ui.Text.new(content)
    nav.label.maxLines = 1
    nav.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
    nav.label.rgba = TEXT_LIGHT
    if not options.withSearch then nav.label.alignHorizontal = ui.AlignMode.CENTRE end
    self:setHeads(options.ids, options.current)
    -- The window's SetSize caught: the cells placed at once for the new size, as PrettyUI keeps it within the limits.
    local setWindowSize = self.window.SetSize
    self.window.SetSize = function(window, newWidth, newHeight)
        setWindowSize(window, newWidth, newHeight)
        if self.closed then return end
        newWidth = math.max(window.minWidth, math.min(window.maxWidth or newWidth, math.floor(newWidth)))
        newHeight = math.max(window.minHeight, math.min(window.maxHeight or newHeight, math.floor(newHeight)))
        self.contentWidth, self.contentHeight = contentSizeOf(newWidth, newHeight)
        self:layout()
    end
    return self
end

return HeadGrid
