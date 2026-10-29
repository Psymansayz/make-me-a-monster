-- Make Me A Monster: choose an NPC in the plugin's page, and its head replaces yours in the game's
-- dialogue boxes.

local Settings = require("src/data/settings")
local NpcDirectory = require("src/game/npc_directory")
local HeadSwap = require("src/game/head_swap")
local VariantsWindow = require("src/ui/variants_window")
local AllHeadsWindow = require("src/ui/all_heads_window")
local Animations = require("src/game/animations")

local PrettyUI = prettyui

-- TEMPORARY debug window (src/debug/head_flagging_window.lua): every head left after the filtering, to flag the ones to
-- blacklist. A button for it is added to the plugin page. Remove DEBUG_HEAD_BROWSER and what uses it when done.
local DEBUG_HEAD_BROWSER = true
local HeadFlaggingWindow = require("src/debug/head_flagging_window")

-- The ids of an NPC group worth showing. With the saved list (src/data/listed_heads.lua) they are all its ids. Without it
-- (development: the file is made from a scan, see finalizeGroups) they are worked out once per group by
-- HeadFilter.variants (again if the group has gained ids since: the NPCs are still being read).
local visibleByGroup = {}

local function visibleIds(npcGroup)
    if NpcDirectory.baked then return npcGroup.ids end
    local HeadFilter = require("src/game/head_filter")
    local cached = visibleByGroup[npcGroup]
    if cached == nil or cached.count ~= #npcGroup.ids then
        cached = { count = #npcGroup.ids, ids = HeadFilter.variants(npcGroup.ids) }
        visibleByGroup[npcGroup] = cached
    end
    return cached.ids
end
local RESULTS_SHOWN = 40 -- NPCs listed in the dropdown at once (there are tens of thousands)

-- The heads in the windows open play the animation chosen (see HeadSwap.npcHeadAnimation).
local function updateOpenWindows()
    pcall(AllHeadsWindow.updateAnimations)
    pcall(VariantsWindow.updateAnimations)
end

-- The saved settings are loaded again on entering the game: the saved data may not be readable yet when the plugin
-- starts.
Settings.load()
VariantsWindow.animationForNpcHeads = function() return HeadSwap.npcHeadAnimation() end
-- The heads in the window are NPC heads: with the player's own head in use they play the NPC version of the animation
-- chosen (the choice itself is kept, so closing the window without picking a head leaves the player's version).
AllHeadsWindow.animationForNpcHeads = VariantsWindow.animationForNpcHeads
VariantsWindow.animationForPlayerHead = function() return HeadSwap.playerHeadAnimation(true) end

-- Nothing is read from the game (its NPCs, their heads, the animations) until the plugin page is first opened:
-- the head in dialogue needs only the saved NPC id.
local engaged = false

local pluginPage = nil -- the plugin page's controls: { view, search, combo, status, progress }
local groupsByEntryID = {} -- entry id -> the group (every NPC of one name) the dropdown lists now
local listingsByEntryID = {} -- entry id -> the animation the animation dropdown lists
local isRefreshingNpcDropdown = false
local isRefreshingAnimationDropdown = false

-- Workaround: a dropdown always shows one of its entries, and unselecting or selecting from code doesn't change its
-- text reliably. So a dropdown's closed box is covered (as read_later does for its books dropdown, see its
-- titleCover): its own text is made invisible (the box's colours, alpha and shadow), and with a title given a label of
-- ours with that title is laid over it; with none the box is blank. The player clicking it open puts it back as it
-- was, and so does it being given a choice to show. (Not on its change events: it can send those on its own after
-- its list is given.)
local coverStates = {} -- dropdown -> { colours = its text's saved colours, covered = whether it is covered now, label = our label }

-- title: the text to show in the covered box, or nil for a blank one.
local function coverDropdownText(dropdown, hideText, overlayText)
    pcall(function()
        local dropdownRoot = dropdown.root
        local coverState = coverStates[dropdown]
        if coverState == nil then
            coverState = { covered = false }
            coverStates[dropdown] = coverState
        end
        if hideText then
            if not coverState.covered then
                coverState.colours = { dropdownRoot.entryText.rgba, dropdownRoot.selectedForegroundRGBA, dropdownRoot.mouseoverForegroundRGBA,
                    alpha = dropdownRoot.entryText.alpha, isShadowed = dropdownRoot.entryText.isShadowed }
                coverState.covered = true
                dropdownRoot.entryText.rgba, dropdownRoot.selectedForegroundRGBA, dropdownRoot.mouseoverForegroundRGBA = 0, 0, 0
                dropdownRoot.entryText.alpha, dropdownRoot.entryText.isShadowed = 0, false
            end
            if overlayText == nil then
                if coverState.label ~= nil then coverState.label.hidden = true end
                return
            end
            local overlayLabel = coverState.label
            if overlayLabel == nil then
                overlayLabel = ui.Text.new(dropdownRoot.parent)
                overlayLabel.clickthrough = true
                overlayLabel.maxLines = 1
                overlayLabel.alignHorizontal = ui.AlignMode.TOPLEFT
                overlayLabel.alignVertical = ui.AlignMode.CENTRE
                coverState.label = overlayLabel
            end
            -- Where the box's own text goes: its 8 inset at the left, clear of its arrow button (as wide as the box
            -- is high) at the right; in its font and colour.
            overlayLabel:SetPos(dropdownRoot.x + 8, dropdownRoot.y)
            overlayLabel:SetSize(math.max(1, dropdownRoot.width - 8 - dropdownRoot.height), dropdownRoot.height)
            overlayLabel.font = dropdownRoot.entryText.font
            overlayLabel.rgba = coverState.colours[1]
            overlayLabel.isShadowed = coverState.colours.isShadowed
            overlayLabel.content = overlayText
            overlayLabel.hidden = false
            overlayLabel:MoveToFront()
        elseif coverState.covered then
            local savedColours = coverState.colours
            coverState.covered = false
            if coverState.label ~= nil then coverState.label.hidden = true end
            dropdownRoot.entryText.rgba, dropdownRoot.selectedForegroundRGBA, dropdownRoot.mouseoverForegroundRGBA = savedColours[1], savedColours[2], savedColours[3]
            dropdownRoot.entryText.alpha, dropdownRoot.entryText.isShadowed = savedColours.alpha, savedColours.isShadowed
        end
    end)
end

-- The player opening a dropdown (clicking it): its text back.
local function showTextWhenClicked(dropdown)
    pcall(function()
        dropdown.root:Subscribe(ui.Hook.ONCLICK, function()
            coverDropdownText(dropdown, false)
            return false
        end)
    end)
end

-- The id of the entry in `shown` (entry id -> item) for which isActive(item) is true, or nil.
local function findSelectedEntryID(shownItems, isChosen)
    for entryID, shownItem in pairs(shownItems) do
        if isChosen(shownItem) then return entryID end
    end
    return nil
end

local function chatheadStatusMessage()
    local npcID = Settings.chosenNpcID
    if npcID == nil then return "Current chathead: my own head" end
    local npcName = NpcDirectory.nameOfNpc(npcID)
    local npcGroup = NpcDirectory.groupOfNpc(npcID)
    local variantSuffix = npcGroup and #npcGroup.ids > 1 and (" (variant ID " .. npcID .. ")") or ""
    return "Current chathead: " .. (npcName or ("NPC " .. npcID)) .. variantSuffix
end

local function animationStatusText()
    local chosenAnimation = Settings.chosenAnimationID
    if chosenAnimation ~= nil then
        return "Animation: " .. (Animations.labelOf(chosenAnimation) or ("ID " .. chosenAnimation))
    end
    return "" -- (the default: nothing to say)
end

local function refreshStatusTexts()
    if pluginPage then
        pcall(function() pluginPage.chatheadStatusText.content = chatheadStatusMessage() end)
        pcall(function() pluginPage.animationStatusText.content = animationStatusText() end)
    end
end

-- The chosen animation changed to one the head in use plays, when the player's own head and an NPC's are switched
-- between (they play different animations, see HeadSwap.animationForHead).
local function fitAnimationToHead()
    if Settings.chosenAnimationID == nil then return end
    -- (with the player's own head and the heads window open, the animation stays as it is until the window closes)
    if Settings.chosenNpcID == nil and AllHeadsWindow.isOpen() then return end
    local fittedAnimation = HeadSwap.animationForHead(Settings.chosenAnimationID, Settings.chosenNpcID == nil)
    if fittedAnimation ~= Settings.chosenAnimationID then
        Settings.setChosenAnimation(fittedAnimation)
        updateOpenWindows()
    end
end

-- The animation dropdown filled with the animations for the head in use (the player's own, or the NPC heads'), in
-- label order, the chosen one selected. A choice saved earlier that is no longer listed is cleared.
local function refreshAnimationDropdown()
    if pluginPage == nil then return end
    fitAnimationToHead()
    if Settings.chosenAnimationID ~= nil and not Animations.isListed(Settings.chosenAnimationID) then
        Settings.setChosenAnimation(nil)
        updateOpenWindows()
        refreshStatusTexts()
    end
    -- The animations for NPC heads, unless the player's own head is in use and no heads window is open (the heads
    -- in it are NPC heads, whatever head is in use).
    local npcHeads = Settings.chosenNpcID ~= nil or AllHeadsWindow.isOpen()
    local listedAnimations = Animations.options(not npcHeads)
    local entries = {}
    listingsByEntryID = {}
    for entryID, listing in ipairs(listedAnimations) do
        entries[#entries + 1] = { label = listing.label, id = entryID }
        listingsByEntryID[entryID] = listing
    end
    -- (the one chosen, as its NPC version if it is one for the player's head and the list is of NPC ones)
    local shownChoiceID = Settings.chosenAnimationID
    if npcHeads then shownChoiceID = HeadSwap.animationForHead(shownChoiceID, false) end
    local selected = findSelectedEntryID(listingsByEntryID, function(listing) return listing.id == shownChoiceID end)
    isRefreshingAnimationDropdown = true
    pcall(function() pluginPage.animationDropdown:SetEntries(entries, selected) end)
    isRefreshingAnimationDropdown = false
    -- (a blank box with nothing chosen, else our label with its name: the dropdown's own text doesn't follow a choice made
    -- by the plugin)
    coverDropdownText(pluginPage.animationDropdown, true, selected ~= nil and listingsByEntryID[selected].label or nil)
end

-- The dropdown refilled with the NPCs matching the search box.
local function refreshNpcDropdown()
    if pluginPage == nil then return end
    local query = ""
    pcall(function() query = pluginPage.npcSearchBox:GetText() end)
    local matchingGroups = NpcDirectory.searchGroups(query, RESULTS_SHOWN, visibleIds)
    local matchCount = #matchingGroups
    -- With nothing typed, the NPC chosen stays in the list (at the top) even if it isn't among the first, so
    -- the dropdown can show it after a restart.
    local activeGroup = Settings.chosenNpcID and NpcDirectory.groupOfNpc(Settings.chosenNpcID) or nil
    if activeGroup ~= nil and query:find("^%s*$") then
        local alreadyListed = false
        for _, npcGroup in ipairs(matchingGroups) do
            if npcGroup == activeGroup then alreadyListed = true end
        end
        if not alreadyListed then table.insert(matchingGroups, 1, activeGroup) end
    end
    local entries = {}
    groupsByEntryID = {}
    for entryID, npcGroup in ipairs(matchingGroups) do
        entries[#entries + 1] = { label = NpcDirectory.labelOfGroup(npcGroup, #visibleIds(npcGroup)), id = entryID }
        groupsByEntryID[entryID] = npcGroup
    end
    local chosenGroup = Settings.chosenNpcID and NpcDirectory.groupOfNpc(Settings.chosenNpcID) or nil
    local selected = findSelectedEntryID(groupsByEntryID, function(npcGroup) return npcGroup == chosenGroup end)
    isRefreshingNpcDropdown = true
    pcall(function() pluginPage.npcDropdown:SetEntries(entries, selected) end)
    isRefreshingNpcDropdown = false
    coverDropdownText(pluginPage.npcDropdown, selected == nil)
    pcall(function()
        if NpcDirectory.done then
            pluginPage.matchCountText.content = matchCount == RESULTS_SHOWN and ("Showing the first " .. RESULTS_SHOWN .. " matches.")
                or (matchCount .. " matches.")
        else
            pluginPage.matchCountText.content = "Reading the game's NPCs: " .. #NpcDirectory.list .. " found so far..."
        end
    end)
end

local openVariantsWindow -- (below)
local openAllHeadsWindow -- (below)
local openAnimationFlaggingWindow -- (below, debug only)
local openHeadFlaggingWindow -- (below, debug only)

local function chooseNpc(npcID, fromDropdown)
    Settings.setChosenNpc(npcID)
    fitAnimationToHead()
    refreshAnimationDropdown()
    if not fromDropdown then refreshNpcDropdown() end -- (the dropdown shows it, or nothing)
    refreshStatusTexts()
end

local function isSelectionEvent(eventType)
    local succeeded, selected = pcall(function() return eventType == ui.SelectionChangeEvent.SELECTED end)
    return not succeeded or selected or eventType == nil
end

-- The window of every NPC sharing the chosen one's name; a click on one makes it the active head.
openVariantsWindow = function()
    -- Works with a single variant too, as a preview of the head.
    -- With the player's own head in use, the window shows just that head.
    local npcGroup = Settings.chosenNpcID and NpcDirectory.groupOfNpc(Settings.chosenNpcID) or nil
    local showPlayerHeadOnly = Settings.chosenNpcID == nil
    local noticeText = ""
    if npcGroup == nil and not showPlayerHeadOnly then
        noticeText = "Choose an NPC first."
    else
        -- The top plugin layer, above the game's own interfaces (as read_later's windows over its dialogue).
        local succeeded, pluginLayer = pcall(function()
            return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        end)
        if succeeded and pluginLayer ~= nil then
            local function chooseFromVariants(npcID) chooseNpc(npcID ~= VariantsWindow.PLAYER_HEAD_ID and npcID or nil) end
            if showPlayerHeadOnly then
                VariantsWindow.open(PrettyUI, pluginLayer, "My head", { VariantsWindow.PLAYER_HEAD_ID }, VariantsWindow.PLAYER_HEAD_ID, chooseFromVariants)
            else
                -- Variants with no head, and ones that look like another, are left out.
                local variantIDs = visibleIds(npcGroup)
                if #variantIDs == 0 then variantIDs = npcGroup.ids end
                VariantsWindow.open(PrettyUI, pluginLayer, npcGroup.name .. " variants", variantIDs, Settings.chosenNpcID, chooseFromVariants, NpcDirectory.nameOfNpc)
            end
        else
            noticeText = "The game screen isn't ready."
        end
    end
    if pluginPage then pcall(function() pluginPage.noticeText.content = noticeText end) end
end

-- The plugin's page in the client's Plugins window.
local function buildPage(pluginLayer)
    engaged = true
    -- The saved list of heads, if there is one: no scan.
    local okList, savedColours = pcall(require, "src/data/listed_heads")
    if okList and type(savedColours) == "table" and not NpcDirectory.baked then NpcDirectory.loadBaked(savedColours) end
    local pageView = PrettyUI.SimpleView.new(pluginLayer, { width = pluginLayer.width, height = pluginLayer.height })
    pageView:AddTitle("Make Me A Monster")
    pageView:AddText("Pick an NPC: its head replaces yours in dialogue boxes.")
    local pageControls = { view = pageView }
    pageControls.chatheadStatusText = pageView:AddText(chatheadStatusMessage())
    pageControls.npcSearchBox = pageView:AddTextField({
        placeholder = "Search NPCs by name or id",
        onChange = function() refreshNpcDropdown() end,
    })
    pageControls.matchCountText = pageView:AddText("")
    pageControls.npcDropdown = pageView:AddComboBox({
        entries = {},
        onChange = function(_, entryID, _, eventType)
            local npcGroup = groupsByEntryID[entryID]
            if isRefreshingNpcDropdown or not isSelectionEvent(eventType) or npcGroup == nil then return end
            coverDropdownText(pageControls.npcDropdown, false)
            -- The first variant that has a head (the lowest id may be blank).
            chooseNpc(visibleIds(npcGroup)[1] or npcGroup.ids[1], true)
        end,
    })
    showTextWhenClicked(pageControls.npcDropdown)
    pageView:AddSimpleButton("View variants", function() openVariantsWindow() end)
    pageView:AddSimpleButton("Browse all heads", function() openAllHeadsWindow() end)
    pageView:AddSimpleButton("Use my own head", function() chooseNpc(nil) end)
    if DEBUG_HEAD_BROWSER then
        pageView:AddSimpleButton("Debug: flag heads for the blacklist", function() openHeadFlaggingWindow() end)
        pageView:AddSimpleButton("Debug: all animations on Hans", function() openAnimationFlaggingWindow() end)
    end
    pageControls.noticeText = pageView:AddText("")
    pageControls.headSizeText = pageView:AddText("Head size: " .. math.floor(Settings.headScale * 100 + 0.5) .. "%")
    pageView:AddSlider({
        min = 100,
        max = 300,
        step = 5,
        value = math.floor(Settings.headScale * 100 + 0.5),
        onChange = function(_, sliderValue)
            local percent = math.max(100, math.min(300, math.floor(sliderValue / 5 + 0.5) * 5))
            Settings.setHeadScale(percent / 100)
            HeadSwap.refreshHeadScale() -- (the heads shown now follow)
            pcall(function() pageControls.headSizeText.content = "Head size: " .. percent .. "%" end)
        end,
    })
    pageView:AddText("Animation for the head:")
    pageControls.animationStatusText = pageView:AddText(animationStatusText())
    pageControls.animationDropdown = pageView:AddComboBox({
        entries = {},
        onChange = function(_, entryID, _, eventType)
            local selectedListing = listingsByEntryID[entryID]
            if isRefreshingAnimationDropdown or not isSelectionEvent(eventType) or selectedListing == nil then return end
            Settings.setChosenAnimation(selectedListing.id)
            coverDropdownText(pageControls.animationDropdown, false)
            updateOpenWindows()
            refreshStatusTexts()
        end,
    })
    showTextWhenClicked(pageControls.animationDropdown)
    pageView:AddSimpleButton("Use default animation", function()
        Settings.setChosenAnimation(nil)
        updateOpenWindows()
        refreshAnimationDropdown()
        refreshStatusTexts()
    end)
    pluginPage = pageControls
    refreshNpcDropdown()
    refreshAnimationDropdown()
end

Event.ContentLayerReady.Subscribe("make_me_a_monster_content", function(event)
    if pluginPage ~= nil then pcall(function() pluginPage.view:Destroy() end) pluginPage = nil end
    local succeeded, errorMessage = pcall(buildPage, event.component)
    if not succeeded then print("[make_me_a_monster] could not build the page: " .. tostring(errorMessage)) end
end)

-- Once every NPC is read, each name is checked for variants worth showing (200 names a frame), names left with
-- none are dropped and the rest are merged into entries (NpcDirectory.regroup).
local finalState = nil
local CHECK_PER_FRAME = 200

local function finalizeGroups()
    if NpcDirectory.baked then return end
    if finalState == nil then
        if not NpcDirectory.done then return end
        finalState = { index = 1 }
    end
    if finalState.done then return end
    for _ = 1, CHECK_PER_FRAME do
        local npcGroup = NpcDirectory.groups[finalState.index]
        if npcGroup == nil then
            NpcDirectory.regroup(function(entry) return #visibleIds(entry) > 0 end)
            -- Development: the list of heads to save as src/data/listed_heads.lua, logged once.
            local lines, heads = NpcDirectory.exportLines(visibleIds)
            print(("[make_me_a_monster] HEADS|begin|%d entries, %d heads, %d lines"):format(#NpcDirectory.groups, heads, #lines))
            for _, line in ipairs(lines) do print(line) end
            print("[make_me_a_monster] HEADS|end")
            refreshNpcDropdown()
            refreshStatusTexts()
            finalState.done = true
            return
        end
        finalState.index = finalState.index + 1
        visibleIds(npcGroup)
    end
end

-- The heads the plugin lists, one per id (those left after the filtering), in name order.
local function listedHeads()
    local heads = {}
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        for _, npcID in ipairs(visibleIds(npcGroup)) do heads[#heads + 1] = npcID end
    end
    local lowered = {}
    for _, npcID in ipairs(heads) do lowered[npcID] = NpcDirectory.lowerCaseAscii(NpcDirectory.nameOfNpc(npcID) or "") end
    table.sort(heads, function(a, b)
        if lowered[a] ~= lowered[b] then return lowered[a] < lowered[b] end
        return a < b
    end)
    return heads
end

-- The heads window closed: the dropdown goes back to the animations of the head in use. With the player's own head
-- in use (no head picked) an NPC animation chosen meanwhile becomes the player's version of it.
AllHeadsWindow.onClosed = function()
    fitAnimationToHead()
    updateOpenWindows()
    refreshAnimationDropdown()
    refreshStatusTexts()
end

-- Opens the window of every head the plugin lists; a click on one makes it the active head.
openAllHeadsWindow = function()
    local noticeText = ""
    if not NpcDirectory.regrouped then
        noticeText = "The NPCs are still being read."
    else
        local succeeded, pluginLayer = pcall(function()
            return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        end)
        if succeeded and pluginLayer ~= nil then
            AllHeadsWindow.open(PrettyUI, pluginLayer, listedHeads(), Settings.chosenNpcID, function(npcID) chooseNpc(npcID) end,
                NpcDirectory.nameOfNpc)
            refreshAnimationDropdown() -- (the animations for NPC heads, if the player's head is in use)
        else
            noticeText = "The game screen isn't ready."
        end
    end
    if pluginPage then pcall(function() pluginPage.noticeText.content = noticeText end) end
end

-- Opens the debug window on every head left after the filtering (once the entries are made).
openHeadFlaggingWindow = function()
    local noticeText = ""
    if not NpcDirectory.regrouped then
        noticeText = "The NPCs are still being read."
    else
        local succeeded, pluginLayer = pcall(function()
            return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        end)
        if succeeded and pluginLayer ~= nil then
            local heads = {}
            for _, npcGroup in ipairs(NpcDirectory.groups) do
                for _, npcID in ipairs(visibleIds(npcGroup)) do heads[#heads + 1] = npcID end
            end
            table.sort(heads)
            HeadFlaggingWindow.scaleFor = function() return Settings.headScale end
            HeadFlaggingWindow.open(PrettyUI, pluginLayer, heads, NpcDirectory.nameOfNpc, function() return HeadSwap.npcHeadAnimation() end)
        else
            noticeText = "The game screen isn't ready."
        end
    end
    if pluginPage then pcall(function() pluginPage.noticeText.content = noticeText end) end
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
local AnimationList = require("src/data/animation_list")
local animationBrowserWanted = false

local TINT_LISTED = { 0.10, 0.28, 0.12, 1 }     -- on the whitelist, listed in the dropdown
local TINT_DUPLICATE = { 0.10, 0.17, 0.34, 1 }  -- on the whitelist as a duplicate

local function showAnimationBrowser()
    local succeeded, pluginLayer = pcall(function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end)
    if not (succeeded and pluginLayer ~= nil) then return false end
    local variantIDs, names, listed, duplicates = {}, {}, {}, {}
    for _, entry in ipairs(AnimationList.npc) do listed[entry.id] = true end
    for _, animID in ipairs(Whitelist.duplicates or {}) do duplicates[animID] = true end
    for _, anim in ipairs(AnimationScan.list) do
        variantIDs[#variantIDs + 1] = anim.id
        names[anim.id] = anim.name
    end
    HeadFlaggingWindow.scaleFor = function() return Settings.headScale end
    HeadFlaggingWindow.open(PrettyUI, pluginLayer, variantIDs, function(animID) return names[animID] end, nil, {
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
                for entryID = first, math.min(#selected, first + ANIMATION_ENTRIES_PER_LINE - 1) do
                    parts[#parts + 1] = selected[entryID] .. "=" .. (names[selected[entryID]] or "?")
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
openAnimationFlaggingWindow = function()
    animationBrowserWanted = true
    if pluginPage then pcall(function() pluginPage.noticeText.content = AnimationScan.done and "" or "Reading the game's animations..." end) end
end

local function continueAnimationBrowser()
    if not animationBrowserWanted then return end
    if not AnimationScan.done then
        AnimationScan.step()
        if pluginPage then
            pcall(function() pluginPage.noticeText.content = "Reading the game's animations: " .. #AnimationScan.list .. " so far..." end)
        end
        return
    end
    animationBrowserWanted = false
    local opened = showAnimationBrowser()
    if pluginPage then pcall(function() pluginPage.noticeText.content = opened and "" or "The game screen isn't ready." end) end
end

local frames = 0
Event.Draw.Subscribe("make_me_a_monster_draw", function()
    if engaged and not NpcDirectory.done then
        local succeeded, errorMessage = pcall(NpcDirectory.step)
        if not succeeded then print("[make_me_a_monster] NPC scan error: " .. tostring(errorMessage)) NpcDirectory.done = true end
        frames = frames + 1
        if NpcDirectory.done or frames % 15 == 0 then
            refreshNpcDropdown()
            refreshStatusTexts()
        end
    end
    if engaged then pcall(finalizeGroups) end
    if DEBUG_HEAD_BROWSER then
        pcall(continueAnimationBrowser)
    end
    local succeeded, errorMessage = pcall(HeadSwap.tick)
    if not succeeded then print("[make_me_a_monster] head error: " .. tostring(errorMessage)) end
end)

Event.GameStateChanged.Subscribe("make_me_a_monster_state", function(event)
    if event.newState == 30 then
        Settings.load()
        refreshAnimationDropdown()
        refreshStatusTexts()
    elseif event.oldState == 30 then
        HeadSwap.reset()
    end
end)

function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe("make_me_a_monster_content")
    Event.Draw.Unsubscribe("make_me_a_monster_draw")
    Event.GameStateChanged.Unsubscribe("make_me_a_monster_state")
    VariantsWindow.close()
    AllHeadsWindow.close()
    HeadFlaggingWindow.close()
    Settings.save()
    if pluginPage ~= nil then pcall(function() pluginPage.view:Destroy() end) pluginPage = nil end
end
