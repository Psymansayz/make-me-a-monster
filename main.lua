-- Make Me A Monster: choose an NPC in the settings, and its head replaces yours in the game's dialogue boxes.
-- This file holds the plugin's page, the settings window, and what happens when a head is chosen.

local Settings = require("src/data/settings")
local NpcDirectory = require("src/game/npc_directory")
local AnimationChoice = require("src/game/animation_choice")
local HeadSwap = require("src/game/head_swap")
local VariantsWindow = require("src/ui/variants_window")
local AllHeadsWindow = require("src/ui/all_heads_window")
local SettingsView = require("src/ui/settings_view")
local WindowPlacement = require("src/ui/window_placement")

local PrettyUI = prettyui

-- The settings are read once, here, and written at shutdown.
Settings.load()
HeadSwap.start()

-- The client's require caches every file for good, and the plugin can't clear that cache, so a data file that is read
-- once is emptied after it is converted. The dev branch doesn't do this, because its debug windows read them again.
local function emptyData(data)
    for key in pairs(data) do data[key] = nil end
end
emptyData(require("src/data/animation_list"))
emptyData(require("src/data/dedicated_animations"))

local pluginPageLayer = nil
local pluginPageToggle = nil
local pluginPageView = nil
local pageNoticeText = nil -- the page's text saying why the window did not open

local function animationChanged()
    HeadSwap.refreshOpenDialogues()
    AllHeadsWindow.updateAnimations()
    VariantsWindow.updateAnimations()
    SettingsView.refreshStatusTexts()
end

local function refitAnimation()
    local changed = AnimationChoice.fitToHead(AllHeadsWindow.isOpen())
    SettingsView.refreshAnimationDropdown()
    if changed then animationChanged() else SettingsView.refreshStatusTexts() end
    return changed
end

-- The group the chosen head was picked from, remembered for this session, since a head can be in several groups.
local pickedGroup = nil

local function groupOfChosenNpc()
    local npcID = Settings.chosenNpcID
    if npcID == nil then return nil end
    if pickedGroup ~= nil and NpcDirectory.memberOfNpc(npcID, pickedGroup) ~= nil then return pickedGroup end
    return NpcDirectory.groupOfNpc(npcID)
end

local openVariantsWindow
local openAllHeadsWindow
local switchSettings

-- chosenFrom is "dropdown" or "variants" when that control already shows the choice. selectedGroup is the group the
-- head was selected under, if its label named one.
local function chooseNpc(npcID, chosenFrom, selectedGroup)
    Settings.chosenNpcID = npcID
    if chosenFrom == nil then pickedGroup = selectedGroup end
    if selectedGroup ~= nil then VariantsWindow.selectGroup(npcID, selectedGroup) end
    local animationRefitted = refitAnimation()
    if chosenFrom ~= "dropdown" then SettingsView.refreshNpcDropdown() end
    if chosenFrom ~= "variants" and VariantsWindow.isOpen() then openVariantsWindow() end
    if not animationRefitted then HeadSwap.refreshOpenDialogues() end -- if it was, animationChanged refreshed them
end

-- The layer that plugin windows go on, or nil while the game screen isn't ready, in which case setNotice says so.
local function windowLayer(setNotice)
    local succeeded, pluginLayer = pcall(function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end)
    pluginLayer = succeeded and pluginLayer or nil
    setNotice(pluginLayer and "" or "The game screen isn't ready.")
    return pluginLayer
end

local function nextGroupButtonText(npcGroup)
    local nextGroup = NpcDirectory.nextGroupOfNpc(Settings.chosenNpcID, npcGroup)
    return nextGroup and ("View " .. nextGroup.name .. " variants") or nil
end

