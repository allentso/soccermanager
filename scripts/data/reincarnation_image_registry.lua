-- data/reincarnation_image_registry.lua
-- 转生球员卡牌立绘路径注册表（粉色系）

local ReincarnationImageRegistry = {}

--- matchName -> 图片资源路径 (相对 assets 根)
local _images = {
    ["Lionel Messi"] = "image/messi_reborn_card_20260614013317.png",
    ["Cristiano Ronaldo"] = "image/cronaldo_reborn_card_20260614013315.png",
}

--- 中文名 -> matchName 反查表
local _nameToMatch = {
    ["梅西"] = "Lionel Messi",
    ["莱昂内尔·梅西"] = "Lionel Messi",
    ["C罗"] = "Cristiano Ronaldo",
    ["克里斯蒂亚诺·罗纳尔多"] = "Cristiano Ronaldo",
}

--- 根据转生名单 matchName 获取卡牌立绘路径
--- @param matchName string 如 "Lionel Messi"
--- @return string|nil 图片资源路径
function ReincarnationImageRegistry.getPath(matchName)
    if not matchName then return nil end
    return _images[matchName]
end

--- 根据中文名获取卡牌立绘路径（兜底用）
--- @param name string 如 "梅西"
--- @return string|nil 图片资源路径
function ReincarnationImageRegistry.getPathByName(name)
    if not name then return nil end
    local matchName = _nameToMatch[name]
    if matchName then return _images[matchName] end
    return nil
end

return ReincarnationImageRegistry
