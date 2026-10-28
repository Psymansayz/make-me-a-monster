-- Make Me A Monster: choose an NPC in the plugin's page, and its head replaces yours in the game's
-- dialogue boxes.

local Settings = require("src/data/settings")
local Npcs = require("src/game/npcs")
local HeadSwap = require("src/game/head_swap")
local Variants = require("src/ui/variants")
local HeadGallery = require("src/ui/head_gallery")
local Anims = require("src/game/anims")

local PrettyUI = prettyui

-- TEMPORARY debug window (src/debug/head_browser.lua): every head left after the filtering, to flag the ones to
-- blacklist. A button for it is added to the plugin page. Remove DEBUG_HEAD_BROWSER and what uses it when done.
local DEBUG_HEAD_BROWSER = true
local HeadBrowser = require("src/debug/head_browser")

-- The ids of an NPC group worth showing. With the saved list (src/data/heads.lua) they are all its ids. Without it
-- (development: the file is made from a scan, see finalizeGroups) they are worked out once per group by
-- HeadFilter.variants (again if the group has gained ids since: the NPCs are still being read).
local visibleByGroup = {}

local function visibleIds(group)
    if Npcs.baked then return group.ids end
    local HeadFilter = require("src/game/head_filter")
    local cached = visibleByGroup[group]
    if cached == nil or cached.count ~= #group.ids then
        cached = { count = #group.ids, ids = HeadFilter.variants(group.ids) }
        visibleByGroup[group] = cached
    end
    return cached.ids
end
local RESULTS_SHOWN = 40 -- NPCs listed in the dropdown at once (there are tens of thousands)

-- The animation the head plays by the player's choice.
local function applyAnimChoice()
    HeadSwap.animOverride = Settings.animOverride
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
HeadGallery.animFor = Variants.animFor
Variants.animForPlayer = function() return HeadSwap.ownHeadAnim(true) end
-- The head size setting applies to the heads in the variants window and the debug window too.
Variants.scaleFor = function() return HeadSwap.scale end
HeadGallery.scaleFor = Variants.scaleFor
HeadSwap.onLearned = function(animID) Settings.setAnim(animID) end

-- Nothing is read from the game (its NPCs, their heads, the animations) until the plugin page is first opened:
-- the head in dialogue needs only the saved NPC id.
local engaged = false

local page = nil -- the plugin page's controls: { view, search, combo, status, progress }
local shownGroups = {} -- entry id -> the group (every NPC of one name) the dropdown lists now
local shownAnimations = {} -- entry id -> the animation the animation dropdown lists
local refreshing = false
local refreshingAnimations = false

-- Workaround: a dropdown always shows one of its entries, and unselecting leaves its text as it was. So a
-- dropdown with no choice of ours to show has its text made invisible (as read_later does for its books
-- dropdown, see its titleCover): the box's colours, alpha and shadow. The player clicking it open puts them
-- back, and so does it being given a choice to show. (Not on its change events: it can send those on its own
-- after its list is given.)
local covers = {} -- dropdown -> its text's saved colours, while hidden

local function setCover(combo, hidden)
    pcall(function()
        local root = combo.root
        local saved = covers[combo]
        if hidden then
            if saved ~= nil then return end
            covers[combo] = { root.entryText.rgba, root.selectedForegroundRGBA, root.mouseoverForegroundRGBA,
                alpha = root.entryText.alpha, isShadowed = root.entryText.isShadowed }
            root.entryText.rgba, root.selectedForegroundRGBA, root.mouseoverForegroundRGBA = 0, 0, 0
            root.entryText.alpha, root.entryText.isShadowed = 0, false
        elseif saved ~= nil then
            covers[combo] = nil
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
    local found = Anims.search("", math.huge, Settings.npcID == nil)
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
    local selected = selectedEntry(shownAnimations, function(anim) return anim.id == Settings.animOverride end)
    refreshingAnimations = true
    pcall(function() page.animCombo:SetEntries(entries, selected) end)
    refreshingAnimations = false
    setCover(page.animCombo, selected == nil)
end

-- The dropdown refilled with the NPCs matching the search box.
local function refreshResults()
    if page == nil then return end
    local query = ""
    pcall(function() query = page.search:GetText() end)
    local found = Npcs.search(query, RESULTS_SHOWN, visibleIds)
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
        entries[#entries + 1] = { label = Npcs.groupLabel(group, #visibleIds(group)), id = index }
        shownGroups[index] = group
    end
    local chosen = Settings.npcID and Npcs.groupOf(Settings.npcID) or nil
    local selected = selectedEntry(shownGroups, function(group) return group == chosen end)
    refreshing = true
    pcall(function() page.combo:SetEntries(entries, selected) end)
    refreshing = false
    setCover(page.combo, selected == nil)
    pcall(function()
        if Npcs.done then
            page.progress.content = matches == RESULTS_SHOWN and ("Showing the first " .. RESULTS_SHOWN .. " matches.")
                or (matches .. " matches.")
        else
            page.progress.content = "Reading the game's NPCs: " .. #Npcs.list .. " found so far..."
        end
    end)
end

local openVariants -- (below)
local openHeadGallery -- (below)
local openAnimationBrowser -- (below, debug only)
local openHeadBrowser -- (below, debug only)

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
                -- Variants with no head, and ones that look like another, are left out.
                local ids = visibleIds(group)
                if #ids == 0 then ids = group.ids end
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
    engaged = true
    -- The saved list of heads, if there is one: no scan.
    local okList, saved = pcall(require, "src/data/heads")
    if okList and type(saved) == "table" and not Npcs.baked then Npcs.loadBaked(saved) end
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
            chooseNpc(visibleIds(group)[1] or group.ids[1], true)
        end,
    })
    showOnClick(made.combo)
    view:AddSimpleButton("View variants", function() openVariants() end)
    view:AddSimpleButton("Browse all heads", function() openHeadGallery() end)
    view:AddSimpleButton("Use my own head", function() chooseNpc(nil) end)
    if DEBUG_HEAD_BROWSER then
        view:AddSimpleButton("Debug: flag heads for the blacklist", function() openHeadBrowser() end)
        view:AddSimpleButton("Debug: all animations on Hans", function() openAnimationBrowser() end)
    end
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
    local ok, err = pcall(buildPage, e.component)
    if not ok then print("[make_me_a_monster] could not build the page: " .. tostring(err)) end
end)