-- page is the page to show, or nil for the page with the chosen head.
local function showVariantsOf(npcGroup, page)
    pickedGroup = npcGroup -- a variant picked in the window stays in this group
    local showPlayerHeadOnly = Settings.chosenNpcID == nil
    if npcGroup == nil and not showPlayerHeadOnly then return SettingsView.setNotice("Choose an NPC first.") end
    local pluginLayer = windowLayer(SettingsView.setNotice)
    if pluginLayer == nil then return end
    local function chooseFromVariants(npcID)
        chooseNpc(npcID ~= VariantsWindow.PLAYER_HEAD_ID and npcID or nil, "variants")
        if Settings.chosenNpcID ~= nil then
            VariantsWindow.remember(Settings.chosenNpcID, pickedGroup)
            VariantsWindow.setButton(nextGroupButtonText(pickedGroup))
        end
    end
    if showPlayerHeadOnly then
        VariantsWindow.open(PrettyUI, pluginLayer, {
            title = "My head", ids = { VariantsWindow.PLAYER_HEAD_ID }, current = VariantsWindow.PLAYER_HEAD_ID,
            onPick = chooseFromVariants,
        })
        return
    end
    VariantsWindow.remember(Settings.chosenNpcID, npcGroup)
    VariantsWindow.open(PrettyUI, pluginLayer, {
        title = npcGroup.name .. " variants", ids = NpcDirectory.idsOf(npcGroup), current = Settings.chosenNpcID,
        onPick = chooseFromVariants, nameOf = NpcDirectory.nameOfNpc, page = page,
        buttonText = nextGroupButtonText(npcGroup),
        onButton = function()
            showVariantsOf(NpcDirectory.nextGroupOfNpc(Settings.chosenNpcID, pickedGroup))
            SettingsView.refreshNpcDropdown()
        end,
    })
end

openVariantsWindow = function()
    local npcID = Settings.chosenNpcID
    if npcID == nil then return showVariantsOf(nil) end
    showVariantsOf(VariantsWindow.firstView(npcID, NpcDirectory.groupsOfNpc(npcID)))
end

-- When the heads window closes, the animation and its dropdown are fitted back to the head in use.
AllHeadsWindow.onClosed = function() refitAnimation() end

openAllHeadsWindow = function()
    local pluginLayer = windowLayer(SettingsView.setNotice)
    if pluginLayer == nil then return end
    AllHeadsWindow.open(PrettyUI, pluginLayer, Settings.chosenNpcID, function(npcID, label)
        SettingsView.clearSearch() -- so the NPC dropdown lists the picked head
        chooseNpc(npcID, nil, NpcDirectory.groupLabelled(npcID, label))
    end)
    refitAnimation()
end

-- The saved heads aren't loaded until the settings are first built, because dialogue only needs the saved NPC id.
local function loadHeads()
    if NpcDirectory.isLoaded then return end
    local listedHeads = require("src/data/listed_heads")
    NpcDirectory.loadListedHeads(listedHeads)
    Settings.forgetUnlistedNpcs(NpcDirectory.groupOfNpc)
    emptyData(listedHeads)
end

local settingsActions = {
    useOwnHead = function()
        SettingsView.clearSearch() -- so the NPC dropdown shows it
        chooseNpc(nil)
    end,
    npcPicked = function(npcID, npcGroup, selectedGroup)
        pickedGroup = npcGroup
        chooseNpc(npcID, "dropdown", selectedGroup)
    end,
    groupOfChosenNpc = groupOfChosenNpc,
    openVariants = function() openVariantsWindow() end,
    openAllHeads = function() openAllHeadsWindow() end,
    headSizeChanged = function()
        HeadSwap.refreshOpenDialogues()
        AllHeadsWindow.refreshHeadSize()
        VariantsWindow.refreshHeadSize()
    end,
    animationChanged = animationChanged,
}

local function buildSettings(view, window)
    loadHeads()
    SettingsView.build(view, window, settingsActions)
    refitAnimation()
end

-- The settings window's size when first opened, and the smallest it can be resized to. Its content scrolls.
local SETTINGS_WIDTH, SETTINGS_HEIGHT = 420, 560
local SETTINGS_MIN_WIDTH, SETTINGS_MIN_HEIGHT = 320, 240

