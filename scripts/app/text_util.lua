-- app/text_util.lua
-- 文本工具：UTF-8 字符计数（# 在 Lua 中按字节计长，不适用于中文）

local TextUtil = {}

local SENSITIVE_NAME_WORDS = {
    -- 冒充官方/系统身份
    "官方", "系统", "管理员", "管理員", "客服", "版主", "gm", "admin", "moderator",
    -- 辱骂、低俗、色情、暴力、毒品、赌博、欺诈
    "傻逼", "煞笔", "傻比", "sb", "草你", "操你", "妈的", "媽的", "垃圾", "废物", "廢物",
    "色情", "黄色", "黃網", "黄网", "裸聊", "卖淫", "賣淫", "嫖娼", "强奸", "強姦", "强暴", "強暴",
    "杀人", "殺人", "恐怖主义", "恐怖主義", "恐袭", "恐襲", "炸弹", "炸彈", "爆炸", "纳粹", "納粹", "希特勒", "法西斯",
    "毒品", "吸毒", "贩毒", "販毒", "冰毒", "海洛因", "大麻", "摇头丸", "搖頭丸",
    "赌博", "賭博", "博彩", "赌球", "賭球", "诈骗", "詐騙", "外挂", "外掛", "代充", "私服",
    -- 现实政治/敏感身份
    "习近平", "習近平", "毛泽东", "毛澤東", "共产党", "共產黨", "法轮功", "法輪功", "台独", "臺獨", "港独", "港獨", "藏独", "藏獨",
}

local function escapeLuaPattern(text)
    return tostring(text or ""):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

local function normalizeForModeration(text)
    text = tostring(text or ""):lower()
    -- 去掉空白/标点/控制符；数字保留，不做 0→o 等混淆映射
    text = text:gsub("[%s%p%c]", "")
    local punctuation = {"　", "·", "•", "・", "。", "，", "“", "”", "‘", "’", "、", "；", "：", "？", "！", "《", "》", "（", "）", "【", "】", "『", "』", "—", "…", "￥"}
    for _, token in ipairs(punctuation) do
        text = text:gsub(escapeLuaPattern(token), "")
    end
    return text
end

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

--- 检查玩家可见姓名是否包含敏感词。
---@param text string|nil
---@return boolean blocked
---@return string|nil matchedWord
function TextUtil.containsSensitiveNameWord(text)
    local normalized = normalizeForModeration(text)
    if normalized == "" then return false, nil end
    for _, word in ipairs(SENSITIVE_NAME_WORDS) do
        local normalizedWord = normalizeForModeration(word)
        if normalizedWord ~= "" and normalized:find(normalizedWord, 1, true) then
            return true, word
        end
    end
    return false, nil
end

return TextUtil
