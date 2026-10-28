-- Make Me A Monster: choose an NPC in the plugin's page, and its head replaces yours in the game's
-- dialogue boxes.

local Settings = require("src/data/settings")
local Npcs = require("src/game/npcs")
local HeadSwap = require("src/game/head_swap")
local Variants = require("src/ui/variants")
local HeadGallery = require("src/ui/head_gallery")
local Anims = require("src/game/anims")

local PrettyUI = prettyui

local RESULTS_SHOWN = 40 -- NPCs listed in the dropdown at once

-- The animation the head plays by the player's choice.
local function applyAnimChoice()
    HeadSwap.animOverride = Settings.animOverride
    -- (the heads in the windows open play it too)
    pcall(HeadGallery.updateAnimations)
    pcall(Variants.updateAnimations)
end

-- The saved choices, applied. (Loaded again on entering the game: the saved data may not be readable yet when
-- the plugin starts.)
local function loadSettings()
    Settings.load()
    Variants.savedSize = Settings.variantsWidth and { width = Settings.variantsWidth, height = Settings.variantsHeight }
        or nil
    HeadGallery.savedSize = Settings.galleryWidth and { width = Settings.galleryWidth, height = Settings.galleryHeight }
        or nil
    HeadSwap.npcID = Settings.npcID
    HeadSwap.scale = Settings.headScale / 100
    applyAnimChoice()
    HeadSwap.learnedAnim = Settings.animID
end

loadSettings()
Variants.onResized = function(width, height)
    Settings.setVariantsSize(width, height)
    Variants.savedSize = { width = width, height = height }
end
HeadGallery.onResized = function(width, height)
    Settings.setGallerySize(width, height)
    HeadGallery.savedSize = { width = width, height = height }
