-- data/reincarnation_image_registry.lua
-- 转生球员卡牌立绘路径注册表（粉色系）

local ReincarnationImageRegistry = {}

--- matchName -> 图片资源路径 (相对 assets 根)
local _images = {
    -- S 级
    ["Lionel Messi"] = "image/messi_reborn_card_20260614013317.png",
    ["Cristiano Ronaldo"] = "image/cronaldo_reborn_card_20260614013315.png",
    -- A 级
    ["Neymar Jr."] = "image/neymar_reborn_card_20260615072023.png",
    ["Robert Lewandowski"] = "image/lewandowski_reborn_card_20260615065449.png",
    ["Karim Benzema"] = "image/benzema_reborn_card_20260615065639.png",
    ["Kevin De Bruyne"] = "image/debruyne_reborn_card_20260615065504.png",
    ["Luka Modrić"] = "image/modric_reborn_card_20260615065439.png",
    ["Manuel Neuer"] = "image/neuer_reborn_card_20260615065558.png",
    -- B 级
    ["Toni Kroos"] = "image/kroos_reborn_card_20260615065449.png",
    ["Luis Suárez"] = "image/suarez_reborn_card_20260615065746.png",
    ["Sergio Ramos"] = "image/ramos_reborn_card_20260615065741.png",
    ["N'Golo Kanté"] = "image/kante_reborn_card_20260615065751.png",
    ["Gareth Bale"] = "image/bale_reborn_card_20260615065750.png",
    ["Eden Hazard"] = "image/hazard_reborn_card_20260615071726.png",
    ["Paul Pogba"] = "image/pogba_reborn_card_20260615065733.png",
    ["Sergio Busquets"] = "image/busquets_reborn_card_v2_20260621071052.png",
    ["Gerard Piqué"] = "image/pique_reborn_card_v2_20260621070917.png",
    ["Zlatan Ibrahimović"] = "image/ibrahimovic_reborn_card_v2_20260621070904.png",
    ["Pepe"] = "image/pepe_reborn_card_v2_20260621070920.png",
    ["Heung-Min Son"] = "image/son_reborn_card_v3_20260621072950.png",
    ["Zheng Zhi"] = "image/zhengzhi_reborn_card_v3_20260621073137.png",
    ["Harry Kane"] = "image/kane_reborn_card_20260627104018.png",
    ["Virgil van Dijk"] = "image/van_dijk_reborn_card_20260627111410.png",
}

--- 重生球员卡牌（开局独立名单，小妖式随机入队）
local _rebirthImages = {
    ["Alexandre Pato"] = "image/pato_rebirth_card_20260627111718.png",
    ["Jack Wilshere"] = "image/wilshere_rebirth_card_20260627112230.png",
    ["Adriano Leite Ribeiro"] = "image/adriano_rebirth_card_20260627112225.png",
    ["Robinho"] = "image/robinho_rebirth_card_20260627112221.png",
    ["Mario Balotelli"] = "image/balotelli_rebirth_card_20260627112236.png",
    ["Giuseppe Rossi"] = "image/rossi_rebirth_card_20260627112224.png",
    ["Ganso"] = "image/ganso_rebirth_card_20260627112727.png",
    ["Antonio Cassano"] = "image/cassano_rebirth_card_20260627112225.png",
    ["Ricardo Quaresma"] = "image/quaresma_rebirth_card_20260627112233.png",
    ["Bojan Krkić"] = "image/bojan_rebirth_card_20260627112220.png",
}

