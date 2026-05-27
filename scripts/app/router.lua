-- app/router.lua
-- 页面路由管理器

local EventBus = require("scripts/app/event_bus")

local Router = {}
local history = {}
local currentScreen = nil
local screenFactories = {}

function Router.register(screenId, factory)
    screenFactories[screenId] = factory
end

function Router.navigate(screenId, params)
    if currentScreen then
        table.insert(history, {id = currentScreen.id, params = currentScreen.params})
    end
    currentScreen = {id = screenId, params = params or {}}
    EventBus.emit("navigate", screenId, params)
end

function Router.back()
    if #history > 0 then
        local prev = table.remove(history)
        currentScreen = prev
        EventBus.emit("navigate", prev.id, prev.params)
        return true
    end
    return false
end

function Router.getCurrentScreen()
    return currentScreen
end

function Router.getFactory(screenId)
    return screenFactories[screenId]
end

function Router.clearHistory()
    history = {}
end

function Router.replaceWith(screenId, params)
    currentScreen = {id = screenId, params = params or {}}
    EventBus.emit("navigate", screenId, params)
end

return Router
