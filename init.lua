-- dock-shortcut (Cmd + 1..9)

require("hs.ipc")
local spaces = require("hs.spaces")
local windowFilter = require("hs.window.filter")

local SHOW_ALERT = true
local CYCLE_WINDOWS_IF_FOCUSED = true

hs.autoLaunch(true)

-- Auto-reload config on save
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(files)
    for _, file in pairs(files) do
        if file:sub(-4) == ".lua" then
            hs.reload()
            return
        end
    end
end):start()

-- Toast indicator
local toastCanvas = nil
local toastTimer = nil

local function showMinimalToast(slotNum, appName, detail)
    if not SHOW_ALERT then return end

    if toastTimer then
        toastTimer:stop()
        toastTimer = nil
    end
    if toastCanvas then
        toastCanvas:delete()
        toastCanvas = nil
    end

    local screen = hs.screen.mainScreen()
    if not screen then return end
    local sFrame = screen:frame()

    local hasDetail = (detail and detail ~= "")
    local width = 230
    local height = hasDetail and 42 or 30
    local marginX = 20
    local marginY = 20

    local x = sFrame.x + sFrame.w - width - marginX
    local y = sFrame.y + sFrame.h - height - marginY

    toastCanvas = hs.canvas.new({ x = x, y = y, w = width, h = height })
    toastCanvas:level(hs.canvas.windowLevels.overlay)
    toastCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)

    toastCanvas[1] = {
        type = "rectangle",
        action = "strokeAndFill",
        fillColor = { white = 0.10, alpha = 0.88 },
        strokeColor = { white = 1.0, alpha = 0.16 },
        strokeWidth = 1,
        roundedRectRadii = { xRadius = 8, yRadius = 8 }
    }

    local textStr = string.format("[%d] %s", slotNum, appName)
    if hasDetail then
        textStr = textStr .. "\n" .. detail
    end

    toastCanvas[2] = {
        type = "text",
        text = hs.styledtext.new(textStr, {
            font = { name = ".AppleSystemUIFont", size = hasDetail and 11.5 or 12 },
            color = { white = 0.95, alpha = 1.0 },
            paragraphStyle = { lineSpacing = 2 }
        }),
        frame = { x = 12, y = hasDetail and 5 or 7, w = width - 24, h = height - 10 }
    }

    toastCanvas:show()

    toastTimer = hs.timer.doAfter(0.9, function()
        if toastCanvas then
            toastCanvas:delete()
            toastCanvas = nil
        end
        toastTimer = nil
    end)
end

-- Helper function to get valid application dock items (excluding separators, trash, folders)
local function getApplicationDockItems()
    local dockApp = hs.application.get("com.apple.dock")
    if not dockApp then return nil end

    local dockElement = hs.axuielement.applicationElement(dockApp)
    if not dockElement then return nil end

    local children = dockElement:attributeValue("AXChildren")
    if not children or #children == 0 then return nil end

    local dockList = children[1]
    local allItems = dockList:attributeValue("AXChildren")
    if not allItems then return nil end

    local appItems = {}
    for _, item in ipairs(allItems) do
        local subrole = item:attributeValue("AXSubrole")
        local role = item:attributeValue("AXRole")
        -- Dock apps have subrole AXApplicationDockItem
        if subrole == "AXApplicationDockItem" then
            table.insert(appItems, item)
        elseif role == "AXDockItem" and subrole ~= "AXSeparatorDockItem" and subrole ~= "AXFolderDockItem" and subrole ~= "AXTrashDockItem" then
            local title = item:attributeValue("AXTitle")
            if title and title ~= "Trash" and title ~= "Bin" then
                table.insert(appItems, item)
            end
        end
    end

    return appItems
end

