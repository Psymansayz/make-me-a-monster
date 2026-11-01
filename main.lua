-- Make Me A Monster: choose an NPC in the plugin's page, and its head replaces yours in the game's
-- dialogue boxes.

local Settings = require("src/data/settings")
local NpcDirectory = require("src/game/npc_directory")
local HeadSwap = require("src/game/head_swap")
local VariantsWindow = require("src/ui/variants_window")
local AllHeadsWindow = require("src/ui/all_heads_window")
local Animations = require("src/game/animations")

local PrettyUI = prettyui

local RESULTS_SHOWN = 40 -- NPCs listed in the dropdown at once

-- The heads in the windows open play the animation chosen (see HeadSwap.npcHeadAnimation).
local function updateOpenWindows()
    HeadSwap.refreshOpenDialogues() -- (the dialogue boxes open follow the animation chosen)
    AllHeadsWindow.updateAnimations()
    VariantsWindow.updateAnimations()
end

-- The saved settings are loaded again on entering the game: the saved data may not be readable yet when the plugin
-- starts.
Settings.load()
HeadSwap.start() -- (watches for dialogue boxes on the server's ticks; stopped at logout and in PluginShutdown)
VariantsWindow.animationForNpcHeads = function(npcID) return HeadSwap.npcHeadAnimation(npcID) end
-- The heads in the window are NPC heads: with the player's own head in use they play the NPC version of the animation
-- chosen (the choice itself is kept, so closing the window without picking a head leaves the player's version).
AllHeadsWindow.animationForNpcHeads = VariantsWindow.animationForNpcHeads
VariantsWindow.animationForPlayerHead = function() return HeadSwap.playerHeadAnimation(true) end

local pluginPage = nil -- the plugin page's controls: { view, search, combo, status, progress }
local matchedMembersByEntryID = {} -- entry id -> the name of the group that matched the search (a member), or nil
local groupsByEntryID = {} -- entry id -> the group (every NPC of one name) the dropdown lists now
local listingsByEntryID = {} -- entry id -> the animation the animation dropdown lists
local isRefreshingNpcDropdown = false
local isRefreshingAnimationDropdown = false

-- Workaround: a dropdown's text doesn't follow a selection made from code, so its closed box is covered: its own text
-- is made invisible (colours, alpha, shadow) and a label of ours laid over it, or nothing for a blank box. Clicking it
-- open, or giving it a choice, puts it back. (Not on its change events: it sends those on its own after SetEntries.)
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
        pluginPage.chatheadStatusText.content = chatheadStatusMessage()
        pluginPage.animationStatusText.content = animationStatusText()
    end
end

-- Whether the head in use plays the player's animations: the player's own head, or an NPC head on the player's rig.
local function playerAnimationsInUse()
    return Settings.chosenNpcID == nil or Animations.isOnPlayerRig(Settings.chosenNpcID)
end

-- The chosen animation changed to one the head in use plays, when a head playing the player's animations and one
-- playing NPC animations are switched between (see HeadSwap.animationForHead).
local function fitAnimationToHead()
    if Settings.chosenAnimationID == nil then return end
    -- (with a head playing the player's animations and the heads window open, the animation stays as it is until the
    -- window closes)
    if playerAnimationsInUse() and AllHeadsWindow.isOpen() then return end
    local fittedAnimation = HeadSwap.animationForHead(Settings.chosenAnimationID, playerAnimationsInUse())
    if fittedAnimation ~= Settings.chosenAnimationID then
        Settings.chosenAnimationID = fittedAnimation
        updateOpenWindows()
    end
end

-- The animation dropdown filled with the animations for the head in use (the player's own, or the NPC heads'), in
-- label order, the chosen one selected. A choice saved earlier that is no longer listed is cleared.
local function refreshAnimationDropdown()
    if pluginPage == nil then return end
    fitAnimationToHead()
    if Settings.chosenAnimationID ~= nil and not Animations.isListed(Settings.chosenAnimationID) then
        Settings.chosenAnimationID = nil
        updateOpenWindows()
        refreshStatusTexts()
    end
    -- The animations for NPC heads, unless the head in use plays the player's animations and no heads window is open
    -- (the heads in it are NPC heads, whatever head is in use).
    local npcHeads = not playerAnimationsInUse() or AllHeadsWindow.isOpen()
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
    local matchingGroups = NpcDirectory.searchGroups(query, RESULTS_SHOWN)
    local matchCount = #matchingGroups
    local chosenGroup = Settings.chosenNpcID and NpcDirectory.groupOfNpc(Settings.chosenNpcID) or nil
    local chosenMember = Settings.chosenNpcID and NpcDirectory.memberOfNpc(Settings.chosenNpcID) or nil
    -- With nothing typed, the NPC chosen stays in the list (at the top) even if it isn't among the first, so
    -- the dropdown can show it after a restart.
    if chosenGroup ~= nil and query:find("^%s*$") then
        local alreadyListed = false
        for _, npcGroup in ipairs(matchingGroups) do
            if npcGroup == chosenGroup then alreadyListed = true end
        end
        if not alreadyListed then table.insert(matchingGroups, 1, chosenGroup) end
    end
    local entries = {}
    groupsByEntryID, matchedMembersByEntryID = {}, {}
    for entryID, npcGroup in ipairs(matchingGroups) do
        -- While searching, an entry shows the name that matched, if it was one name of the group. The entry of the group
        -- the NPC chosen is in shows that NPC's name instead (it can be another name of the group, picked as a variant):
        -- it stays when the dropdown is opened and closed without picking, and goes when another entry is picked.
        -- (one name is shown, with how many NPCs matched the search in all)
        local matchedMember, matchedNpcCount = NpcDirectory.memberMatching(npcGroup, query)
        if npcGroup == chosenGroup and chosenMember ~= nil then matchedMember, matchedNpcCount = chosenMember, nil end
        local label = matchedMember and NpcDirectory.labelOfMember(matchedMember, matchedNpcCount) or NpcDirectory.labelOfGroup(npcGroup, #npcGroup.ids)
        entries[#entries + 1] = { label = label, id = entryID }
        groupsByEntryID[entryID] = npcGroup
        matchedMembersByEntryID[entryID] = matchedMember
    end
    local selected = findSelectedEntryID(groupsByEntryID, function(npcGroup) return npcGroup == chosenGroup end)
    isRefreshingNpcDropdown = true
    pcall(function() pluginPage.npcDropdown:SetEntries(entries, selected) end)
    isRefreshingNpcDropdown = false
    -- The closed box shows that name at once (the dropdown's own text doesn't follow a selection made by the plugin until it is
    -- opened), and nothing if the NPC isn't in the list.
    if selected ~= nil and chosenMember ~= nil then
        coverDropdownText(pluginPage.npcDropdown, true, NpcDirectory.labelOfMember(chosenMember))
    else
        coverDropdownText(pluginPage.npcDropdown, selected == nil)
    end
    pcall(function()
        pluginPage.matchCountText.content = matchCount == RESULTS_SHOWN and ("Showing the first " .. RESULTS_SHOWN .. " matches.")
            or (matchCount .. " matches.")
    end)
end

local openVariantsWindow -- (below)
local openAllHeadsWindow -- (below)

-- chosenFrom: "dropdown" or "variants" when the choice came from the NPC dropdown or the variants window (which then
-- already show it), else nil.
local function chooseNpc(npcID, chosenFrom)
    Settings.chosenNpcID = npcID
    refreshAnimationDropdown() -- (fits the animation to the head first; the windows open follow if it changed)
    HeadSwap.refreshOpenDialogues() -- (the dialogue boxes open follow the head chosen)
    if chosenFrom ~= "dropdown" then refreshNpcDropdown() end -- (the dropdown shows it, or nothing)
    -- (the variants window open shows the variants of the head chosen)
    if chosenFrom ~= "variants" and VariantsWindow.isOpen() then openVariantsWindow() end
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
            local function chooseFromVariants(npcID) chooseNpc(npcID ~= VariantsWindow.PLAYER_HEAD_ID and npcID or nil, "variants") end
            if showPlayerHeadOnly then
                VariantsWindow.open(PrettyUI, pluginLayer, "My head", { VariantsWindow.PLAYER_HEAD_ID }, VariantsWindow.PLAYER_HEAD_ID, chooseFromVariants)
            else
                local variantIDs = npcGroup.ids
                VariantsWindow.open(PrettyUI, pluginLayer, npcGroup.name .. " variants", variantIDs, Settings.chosenNpcID, chooseFromVariants, NpcDirectory.nameOfNpc)
            end
        else
            noticeText = "The game screen isn't ready."
        end
    end
    if pluginPage then pluginPage.noticeText.content = noticeText end
end

-- The plugin's page in the client's Plugins window.
local function buildPage(pluginLayer)
    -- The saved list of heads (src/data/listed_heads.lua): nothing is read from the game.
    if not NpcDirectory.isLoaded then NpcDirectory.loadListedHeads(require("src/data/listed_heads")) end
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
            -- The first NPC of the name that matched the search, else of the group.
            local matchedMember = matchedMembersByEntryID[entryID]
            chooseNpc((matchedMember or npcGroup).ids[1], "dropdown")
        end,
    })
    showTextWhenClicked(pageControls.npcDropdown)
    pageView:AddSimpleButton("View variants", function() openVariantsWindow() end)
    pageView:AddSimpleButton("Browse all heads", function() openAllHeadsWindow() end)
    pageView:AddSimpleButton("Use my own head", function() chooseNpc(nil) end)
    pageControls.noticeText = pageView:AddText("")
    pageControls.headSizeText = pageView:AddText("Head size: " .. Settings.headSizePercent() .. "%")
    pageView:AddSlider({
        min = 50,
        max = 300,
        step = 5,
        value = Settings.headSizePercent(),
        onChange = function(_, sliderValue)
            local percent = math.max(50, math.min(300, math.floor(sliderValue / 5 + 0.5) * 5))
            Settings.setHeadSizePercent(percent)
            HeadSwap.refreshHeadViewDistance() -- (the heads shown now follow)
            AllHeadsWindow.refreshHeadSize()
            VariantsWindow.refreshHeadSize()
            pageControls.headSizeText.content = "Head size: " .. percent .. "%"
        end,
    })
    pageView:AddText("Animation for the head:")
    pageControls.animationStatusText = pageView:AddText(animationStatusText())
    pageControls.animationDropdown = pageView:AddComboBox({
        entries = {},
        onChange = function(_, entryID, _, eventType)
            local selectedListing = listingsByEntryID[entryID]
            if isRefreshingAnimationDropdown or not isSelectionEvent(eventType) or selectedListing == nil then return end
            Settings.chosenAnimationID = selectedListing.id
            coverDropdownText(pageControls.animationDropdown, false)
            updateOpenWindows()
            refreshStatusTexts()
        end,
    })
    showTextWhenClicked(pageControls.animationDropdown)
    pageView:AddSimpleButton("Use default animation", function()
        Settings.chosenAnimationID = nil
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
    pcall(buildPage, event.component)
end)

-- The heads window closed: the dropdown goes back to the animations of the head in use. With the player's own head
-- in use (no head picked) an NPC animation chosen meanwhile becomes the player's version of it (the windows open
-- follow when it changes).
AllHeadsWindow.onClosed = function()
    refreshAnimationDropdown()
    refreshStatusTexts()
end

-- Opens the window of every head the plugin lists; a click on one makes it the active head.
openAllHeadsWindow = function()
    local noticeText = ""
    do
        local succeeded, pluginLayer = pcall(function()
            return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        end)
        if succeeded and pluginLayer ~= nil then
            AllHeadsWindow.open(PrettyUI, pluginLayer, NpcDirectory.headsInNameOrder(), Settings.chosenNpcID, function(npcID) chooseNpc(npcID) end,
                NpcDirectory.nameOfNpc)
            refreshAnimationDropdown() -- (the animations for NPC heads, if the player's head is in use)
        else
            noticeText = "The game screen isn't ready."
        end
    end
    if pluginPage then pluginPage.noticeText.content = noticeText end
end

-- Nothing of the plugin's runs every frame: the dialogue boxes are watched on the server's ticks while in the game
-- (HeadSwap), and the windows act on their buttons and boxes.
Event.GameStateChanged.Subscribe("make_me_a_monster_state", function(event)
    if event.newState == 30 then
        Settings.load()
        HeadSwap.start()
        refreshAnimationDropdown()
        refreshStatusTexts()
    elseif event.oldState == 30 then
        HeadSwap.reset()
    end
end)

function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe("make_me_a_monster_content")
    Event.GameStateChanged.Unsubscribe("make_me_a_monster_state")
    HeadSwap.stop()
    VariantsWindow.close()
    AllHeadsWindow.close()
    Settings.save()
    if pluginPage ~= nil then pcall(function() pluginPage.view:Destroy() end) pluginPage = nil end
end
