-- data/legend_image_registry.lua
-- 传奇球员卡牌立绘路径注册表

local LegendImageRegistry = {}

--- legend-id -> 图片资源路径 (相对 assets 根)
local _images = {
    ["legend-001"] = "image/pele_legend_card_20260607122613.png",
    ["legend-002"] = "image/maradona_legend_card_20260607122621.png",
    ["legend-003"] = "image/cruyff_legend_card_20260607122613.png",
    ["legend-004"] = "image/beckenbauer_legend_card_20260607122251.png",
    ["legend-005"] = "image/zidane_legend_card_20260607122634.png",
    ["legend-006"] = "image/ronaldo_nazario_legend_card_20260607122611.png",
    ["legend-007"] = "image/maldini_legend_card_20260607122611.png",
    ["legend-008"] = "image/ronaldinho_legend_card_20260607121820.png",
    ["legend-009"] = "image/platini_legend_card_20260607122619.png",
    ["legend-010"] = "image/vanbasten_legend_card_20260607122627.png",
    ["legend-011"] = "image/eusebio_legend_card_20260607122835.png",
    ["legend-012"] = "image/distefano_legend_card_20260607122828.png",
    ["legend-013"] = "image/matthaus_legend_card_20260607122836.png",
    ["legend-014"] = "image/baresi_legend_card_20260607122845.png",
    ["legend-015"] = "image/garrincha_legend_card_20260607122840.png",
    ["legend-016"] = "image/puskas_legend_card_20260607122846.png",
    ["legend-017"] = "image/roberto_carlos_legend_card_20260607122834.png",
    ["legend-018"] = "image/xavi_legend_card_20260607122836.png",
    ["legend-019"] = "image/iniesta_legend_card_20260607123024.png",
    ["legend-020"] = "image/henry_legend_card_20260607122840.png",
    ["legend-021"] = "image/rivaldo_legend_card_20260607123252.png",
    ["legend-022"] = "image/cafu_legend_card_20260607123258.png",
    ["legend-023"] = "image/buffon_legend_card_20260607122305.png",
    ["legend-024"] = "image/yashin_legend_card_20260607123251.png",
    ["legend-025"] = "image/neeskens_legend_card_20260607123245.png",
    ["legend-026"] = "image/zanetti_legend_card_20260607123254.png",
    ["legend-027"] = "image/pirlo_legend_card_20260607123300.png",
    ["legend-028"] = "image/seedorf_legend_card_20260607123440.png",
    ["legend-029"] = "image/bergkamp_legend_card_20260607123301.png",
    ["legend-030"] = "image/baggio_legend_card_20260607123248.png",
    ["legend-031"] = "image/romario_legend_card_20260607123647.png",
    ["legend-032"] = "image/gullit_legend_card_20260607123654.png",
    ["legend-033"] = "image/laudrup_legend_card_20260607123651.png",
    ["legend-034"] = "image/figo_legend_card_20260607123650.png",
    ["legend-035"] = "image/cantona_legend_card_20260607123651.png",
    ["legend-036"] = "image/scholes_legend_card_20260607123642.png",
    ["legend-037"] = "image/gerrard_legend_card_20260607123643.png",
    ["legend-038"] = "image/lampard_legend_card_20260607123656.png",
    ["legend-039"] = "image/nedved_legend_card_20260607123700.png",
    ["legend-040"] = "image/drogba_legend_card_20260607123643.png",
    ["legend-041"] = "image/etoo_legend_card_20260607123918.png",
    ["legend-042"] = "image/shevchenko_legend_card_20260607123911.png",
    ["legend-043"] = "image/cannavaro_legend_card_20260607123901.png",
    ["legend-044"] = "image/moore_legend_card_20260607123905.png",
    ["legend-045"] = "image/charlton_legend_card_20260607123917.png",
    ["legend-046"] = "image/best_legend_card_20260607123902.png",
    ["legend-047"] = "image/kaka_legend_card_20260607123921.png",
    ["legend-048"] = "image/raul_legend_card_20260607123913.png",
    ["legend-049"] = "image/riquelme_legend_card_20260607123929.png",
    ["legend-050"] = "image/stoichkov_legend_card_20260607123910.png",
}

--- 中文名 -> legend-id 反查表
local _nameToId = {
    ["贝利"] = "legend-001",
    ["马拉多纳"] = "legend-002",
    ["克鲁伊夫"] = "legend-003",
    ["贝肯鲍尔"] = "legend-004",
    ["齐达内"] = "legend-005",
    ["罗纳尔多"] = "legend-006",
    ["马尔蒂尼"] = "legend-007",
    ["罗纳尔迪尼奥"] = "legend-008",
    ["普拉蒂尼"] = "legend-009",
    ["范巴斯滕"] = "legend-010",
    ["尤西比奥"] = "legend-011",
    ["迪斯蒂法诺"] = "legend-012",
    ["马特乌斯"] = "legend-013",
    ["巴雷西"] = "legend-014",
    ["加林查"] = "legend-015",
    ["普斯卡什"] = "legend-016",
    ["罗伯托·卡洛斯"] = "legend-017",
    ["哈维"] = "legend-018",
    ["伊涅斯塔"] = "legend-019",
    ["亨利"] = "legend-020",
    ["里瓦尔多"] = "legend-021",
    ["卡福"] = "legend-022",
    ["布冯"] = "legend-023",
    ["雅辛"] = "legend-024",
    ["内斯肯斯"] = "legend-025",
    ["萨内蒂"] = "legend-026",
    ["皮尔洛"] = "legend-027",
    ["西多夫"] = "legend-028",
    ["博格坎普"] = "legend-029",
    ["巴乔"] = "legend-030",
    ["罗马里奥"] = "legend-031",
    ["古利特"] = "legend-032",
    ["劳德鲁普"] = "legend-033",
    ["菲戈"] = "legend-034",
    ["坎通纳"] = "legend-035",
    ["斯科尔斯"] = "legend-036",
    ["杰拉德"] = "legend-037",
    ["兰帕德"] = "legend-038",
    ["内德维德"] = "legend-039",
    ["德罗巴"] = "legend-040",
    ["埃托奥"] = "legend-041",
    ["舍甫琴科"] = "legend-042",
    ["卡纳瓦罗"] = "legend-043",
    ["博比·摩尔"] = "legend-044",
    ["博比·查尔顿"] = "legend-045",
    ["乔治·贝斯特"] = "legend-046",
    ["卡卡"] = "legend-047",
    ["劳尔"] = "legend-048",
    ["里克尔梅"] = "legend-049",
    ["斯托伊奇科夫"] = "legend-050",
}

--- 根据传奇球员 ID 获取卡牌立绘路径
--- @param legendId string 如 "legend-001"
--- @return string|nil 图片资源路径
function LegendImageRegistry.getPath(legendId)
    if not legendId then return nil end
    return _images[legendId]
end

--- 根据中文名获取卡牌立绘路径（兜底用）
--- @param name string 如 "菲戈"
--- @return string|nil 图片资源路径
function LegendImageRegistry.getPathByName(name)
    if not name then return nil end
    local id = _nameToId[name]
    if id then return _images[id] end
    return nil
end

return LegendImageRegistry