--- 中文名 -> matchName 反查表
local _nameToMatch = {
    -- S 级
    ["梅西"] = "Lionel Messi",
    ["莱昂内尔·梅西"] = "Lionel Messi",
    ["C罗"] = "Cristiano Ronaldo",
    ["克里斯蒂亚诺·罗纳尔多"] = "Cristiano Ronaldo",
    -- A 级
    ["内马尔"] = "Neymar Jr.",
    ["内马尔·达席尔瓦"] = "Neymar Jr.",
    ["莱万多夫斯基"] = "Robert Lewandowski",
    ["莱万"] = "Robert Lewandowski",
    ["罗伯特·莱万多夫斯基"] = "Robert Lewandowski",
    ["本泽马"] = "Karim Benzema",
    ["卡里姆·本泽马"] = "Karim Benzema",
    ["德布劳内"] = "Kevin De Bruyne",
    ["凯文·德布劳内"] = "Kevin De Bruyne",
    ["莫德里奇"] = "Luka Modrić",
    ["卢卡·莫德里奇"] = "Luka Modrić",
    ["诺伊尔"] = "Manuel Neuer",
    ["曼努埃尔·诺伊尔"] = "Manuel Neuer",
    -- B 级
    ["克罗斯"] = "Toni Kroos",
    ["托尼·克罗斯"] = "Toni Kroos",
    ["苏亚雷斯"] = "Luis Suárez",
    ["路易斯·苏亚雷斯"] = "Luis Suárez",
    ["拉莫斯"] = "Sergio Ramos",
    ["塞尔吉奥·拉莫斯"] = "Sergio Ramos",
    ["坎特"] = "N'Golo Kanté",
    ["恩戈洛·坎特"] = "N'Golo Kanté",
    ["贝尔"] = "Gareth Bale",
    ["加雷斯·贝尔"] = "Gareth Bale",
    ["阿扎尔"] = "Eden Hazard",
    ["埃登·阿扎尔"] = "Eden Hazard",
    ["博格巴"] = "Paul Pogba",
    ["保罗·博格巴"] = "Paul Pogba",
    ["布斯克茨"] = "Sergio Busquets",
    ["塞尔吉奥·布斯克茨"] = "Sergio Busquets",
    ["皮克"] = "Gerard Piqué",
    ["杰拉德·皮克"] = "Gerard Piqué",
    ["伊布"] = "Zlatan Ibrahimović",
    ["兹拉坦·伊布拉希莫维奇"] = "Zlatan Ibrahimović",
    ["佩佩"] = "Pepe",
    ["孙兴慜"] = "Heung-Min Son",
    ["孙兴民"] = "Heung-Min Son",
    ["郑智"] = "Zheng Zhi",
    ["哈里·凯恩"] = "Harry Kane",
    ["凯恩"] = "Harry Kane",
    ["维吉尔·范戴克"] = "Virgil van Dijk",
    ["范戴克"] = "Virgil van Dijk",
    -- 重生
    ["帕托"] = "Alexandre Pato",
    ["亚历山大·帕托"] = "Alexandre Pato",
    ["威尔谢尔"] = "Jack Wilshere",
    ["杰克·威尔谢尔"] = "Jack Wilshere",
    ["阿德里亚诺"] = "Adriano Leite Ribeiro",
    ["罗比尼奥"] = "Robinho",
    ["博扬"] = "Bojan Krkić",
    ["博扬·克尔基奇"] = "Bojan Krkić",
    ["巴洛特利"] = "Mario Balotelli",
    ["马里奥·巴洛特利"] = "Mario Balotelli",
    ["朱塞佩·罗西"] = "Giuseppe Rossi",
    ["罗西"] = "Giuseppe Rossi",
    ["甘索"] = "Ganso",
    ["卡萨诺"] = "Antonio Cassano",
    ["安东尼奥·卡萨诺"] = "Antonio Cassano",
    ["夸雷斯马"] = "Ricardo Quaresma",
    ["里卡多·夸雷斯马"] = "Ricardo Quaresma",
}

--- 根据转生名单 matchName 获取卡牌立绘路径
--- @param matchName string 如 "Lionel Messi"
--- @return string|nil 图片资源路径
function ReincarnationImageRegistry.getPath(matchName)
    if not matchName then return nil end
    return _images[matchName] or _rebirthImages[matchName]
end

--- 是否为重生（非转生）卡面
function ReincarnationImageRegistry.isRebirthCard(matchName)
    if not matchName then return false end
    return _rebirthImages[matchName] ~= nil
end

--- 根据中文名获取卡牌立绘路径（兜底用）
--- @param name string 如 "梅西"
--- @return string|nil 图片资源路径
function ReincarnationImageRegistry.getPathByName(name)
    if not name then return nil end
    local matchName = _nameToMatch[name]
    if matchName then return _images[matchName] or _rebirthImages[matchName] end
    return nil
end

return ReincarnationImageRegistry
