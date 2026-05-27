-- app/event_bus.lua
-- 简易事件总线，用于模块间解耦通信

local EventBus = {}
local listeners = {}

function EventBus.on(event, callback)
    if not listeners[event] then
        listeners[event] = {}
    end
    table.insert(listeners[event], callback)
end

function EventBus.off(event, callback)
    if not listeners[event] then return end
    for i = #listeners[event], 1, -1 do
        if listeners[event][i] == callback then
            table.remove(listeners[event], i)
            break
        end
    end
end

function EventBus.emit(event, ...)
    if not listeners[event] then return end
    for _, callback in ipairs(listeners[event]) do
        callback(...)
    end
end

function EventBus.clear(event)
    if event then
        listeners[event] = nil
    else
        listeners = {}
    end
end

return EventBus