-- Once every NPC is read, each name is checked for variants worth showing (200 names a frame), names left with
-- none are dropped and the rest are merged into entries (Npcs.regroup).
local finalState = nil
local CHECK_PER_FRAME = 200

local function finalizeGroups()
    if Npcs.baked then return end
    if finalState == nil then
        if not Npcs.done then return end
        finalState = { index = 1 }
    end
    if finalState.done then return end
    for _ = 1, CHECK_PER_FRAME do
        local group = Npcs.groups[finalState.index]
        if group == nil then
            Npcs.regroup(function(entry) return #visibleIds(entry) > 0 end)
            -- Development: the list of heads to save as src/data/heads.lua, logged once.
            local lines, heads = Npcs.exportLines(visibleIds)
            print(("[make_me_a_monster] HEADS|begin|%d entries, %d heads, %d lines"):format(#Npcs.groups, heads, #lines))
            for _, line in ipairs(lines) do print(line) end
            print("[make_me_a_monster] HEADS|end")
            refreshResults()
            refreshStatus()
            finalState.done = true
            return
        end
        finalState.index = finalState.index + 1
        visibleIds(group)
    end
end

-- The heads the plugin lists, one per id (those left after the filtering), in name order.
local listedCache = nil

local function listedHeads()
    if listedCache ~= nil then return listedCache end
    local heads = {}
    for _, group in ipairs(Npcs.groups) do
        for _, npcID in ipairs(visibleIds(group)) do heads[#heads + 1] = npcID end
    end
    local lowered = {}
    for _, npcID in ipairs(heads) do lowered[npcID] = Npcs.lower(Npcs.nameOf(npcID) or "") end
    table.sort(heads, function(a, b)
        if lowered[a] ~= lowered[b] then return lowered[a] < lowered[b] end
        return a < b
    end)
    listedCache = heads
    return heads
end

-- Opens the window of every head the plugin lists; a click on one makes it the active head.
openHeadGallery = function()
    local note = ""
    if not Npcs.regrouped then
        note = "The NPCs are still being read."
    else
        local ok, parent = pcall(function()
            return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        end)
        if ok and parent ~= nil then
            HeadGallery.open(PrettyUI, parent, listedHeads(), Settings.npcID, function(npcID) chooseNpc(npcID) end,
                Npcs.nameOf)
        else
            note = "The game screen isn't ready."
        end
    end
    if page then pcall(function() page.variantsNote.content = note end) end
end

-- Opens the debug window on every head left after the filtering (once the entries are made).
openHeadBrowser = function()
    local note = ""
    if not Npcs.regrouped then
        note = "The NPCs are still being read."
    else
        local ok, parent = pcall(function()
            return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        end)
        if ok and parent ~= nil then
            local heads = {}
            for _, group in ipairs(Npcs.groups) do
                for _, npcID in ipairs(visibleIds(group)) do heads[#heads + 1] = npcID end
            end
            table.sort(heads)
            HeadBrowser.scaleFor = Variants.scaleFor
            HeadBrowser.open(PrettyUI, parent, heads, Npcs.nameOf, function() return HeadSwap.currentAnim() end)
        else
            note = "The game screen isn't ready."
        end
    end
    if page then pcall(function() page.variantsNote.content = note end) end
end

-- Debug: every animation in the game, each played on Hans (NPC id 0) in its own cell, in the debug window, with the
-- animations already on the whitelist tinted green and its duplicates blue. Clicking an animation selects it (red)
-- and logs it; "Log flagged" prints every selected animation as id=name, for adding to or taking off the
-- whitelist (src/data/animation_whitelist.lua). The search box narrows the list by name or id, for example to
-- "chat". Reading every animation takes a few seconds the first time (src/debug/animation_scan.lua).
local ANIMATION_HEAD = 0
local ANIMATION_ENTRIES_PER_LINE = 12
local AnimationScan = require("src/debug/animation_scan")
local Whitelist = require("src/data/animation_whitelist")
local animationBrowserWanted = false

local TINT_LISTED = { 0.10, 0.28, 0.12, 1 }     -- on the whitelist, listed in the dropdown
local TINT_DUPLICATE = { 0.10, 0.17, 0.34, 1 }  -- on the whitelist as a duplicate

local function showAnimationBrowser()
    local ok, parent = pcall(function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end)
    if not (ok and parent ~= nil) then return false end
    local ids, names, listed, duplicates = {}, {}, {}, {}
    for _, animID in ipairs(Whitelist.ids or {}) do listed[animID] = true end
    for _, animID in ipairs(Whitelist.duplicates or {}) do duplicates[animID] = true end
    for _, anim in ipairs(AnimationScan.list) do
        ids[#ids + 1] = anim.id
        names[anim.id] = anim.name
    end
    HeadBrowser.scaleFor = Variants.scaleFor
    HeadBrowser.open(PrettyUI, parent, ids, function(animID) return names[animID] end, nil, {
        title = "Debug: all animations on Hans (green: whitelisted, blue: duplicate; click to select)",
        logLabel = "animation selected",
        setup = function(model, animID)
            model:SetModel(ui.ModelType.NPC_HEAD, ANIMATION_HEAD)
            model.animID = animID
        end,
        tint = function(animID)
            return listed[animID] and TINT_LISTED or duplicates[animID] and TINT_DUPLICATE or nil
        end,
        flaggedLines = function(selected)
            local lines = { ("animations selected: %d (id=name)"):format(#selected) }
            for first = 1, #selected, ANIMATION_ENTRIES_PER_LINE do
                local parts = {}
                for index = first, math.min(#selected, first + ANIMATION_ENTRIES_PER_LINE - 1) do
                    parts[#parts + 1] = selected[index] .. "=" .. (names[selected[index]] or "?")
                end
                lines[#lines + 1] = ("animations selected #%d: %s"):format(
                    math.floor((first - 1) / ANIMATION_ENTRIES_PER_LINE) + 1, table.concat(parts, " | "))
            end
            return lines
        end,
    })
    return true
end

-- The button: reads every animation if that has not been done (a few frames at a time, from the Draw event, see
-- continueAnimationBrowser), then opens the window.
openAnimationBrowser = function()
    animationBrowserWanted = true
    if page then pcall(function() page.variantsNote.content = AnimationScan.done and "" or "Reading the game's animations..." end) end
end

local function continueAnimationBrowser()
    if not animationBrowserWanted then return end
    if not AnimationScan.done then
        AnimationScan.step()
        if page then
            pcall(function() page.variantsNote.content = "Reading the game's animations: " .. #AnimationScan.list .. " so far..." end)
        end
        return
    end
    animationBrowserWanted = false
    local opened = showAnimationBrowser()
    if page then pcall(function() page.variantsNote.content = opened and "" or "The game screen isn't ready." end) end
end

local frames = 0
Event.Draw.Subscribe("make_me_a_monster_draw", function()
    if engaged and not Npcs.done then
        local ok, err = pcall(Npcs.step)
        if not ok then print("[make_me_a_monster] NPC scan error: " .. tostring(err)) Npcs.done = true end
        frames = frames + 1
        if Npcs.done or frames % 15 == 0 then
            refreshResults()
            refreshStatus()
        end
    end
    if engaged then pcall(finalizeGroups) end
    pcall(Variants.tick)
    pcall(HeadGallery.tick)
    if DEBUG_HEAD_BROWSER then
        pcall(HeadBrowser.tick)
        pcall(continueAnimationBrowser)
    end
    local ok, err = pcall(HeadSwap.tick)
    if not ok then print("[make_me_a_monster] head error: " .. tostring(err)) end
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
    HeadBrowser.close()
    Settings.save()
    if page ~= nil then pcall(function() page.view:Destroy() end) page = nil end
end