-- Helper to get running hs.application for a dock item
local function getAppForDockItem(dockItem)
    local title = dockItem:attributeValue("AXTitle")
    local axUrl = dockItem:attributeValue("AXURL")
    local bundleID = nil
    if axUrl and axUrl.filePath then
        local info = hs.application.infoForBundlePath(axUrl.filePath)
        bundleID = info and info.CFBundleIdentifier
    end
    if bundleID then
        local apps = hs.application.applicationsForBundleID(bundleID)
        if apps and #apps > 0 then return apps[1] end
    end
    if title and title ~= "" then
        return hs.application.get(title) or hs.application.find(title)
    end
    return nil
end

-- Cycle windows via app Window menu
local function cycleViaWindowMenu(app)
    if not app then return false end
    local ax = hs.axuielement.applicationElement(app)
    if not ax then return false end
    local mb = ax:attributeValue("AXMenuBar")
    if not mb then return false end

    local windowMenu = nil
    for _, item in ipairs(mb:attributeValue("AXChildren") or {}) do
        if item:attributeValue("AXTitle") == "Window" then
            local children = item:attributeValue("AXChildren")
            if children and #children > 0 then
                windowMenu = children[1]
                break
            end
        end
    end
    if not windowMenu then return false end

    local menuItems = windowMenu:attributeValue("AXChildren") or {}
    -- Find last separator index (open project/document windows always follow the last separator)
    local lastSepIdx = 0
    for idx, item in ipairs(menuItems) do
        local t = item:attributeValue("AXTitle")
        if not t or t == "" then
            lastSepIdx = idx
        end
    end

    local winItems = {}
    local curIdx = nil
    local focusedWin = hs.window.focusedWindow()
    local focusedTitle = focusedWin and focusedWin:title() or ""

    for idx = lastSepIdx + 1, #menuItems do
        local item = menuItems[idx]
        local t = item:attributeValue("AXTitle")
        if t and t ~= "" then
            table.insert(winItems, item)
            local mark = item:attributeValue("AXMenuItemMarkChar")
            -- Checkmark (✓) indicates the focused window/tab. Bullets (•) indicate background tasks in Terminal.
            if mark == "✓" or (mark ~= "•" and focusedTitle ~= "" and focusedTitle:find(t, 1, true)) then
                curIdx = #winItems
            end
        end
    end

    if #winItems <= 1 then return false end

    -- Move in natural forward tab/window order (decrements menu index, wrapping to end)
    local nextIdx = curIdx and (curIdx == 1 and #winItems or curIdx - 1) or #winItems
    local targetItem = winItems[nextIdx]
    local targetTitle = targetItem:attributeValue("AXTitle") or "Window"

    targetItem:performAction("AXPress")
    app:activate(true)

    return true, targetTitle, nextIdx, #winItems
end

-- Fallback helper to get all standard windows for an app
local function getAllWindowsForApp(targetApp, appTitle)
    local queryNames = {}
    if targetApp then
        table.insert(queryNames, targetApp:name())
    end
    if appTitle and appTitle ~= "" and (not targetApp or appTitle ~= targetApp:name()) then
        table.insert(queryNames, appTitle)
    end

    local foundWins = {}
    local seenIDs = {}

    local wf = windowFilter.new(queryNames)
    if wf then
        wf:setCurrentSpace(nil)
        local rawFilterWins = wf:getWindows() or {}
        for _, w in ipairs(rawFilterWins) do
            if w:isStandard() and not w:isMinimized() and not seenIDs[w:id()] then
                seenIDs[w:id()] = true
                table.insert(foundWins, w)
            end
        end
    end

    if targetApp then
        local appWins = targetApp:allWindows() or {}
        for _, w in ipairs(appWins) do
            if w:isStandard() and not w:isMinimized() and not seenIDs[w:id()] then
                seenIDs[w:id()] = true
                table.insert(foundWins, w)
            end
        end
    end

    return foundWins
end

-- Helper to activate or cycle windows of an app
local function activateDockSlot(slotNumber)
    if not hs.accessibilityState() then
        hs.alert.show("Hammerspoon needs Accessibility permission! Restart Hammerspoon after granting.", 2)
        return
    end

    local appItems = getApplicationDockItems()
    if not appItems or #appItems == 0 then
        return
    end

    -- In Dock order:
    -- appItems[1] is Finder.
    -- appItems[2] is App 1 (e.g. Google Chrome).
    -- appItems[3] is App 2 (e.g. Slack).
    -- appItems[N + 1] is App N.
    local targetItem = nil
    if slotNumber == 0 then
        targetItem = appItems[1] -- Finder
    else
        targetItem = appItems[slotNumber + 1]
    end

    if not targetItem then
        return
    end

    local appTitle = targetItem:attributeValue("AXTitle") or "App"
    local targetApp = getAppForDockItem(targetItem)
    local frontmost = hs.application.frontmostApplication()

    local isAlreadyFrontmost = false
    if targetApp and frontmost then
        if frontmost:pid() == targetApp:pid() then
            isAlreadyFrontmost = true
        elseif frontmost:bundleID() and targetApp:bundleID() and frontmost:bundleID() == targetApp:bundleID() then
            isAlreadyFrontmost = true
        end
    elseif frontmost and appTitle and frontmost:title() == appTitle then
        isAlreadyFrontmost = true
    end

    if CYCLE_WINDOWS_IF_FOCUSED and isAlreadyFrontmost and targetApp then
        -- Terminal tabs
        if targetApp:name() == "Terminal" or targetApp:bundleID() == "com.apple.Terminal" then
            hs.eventtap.keyStroke({"ctrl"}, "tab")
            hs.timer.doAfter(0.12, function()
                local curWin = hs.window.focusedWindow()
                local shortTitle = curWin and curWin:title() or "Terminal"
                if #shortTitle > 28 then shortTitle = shortTitle:sub(1, 28) .. "..." end
                showMinimalToast(slotNumber, appTitle, shortTitle)
            end)
            return
        end

        -- Cycle via Window menu
        local menuSuccess, menuWinTitle, nextIdx, totalWins = cycleViaWindowMenu(targetApp)
        if menuSuccess then
            local shortTitle = menuWinTitle or ""
            if #shortTitle > 28 then shortTitle = shortTitle:sub(1, 28) .. "..." end
            local detail = string.format("(%d/%d) %s", nextIdx, totalWins, shortTitle)
            showMinimalToast(slotNumber, appTitle, detail)
            return
        end

        -- Fallback window cycle
        local windows = getAllWindowsForApp(targetApp, appTitle)
        if windows and #windows > 1 then
            local curWin = hs.window.focusedWindow()
            local curIdx = nil
            for i, win in ipairs(windows) do
                if curWin and win:id() == curWin:id() then
                    curIdx = i
                    break
                end
            end
            local nextIdx = curIdx and ((curIdx % #windows) + 1) or 1
            local targetWin = windows[nextIdx]
            targetWin:focus()
            targetWin:raise()
            local shortTitle = targetWin:title() or ""
            if #shortTitle > 28 then shortTitle = shortTitle:sub(1, 28) .. "..." end
            local detail = string.format("(%d/%d) %s", nextIdx, #windows, shortTitle)
            showMinimalToast(slotNumber, appTitle, detail)
            return
        end
    end

    -- First activation / launch
    showMinimalToast(slotNumber, appTitle, nil)

    -- Otherwise, perform standard AXPress on the dock item
    targetItem:performAction("AXPress")
end

-- Bind Command + 1 ... 9 to Apps 1 ... 9
for i = 1, 9 do
    hs.hotkey.bind({"cmd"}, tostring(i), function()
        activateDockSlot(i)
    end)
end

-- Bind Command + 0 to Finder
hs.hotkey.bind({"cmd"}, "0", function()
    activateDockSlot(0)
end)

showMinimalToast(0, "Dock Shortcuts Ready", "Cmd + 1..9 Active")