local function setPageNotice(text)
    pageNoticeText.content = text
end

-- Opening it again brings it to the front.
local function openSettingsWindow()
    if SettingsView.isBuilt() then
        local openWindow = SettingsView.window()
        if openWindow ~= nil then openWindow:Show() end
        return
    end
    local pluginLayer = windowLayer(setPageNotice)
    if pluginLayer == nil then return end
    local placement = Settings.windows.settings
    local width, height = WindowPlacement.size(pluginLayer, placement, SETTINGS_WIDTH, SETTINGS_HEIGHT,
        SETTINGS_MIN_WIDTH, SETTINGS_MIN_HEIGHT)
    local x, y = WindowPlacement.position(pluginLayer, width, height, placement)
    local window = nil
    local opened = pcall(function()
        window = PrettyUI.Window.new(pluginLayer, {
            title = "Make Me A Monster", width = width, height = height, x = x, y = y, destroyOnClose = true,
            resizable = true, minWidth = math.min(SETTINGS_MIN_WIDTH, width),
            minHeight = math.min(SETTINGS_MIN_HEIGHT, height),
            -- Called when its X is clicked. The window destroys itself, and the settings move back to the page.
            onClose = function()
                SettingsView.release()
                switchSettings(false)
            end,
        })
        buildSettings(window, window)
    end)
    if not opened then
        setPageNotice("The settings window could not open.")
        SettingsView.release()
        if window ~= nil then pcall(function() window:Destroy() end) end
    end
end

local function closeSettingsWindow()
    local window = SettingsView.window()
    if window == nil then return end
    SettingsView.release()
    window:Destroy()
end

-- The page's top row holds the button that switches the settings between the page and their own window.
local TOGGLE_SIZE, TOGGLE_INSET = 20, 4 -- matching how PrettyUI's panels draw this button
local TOGGLE_ROW_HEIGHT = TOGGLE_SIZE + TOGGLE_INSET * 2

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
        buildSettings(pageView)
    end
end

local function emptyPage()
    if pluginPageView == nil then return end
    if SettingsView.isBuilt() and SettingsView.window() == nil then SettingsView.release() end
    pcall(function() pluginPageView:Destroy() end)
    pluginPageView = nil
end

local showPageToggleState = nil -- set by buildPageToggle

switchSettings = function(poppedOut)
    closeSettingsWindow()
    emptyPage()
    Settings.settingsPoppedOut = poppedOut
    -- The window can outlive the page, which unloads without notice. If it has, the page is built when the client next
    -- provides a layer.
    if ui.Interfaces:GetInterface(pluginPageLayer.interfaceID) == nil then return end
    showPageToggleState()
    local succeeded = pcall(fillPage, pluginPageLayer)
    if succeeded and poppedOut then openSettingsWindow() end
end

-- Components can't be destroyed in their own click handler, and switching replaces the view, so the button is a sprite
-- on the page itself rather than one of the view's controls.
local function buildPageToggle(pluginLayer)
    local button = ui.Sprite.new(pluginLayer)
    button:SetPos(-TOGGLE_SIZE - TOGGLE_INSET, TOGGLE_INSET, 1.0) -- from the page's right edge
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
    pcall(buildPage, event.component)
end)

Event.GameStateChanged.Subscribe("make_me_a_monster_state", function(event)
    if event.newState == GameState.GAME then
        HeadSwap.start()
    elseif event.oldState == GameState.GAME then
        HeadSwap.reset()
    end
end)

-- Closing the heads window refits the animation and refreshes the boxes, so the settings close first and the player's
-- head is put back last.
function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe("make_me_a_monster_content")
    Event.GameStateChanged.Unsubscribe("make_me_a_monster_state")
    closeSettingsWindow()
    closePage()
    VariantsWindow.close()
    AllHeadsWindow.close()
    NpcDirectory.forgetCaches()
    HeadSwap.stop()
    Settings.save()
end
