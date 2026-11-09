-- Make Me A Monster: choose an NPC in the settings, and its head replaces yours in the game's
-- dialogue boxes.

local Settings = require("src/data/settings")
local NpcDirectory = require("src/game/npc_directory")
local HeadSwap = require("src/game/head_swap")
local VariantsWindow = require("src/ui/variants_window")
local AllHeadsWindow = require("src/ui/all_heads_window")
local Animations = require("src/game/animations")
local GameIds = require("src/game/game_ids")

local PrettyUI = prettyui

-- TEMPORARY debug windows: a button for each is added to the settings. Remove DEBUG_HEAD_BROWSER and what uses it when
-- done.
local DEBUG_HEAD_BROWSER = true
local HeadFlaggingWindow = require("src/debug/head_flagging_window")
local HeadGroupingWindow = require("src/debug/head_grouping_window")

-- Development: names in the plugin's data that this game build does not know.
if #GameIds.unresolved > 0 then
    print("[make_me_a_monster] UNRESOLVED|" .. table.concat(GameIds.unresolved, " "))
end

-- The ids of an NPC group worth showing: all of them with the saved list, else from HeadFilter during the dev scan.
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
local RESULTS_SHOWN = 40 -- NPCs listed in the dropdown at once

local function updateOpenWindows()
    HeadSwap.refreshOpenDialogues()
    AllHeadsWindow.updateAnimations()
    VariantsWindow.updateAnimations()
    HeadFlaggingWindow.updateAnimations() -- (debug only)
end

-- The settings are read once, here, and written at shutdown.
Settings.load()
HeadSwap.start()
VariantsWindow.animationForNpcHeads = HeadSwap.npcHeadAnimation
-- The window shows NPC heads: they play the NPC version of the animation chosen, whichever head is in use.
AllHeadsWindow.animationForNpcHeads = VariantsWindow.animationForNpcHeads
VariantsWindow.animationForPlayerHead = function() return HeadSwap.playerHeadAnimation(true) end

-- Nothing is read from the game until the settings are first built: dialogue needs only the saved NPC id.
local engaged = false

local pluginPageLayer = nil -- the layer the client gives the plugin's page
local pluginPageToggle = nil -- the page's button switching the settings between the page and their own window
local pluginPageView = nil -- what the page holds under that button
local pageNoticeText = nil -- says on the page why the window did not open
local settingsControls = nil -- the controls while they are built; .window is the window holding them, if one is
local matchedMembersByEntryID = {} -- entry id -> the member of the group that matched the search, or nil
local groupsByEntryID = {} -- entry id -> the group
local listingsByEntryID = {} -- entry id -> the animation
local isRefreshingNpcDropdown = false
local isRefreshingAnimationDropdown = false

-- A dropdown's text doesn't follow a selection made from code: so its text is hidden and a label of ours laid over it.
-- Clicking it open puts it back. (Not on its change events: SetEntries sends those too.)
local coverStates = {} -- dropdown -> { colours, covered, label }

-- overlayText: what the covered box shows, or nil for a blank one.
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
                coverState.colours = {
                    dropdownRoot.entryText.rgba, dropdownRoot.selectedForegroundRGBA,
                    dropdownRoot.mouseoverForegroundRGBA,
                    alpha = dropdownRoot.entryText.alpha, isShadowed = dropdownRoot.entryText.isShadowed,
                }
                coverState.covered = true
                dropdownRoot.entryText.rgba = 0
                dropdownRoot.selectedForegroundRGBA, dropdownRoot.mouseoverForegroundRGBA = 0, 0
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
            -- Where the box's own text goes: inset 8, clear of its arrow button (as wide as the box is high).
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
            dropdownRoot.entryText.rgba = savedColours[1]
            dropdownRoot.selectedForegroundRGBA, dropdownRoot.mouseoverForegroundRGBA = savedColours[2], savedColours[3]
            dropdownRoot.entryText.alpha, dropdownRoot.entryText.isShadowed = savedColours.alpha, savedColours.isShadowed
        end
    end)
end

local function showTextWhenClicked(dropdown)
    dropdown.root:Subscribe(ui.Hook.ONCLICK, function()
        coverDropdownText(dropdown, false)
        return false
    end)
end

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
    return ""
end

local function refreshStatusTexts()
    if settingsControls then
        settingsControls.chatheadStatusText.content = chatheadStatusMessage()
        settingsControls.animationStatusText.content = animationStatusText()
    end
end

-- Whether the head in use plays the player's animations: the player's own head, or an NPC head on the player's rig.
local function playerAnimationsInUse()
    return Settings.chosenNpcID == nil or Animations.isOnPlayerRig(Settings.chosenNpcID)
end

local function animationChanged()
    updateOpenWindows()
    refreshStatusTexts()
end

-- Keeps the chosen animation one that the head in use can play.
local function fitAnimationToHead()
    if Settings.chosenAnimationID == nil then return end
    -- The heads window shows NPC heads: the animation stays as it is until it closes.
    if playerAnimationsInUse() and AllHeadsWindow.isOpen() then return end
    local fittedAnimation = HeadSwap.animationForHead(Settings.chosenAnimationID, playerAnimationsInUse())
    if fittedAnimation ~= Settings.chosenAnimationID then
        Settings.chosenAnimationID = fittedAnimation
        animationChanged()
    end
end