end
Variants.animFor = function() return HeadSwap.currentAnim() end
-- The heads in the window are NPC heads: with the player's own head in use they play the NPC version of the animation
-- chosen (the choice itself is kept, so closing the window without picking a head leaves the player's version).
HeadGallery.animFor = function() return HeadSwap.animForHead(HeadSwap.currentAnim(), false) end
Variants.animForPlayer = function() return HeadSwap.ownHeadAnim(true) end
-- The head size setting applies to the heads in the variants and all-heads windows too.
Variants.scaleFor = function() return HeadSwap.scale end
HeadGallery.scaleFor = Variants.scaleFor
HeadSwap.onLearned = function(animID) Settings.setAnim(animID) end

local page = nil -- the plugin page's controls: { view, search, combo, status, progress }
local shownGroups = {} -- entry id -> the group (every NPC of one name) the dropdown lists now
local shownAnimations = {} -- entry id -> the animation the animation dropdown lists
local refreshing = false
local refreshingAnimations = false

-- Workaround: a dropdown always shows one of its entries, and unselecting or selecting from code doesn't change its
-- text reliably. So a dropdown's closed box is covered (as read_later does for its books dropdown, see its
-- titleCover): its own text is made invisible (the box's colours, alpha and shadow), and with a title given a label of
-- ours with that title is laid over it; with none the box is blank. The player clicking it open puts it back as it
-- was, and so does it being given a choice to show. (Not on its change events: it can send those on its own after
-- its list is given.)
local covers = {} -- dropdown -> { colours = its text's saved colours, covered = whether it is covered now, label = our label }

-- title: the text to show in the covered box, or nil for a blank one.
local function setCover(combo, hidden, title)
    pcall(function()
        local root = combo.root
        local cover = covers[combo]
        if cover == nil then
            cover = { covered = false }
            covers[combo] = cover
        end
        if hidden then
            if not cover.covered then
                cover.colours = { root.entryText.rgba, root.selectedForegroundRGBA, root.mouseoverForegroundRGBA,
                    alpha = root.entryText.alpha, isShadowed = root.entryText.isShadowed }
                cover.covered = true
                root.entryText.rgba, root.selectedForegroundRGBA, root.mouseoverForegroundRGBA = 0, 0, 0
                root.entryText.alpha, root.entryText.isShadowed = 0, false
            end
            if title == nil then
                if cover.label ~= nil then cover.label.hidden = true end
                return
            end
            local label = cover.label
            if label == nil then
                label = ui.Text.new(root.parent)
                label.clickthrough = true
                label.maxLines = 1
                label.alignHorizontal = ui.AlignMode.TOPLEFT
                label.alignVertical = ui.AlignMode.CENTRE
                cover.label = label
            end
            -- Where the box's own text goes: its 8 inset at the left, clear of its arrow button (as wide as the box
            -- is high) at the right; in its font and colour.
            label:SetPos(root.x + 8, root.y)
            label:SetSize(math.max(1, root.width - 8 - root.height), root.height)
            label.font = root.entryText.font
            label.rgba = cover.colours[1]
            label.isShadowed = cover.colours.isShadowed
            label.content = title
            label.hidden = false
            label:MoveToFront()
        elseif cover.covered then
            local saved = cover.colours
            cover.covered = false
            if cover.label ~= nil then cover.label.hidden = true end
            root.entryText.rgba, root.selectedForegroundRGBA, root.mouseoverForegroundRGBA = saved[1], saved[2], saved[3]
            root.entryText.alpha, root.entryText.isShadowed = saved.alpha, saved.isShadowed
        end
    end)
end

-- The player opening a dropdown (clicking it): its text back.
local function showOnClick(combo)
    pcall(function()
        combo.root:Subscribe(ui.Hook.ONCLICK, function()
            setCover(combo, false)
            return false
        end)
    end)
end

-- The id of the entry in `shown` (entry id -> item) for which isActive(item) is true, or nil.
local function selectedEntry(shown, isActive)
    for entryID, item in pairs(shown) do
        if isActive(item) then return entryID end
    end
    return nil
end

local function statusText()
    local npcID = Settings.npcID
    if npcID == nil then return "Current chathead: my own head" end
    local name = Npcs.nameOf(npcID)
    local group = Npcs.groupOf(npcID)
    local variant = group and #group.ids > 1 and (" (variant ID " .. npcID .. ")") or ""
    return "Current chathead: " .. (name or ("NPC " .. npcID)) .. variant
end

local function animStatusText()
    local chosen = Settings.animOverride
    if chosen ~= nil then
        return "Animation: " .. (Anims.displayName(chosen) or ("ID " .. chosen))
    end
    return "" -- (the default: nothing to say)
end

local function refreshStatus()
    if page then
        pcall(function() page.status.content = statusText() end)
        pcall(function() page.animStatus.content = animStatusText() end)
    end
end

-- The chosen animation changed to one the head in use plays, when the player's own head and an NPC's are switched
-- between (they play different animations, see HeadSwap.animForHead).
local function fitAnimToHead()
    if not Anims.done or Settings.animOverride == nil then return end
    -- (with the player's own head and the heads window open, the animation stays as it is until the window closes)
    if Settings.npcID == nil and HeadGallery.isOpen() then return end
    local fitted = HeadSwap.animForHead(Settings.animOverride, Settings.npcID == nil)
    if fitted ~= Settings.animOverride then
        Settings.setAnimOverride(fitted)
        applyAnimChoice()
    end
end

-- The animation dropdown filled with the animations for the head in use (the player's own: for the NPC heads'
-- ones, as the lists show them, in name order), the chosen one selected. A choice saved earlier that is no longer on the whitelist is cleared once they are read.
local function refreshAnimations()
    if page == nil then return end
    fitAnimToHead()
    if Anims.done and Settings.animOverride ~= nil and Anims.find(Settings.animOverride) == nil then
        Settings.setAnimOverride(nil)
        applyAnimChoice()
        refreshStatus()
    end
    -- The animations for NPC heads, unless the player's own head is in use and no heads window is open (the heads
    -- in it are NPC heads, whatever head is in use).
    local npcHeads = Settings.npcID ~= nil or HeadGallery.isOpen()
    local found = Anims.search("", math.huge, not npcHeads)
    table.sort(found, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end)
    local entries = {}
    shownAnimations = {}
    for index, anim in ipairs(found) do
        entries[#entries + 1] = { label = anim.label, id = index }
        shownAnimations[index] = anim
    end
    -- (the one chosen, as its NPC version if it is one for the player's head and the list is of NPC ones)
    local shownChoice = Settings.animOverride
    if npcHeads then shownChoice = HeadSwap.animForHead(shownChoice, false) end
    local selected = selectedEntry(shownAnimations, function(anim) return anim.id == shownChoice end)
    refreshingAnimations = true
    pcall(function() page.animCombo:SetEntries(entries, selected) end)
    refreshingAnimations = false
    -- (a blank box with nothing chosen, else our label with its name: the dropdown's own text doesn't follow a choice made
    -- by the plugin)
    setCover(page.animCombo, true, selected ~= nil and shownAnimations[selected].label or nil)
end

-- The dropdown refilled with the NPCs matching the search box.
local function refreshResults()
    if page == nil then return end
    local query = ""
    pcall(function() query = page.search:GetText() end)
    local found = Npcs.search(query, RESULTS_SHOWN)
    local matches = #found
    -- With nothing typed, the NPC chosen stays in the list (at the top) even if it isn't among the first, so
    -- the dropdown can show it after a restart.
    local active = Settings.npcID and Npcs.groupOf(Settings.npcID) or nil
    if active ~= nil and query:find("^%s*$") then
        local present = false
        for _, group in ipairs(found) do
            if group == active then present = true end
        end
        if not present then table.insert(found, 1, active) end
    end
    local entries = {}
    shownGroups = {}
    for index, group in ipairs(found) do
        entries[#entries + 1] = { label = Npcs.groupLabel(group, #group.ids), id = index }
        shownGroups[index] = group
    end
    local chosen = Settings.npcID and Npcs.groupOf(Settings.npcID) or nil
    local selected = selectedEntry(shownGroups, function(group) return group == chosen end)
    refreshing = true
    pcall(function() page.combo:SetEntries(entries, selected) end)
    refreshing = false
    setCover(page.combo, selected == nil)
    pcall(function()
        page.progress.content = matches == RESULTS_SHOWN and ("Showing the first " .. RESULTS_SHOWN .. " matches.")
            or (matches .. " matches.")
    end)
end

local openVariants -- (below)
local openHeadGallery -- (below)

local function chooseNpc(npcID, fromCombo)
    Settings.setNpc(npcID)
    HeadSwap.npcID = npcID
    fitAnimToHead()
    refreshAnimations()
    if not fromCombo then refreshResults() end -- (the dropdown shows it, or nothing)
    refreshStatus()
end

local function isSelected(eventType)
    local ok, selected = pcall(function() return eventType == ui.SelectionChangeEvent.SELECTED end)
    return not ok or selected or eventType == nil
end

-- The window of every NPC sharing the chosen one's name; a click on one makes it the active head.
openVariants = function()
    -- Works with a single variant too, as a preview of the head.
    -- With the player's own head in use, the window shows just that head.
    local group = Settings.npcID and Npcs.groupOf(Settings.npcID) or nil
    local own = Settings.npcID == nil
    local note = ""
    if group == nil and not own then
        note = "Choose an NPC first."
    else
        -- The top plugin layer, above the game's own interfaces (as read_later's windows over its dialogue).
        local ok, parent = pcall(function()
            return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        end)
        if ok and parent ~= nil then
            local function picked(npcID) chooseNpc(npcID ~= Variants.PLAYER and npcID or nil) end
            if own then
                Variants.open(PrettyUI, parent, "My head", { Variants.PLAYER }, Variants.PLAYER, picked)
            else
                local ids = group.ids
                Variants.open(PrettyUI, parent, group.name .. " variants", ids, Settings.npcID, picked, Npcs.nameOf)
            end
        else
            note = "The game screen isn't ready."
        end
    end
    if page then pcall(function() page.variantsNote.content = note end) end
end

-- The plugin's page in the client's Plugins window.
local function buildPage(parent)
    -- The saved list of heads (src/data/heads.lua): nothing is read from the game.
    if not Npcs.loaded then Npcs.load(require("src/data/heads")) end
    pcall(Anims.load) -- (about a hundred lookups: the animation dropdown needs them)
    local view = PrettyUI.SimpleView.new(parent, { width = parent.width, height = parent.height })
    view:AddTitle("Make Me A Monster")
    view:AddText("Pick an NPC: its head replaces yours in dialogue boxes.")
    local made = { view = view }
    made.status = view:AddText(statusText())
    made.search = view:AddTextField({
        placeholder = "Search NPCs by name or id",
        onChange = function() refreshResults() end,
    })
    made.progress = view:AddText("")
    made.combo = view:AddComboBox({
        entries = {},
        onChange = function(_, entryID, _, eventType)
            local group = shownGroups[entryID]
            if refreshing or not isSelected(eventType) or group == nil then return end
            setCover(made.combo, false)
            -- The first variant that has a head (the lowest id may be blank).
            chooseNpc(group.ids[1], true)
        end,
    })
    showOnClick(made.combo)
    view:AddSimpleButton("View variants", function() openVariants() end)
    view:AddSimpleButton("Browse all heads", function() openHeadGallery() end)
    view:AddSimpleButton("Use my own head", function() chooseNpc(nil) end)
    made.variantsNote = view:AddText("")
    made.sizeText = view:AddText("Head size: " .. Settings.headScale .. "%")
    view:AddSlider({
        min = 100,
        max = 300,
        step = 5,
        value = Settings.headScale,
        onChange = function(_, value)
            local percent = math.max(100, math.min(300, math.floor(value / 5 + 0.5) * 5))
            Settings.setHeadScale(percent)
            HeadSwap.scale = percent / 100
            pcall(function() made.sizeText.content = "Head size: " .. percent .. "%" end)
        end,
    })
    view:AddText("Animation for the head:")
    made.animStatus = view:AddText(animStatusText())
    made.animCombo = view:AddComboBox({
        entries = {},
        onChange = function(_, entryID, _, eventType)
            local anim = shownAnimations[entryID]
            if refreshingAnimations or not isSelected(eventType) or anim == nil then return end
            Settings.setAnimOverride(anim.id)
            setCover(made.animCombo, false)
            applyAnimChoice()
            refreshStatus()
        end,
    })
    showOnClick(made.animCombo)
    view:AddSimpleButton("Use default animation", function()
        Settings.setAnimOverride(nil)
        applyAnimChoice()
        refreshAnimations()
        refreshStatus()
    end)
    page = made
    refreshResults()
    refreshAnimations()
end

Event.ContentLayerReady.Subscribe("make_me_a_monster_content", function(e)
    if page ~= nil then pcall(function() page.view:Destroy() end) page = nil end
    pcall(buildPage, e.component)
end)

-- The heads the plugin lists, one per id, in name order.
local function listedHeads()
    local heads = {}
    for _, group in ipairs(Npcs.groups) do
        for _, npcID in ipairs(group.ids) do heads[#heads + 1] = npcID end
    end
    local lowered = {}
    for _, npcID in ipairs(heads) do lowered[npcID] = Npcs.lower(Npcs.nameOf(npcID) or "") end
    table.sort(heads, function(a, b)
        if lowered[a] ~= lowered[b] then return lowered[a] < lowered[b] end
        return a < b
    end)
    return heads
end

-- The heads window closed: the dropdown goes back to the animations of the head in use. With the player's own head
-- in use (no head picked) an NPC animation chosen meanwhile becomes the player's version of it.
HeadGallery.onClosed = function()
    fitAnimToHead()
    applyAnimChoice()
    refreshAnimations()
    refreshStatus()
end

-- Opens the window of every head the plugin lists; a click on one makes it the active head.
openHeadGallery = function()
    local note = ""
    do
        local ok, parent = pcall(function()
            return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        end)
        if ok and parent ~= nil then
            HeadGallery.open(PrettyUI, parent, listedHeads(), Settings.npcID, function(npcID) chooseNpc(npcID) end,
                Npcs.nameOf)
            refreshAnimations() -- (the animations for NPC heads, if the player's head is in use)
        else
            note = "The game screen isn't ready."
        end
    end
    if page then pcall(function() page.variantsNote.content = note end) end
end

Event.Draw.Subscribe("make_me_a_monster_draw", function()
    pcall(Variants.tick)
    pcall(HeadGallery.tick)
    pcall(HeadSwap.tick)
end)

Event.GameStateChanged.Subscribe("make_me_a_monster_state", function(e)
    if e.newState == 30 then
        loadSettings()
        refreshAnimations()
        refreshStatus()
    elseif e.oldState == 30 then
        HeadSwap.reset()
        Settings.save()
    end
end)

function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe("make_me_a_monster_content")
    Event.Draw.Unsubscribe("make_me_a_monster_draw")
    Event.GameStateChanged.Unsubscribe("make_me_a_monster_state")
    Variants.close()
    HeadGallery.close()
    Settings.save()
    if page ~= nil then pcall(function() page.view:Destroy() end) page = nil end
end
