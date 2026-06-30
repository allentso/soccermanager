-- app/text_util.lua
-- 文本工具：UTF-8 字符计数（# 在 Lua 中按字节计长，不适用于中文）

local TextUtil = {}

--- 统计 UTF-8 字符串的 Unicode 字符数（非字节数）
---@param str string|nil
---@return number
function TextUtil.utf8Len(str)
    if str == nil or str == "" then return 0 end
    local ok, len = pcall(function()
        local utf8 = require("utf8")
        return utf8.len(str)
    end)
    if ok and type(len) == "number" then return len end

    local count = 0
    for _ in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
    end
    return count
end

return TextUtil