-- Fills the animation dropdown for the head in use. A choice saved earlier that is no longer listed is cleared.
local function refreshAnimationDropdown()
    if not engaged then return end
    -- (also with the settings closed: a heads window can stay open and change the head in use)
    fitAnimationToHead()
    if Settings.chosenAnimationID ~= nil and not Animations.isListed(Settings.chosenAnimationID) then
        Settings.chosenAnimationID = nil
        animationChanged()
    end
    if settingsControls == nil then return end
    -- The heads window shows NPC heads, whatever head is in use.
    local npcHeads = not playerAnimationsInUse() or AllHeadsWindow.isOpen()
    local listedAnimations = Animations.options(not npcHeads)
    local entries = {}
    listingsByEntryID = {}
    for entryID, listing in ipairs(listedAnimations) do
        entries[#entries + 1] = { label = listing.label, id = entryID }
        listingsByEntryID[entryID] = listing
    end
    local shownChoiceID = Settings.chosenAnimationID
    if npcHeads then shownChoiceID = HeadSwap.animationForHead(shownChoiceID, false) end
    local selected = findSelectedEntryID(listingsByEntryID, function(listing) return listing.id == shownChoiceID end)
    isRefreshingAnimationDropdown = true
    pcall(function() settingsControls.animationDropdown:SetEntries(entries, selected) end)
    isRefreshingAnimationDropdown = false
    coverDropdownText(settingsControls.animationDropdown, true,
        selected ~= nil and listingsByEntryID[selected].label or nil)
end

-- A head can be in several groups: the one the head chosen was picked from, kept for this session.
local pickedGroup = nil

local function groupOfChosenNpc()
    local npcID = Settings.chosenNpcID
    if npcID == nil then return nil end
    if pickedGroup ~= nil then
        for _, groupNpcID in ipairs(pickedGroup.ids) do
            if groupNpcID == npcID then return pickedGroup end
        end
    end
    return NpcDirectory.groupOfNpc(npcID)
end

-- A name equal to its group's stands for the whole group (Fairy holds Jukat too): so it counts the group's heads.
local function labelOfEntry(npcGroup, member, memberNpcCount)
    if member == nil or NpcDirectory.lowerCaseAscii(member.name) == NpcDirectory.lowerCaseAscii(npcGroup.name) then
        return NpcDirectory.labelOf(npcGroup.name, #visibleIds(npcGroup))
    end
    return NpcDirectory.labelOf(member.name, memberNpcCount or #member.ids)
end

local function refreshNpcDropdown()
    if settingsControls == nil then return end
    local query = settingsControls.npcSearchBox:GetText()
    local matchingGroups = NpcDirectory.searchGroups(query, RESULTS_SHOWN, visibleIds)
    local matchCount = #matchingGroups
    local chosenGroup = groupOfChosenNpc()
    local chosenMember = chosenGroup and NpcDirectory.memberOfNpc(Settings.chosenNpcID, chosenGroup)
    -- With nothing typed the NPC chosen stays listed, so the dropdown can show it after a restart.
    if chosenGroup ~= nil and query:find("^%s*$") then
        local alreadyListed = false
        for _, npcGroup in ipairs(matchingGroups) do
            if npcGroup == chosenGroup then
                alreadyListed = true
                break
            end
        end
        if not alreadyListed then table.insert(matchingGroups, 1, chosenGroup) end
    end
    local entries = {}
    groupsByEntryID, matchedMembersByEntryID = {}, {}
    for entryID, npcGroup in ipairs(matchingGroups) do
        -- An entry shows the name that matched the search; the chosen NPC's group shows that NPC's name instead.
        local matchedMember, matchedNpcCount = NpcDirectory.memberMatching(npcGroup, query)
        if npcGroup == chosenGroup and chosenMember ~= nil then matchedMember, matchedNpcCount = chosenMember, nil end
        entries[#entries + 1] = { label = labelOfEntry(npcGroup, matchedMember, matchedNpcCount), id = entryID }
        groupsByEntryID[entryID] = npcGroup
        matchedMembersByEntryID[entryID] = matchedMember
    end
    local selected = findSelectedEntryID(groupsByEntryID, function(npcGroup) return npcGroup == chosenGroup end)
    isRefreshingNpcDropdown = true
    pcall(function() settingsControls.npcDropdown:SetEntries(entries, selected) end)
    isRefreshingNpcDropdown = false
    -- The closed box shows the NPC's name, or nothing if it isn't in the list.
    if selected ~= nil and chosenMember ~= nil then
        coverDropdownText(settingsControls.npcDropdown, true, labelOfEntry(chosenGroup, chosenMember))
    else
        coverDropdownText(settingsControls.npcDropdown, selected == nil)
    end
    if NpcDirectory.done then
        settingsControls.matchCountText.content = matchCount == RESULTS_SHOWN
            and ("Showing the first " .. RESULTS_SHOWN .. " matches.") or (matchCount .. " matches.")
    else
        settingsControls.matchCountText.content = "Reading the game's NPCs: " .. #NpcDirectory.list .. " found so far..."
    end
end

-- Defined below.
local openVariantsWindow
local closeSettingsWindow
local switchSettings
local openAllHeadsWindow
-- Defined below, debug only.
local openAnimationFlaggingWindow
local openHeadFlaggingWindow
local openBlacklistedHeadsWindow
local openNewestHeadsWindow
local openHeadGroupingWindow
local logExactDuplicates
local logListedHeadModels
local logListedHeadNames
local logBlacklistConstants

-- Development: an NPC's name in the game (what the plugin's data holds), or "?".
local function configNameOf(npcID)
    local named, configName = pcall(function() return config.NPC.FromID(npcID).configName end)
    return named and configName or "?"
end

-- chosenFrom: "dropdown" or "variants" if that already shows the choice. selectedGroup: the group the head was selected
-- under, if its label named one.
local function chooseNpc(npcID, chosenFrom, selectedGroup)
    Settings.chosenNpcID = npcID
    if chosenFrom == nil then pickedGroup = selectedGroup end
    if selectedGroup ~= nil then VariantsWindow.selectGroup(npcID, selectedGroup) end
    refreshAnimationDropdown()
    HeadSwap.refreshOpenDialogues()
    if chosenFrom ~= "dropdown" then refreshNpcDropdown() end
    if chosenFrom ~= "variants" and VariantsWindow.isOpen() then openVariantsWindow() end
    refreshStatusTexts()
end

local function isSelectionEvent(eventType)
    return eventType == nil or eventType == ui.SelectionChangeEvent.SELECTED
end

-- The layer plugin windows go on, or nil while the game screen isn't ready.
local function pluginBuildLayer()
    local succeeded, pluginLayer = pcall(function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end)
    return succeeded and pluginLayer or nil
end

-- The variants window's button text for the NPC chosen, or nil if it is in no other group.
local function nextGroupButtonText(npcGroup)
    local nextGroup = NpcDirectory.nextGroupOfNpc(Settings.chosenNpcID, npcGroup)
    return nextGroup and ("View " .. nextGroup.name .. " variants") or nil
end

-- page: the page to show, else that of the head chosen.
local function showVariantsOf(npcGroup, page)
    pickedGroup = npcGroup -- (a variant picked in the window stays in this group)
    local showPlayerHeadOnly = Settings.chosenNpcID == nil
    local noticeText = ""
    if npcGroup == nil and not showPlayerHeadOnly then
        noticeText = "Choose an NPC first."
    else
        local pluginLayer = pluginBuildLayer()
        if pluginLayer ~= nil then
            local function chooseFromVariants(npcID)
                chooseNpc(npcID ~= VariantsWindow.PLAYER_HEAD_ID and npcID or nil, "variants")
                if Settings.chosenNpcID ~= nil then
                    VariantsWindow.remember(Settings.chosenNpcID, pickedGroup)
                    VariantsWindow.setButton(nextGroupButtonText(pickedGroup))
                end
            end
            if showPlayerHeadOnly then
                VariantsWindow.open(PrettyUI, pluginLayer, "My head", { VariantsWindow.PLAYER_HEAD_ID },
                    VariantsWindow.PLAYER_HEAD_ID, chooseFromVariants)
            else
                local variantIDs = visibleIds(npcGroup)
                if #variantIDs == 0 then variantIDs = npcGroup.ids end
                VariantsWindow.remember(Settings.chosenNpcID, npcGroup)
                VariantsWindow.open(PrettyUI, pluginLayer, npcGroup.name .. " variants", variantIDs,
                    Settings.chosenNpcID, chooseFromVariants, NpcDirectory.nameOfNpc, {
                        page = page,
                        buttonText = nextGroupButtonText(npcGroup),
                        onButton = function()
                            showVariantsOf(NpcDirectory.nextGroupOfNpc(Settings.chosenNpcID, pickedGroup))
                            refreshNpcDropdown()
                        end,
                    })
            end
        else
            noticeText = "The game screen isn't ready."
        end
    end
    if settingsControls then settingsControls.noticeText.content = noticeText end
end

openVariantsWindow = function()
    local npcID = Settings.chosenNpcID
    if npcID == nil then return showVariantsOf(nil) end
    showVariantsOf(VariantsWindow.firstView(npcID, NpcDirectory.groupsOfNpc(npcID)))
end

-- TEMPORARY: every Troll head's customisation (models, recolours, texture targets), to find the group's duplicates.
-- Removed once answered, with its button.
local function logTrollLooks()
    local HeadFilter = require("src/game/head_filter")
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        if npcGroup.name == "Troll" then
            print(("[make_me_a_monster] TROLLLOOK|begin|%d heads"):format(#npcGroup.ids))
            for _, npcID in ipairs(npcGroup.ids) do
                print(("[make_me_a_monster] TROLLLOOK|%d|%s|%s"):format(npcID, NpcDirectory.nameOfNpc(npcID) or "?",
                    HeadFilter.describeHead(npcID)))
            end
            print("[make_me_a_monster] TROLLLOOK|end")
        end
    end
end

local MIN_HEAD_PERCENT, MAX_HEAD_PERCENT, HEAD_PERCENT_STEP = 50, 300, 5

-- The settings window's size, unless the screen is smaller.
local SETTINGS_WIDTH, SETTINGS_HEIGHT = 420, 560

local function buildSettingsControls(view, window)
    view:AddText("Pick an NPC: its head replaces yours in dialogue boxes.")
    local controls = { window = window }
    controls.chatheadStatusText = view:AddText(chatheadStatusMessage())
    controls.npcSearchBox = view:AddTextField({
        placeholder = "Search NPCs by name or id",
        onChange = function() refreshNpcDropdown() end,
    })
    controls.matchCountText = view:AddText("")
    controls.npcDropdown = view:AddComboBox({
        entries = {},
        onChange = function(_, entryID, _, eventType)
            local npcGroup = groupsByEntryID[entryID]
            if isRefreshingNpcDropdown or not isSelectionEvent(eventType) or npcGroup == nil then return end
            coverDropdownText(controls.npcDropdown, false)
            -- The first NPC of the name that matched the search, else the first of the group that has a head.
            local matchedMember = matchedMembersByEntryID[entryID]
            pickedGroup = npcGroup
            local npcID = matchedMember and matchedMember.ids[1] or visibleIds(npcGroup)[1] or npcGroup.ids[1]
            -- A member's name can be another group's.
            local label = matchedMember and matchedMember.name or npcGroup.name
            chooseNpc(npcID, "dropdown",
                label == npcGroup.name and npcGroup or NpcDirectory.groupLabelled(npcID, label))
        end,
    })
    showTextWhenClicked(controls.npcDropdown)
    view:AddSimpleButton("View variants", function() openVariantsWindow() end)
    view:AddSimpleButton("Browse all heads", function() openAllHeadsWindow() end)
    view:AddSimpleButton("Use my own head", function() chooseNpc(nil) end)
    if DEBUG_HEAD_BROWSER then
        view:AddSimpleButton("Debug: flag heads for the blacklist", function() openHeadFlaggingWindow() end)
        view:AddSimpleButton("Debug: all animations on Hans", function() openAnimationFlaggingWindow() end)
        view:AddSimpleButton("Debug: blacklisted heads with the player's animations", function()
            openBlacklistedHeadsWindow()
        end)
        view:AddSimpleButton("Debug: listed heads, newest models first", function() openNewestHeadsWindow() end)
        view:AddSimpleButton("Debug: group heads by hand (by model)", function() openHeadGroupingWindow() end)
        view:AddSimpleButton("Debug: log exact duplicate heads (next page)", function() logExactDuplicates() end)
        view:AddSimpleButton("Debug: log the Troll group's looks", function() logTrollLooks() end)
        view:AddSimpleButton("Debug: log the listed heads' names and models", function() logListedHeadModels() end)
        view:AddSimpleButton("Debug: log the listed heads' game names (id.NPC)", function() logListedHeadNames() end)
        view:AddSimpleButton("Debug: log the blacklisted heads' constants (next page)", function()
            logBlacklistConstants()
        end)
    end
    controls.noticeText = view:AddText("")
    controls.headSizeText = view:AddText("Head size: " .. Settings.headSizePercent() .. "%")
    view:AddSlider({
        min = MIN_HEAD_PERCENT,
        max = MAX_HEAD_PERCENT,
        step = HEAD_PERCENT_STEP,
        value = Settings.headSizePercent(),
        onChange = function(_, sliderValue)
            local percent = math.floor(sliderValue / HEAD_PERCENT_STEP + 0.5) * HEAD_PERCENT_STEP
            percent = math.max(MIN_HEAD_PERCENT, math.min(MAX_HEAD_PERCENT, percent))
            Settings.setHeadSizePercent(percent)
            HeadSwap.refreshOpenDialogues()
            AllHeadsWindow.refreshHeadSize()
            VariantsWindow.refreshHeadSize()
            controls.headSizeText.content = "Head size: " .. percent .. "%"
        end,
    })
    view:AddText("Animation for the head:")
    controls.animationStatusText = view:AddText(animationStatusText())
    controls.animationDropdown = view:AddComboBox({
        entries = {},
        onChange = function(_, entryID, _, eventType)
            local selectedListing = listingsByEntryID[entryID]
            if isRefreshingAnimationDropdown or not isSelectionEvent(eventType) or selectedListing == nil then
                return
            end
            Settings.chosenAnimationID = selectedListing.id
            coverDropdownText(controls.animationDropdown, false)
            animationChanged()
        end,
    })
    showTextWhenClicked(controls.animationDropdown)
    view:AddSimpleButton("Use default animation", function()
        Settings.chosenAnimationID = nil
        animationChanged()
        refreshAnimationDropdown()
    end)
    settingsControls = controls
    refreshNpcDropdown()
    refreshAnimationDropdown()
end

-- A page's layer can be gone by now, its interface unloading silently: so the dropdowns' labels go under pcall.
local function releaseSettingsControls()
    if settingsControls.window ~= nil then
        local windowRoot = settingsControls.window.root
        Settings.settingsX, Settings.settingsY = math.floor(windowRoot.x), math.floor(windowRoot.y)
    end
    for _, coverState in pairs(coverStates) do
        if coverState.label ~= nil then pcall(function() coverState.label:Destroy() end) end
    end
    coverStates = {}
    groupsByEntryID, matchedMembersByEntryID, listingsByEntryID = {}, {}, {}
    settingsControls = nil
end

closeSettingsWindow = function()
    if settingsControls == nil or settingsControls.window == nil then return end
    local window = settingsControls.window
    releaseSettingsControls()
    window:Destroy()
end

-- A saved NPC the list no longer has (taken out as a bad head) is forgotten.
local function forgetUnlistedNpcs()
    if Settings.chosenNpcID ~= nil and NpcDirectory.groupOfNpc(Settings.chosenNpcID) == nil then
        Settings.chosenNpcID = nil
    end
    if Settings.variantsNpcID ~= nil and NpcDirectory.groupOfNpc(Settings.variantsNpcID) == nil then
        Settings.variantsNpcID = nil
    end
end

local function engage()
    engaged = true
    -- The saved list of heads, if there is one: no scan.
    local okList, savedHeads = pcall(require, "src/data/listed_heads")
    if okList and type(savedHeads) == "table" and not NpcDirectory.baked then
        NpcDirectory.loadBaked(savedHeads)
        forgetUnlistedNpcs()
    end
end

-- Opening it again brings it to the front.
local function openSettingsWindow()
    if settingsControls ~= nil then return settingsControls.window:Show() end
    local pluginLayer = pluginBuildLayer()
    if pluginLayer == nil then
        pageNoticeText.content = "The game screen isn't ready."
        return
    end
    pageNoticeText.content = ""
    engage()
    local width = math.min(SETTINGS_WIDTH, pluginLayer.width)
    local height = math.min(SETTINGS_HEIGHT, pluginLayer.height)
    -- Where it was left, else the middle (kept on the screen).
    local x = Settings.settingsX or math.floor((pluginLayer.width - width) / 2)
    local y = Settings.settingsY or math.floor((pluginLayer.height - height) / 2)
    local window = nil
    local opened, openError = pcall(function()
        window = PrettyUI.Window.new(pluginLayer, {
            title = "Make Me A Monster", width = width, height = height, destroyOnClose = true,
            x = math.max(0, math.min(x, pluginLayer.width - width)),
            y = math.max(0, math.min(y, pluginLayer.height - height)),
            -- Closed with its X: the window destroys itself, and the settings go back to the page.
            onClose = function()
                releaseSettingsControls()
                switchSettings(false)
            end,
        })
        buildSettingsControls(window, window)
    end)
    if not opened then
        print("[make_me_a_monster] could not build the settings window: " .. tostring(openError))
        pageNoticeText.content = "The settings window could not open."
        if settingsControls ~= nil then releaseSettingsControls() end
        if window ~= nil then pcall(function() window:Destroy() end) end
    end
end

-- The page's top row holds the button switching the settings between the page and their own window.
local TOGGLE_SIZE, TOGGLE_INSET = 20, 4 -- (as PrettyUI's panels draw this button)
local TOGGLE_ROW_HEIGHT = TOGGLE_SIZE + TOGGLE_INSET * 2

-- Under the button: the controls, or with the settings in their window, a way to open it.
local function fillPage(pluginLayer)
    local pageView = PrettyUI.SimpleView.new(pluginLayer, {
        y = TOGGLE_ROW_HEIGHT, width = pluginLayer.width, height = pluginLayer.height - TOGGLE_ROW_HEIGHT,
    })
    pluginPageView = pageView
    pageView:AddTitle("Make Me A Monster")
    if Settings.settingsPoppedOut then
        pageView:AddText("The settings are in their own window.")
        pageView:AddSimpleButton("Open settings", function() openSettingsWindow() end)
        pageNoticeText = pageView:AddText("")
    else
        engage()
        buildSettingsControls(pageView)
    end
end

local function emptyPage()
    if pluginPageView == nil then return end
    if settingsControls ~= nil and settingsControls.window == nil then releaseSettingsControls() end
    pcall(function() pluginPageView:Destroy() end)
    pluginPageView = nil
end

local showPageToggleState = nil -- (set by buildPageToggle)

switchSettings = function(poppedOut)
    closeSettingsWindow()
    emptyPage()
    Settings.settingsPoppedOut = poppedOut
    -- The window can outlive the page, which unloads silently: it is built when the client next gives a layer.
    if ui.Interfaces:GetInterface(pluginPageLayer.interfaceID) == nil then return end
    showPageToggleState()
    local succeeded, errorMessage = pcall(fillPage, pluginPageLayer)
    if not succeeded then print("[make_me_a_monster] could not build the page: " .. tostring(errorMessage)) end
    if succeeded and poppedOut then openSettingsWindow() end
end

-- Components can't be destroyed in their own click handler, and switching replaces the view: so the button is a sprite
-- of the page's own, not one of the view's controls.
local function buildPageToggle(pluginLayer)
    local button = ui.Sprite.new(pluginLayer)
    button:SetPos(-TOGGLE_SIZE - TOGGLE_INSET, TOGGLE_INSET, 1.0) -- (from the page's right edge)
    button:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
    button.clickthrough = false
    local hovered, pressed = false, false
    local function showState()
        local states = Settings.settingsPoppedOut and PrettyUI.Sprites.PANEL_DOCK_BUTTON
            or PrettyUI.Sprites.PANEL_POPOUT_BUTTON
        button.spriteID = pressed and states.mousedown or hovered and states.hovered or states.neutral
    end
    button:Subscribe(ui.Hook.ONMOUSEOVER, function()
        hovered = true
        showState()
        return true
    end)
    button:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        hovered, pressed = false, false
        showState()
        return true
    end)
    button:Subscribe(ui.Hook.ONCLICK, function()
        pressed = true
        showState()
        return false
    end)
    button:Subscribe(ui.Hook.ONRELEASE, function()
        local activated = pressed
        pressed = false
        if activated then switchSettings(not Settings.settingsPoppedOut) end
        showState()
        return false
    end)
    showPageToggleState = showState
    showState()
    return button
end

local function closePage()
    emptyPage()
    if pluginPageToggle ~= nil then pcall(function() pluginPageToggle:Destroy() end) pluginPageToggle = nil end
end

local function buildPage(pluginLayer)
    pluginPageLayer = pluginLayer
    pluginPageToggle = buildPageToggle(pluginLayer)
    fillPage(pluginLayer)
end

Event.ContentLayerReady.Subscribe("make_me_a_monster_content", function(event)
    closePage()
    local succeeded, errorMessage = pcall(buildPage, event.component)
    if not succeeded then print("[make_me_a_monster] could not build the page: " .. tostring(errorMessage)) end
end)

-- Dev scan: once every NPC is read, each name is checked for variants worth showing, then merged into entries.
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
            -- The list of heads to save as src/data/listed_heads.lua.
            local lines, heads = NpcDirectory.exportLines(visibleIds)
            print(("[make_me_a_monster] HEADS|begin|%d entries, %d heads, %d lines"):format(#NpcDirectory.groups, heads, #lines))
            for _, line in ipairs(lines) do print(line) end
            print("[make_me_a_monster] HEADS|end")
            logListedHeadNames()
            refreshNpcDropdown()
            refreshStatusTexts()
            finalState.done = true
            return
        end
        finalState.index = finalState.index + 1
        visibleIds(npcGroup)
    end
end

-- The heads window closed: the dropdown goes back to the animations of the head in use.
AllHeadsWindow.onClosed = function()
    refreshAnimationDropdown()
    refreshStatusTexts()
end

openAllHeadsWindow = function()
    local noticeText = ""
    if not NpcDirectory.regrouped then
        noticeText = "The NPCs are still being read."
    else
        local pluginLayer = pluginBuildLayer()
        if pluginLayer ~= nil then
            AllHeadsWindow.open(PrettyUI, pluginLayer, NpcDirectory.headsInNameOrder(visibleIds),
                NpcDirectory.headsOfEachGroup(visibleIds), Settings.chosenNpcID, function(npcID, label)
                    chooseNpc(npcID, nil, NpcDirectory.groupLabelled(npcID, label))
                end)
            refreshAnimationDropdown()
        else
            noticeText = "The game screen isn't ready."
        end
    end
    if settingsControls then settingsControls.noticeText.content = noticeText end
end

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
            for _, npcID in ipairs(NpcDirectory.headsInNameOrder(visibleIds)) do heads[#heads + 1] = npcID end
            table.sort(heads)
            HeadFlaggingWindow.scaleFor = Settings.headScaleMultiplier
            HeadFlaggingWindow.open(PrettyUI, pluginLayer, heads, NpcDirectory.nameOfNpc, function(npcID) return HeadSwap.npcHeadAnimation(npcID) end)
        else
            noticeText = "The game screen isn't ready."
        end
    end
    if settingsControls then settingsControls.noticeText.content = noticeText end
end

-- Debug: every animation in the game played on Hans, for choosing the whitelist (src/data/animation_whitelist.lua).
local ANIMATION_HEAD = id.NPC.HANS
local ANIMATION_ENTRIES_PER_LINE = 12
local AnimationScan = require("src/debug/animation_scan")
local Whitelist = require("src/data/animation_whitelist")
local animationBrowserWanted = false

local TINT_LISTED = { 0.10, 0.28, 0.12, 1 }     -- on the whitelist, listed in the dropdown
local TINT_DUPLICATE = { 0.10, 0.17, 0.34, 1 }  -- on the whitelist as a duplicate

local function showAnimationBrowser()
    local succeeded, pluginLayer = pcall(function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end)
    if not (succeeded and pluginLayer ~= nil) then return false end
    local variantIDs, names, listed, duplicates = {}, {}, {}, {}
    for _, entry in ipairs(Animations.options(false)) do listed[entry.id] = true end
    for _, animID in ipairs(Whitelist.duplicates or {}) do duplicates[animID] = true end
    for _, anim in ipairs(AnimationScan.list) do
        variantIDs[#variantIDs + 1] = anim.id
        names[anim.id] = anim.name
    end
    HeadFlaggingWindow.scaleFor = Settings.headScaleMultiplier
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

-- Reads every animation a few at a time (continueAnimationBrowser), then opens the window.
openAnimationFlaggingWindow = function()
    animationBrowserWanted = true
    if settingsControls then settingsControls.noticeText.content = AnimationScan.done and "" or "Reading the game's animations..." end
end

local function continueAnimationBrowser()
    if not animationBrowserWanted then return end
    if not AnimationScan.done then
        AnimationScan.step()
        if settingsControls then
            settingsControls.noticeText.content = "Reading the game's animations: " .. #AnimationScan.list .. " so far..."
        end
        return
    end
    animationBrowserWanted = false
    local opened = showAnimationBrowser()
    if settingsControls then settingsControls.noticeText.content = opened and "" or "The game screen isn't ready." end
end

-- What the debug windows' heads play, worked out at every fill so the heads follow the dropdown.
local function playerVersionOfChosenAnimation()
    return HeadSwap.animationForHead(Settings.chosenAnimationID or Animations.fallback, true)
end

-- Debug: the blacklisted heads with the player's animations, to find heads built on the player's rig: a head that was
-- blank with NPC animations but moves here belongs in Animations.headsOnPlayerRig.
openBlacklistedHeadsWindow = function()
    local succeeded, pluginLayer = pcall(function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end)
    if not (succeeded and pluginLayer ~= nil) then
        if settingsControls then settingsControls.noticeText.content = "The game screen isn't ready." end
        return
    end
    local Blacklist = require("src/data/head_blacklist")
    local BlacklistNames = require("src/data/head_blacklist_names")
    local HeadFilter = require("src/game/head_filter")
    -- The blank heads have no model to show.
    local heads, names = {}, {}
    for _, groupName in ipairs({ "identical", "manual" }) do
        local groupNames = BlacklistNames[groupName] or {}
        for _, npcID in ipairs(Blacklist[groupName] or {}) do
            heads[#heads + 1] = npcID
            names[npcID] = groupNames[npcID]
        end
    end
    local playerRigIDs = {}
    for npcID in pairs(Animations.headsOnPlayerRig) do
        heads[#heads + 1] = npcID
        playerRigIDs[#playerRigIDs + 1] = npcID
    end
    table.sort(heads)
    table.sort(playerRigIDs)
    local function nameOf(npcID)
        if names[npcID] == nil then
            local fetched, name = pcall(function() return config.NPC.FromID(npcID).name end)
            names[npcID] = NpcDirectory.nameOfNpc(npcID) or (fetched and name) or "?"
        end
        return names[npcID]
    end
    -- For telling look-alikes apart: the heads on the player's rig, and the listed heads sharing a name with one.
    local playerRigNames = {}
    for _, npcID in ipairs(playerRigIDs) do
        playerRigNames[nameOf(npcID)] = true
        print(("[make_me_a_monster] HEADDATA|%d|%s|%s"):format(npcID, nameOf(npcID), HeadFilter.describeHead(npcID)))
    end
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        for _, member in ipairs(npcGroup.members or {}) do
            if playerRigNames[member.name] then
                for _, npcID in ipairs(member.ids) do
                    if not Animations.headsOnPlayerRig[npcID] then
                        print(("[make_me_a_monster] HEADDATA|%d|%s (listed)|%s"):format(npcID, member.name, HeadFilter.describeHead(npcID)))
                    end
                end
            end
        end
    end
    HeadFlaggingWindow.scaleFor = Settings.headScaleMultiplier
    HeadFlaggingWindow.open(PrettyUI, pluginLayer, heads, nameOf, nil, {
        title = "Debug: blacklisted heads and heads on the player's rig (green), with the player's animations",
        logLabel = "player rig",
        setup = function(model, npcID)
            model:SetModel(ui.ModelType.NPC_HEAD, npcID)
            model.animID = playerVersionOfChosenAnimation()
        end,
        tint = function(npcID) return Animations.headsOnPlayerRig[npcID] and TINT_LISTED or nil end,
        flaggedLines = function(selected)
            local lines = { ("heads on the player's rig: %d (lines for Animations.headsOnPlayerRig)"):format(#selected) }
            for _, npcID in ipairs(selected) do
                lines[#lines + 1] = ("        \"%s\", -- %d %s"):format(configNameOf(npcID), npcID, names[npcID] or "?")
            end
            for _, npcID in ipairs(selected) do
                lines[#lines + 1] = ("HEADDATA|%d|%s|%s"):format(npcID, nameOf(npcID), HeadFilter.describeHead(npcID))
            end
            return lines
        end,
    })
    if settingsControls then settingsControls.noticeText.content = "" end
end

-- Debug: the listed heads, newest models first, with the player's animations, to find newer heads on the player's rig.
openNewestHeadsWindow = function()
    local succeeded, pluginLayer = pcall(function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end)
    if not (succeeded and pluginLayer ~= nil) or not NpcDirectory.regrouped then
        if settingsControls then settingsControls.noticeText.content = "The game screen isn't ready." end
        return
    end
    local HeadFilter = require("src/game/head_filter")
    local heads, newestModel = {}, {}
    for _, npcID in ipairs(NpcDirectory.headsInNameOrder(visibleIds)) do
        heads[#heads + 1] = npcID
        newestModel[npcID] = HeadFilter.newestModel(npcID)
    end
    table.sort(heads, function(a, b)
        if newestModel[a] ~= newestModel[b] then return newestModel[a] > newestModel[b] end
        return a < b
    end)
    HeadFlaggingWindow.scaleFor = Settings.headScaleMultiplier
    HeadFlaggingWindow.open(PrettyUI, pluginLayer, heads,
        function(npcID) return (NpcDirectory.nameOfNpc(npcID) or "?") .. " (model " .. newestModel[npcID] .. ")" end, nil, {
        title = "Debug: listed heads, newest models first, with the player's animations (green: on the player's rig)",
        logLabel = "player rig",
        setup = function(model, npcID)
            model:SetModel(ui.ModelType.NPC_HEAD, npcID)
            model.animID = playerVersionOfChosenAnimation()
        end,
        tint = function(npcID) return Animations.headsOnPlayerRig[npcID] and TINT_LISTED or nil end,
        flaggedLines = function(selected)
            local lines = { ("heads on the player's rig: %d (lines for Animations.headsOnPlayerRig)"):format(#selected) }
            for _, npcID in ipairs(selected) do
                lines[#lines + 1] = ("        \"%s\", -- %d %s"):format(configNameOf(npcID), npcID,
                    NpcDirectory.nameOfNpc(npcID) or "?")
            end
            return lines
        end,
    })
    if settingsControls then settingsControls.noticeText.content = "" end
end

-- Debug: every listed head sorted by its models, for grouping them by hand (src/debug/head_grouping_window.lua).
openHeadGroupingWindow = function()
    local pluginLayer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    if pluginLayer == nil or not NpcDirectory.regrouped then
        if settingsControls then settingsControls.noticeText.content = "The game screen isn't ready." end
        return
    end
    HeadFlaggingWindow.scaleFor = Settings.headScaleMultiplier
    HeadGroupingWindow.open(PrettyUI, pluginLayer, NpcDirectory.headsInNameOrder(visibleIds), NpcDirectory.nameOfNpc,
        function(npcID) return HeadSwap.npcHeadAnimation(npcID) end)
    if settingsControls then settingsControls.noticeText.content = "" end
end

-- Debug: the listed heads with exactly the same customisation logged as duplicates, for tools/apply_grouping_log.py.
logExactDuplicates = function()
    if not NpcDirectory.regrouped then
        if settingsControls then settingsControls.noticeText.content = "The NPCs are still being read." end
        return
    end
    local logged, total = HeadGroupingWindow.logExactDuplicates(NpcDirectory.headsInNameOrder(visibleIds),
        NpcDirectory.nameOfNpc)
    if settingsControls then
        settingsControls.noticeText.content = logged >= total and ("All %d batches logged"):format(total)
            or ("Logged %d of %d batches: paste them, then press again"):format(logged, total)
    end
end

-- Debug: every listed head's name and models, several to a line (the console keeps about a thousand lines), for
-- tools/make_heads_models.py.
local MODELS_PER_LINE = 10

logListedHeadModels = function()
    if not NpcDirectory.regrouped then
        if settingsControls then settingsControls.noticeText.content = "The NPCs are still being read." end
        return
    end
    local HeadFilter = require("src/game/head_filter")
    local heads = NpcDirectory.headsInNameOrder(visibleIds)
    local records = {}
    for _, npcID in ipairs(heads) do
        records[#records + 1] = ("%d=%s:%s@%s"):format(npcID, NpcDirectory.nameOfNpc(npcID) or "?",
            table.concat(HeadFilter.headModels(npcID), ","), configNameOf(npcID))
    end
    local lineCount = math.ceil(#records / MODELS_PER_LINE)
    print(("[make_me_a_monster] MODELS|begin|%d heads, %d lines"):format(#records, lineCount))
    for index = 1, lineCount do
        local first = (index - 1) * MODELS_PER_LINE
        print(("[make_me_a_monster] MODELS|%d/%d|%s"):format(index, lineCount,
            table.concat(records, "~", first + 1, math.min(#records, first + MODELS_PER_LINE))))
    end
    print("[make_me_a_monster] MODELS|end")
    if settingsControls then settingsControls.noticeText.content = "Logged: paste the console and run tools/make_heads_models.py" end
end

-- Debug: every listed head's constant (id=!NAME if it does not give its id back), and the animation names id.Seq did
-- not know, for tools/name_listed_heads.py.
local NAMES_PER_LINE = 20

logListedHeadNames = function()
    if not NpcDirectory.regrouped then
        if settingsControls then settingsControls.noticeText.content = "The NPCs are still being read." end
        return
    end
    local npcIDs, isLogged = {}, {}
    for _, npcID in ipairs(NpcDirectory.headsInNameOrder(visibleIds)) do
        npcIDs[#npcIDs + 1], isLogged[npcID] = npcID, true
    end
    for npcID in pairs(Animations.headsOnPlayerRig) do
        if not isLogged[npcID] then npcIDs[#npcIDs + 1] = npcID end
    end
    local records, problems = {}, 0
    for _, npcID in ipairs(npcIDs) do
        local named, configName = pcall(function() return config.NPC.FromID(npcID).configName end)
        configName = named and configName or ""
        local givesID, idBack = pcall(function() return id.NPC[configName] end)
        local good = configName ~= "" and givesID and idBack == npcID
        if not good then problems = problems + 1 end
        records[#records + 1] = ("%d=%s%s"):format(npcID, good and "" or "!", configName)
    end
    local unknownRead, unknownValue = pcall(function() return id.NPC.MAKE_ME_A_MONSTER_NO_SUCH_NPC end)
    print(("[make_me_a_monster] NPCNAMES|unknown name check: %s, %s"):format(tostring(unknownRead), tostring(unknownValue)))
    print(("[make_me_a_monster] NPCNAMES|animation names id.Seq did not know: %d %s"):format(#GameIds.unresolved,
        table.concat(GameIds.unresolved, " ")))
    local lineCount = math.ceil(#records / NAMES_PER_LINE)
    print(("[make_me_a_monster] NPCNAMES|begin|%d heads, %d lines"):format(#records, lineCount))
    for index = 1, lineCount do
        local first = (index - 1) * NAMES_PER_LINE
        print(("[make_me_a_monster] NPCNAMES|%d/%d|%s"):format(index, lineCount,
            table.concat(records, "~", first + 1, math.min(#records, first + NAMES_PER_LINE))))
    end
    print(("[make_me_a_monster] NPCNAMES|end|%d problems"):format(problems))
    if settingsControls then
        settingsControls.noticeText.content = ("Logged (%d problems): paste the console and run tools/name_listed_heads.py"):format(problems)
    end
end

-- Debug: every blacklisted head's constant, for tools/make_blacklist_constants.py. There are more than the console
-- keeps (about a thousand lines): so each press logs the next page.
local BLACKLIST_LINE_LENGTH, BLACKLIST_LINES_PER_PAGE = 860, 700
local blacklistLines, blacklistNextLine = nil, 1

logBlacklistConstants = function()
    if blacklistLines == nil then
        local Blacklist = require("src/data/head_blacklist")
        local npcIDs = {}
        for _, groupName in ipairs({ "blank", "identical", "manual" }) do
            for _, npcID in ipairs(Blacklist[groupName]) do npcIDs[#npcIDs + 1] = npcID end
        end
        table.sort(npcIDs)
        blacklistLines = {}
        local current, length = {}, 0
        for _, npcID in ipairs(npcIDs) do
            local constant = configNameOf(npcID)
            local givesID, idBack = pcall(function() return id.NPC[constant] end)
            local record = ("%d=%s%s"):format(npcID, (givesID and idBack == npcID) and "" or "!", constant)
            if length + #record + 1 > BLACKLIST_LINE_LENGTH then
                blacklistLines[#blacklistLines + 1] = table.concat(current, "~")
                current, length = {}, 0
            end
            current[#current + 1], length = record, length + #record + 1
        end
        if #current > 0 then blacklistLines[#blacklistLines + 1] = table.concat(current, "~") end
    end
    local lastLine = math.min(#blacklistLines, blacklistNextLine + BLACKLIST_LINES_PER_PAGE - 1)
    for index = blacklistNextLine, lastLine do
        print(("[make_me_a_monster] BLACKCONST|%d/%d|%s"):format(index, #blacklistLines, blacklistLines[index]))
    end
    local finished = lastLine >= #blacklistLines
    if settingsControls then
        settingsControls.noticeText.content = finished and "All logged: run tools/make_blacklist_constants.py"
            or ("Logged lines up to %d of %d: paste them, then press again"):format(lastLine, #blacklistLines)
    end
    blacklistNextLine = finished and 1 or lastLine + 1
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
end)

-- Dialogue boxes are only watched in the game.
Event.GameStateChanged.Subscribe("make_me_a_monster_state", function(event)
    if event.newState == GameState.GAME then
        HeadSwap.start()
    elseif event.oldState == GameState.GAME then
        HeadSwap.reset()
    end
end)

-- The heads window's closing fits the animation to the head in use: so the dialogue boxes are put back after it.
function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe("make_me_a_monster_content")
    Event.Draw.Unsubscribe("make_me_a_monster_draw")
    Event.GameStateChanged.Unsubscribe("make_me_a_monster_state")
    closeSettingsWindow()
    closePage()
    VariantsWindow.close()
    AllHeadsWindow.close()
    HeadFlaggingWindow.close()
    HeadSwap.stop()
    Settings.save()
end
