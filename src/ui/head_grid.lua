-- A window of chat heads in a paged grid (the "all heads" and "variants" windows, and the debug windows). The cells are made once and reused
-- for every page. Heads aren't drawn in their own windows to avoid graphical errors.
--
-- Models aren't clipped by a scroll area: so pages, not scrolling.
-- Models drawn in two regions of the tree (a window's content or root, a dialogue box) make the game flicker along
-- their top and right edges: so they are drawn in a single layer, overlaid on the windows.
-- Components left to a parent's Destroy make the plugin lag when it unloads: so a closing window destroys every part
-- of every cell itself, the models first.
--
-- HeadGrid.open(PrettyUI, parent, options) -> the grid, or nil. options: title; columns, rows; ids; current;
--   minWidth; savedWidth/Height/X/Y; page (else the page of the head in use); withSearch;
--   toggle = { text, selected, onChange(selected) } (a check box, with withSearch);
--   extraButton = { text, onClick() } (a button at the row's end, without withSearch; hidden without a text);
--   numberBox = { placeholder, onSubmit(number) } (a number field after Next, without withSearch);
--   marksPick = false (a head clicked is not marked as the one in use);
--   nameOf(id, position); isPlayerHead(id); animationFor(id, position) (position: the head's place in ids, for a head
--   listed more than once); pageLabel(page, pages, shown); onPick(id); onSearch(text);
--   onPlacement(width, height, x, y); onClosed().
-- grid:setHeads(ids, current, title, page); grid:setExtraButton(text); grid:updateAnimations();
-- grid:refreshHeadSize(); grid:close(). HeadGrid.addWindowFunctions gives a window module its isOpen,
-- updateAnimations, refreshHeadSize and close.

local Settings = require("src/data/settings")
local HeadSizes = require("src/game/head_sizes")

local HeadGrid = {}
HeadGrid.__index = HeadGrid

local PAD, GAP = 8, 6
local NAV_HEIGHT = 36
local NAV_BUTTON = 80
local NAV_TOGGLE = 130 -- (a check box and its label)
local NAV_NUMBER = 70
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
local CELL_PARTS = { "model", "name", "idLabel", "background", "click" } -- (the order they are destroyed in)
local raiseCount = 0 -- (for a Draw subscription id of each grid's own)

local function frameSize(columns, rows, cellW, cellH)
    return columns * cellW + (columns - 1) * GAP + PAD * 2 + BORDERS,
        rows * cellH + (rows - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
end

local WIDTH_SHARE, HEIGHT_SHARE = 0.45, 0.75

function HeadGrid.defaultSize(parent)
    local width, height = frameSize(5, 4, START_CELL_W, START_CELL_H)
    local scale = math.min(parent.width * WIDTH_SHARE / width, parent.height * HEIGHT_SHARE / height)
    return math.floor(width * scale), math.floor(height * scale)
end

local function contentSizeOf(windowWidth, windowHeight)
    return windowWidth - BORDERS, windowHeight - TITLE_AND_BOTTOM
end

local function pageOf(ids, current, pageSize)
    for position, npcID in ipairs(ids) do
        if npcID == current then return math.ceil(position / pageSize) end
    end
    return 1
end

function HeadGrid:geometry()
    local width, height = self.contentWidth, self.contentHeight
    local cellW = math.max(40, math.floor((width - PAD * 2 - (self.columns - 1) * GAP) / self.columns))
    local cellH = math.max(60, math.floor((height - PAD * 2 - NAV_HEIGHT - 4 - (self.rows - 1) * GAP) / self.rows))
    local gridW = self.columns * cellW + (self.columns - 1) * GAP
    return { width = width, cellW = cellW, cellH = cellH, originX = math.max(0, math.floor((width - gridW) / 2)),
        originY = PAD, gridH = self.rows * cellH + (self.rows - 1) * GAP }
end

function HeadGrid:placeCell(cell, g)
    local column, row = (cell.index - 1) % self.columns, math.floor((cell.index - 1) / self.columns)
    local x, y = g.originX + column * (g.cellW + GAP), g.originY + row * (g.cellH + GAP)
    local headSize = math.max(16, math.min(g.cellW, g.cellH - LABELS_HEIGHT)) -- (square, over the labels)
    cell.background:SetPos(x, y)
    cell.background:SetSize(g.cellW, g.cellH)
    cell.model:SetPos(g.offsetX + x + math.floor((g.cellW - headSize) / 2), g.offsetY + y)
    -- A model set again is redrawn from nothing, and a resize places the cells at every step: so only when they change.
    if cell.headSize ~= headSize then
        cell.headSize = headSize
        cell.model:SetSize(headSize, headSize)
    end
    -- A head is drawn larger by moving the camera closer.
    local viewDistance = math.max(1, math.floor(BASE_VIEW * BASE_SIZE / headSize / WINDOW_HEAD_SCALE
        / Settings.headScaleMultiplier() / HeadSizes.of(cell.id)))
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

function HeadGrid:placeNavigation(g)
    local y = g.originY + g.gridH + 4
    local nav = self.nav
    nav.previous.root:SetPos(PAD, y + 2)
    nav.after.root:SetPos(PAD + NAV_BUTTON + 6, y + 2)
    if nav.search then
        nav.search.root:SetPos(PAD + 180, y + 2)
        nav.jump.root:SetPos(PAD + 392, y + 2)
        local labelX = 470
        if nav.toggle then
            nav.toggle.root:SetPos(PAD + labelX, y + 6)
            labelX = labelX + NAV_TOGGLE
        end
        nav.label:SetPos(PAD + labelX, y + 8)
        nav.label:SetSize(math.max(1, g.width - PAD * 2 - labelX), 20)
    else
        local labelX, labelEnd = PAD + (NAV_BUTTON + 6) * 2, g.width - PAD
        if nav.number then
            nav.number.root:SetPos(labelX, y + 2)
            labelX = labelX + NAV_NUMBER + 6
        end
        if nav.extra and not nav.extra.root.hidden then
            labelEnd = labelEnd - self.extraWidth
            nav.extra.root:SetPos(labelEnd, y + 2)
            labelEnd = labelEnd - 6
        end
        nav.label:SetPos(labelX, y + 8)
        nav.label:SetSize(math.max(1, labelEnd - labelX), 20)
    end
end

function HeadGrid:place()
    local g = self:geometry()
    -- The heads and labels are in layers on the plugin layer: placed from where the content is there.
    local root = self.window.root
    g.offsetX, g.offsetY = root.x + BORDERS / 2, root.y + TITLE_AND_BOTTOM - BORDERS / 2
    for _, cell in ipairs(self.cells) do self:placeCell(cell, g) end
    self:placeNavigation(g)
end

-- Only with the window: raising these layers on anything else (a page, the head size) would put its heads over a window
-- in front of it.
function HeadGrid:layout()
    self:place()
    self.headsLayer:MoveToFront()
    self.labelsLayer:MoveToFront()
end

local function setCellHidden(cell, hidden)
    for _, part in ipairs(CELL_PARTS) do cell[part].hidden = hidden end
end

function HeadGrid:paintCell(cell, hovered)
    cell.background.colour = hovered and HOVER or (cell.id == self.current and CURRENT or BACKGROUND)
end

function HeadGrid:pick(pickedCell)
    if self.marksPick then self.current = pickedCell.id end
    self.onPick(pickedCell.id)
    for _, cell in ipairs(self.cells) do self:paintCell(cell, cell == pickedCell) end
end

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
    -- Over the rest, taking the click.
    cell.click = ui.Layer.new(content)
    cell.click.clickthrough = false
    cell.click:Subscribe(ui.Hook.ONMOUSEOVER, function() self:paintCell(cell, true) end)
    cell.click:Subscribe(ui.Hook.ONMOUSELEAVE, function() self:paintCell(cell, false) end)
    cell.click:Subscribe(ui.Hook.ONCLICK, function() if cell.id ~= nil then self:pick(cell) end end)
    setCellHidden(cell, true)
end

local function modelTypeFor(self, npcID)
    return self.isPlayerHead(npcID) and ui.ModelType.PLAYER_HEAD or ui.ModelType.NPC_HEAD
end

-- A model set again is redrawn from nothing: so a cell keeping its head keeps its model.
function HeadGrid:fillCell(cell, npcID, position)
    cell.position = position
    if cell.id ~= npcID then
        cell.id = npcID
        cell.model:SetModel(modelTypeFor(self, npcID), npcID)
        cell.viewDistance = nil -- (SetModel puts the view distance back to its default: placeCell sets it again)
        local animationID = self.animationFor(npcID, position)
        if animationID ~= nil then cell.model.animID = animationID end
    end
    local isPlayer = self.isPlayerHead(npcID)
    local name = not isPlayer and self.nameOf(npcID, position) or nil
    cell.name.content = isPlayer and "My head" or name or ("ID " .. npcID)
    cell.idLabel.content = name and ("ID " .. npcID) or ""
    setCellHidden(cell, false)
    self:paintCell(cell, false)
end

-- The model is let go, not just hidden, so a page with few heads keeps few loaded.
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
        if npcID == nil then emptyCell(cell) else self:fillCell(cell, npcID, first + cell.index) end
    end
    self.nav.label.content = self.pageLabel(self.page, self.pages, #self.ids)
    self:place()
    self.nav.previous.root.hidden = self.page <= 1
    self.nav.after.root.hidden = self.page >= self.pages
end

-- Shows other heads, on this page, else on the page of the one in use.
function HeadGrid:setHeads(ids, current, title, page)
    self.ids, self.current = ids, current
    self.pages = math.max(1, math.ceil(#ids / self.pageSize))
    self.page = page or pageOf(ids, current, self.pageSize)
    if title ~= nil then self.window:SetTitle(title) end
    self:showPage()
end

-- No text, no button.
function HeadGrid:setExtraButton(text)
    local button = self.nav.extra
    if button == nil then return end
    button.root.hidden = text == nil
    if text ~= nil then
        button.content.content = text
        self.extraWidth = self.simpleButton.getSize(text)
        button.root:SetSize(self.extraWidth, button.root.height)
    end
    if #self.cells > 0 then self:place() end -- (else the first page places it)
end

function HeadGrid:changePage(pageChange)
    local page = math.max(1, math.min(self.pages, self.page + pageChange))
    if page ~= self.page then
        self.page = page
        self:showPage()
    end
end

function HeadGrid:updateAnimations()
    for _, cell in ipairs(self.cells) do
        if cell.id ~= nil then
            local animationID = self.animationFor(cell.id, cell.position)
            if animationID ~= nil then
                cell.model.animID = animationID
            else
                cell.model:SetModel(modelTypeFor(self, cell.id), cell.id) -- (no animation: the head as it starts)
                cell.model.viewDistance = cell.viewDistance
            end
        end
    end
end

function HeadGrid:refreshHeadSize()
    self:place()
end

-- Runs however the window was closed.
function HeadGrid:release()
    if self.closed then return end
    self.closed = true
    local root = self.window.root
    self.onPlacement(math.floor(root.width), math.floor(root.height),
        math.max(0, math.floor(root.x)), math.max(0, math.floor(root.y)))
    Event.Draw.Unsubscribe(self.raiseSubscription)
    self.window:_UnregisterOverlay(self.labelsLayer)
    -- Every part destroyed one by one: see the top of this file.
    for _, cell in ipairs(self.cells) do
        for _, part in ipairs(CELL_PARTS) do cell[part]:Destroy() end
    end
    self.cells = {}
    for _, control in pairs(self.nav) do control:Destroy() end
    self.nav = {}
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
        marksPick = options.marksPick ~= false,
        cells = {}, nav = {}, closed = false, page = options.page, simpleButton = PrettyUI.SimpleButton,
    }, HeadGrid)
    -- As it was left, else the default; kept on the screen.
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
    -- Beside the window, not in it: see the top of this file.
    for _, layerName in ipairs({ "headsLayer", "labelsLayer" }) do
        local layer = ui.Layer.new(parent)
        layer.clickthrough = true
        layer:SetPos(0, 0)
        layer:SetSize(0, 0, 1.0, 1.0)
        self[layerName] = layer
    end
    -- Placed again when the window is shown, resized or dropped. The labels layer is the overlay: PrettyUI raises it
    -- after the layout raises the heads, so the labels end up on top.
    window:_RegisterOverlay(self.labelsLayer, nil, function() if not self.closed then self:layout() end end)
    -- Placed again at each step of a title-bar drag: PrettyUI notes the position through the drag bounds.
    local dragBounds = window.dragBounds
    local rememberPosition = dragBounds.RememberPosition
    dragBounds.RememberPosition = function(...)
        rememberPosition(...)
        if not self.closed then self:layout() end
    end
    -- A title-bar click raises the window over the layers, and its hook stops later listeners: so the layers are raised
    -- a frame after its handler disables the resize controller.
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
    -- The game reads "<" in a button's text as the start of a markup tag.
    local nav = self.nav
    local buttonOptions = { width = NAV_BUTTON }
    nav.previous = PrettyUI.SimpleButton.new(content, "Previous", function() self:changePage(-1) end, buttonOptions)
    nav.after = PrettyUI.SimpleButton.new(content, "Next", function() self:changePage(1) end, buttonOptions)
    local function numberField(placeholder, onNumber)
        return PrettyUI.TextField.new(content, {
            width = NAV_NUMBER, height = 30, placeholder = placeholder, filterMode = ui.InputFieldFilterMode.NUMERIC,
            onSubmit = function(_, text)
                local number = tonumber(text)
                if number ~= nil and not self.closed then onNumber(math.floor(number)) end
            end,
        })
    end
    if options.withSearch then
        nav.search = PrettyUI.TextField.new(content, {
            width = 204, height = 30, placeholder = "Search name or id",
            onChange = function(_, _, text) if not self.closed then self.onSearch(text) end end,
        })
        nav.jump = numberField("Page", function(page) self:changePage(page - self.page) end)
    end
    if options.numberBox then nav.number = numberField(options.numberBox.placeholder, options.numberBox.onSubmit) end
    if options.extraButton then
        nav.extra = PrettyUI.SimpleButton.new(content, "", function()
            if not self.closed then options.extraButton.onClick() end
        end)
        nav.extra.root.hidden = true -- (until it has a text, and so a width)
    end
    if options.toggle then
        nav.toggle = PrettyUI.CheckboxButton.new(content,
            { { text = options.toggle.text, value = true, selected = options.toggle.selected } }, {
                width = NAV_TOGGLE,
                onChange = function(_, _, _, selected)
                    if not self.closed then options.toggle.onChange(selected) end
                end,
            })
    end
    nav.label = ui.Text.new(content)
    nav.label.maxLines = 1
    nav.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
    nav.label.rgba = TEXT_LIGHT
    if options.extraButton then self:setExtraButton(options.extraButton.text) end
    self:setHeads(options.ids, options.current, nil, options.page)
    -- Catches resizes. The content takes its new size only a moment later: so the size is worked out here, as PrettyUI
    -- keeps it within its limits, before PrettyUI lays the overlay out again.
    local setWindowSize = self.window.SetSize
    self.window.SetSize = function(window, newWidth, newHeight)
        if not self.closed then
            newWidth = math.max(window.minWidth, math.min(window.maxWidth or newWidth, math.floor(newWidth)))
            newHeight = math.max(window.minHeight, math.min(window.maxHeight or newHeight, math.floor(newHeight)))
            self.contentWidth, self.contentHeight = contentSizeOf(newWidth, newHeight)
        end
        setWindowSize(window, newWidth, newHeight)
    end
    return self
end

-- A window module's functions for its grid, while one is open: currentGrid() gives it, or nil.
function HeadGrid.addWindowFunctions(windowModule, currentGrid)
    function windowModule.isOpen() return currentGrid() ~= nil end
    function windowModule.updateAnimations() if currentGrid() then currentGrid():updateAnimations() end end
    function windowModule.refreshHeadSize() if currentGrid() then currentGrid():refreshHeadSize() end end
    function windowModule.close() if currentGrid() then currentGrid():close() end end
end

return HeadGrid
