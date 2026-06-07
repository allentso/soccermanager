-- systems/youth_manager.lua
-- 青训系统：青年球员刷新、签入、提拔至一线队

local Constants = require("scripts/app/constants")
local Player = require("scripts/domain/player")
local StaffManager = require("scripts/systems/staff_manager")
local MessageManager = require("scripts/systems/message_manager")
local EventBus = require("scripts/app/event_bus")
local PotentialSystem = require("scripts/systems/potential_system")

local YouthManager = {}

------------------------------------------------------
-- 常量
------------------------------------------------------
local YOUTH_REFRESH_INTERVAL = 3   -- 每3个月刷新一批（processMonthly每月调用一次）
local YOUTH_POOL_SIZE = 10         -- 每次刷新10名候选
local MAX_YOUTH_SQUAD = 15         -- 最多15名青训球员
local INITIAL_YOUTH_COUNT = 10     -- 每队初始青训人数
local YOUTH_MIN_AGE = 15
local YOUTH_MAX_AGE = 18
local YOUTH_WAGE = 500             -- 青训球员固定周薪

-- 按国籍分的中文名字池（全部汉化显示）
local YOUTH_NAMES_BY_NATION = {
    -- 中国球员
    CN = {
        { "李浩然" }, { "王子轩" }, { "张宇航" }, { "刘梓豪" }, { "陈俊杰" },
        { "杨天翼" }, { "赵志远" }, { "黄博文" }, { "周昊天" }, { "吴瑞祥" },
        { "徐嘉伟" }, { "孙明哲" }, { "胡晨曦" }, { "朱逸飞" }, { "高鹏程" },
        { "林思远" }, { "何泽宇" }, { "郭煜城" }, { "马星辰" }, { "罗承恩" },
        { "梁铭轩" }, { "宋睿智" }, { "郑翰林" }, { "谢文昊" }, { "韩致远" },
        { "唐鸿飞" }, { "冯修远" }, { "于凯旋" }, { "董子墨" }, { "萧晋鹏" },
    },
    -- 巴西球员（中文音译）
    BRA = {
        { "席尔瓦" }, { "桑托斯" }, { "奥利维拉" }, { "费雷拉" }, { "罗德里格斯" },
        { "阿尔梅达" }, { "纳西门托" }, { "利马" }, { "科斯塔" }, { "佩雷拉" },
        { "卡瓦略" }, { "巴博萨" }, { "里贝罗" }, { "马丁斯" }, { "苏亚雷斯" },
        { "维埃拉" }, { "弗雷塔斯" }, { "门德斯" }, { "卡多佐" }, { "贡萨尔维斯" },
    },
    -- 阿根廷球员（中文音译）
    ARG = {
        { "冈萨雷斯" }, { "罗德里格斯" }, { "费尔南德斯" }, { "洛佩斯" }, { "马丁内斯" },
        { "加西亚" }, { "罗梅罗" }, { "迪亚斯" }, { "佩雷斯" }, { "桑切斯" },
        { "阿尔瓦雷斯" }, { "阿奎罗" }, { "拉莫斯" }, { "埃切维里亚" }, { "伊瓜因" },
        { "巴内加" }, { "奥塔门迪" }, { "帕拉西奥" }, { "萨巴莱塔" }, { "马斯切拉诺" },
    },
    -- 日本球员（汉字名）
    JP = {
        { "田中翔太" }, { "佐藤悠太" }, { "铃木优斗" }, { "渡边大翔" }, { "伊藤飙太" },
        { "山本苍空" }, { "中村陆斗" }, { "小林悠真" }, { "加藤骏" }, { "吉田拓实" },
        { "山田健太" }, { "松本大地" }, { "井上晴人" }, { "木村莲" }, { "林隼人" },
        { "斉藤瑛太" }, { "清水壮太" }, { "森田翼" }, { "池田悠人" }, { "高桥拓海" },
    },
    -- 韩国球员（中文汉字）
    KR = {
        { "金民俊" }, { "李在成" }, { "朴志勋" }, { "崔英杰" }, { "郑宇成" },
        { "姜秀赫" }, { "赵俊浩" }, { "韩尚勋" }, { "尹载元" }, { "吴承民" },
        { "申东赫" }, { "权赫俊" }, { "黄仁成" }, { "孙兴浩" }, { "裴镇宇" },
        { "南泰旭" }, { "柳在石" }, { "洪正浩" }, { "文尚允" }, { "白承训" },
    },
    -- 法国球员（中文音译）
    FRA = {
        { "杜邦" }, { "莫雷尔" }, { "伯纳德" }, { "佩蒂特" }, { "罗贝尔" },
        { "理查德" }, { "杜瓦尔" }, { "勒鲁瓦" }, { "莫罗" }, { "西蒙" },
        { "洛朗" }, { "米歇尔" }, { "勒费弗尔" }, { "加西亚" }, { "达维" },
        { "布朗" }, { "马丁" }, { "蒂埃里" }, { "雷诺" }, { "弗朗索瓦" },
    },
    -- 德国球员（中文音译）
    GER = {
        { "穆勒" }, { "施密特" }, { "施奈德" }, { "菲舍尔" }, { "韦伯" },
        { "迈尔" }, { "瓦格纳" }, { "贝克尔" }, { "舒尔茨" }, { "霍夫曼" },
        { "克洛泽" }, { "赫尔曼" }, { "柯尼希" }, { "沃尔夫" }, { "哈恩" },
        { "克劳斯" }, { "弗兰克" }, { "齐默尔曼" }, { "布劳恩" }, { "哈特曼" },
    },
    -- 西班牙球员（中文音译）
    ESP = {
        { "加西亚" }, { "马丁内斯" }, { "洛佩斯" }, { "桑切斯" }, { "罗梅罗" },
        { "冈萨雷斯" }, { "费尔南德斯" }, { "佩雷斯" }, { "迪亚斯" }, { "鲁伊斯" },
        { "莫雷诺" }, { "阿隆索" }, { "希门尼斯" }, { "纳瓦罗" }, { "多明格斯" },
        { "卡斯蒂略" }, { "奥尔特加" }, { "德尔加多" }, { "拉莫斯" }, { "伊格莱西亚斯" },
    },
    -- 英格兰球员（中文音译）
    ENG = {
        { "史密斯" }, { "琼斯" }, { "威廉姆斯" }, { "布朗" }, { "泰勒" },
        { "戴维斯" }, { "威尔逊" }, { "埃文斯" }, { "托马斯" }, { "罗伯茨" },
        { "约翰逊" }, { "沃克" }, { "怀特" }, { "杰克逊" }, { "伍德" },
        { "哈里斯" }, { "马丁" }, { "克拉克" }, { "霍尔" }, { "阿伦" },
    },
    -- 荷兰球员（中文音译）
    NED = {
        { "德容" }, { "范戴克" }, { "德弗里" }, { "范德贝克" }, { "德利赫特" },
        { "斯特格" }, { "布林德" }, { "维纳尔杜姆" }, { "贝尔温" }, { "马伦" },
        { "范贝尔" }, { "克拉森" }, { "普罗梅斯" }, { "阿克" }, { "邓弗里斯" },
        { "博古伊斯" }, { "蒂尔" }, { "范安霍尔特" }, { "德佩" }, { "卢克" },
    },
    -- 葡萄牙球员（中文音译）
    POR = {
        { "席尔瓦" }, { "桑托斯" }, { "费雷拉" }, { "科斯塔" }, { "佩雷拉" },
        { "奥利维拉" }, { "罗德里格斯" }, { "马丁斯" }, { "阿尔梅达" }, { "里贝罗" },
        { "卡瓦略" }, { "贡萨尔维斯" }, { "努内斯" }, { "门德斯" }, { "维埃拉" },
        { "洛佩斯" }, { "迪亚斯" }, { "平托" }, { "索阿雷斯" }, { "特谢拉" },
    },
    -- 意大利球员（中文音译）
    ITA = {
        { "罗西" }, { "贝尔纳迪" }, { "巴雷拉" }, { "基耶萨" }, { "洛卡特利" },
        { "因西涅" }, { "维拉蒂" }, { "博努奇" }, { "斯皮纳佐拉" }, { "多纳鲁马" },
        { "佩莱格里尼" }, { "托纳利" }, { "拉斯帕多里" }, { "巴斯托尼" }, { "迪马尔科" },
        { "弗拉泰西" }, { "斯卡马卡" }, { "里奇" }, { "卡拉菲奥里" }, { "法焦利" },
    },
    -- 比利时球员（中文音译）
    BEL = {
        { "德布劳内" }, { "阿扎尔" }, { "卢卡库" }, { "库尔图瓦" }, { "蒂勒曼斯" },
        { "维通亨" }, { "卡拉斯科" }, { "奥纳纳" }, { "德凯特拉雷" }, { "多库" },
        { "奥彭达" }, { "特罗萨德" }, { "法斯" }, { "卡斯塔涅" }, { "德巴斯特" },
        { "塞尔斯" }, { "博亚塔" }, { "范阿尔肯" }, { "巴克约科" }, { "卢卡斯" },
    },
    -- 哥伦比亚球员（中文音译）
    COL = {
        { "哈梅斯" }, { "法尔考" }, { "金特罗" }, { "穆里尔" }, { "萨帕塔" },
        { "夸德拉多" }, { "迪亚斯" }, { "米纳" }, { "阿里亚斯" }, { "莫雷诺" },
        { "博尔哈" }, { "辛苏埃" }, { "乌里韦" }, { "杜兰" }, { "科尔多巴" },
        { "卡斯塔诺" }, { "马查多" }, { "门多萨" }, { "卡里略" }, { "帕拉西奥斯" },
    },
    -- 乌拉圭球员（中文音译）
    URU = {
        { "苏亚雷斯" }, { "卡瓦尼" }, { "戈丁" }, { "希门尼斯" }, { "巴尔韦德" },
        { "努涅斯" }, { "本坦库尔" }, { "韦西诺" }, { "阿劳霍" }, { "卡塞雷斯" },
        { "穆斯莱拉" }, { "托雷拉" }, { "德拉克鲁斯" }, { "佩利斯特里" }, { "奥利维拉" },
        { "罗德里格斯" }, { "马丁内斯" }, { "坎诺比奥" }, { "维尼亚" }, { "戈麦斯" },
    },
    -- 克罗地亚球员（中文音译）
    CRO = {
        { "莫德里奇" }, { "科瓦契奇" }, { "佩里西奇" }, { "布罗佐维奇" }, { "格瓦迪奥尔" },
        { "克拉马里奇" }, { "弗拉希奇" }, { "洛夫伦" }, { "维达" }, { "利瓦科维奇" },
        { "帕萨利奇" }, { "巴里希奇" }, { "尤拉诺维奇" }, { "苏契奇" }, { "马耶尔" },
        { "布迪米尔" }, { "佩特科维奇" }, { "伊瓦努舍茨" }, { "索萨" }, { "雅基奇" },
    },
    -- 塞尔维亚球员（中文音译）
    SRB = {
        { "弗拉霍维奇" }, { "约维奇" }, { "塔迪奇" }, { "米特洛维奇" }, { "科斯蒂奇" },
        { "米林科维奇" }, { "帕夫洛维奇" }, { "古德利" }, { "日夫科维奇" }, { "拉多尼奇" },
        { "卢基奇" }, { "萨马尔季奇" }, { "姆拉德诺维奇" }, { "拉佐维奇" }, { "伊利奇" },
        { "约基奇" }, { "马克西莫维奇" }, { "加契诺维奇" }, { "拉伊科维奇" }, { "格鲁伊奇" },
    },
    -- 墨西哥球员（中文音译）
    MEX = {
        { "洛萨诺" }, { "希门尼斯" }, { "奥乔亚" }, { "阿尔瓦雷斯" }, { "瓜尔达多" },
        { "科罗纳" }, { "埃雷拉" }, { "莫雷诺" }, { "加利亚多" }, { "马丁内斯" },
        { "安图纳" }, { "罗莫" }, { "桑切斯" }, { "阿里亚加" }, { "奎尼奥内斯" },
        { "拉莫斯" }, { "洛佩斯" }, { "弗洛雷斯" }, { "皮涅达" }, { "巴斯克斯" },
    },
    -- 尼日利亚球员（中文音译）
    NGA = {
        { "奥西门" }, { "恩迪迪" }, { "伊沃比" }, { "穆萨" }, { "伊海纳乔" },
        { "奥纳纳" }, { "阿德耶米" }, { "巴西" }, { "奥乔查" }, { "努瓦卡利" },
        { "查克维泽" }, { "恩多卡" }, { "奥帕布尼米" }, { "阿约" }, { "奥科" },
        { "埃泽" }, { "伊布拉希姆" }, { "阿迪穆拉" }, { "穆罕默德" }, { "乌玛尔" },
    },
}

-- 国籍池：按真实足球人才输出分配（共50条目）
-- 南美：巴西18% 阿根廷10% 哥伦比亚4% 乌拉圭4% = 36%
-- 欧洲：法国10% 英格兰8% 西班牙8% 德国8% 意大利6% 葡萄牙4% 荷兰4% 比利时4% 克罗地亚2% 塞尔维亚2% = 56%
-- 其他：墨西哥2% 尼日利亚2% 日本2% = 6%
-- 中国 2% (本土)
local YOUTH_NATIONALITIES = {
    "BRA", "BRA", "BRA", "BRA", "BRA", "BRA", "BRA", "BRA", "BRA", -- 巴西 9/50 = 18%
    "ARG", "ARG", "ARG", "ARG", "ARG",                              -- 阿根廷 5/50 = 10%
    "FRA", "FRA", "FRA", "FRA", "FRA",                              -- 法国 5/50 = 10%
    "ENG", "ENG", "ENG", "ENG",                                     -- 英格兰 4/50 = 8%
    "ESP", "ESP", "ESP", "ESP",                                     -- 西班牙 4/50 = 8%
    "GER", "GER", "GER", "GER",                                     -- 德国 4/50 = 8%
    "ITA", "ITA", "ITA",                                            -- 意大利 3/50 = 6%
    "POR", "POR",                                                   -- 葡萄牙 2/50 = 4%
    "NED", "NED",                                                   -- 荷兰 2/50 = 4%
    "BEL", "BEL",                                                   -- 比利时 2/50 = 4%
    "COL", "COL",                                                   -- 哥伦比亚 2/50 = 4%
    "URU", "URU",                                                   -- 乌拉圭 2/50 = 4%
    "CRO",                                                          -- 克罗地亚 1/50 = 2%
    "SRB",                                                          -- 塞尔维亚 1/50 = 2%
    "MEX",                                                          -- 墨西哥 1/50 = 2%
    "NGA",                                                          -- 尼日利亚 1/50 = 2%
    "JP",                                                           -- 日本 1/50 = 2%
    "CN",                                                           -- 中国 1/50 = 2%
}

-- 导出常量供 UI 使用
YouthManager.MAX_YOUTH_SQUAD = MAX_YOUTH_SQUAD
YouthManager.YOUTH_POOL_SIZE = YOUTH_POOL_SIZE
YouthManager.INITIAL_YOUTH_COUNT = INITIAL_YOUTH_COUNT

------------------------------------------------------
-- 传奇球星池抽卡配置
------------------------------------------------------
local LEGEND_UNLOCK_ADS = 10        -- 看10次广告解锁传奇池
local LEGEND_PULL_PER_AD = 2        -- 解锁后每次广告获得2次抽取
local LEGEND_TEN_PULL_ADS = 3       -- 3次广告 = 一次十连抽
local LEGEND_BASE_RATE = 0.05       -- 单抽传奇基础概率 5%
local LEGEND_RATE_INCREMENT = 0.005 -- 每次未出传奇十连 +0.5%
local LEGEND_RATE_CAP = 0.10        -- 概率上限10%
local LEGEND_PITY_COUNT = 10        -- 10次十连保底出传奇
local LEGEND_FIRST_GUARANTEED = true -- 首次十连保底一个传奇
local LEGEND_MAX_PER_PULL = 1       -- 每次十连最多出1个传奇

-- 英文完整位置名 → 游戏简写位置映射（wonderkids JSON 使用完整英文）
local POSITION_MAP = {
    Goalkeeper = "GK",
    CentreBack = "CB",
    LeftBack = "LB",
    RightBack = "RB",
    DefensiveMidfielder = "CDM",
    CentralMidfielder = "CM",
    AttackingMidfielder = "CAM",
    LeftWing = "LW",
    RightWing = "RW",
    Striker = "ST",
}

--- 将传奇数据中的英文位置转换为游戏简写
local function mapPosition(pos)
    if not pos then return "ST" end
    return POSITION_MAP[pos] or pos
end

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 每月处理：刷新青训候选池
---@param gameState table
function YouthManager.processMonthly(gameState)
    gameState._youthCandidates = gameState._youthCandidates or {}
    gameState._youthRefreshCounter = (gameState._youthRefreshCounter or 0) + 1

    if gameState._youthRefreshCounter >= YOUTH_REFRESH_INTERVAL then
        gameState._youthRefreshCounter = 0
        YouthManager._refreshCandidates(gameState)
    end
end

--- 获取当前青训候选球员列表
---@param gameState table
---@return table[]
function YouthManager.getCandidates(gameState)
    return gameState._youthCandidates or {}
end

--- 签入候选青训球员
---@param gameState table
---@param candidateIndex number 候选列表中的索引
---@return boolean success, string? error
function YouthManager.signCandidate(gameState, candidateIndex)
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    gameState._youthCandidates = gameState._youthCandidates or {}
    local candidate = gameState._youthCandidates[candidateIndex]
    if not candidate then return false, "候选球员不存在" end

    -- 青训名额检查
    team._youthPlayerIds = team._youthPlayerIds or {}
    if #team._youthPlayerIds >= MAX_YOUTH_SQUAD then
        return false, string.format("青训名额已满(%d人)", MAX_YOUTH_SQUAD)
    end

    -- 创建球员实体
    local playerData = {
        firstName = candidate.firstName,
        lastName = candidate.lastName,
        displayName = candidate.displayName,
        nationality = candidate.nationality,
        birthYear = candidate.birthYear,
        position = candidate.position,
        attributes = candidate.attributes,
        potential = candidate.potential,
        overall = candidate.overall,
        wage = YOUTH_WAGE,
        isYouth = true,
        contractEnd = {year = gameState.date.year + 3, month = 6, day = 30},
        -- 传奇球员额外字段
        isLegend = candidate.isLegend or false,
        legendName = candidate.legendName,
        legendData = candidate.legendData,
    }
    local player = gameState:addPlayer(playerData)

    -- 设置球队归属
    player.teamId = team.id

    -- 初始化潜力评级
    player.paRating = PotentialSystem.rawToRating(player.potential)
    player.actualPotential = PotentialSystem.generateActualPotential(player.paRating, (gameState.potentialSeed or 0) + player.id * 7919)

    -- 加入青训队
    table.insert(team._youthPlayerIds, player.id)

    -- 从候选池移除
    table.remove(gameState._youthCandidates, candidateIndex)

    MessageManager.send(gameState, "youth_signed", {player.displayName, player.position})

    EventBus.emit("youth_signed", {teamId = team.id, playerId = player.id})
    return true
end

--- 提拔青训球员到一线队
---@param gameState table
---@param playerId number
---@return boolean success, string? error
function YouthManager.promote(gameState, playerId)
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    -- 检查是否在青训队
    team._youthPlayerIds = team._youthPlayerIds or {}
    local found = false
    for i, yid in ipairs(team._youthPlayerIds) do
        if yid == playerId then
            table.remove(team._youthPlayerIds, i)
            found = true
            break
        end
    end
    if not found then return false, "该球员不在青训队中" end

    -- 加入一线队
    table.insert(team.playerIds, playerId)

    local player = gameState.players[playerId]
    if player then
        player.isYouth = false
        player.teamId = team.id
        -- 提拔后给予正式合同
        player.contractEnd = {year = gameState.date.year + 3, month = 6, day = 30}
        player.wage = math.max(YOUTH_WAGE * 2, math.floor(player.overall * 80))

        MessageManager.send(gameState, "youth_promoted", {player.displayName})
        EventBus.emit("youth_promoted", {teamId = team.id, playerId = playerId})
    end

    return true
end

--- 释放青训球员
---@param gameState table
---@param playerId number
---@return boolean success, string? error
function YouthManager.release(gameState, playerId)
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    team._youthPlayerIds = team._youthPlayerIds or {}
    local found = false
    for i, yid in ipairs(team._youthPlayerIds) do
        if yid == playerId then
            table.remove(team._youthPlayerIds, i)
            found = true
            break
        end
    end
    if not found then return false, "该球员不在青训队中" end

    -- 标记为已释放（不从 players 表删除，保留历史）
    local player = gameState.players[playerId]
    if player then
        player.retired = true
        player.isYouth = false
    end

    return true
end

--- 获取球队青训球员列表
---@param gameState table
---@return table[]
function YouthManager.getYouthSquad(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return {} end

    team._youthPlayerIds = team._youthPlayerIds or {}
    local result = {}
    for _, pid in ipairs(team._youthPlayerIds) do
        local p = gameState.players[pid]
        if p then
            table.insert(result, p)
        end
    end
    return result
end

--- 每日训练：青训球员成长（受青训加成影响）
---@param gameState table
function YouthManager.processDailyTraining(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    team._youthPlayerIds = team._youthPlayerIds or {}
    local youthBonus = StaffManager.getYouthDevBonus(gameState, team.id)

    for _, pid in ipairs(team._youthPlayerIds) do
        local player = gameState.players[pid]
        if player and player.attributes then
            -- 每天有小概率提升某项属性
            local growthChance = 0.03 + youthBonus  -- 3% + 加成（最高 ~18%）
            if Random() < growthChance then
                -- 随机选一项属性
                local attrKeys = {}
                for k, _ in pairs(player.attributes) do
                    table.insert(attrKeys, k)
                end
                if #attrKeys > 0 then
                    local key = attrKeys[RandomInt(1, #attrKeys)]
                    local maxVal = math.min(20, math.floor((player.actualPotential or player.potential or 60) / 5))
                    if player.attributes[key] < maxVal then
                        player.attributes[key] = player.attributes[key] + 1
                        player:calculateOverall()
                    end
                end
            end
        end
    end
end

------------------------------------------------------
-- 内部函数
------------------------------------------------------

function YouthManager._refreshCandidates(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    local youthDevBonus = StaffManager.getYouthDevBonus(gameState, team.id)

    -- 青训设施加成：提升潜力和质量
    local FinanceManager = require("scripts/systems/finance_manager")
    local facilityBonuses = FinanceManager.getFacilityBonuses(team)
    local facilityYouthBonus = facilityBonuses.youthQuality or 1.0

    local candidates = {}

    for _ = 1, YOUTH_POOL_SIZE do
        local candidate = YouthManager._generateYouthPlayer(gameState, youthDevBonus, facilityYouthBonus)
        table.insert(candidates, candidate)
    end

    gameState._youthCandidates = candidates

    -- 通知
    gameState:sendMessage({
        category = "youth",
        title = "青训报告",
        body = string.format("球探发现了 %d 名有潜力的青年球员，请前往青训页面查看。", #candidates),
        priority = "normal",
    })
end

function YouthManager._generateYouthPlayer(gameState, youthDevBonus, facilityYouthBonus)
    facilityYouthBonus = facilityYouthBonus or 1.0
    local positions = {"GK", "CB", "LB", "RB", "CM", "CDM", "CAM", "LW", "RW", "ST"}
    local position = positions[RandomInt(1, #positions)]

    local age = RandomInt(YOUTH_MIN_AGE, YOUTH_MAX_AGE)
    local birthYear = gameState.date.year - age

    -- 潜力受青训教练加成 + 青训设施加成影响
    -- 设施加成：提高潜力下限（Lv5 时下限从45提升到 ~57）
    local potentialFloor = math.floor(45 * facilityYouthBonus)
    local basePotential = RandomInt(potentialFloor, 85)
    local potential = math.min(99, basePotential + math.floor(youthDevBonus * 30))

    -- 当前能力（设施加成提升起始能力）
    local overallCap = math.max(25, math.floor(potential * 0.5))
    local overallFloor = math.floor(25 * facilityYouthBonus)
    local overall = RandomInt(overallFloor, overallCap)

    -- 生成属性（基于 overall 和位置）
    local attributes = YouthManager._generateAttributes(position, overall)

    -- 先随机国籍，再从对应国籍名字池中取名
    local nationality = YOUTH_NATIONALITIES[RandomInt(1, #YOUTH_NATIONALITIES)]
    local namePool = YOUTH_NAMES_BY_NATION[nationality] or YOUTH_NAMES_BY_NATION["CN"]
    local nameEntry = namePool[RandomInt(1, #namePool)]
    local fullName = nameEntry[1]

    return {
        firstName = fullName,
        lastName = fullName,
        displayName = fullName,
        nationality = nationality,
        birthYear = birthYear,
        position = position,
        potential = potential,
        overall = overall,
        attributes = attributes,
        age = age,
    }
end

function YouthManager._generateAttributes(position, overall)
    local baseVal = math.max(1, math.floor(overall / 7))

    -- 使用与 Player 模型一致的属性键名
    local attrs = {
        speed = baseVal + RandomInt(-2, 3),
        stamina = baseVal + RandomInt(-2, 3),
        strength = baseVal + RandomInt(-2, 3),
        agility = baseVal + RandomInt(-2, 3),
        passing = baseVal + RandomInt(-2, 3),
        shooting = baseVal + RandomInt(-2, 3),
        tackling = baseVal + RandomInt(-2, 3),
        dribbling = baseVal + RandomInt(-2, 3),
        defending = baseVal + RandomInt(-2, 3),
        positioning = baseVal + RandomInt(-2, 3),
        vision = baseVal + RandomInt(-2, 3),
        decisions = baseVal + RandomInt(-2, 3),
        composure = baseVal + RandomInt(-2, 3),
        aggression = baseVal + RandomInt(-2, 3),
        teamwork = baseVal + RandomInt(-2, 3),
        leadership = baseVal + RandomInt(-2, 3),
        aerial = baseVal + RandomInt(-2, 3),
        handling = 1,
        reflexes = 1,
    }

    -- 位置专精
    if position == "GK" then
        attrs.handling = baseVal + RandomInt(2, 5)
        attrs.reflexes = baseVal + RandomInt(2, 5)
        attrs.positioning = attrs.positioning + RandomInt(1, 3)
        attrs.composure = attrs.composure + RandomInt(1, 2)
    elseif position == "CB" then
        attrs.defending = attrs.defending + RandomInt(2, 4)
        attrs.tackling = attrs.tackling + RandomInt(2, 4)
        attrs.strength = attrs.strength + RandomInt(1, 3)
        attrs.aerial = attrs.aerial + RandomInt(1, 3)
    elseif position == "LB" or position == "RB" then
        attrs.defending = attrs.defending + RandomInt(1, 3)
        attrs.speed = attrs.speed + RandomInt(2, 4)
        attrs.stamina = attrs.stamina + RandomInt(1, 3)
    elseif position == "CDM" then
        attrs.tackling = attrs.tackling + RandomInt(2, 4)
        attrs.defending = attrs.defending + RandomInt(1, 3)
        attrs.passing = attrs.passing + RandomInt(1, 3)
    elseif position == "CM" or position == "CAM" then
        attrs.passing = attrs.passing + RandomInt(2, 4)
        attrs.vision = attrs.vision + RandomInt(1, 3)
        attrs.dribbling = attrs.dribbling + RandomInt(1, 3)
    elseif position == "LW" or position == "RW" then
        attrs.speed = attrs.speed + RandomInt(2, 4)
        attrs.dribbling = attrs.dribbling + RandomInt(2, 3)
        attrs.agility = attrs.agility + RandomInt(1, 3)
    elseif position == "ST" or position == "CF" then
        attrs.shooting = attrs.shooting + RandomInt(2, 4)
        attrs.composure = attrs.composure + RandomInt(1, 3)
        attrs.speed = attrs.speed + RandomInt(1, 3)
    end

    -- 限制范围
    for k, v in pairs(attrs) do
        attrs[k] = math.max(1, math.min(20, v))
    end
    return attrs
end

------------------------------------------------------
-- 初始化：为所有球队填充青训到 INITIAL_YOUTH_COUNT 人
------------------------------------------------------

--- 为所有球队填充青训球员至初始人数
--- 已有的 wonderkids 不会被覆盖，只补齐差额
---@param gameState table
function YouthManager.fillAllTeamsYouth(gameState)
    local totalGenerated = 0

    for teamId, team in pairs(gameState.teams) do
        team._youthPlayerIds = team._youthPlayerIds or {}
        local currentCount = #team._youthPlayerIds
        local needed = INITIAL_YOUTH_COUNT - currentCount

        if needed > 0 then
            -- 获取球队相关加成（AI球队使用默认值）
            local youthDevBonus = 0.05
            local facilityYouthBonus = 1.0

            -- 尝试获取实际加成（玩家球队有职员系统）
            local ok, bonus = pcall(StaffManager.getYouthDevBonus, gameState, teamId)
            if ok and bonus then youthDevBonus = bonus end

            for _ = 1, needed do
                local candidate = YouthManager._generateYouthPlayer(gameState, youthDevBonus, facilityYouthBonus)

                -- 转换为正式青训球员
                local playerData = {
                    firstName = candidate.firstName,
                    lastName = candidate.lastName,
                    displayName = candidate.displayName,
                    nationality = candidate.nationality,
                    birthYear = candidate.birthYear,
                    position = candidate.position,
                    attributes = candidate.attributes,
                    potential = candidate.potential,
                    overall = candidate.overall,
                    wage = YOUTH_WAGE,
                    isYouth = true,
                    teamId = teamId,
                    squadRole = "youth",
                    contractEnd = {year = gameState.date.year + 3, month = 6, day = 30},
                }
                local player = gameState:addPlayer(playerData)
                player.teamId = teamId

                -- 初始化潜力评级
                player.paRating = PotentialSystem.rawToRating(player.potential)
                player.actualPotential = PotentialSystem.generateActualPotential(
                    player.paRating, (gameState.potentialSeed or 0) + player.id * 7919)

                table.insert(team._youthPlayerIds, player.id)
                totalGenerated = totalGenerated + 1
            end
        end
    end

    log:Write(LOG_INFO, "YouthManager: 为所有球队填充青训完毕，生成 " .. totalGenerated .. " 名球员")
end

------------------------------------------------------
-- 传奇球星池抽卡系统
------------------------------------------------------

--- 获取抽卡状态
---@param gameState table
---@return table state
function YouthManager.getLegendGachaState(gameState)
    gameState._legendGacha = gameState._legendGacha or {
        adsWatched = 0,          -- 累计观看广告次数（解锁前）
        unlocked = false,        -- 是否已解锁传奇池
        pulls = 0,              -- 当前可用抽取次数
        tenPullCount = 0,       -- 已进行的十连次数
        pityCounter = 0,        -- 距上次出传奇的十连次数（保底计数）
        firstTenPull = true,    -- 是否为首次十连（保底）
    }
    return gameState._legendGacha
end

--- 观看广告（解锁阶段）
---@param gameState table
---@return boolean unlocked 是否刚刚解锁
---@return number progress 当前进度
function YouthManager.watchAdForUnlock(gameState)
    local state = YouthManager.getLegendGachaState(gameState)
    if state.unlocked then return false, LEGEND_UNLOCK_ADS end

    state.adsWatched = state.adsWatched + 1
    if state.adsWatched >= LEGEND_UNLOCK_ADS then
        state.unlocked = true
        -- 解锁赠送一次十连抽
        state.pulls = state.pulls + 10
        log:Write(LOG_INFO, "YouthManager: 传奇池已解锁，赠送10次抽取")
        return true, state.adsWatched
    end
    return false, state.adsWatched
end

--- 观看广告获得抽取次数（解锁后）
---@param gameState table
---@return number newPulls 新增次数
function YouthManager.watchAdForPulls(gameState)
    local state = YouthManager.getLegendGachaState(gameState)
    if not state.unlocked then return 0 end

    state.pulls = state.pulls + LEGEND_PULL_PER_AD
    return LEGEND_PULL_PER_AD
end

--- 是否可以进行十连抽
---@param gameState table
---@return boolean
function YouthManager.canTenPull(gameState)
    local state = YouthManager.getLegendGachaState(gameState)
    return state.unlocked and state.pulls >= 10
end

--- 获取解锁所需广告次数
function YouthManager.getUnlockAdsRequired()
    return LEGEND_UNLOCK_ADS
end

--- 获取十连抽所需广告次数
function YouthManager.getTenPullAdsRequired()
    return LEGEND_TEN_PULL_ADS
end

--- 执行十连抽：刷新候选池为10名球员，按概率出传奇
---@param gameState table
---@return table|nil results {candidates=候选列表, legendCount=出传奇数, isFirstTenPull=bool}
function YouthManager.doTenPull(gameState)
    local state = YouthManager.getLegendGachaState(gameState)
    if not state.unlocked or state.pulls < 10 then
        return nil
    end

    state.pulls = state.pulls - 10
    state.tenPullCount = state.tenPullCount + 1
    state.pityCounter = state.pityCounter + 1

    local isFirst = state.firstTenPull
    local isPity = (state.pityCounter >= LEGEND_PITY_COUNT)

    -- 加载传奇球员池（排除已抽到的传奇）
    local JsonLoader = require("scripts/data/json_loader")
    local legendData = JsonLoader.loadFromResource("Data/legends_alltime_top50.json")
    local allLegends = (legendData and legendData.players) or {}

    -- 已抽到的传奇列表（持久化去重）
    state.pulledLegends = state.pulledLegends or {}
    local pulledSet = {}
    for _, name in ipairs(state.pulledLegends) do
        pulledSet[name] = true
    end

    -- 过滤已抽到的传奇
    local legendPool = {}
    for _, p in ipairs(allLegends) do
        local key = p.full_name_cn or p.match_name or ""
        if not pulledSet[key] then
            table.insert(legendPool, p)
        end
    end

    local team = gameState:getPlayerTeam()
    local youthDevBonus = 0.05
    local facilityYouthBonus = 1.0
    if team then
        local ok, bonus = pcall(StaffManager.getYouthDevBonus, gameState, team.id)
        if ok and bonus then youthDevBonus = bonus end
    end

    local candidates = {}
    local legendCount = 0
    local guaranteedSlot = 0  -- 保底传奇放在第几个位置

    -- 判断是否触发保底（前提：池中还有传奇可抽）
    if #legendPool > 0 then
        if isFirst and LEGEND_FIRST_GUARANTEED then
            guaranteedSlot = RandomInt(1, 10)
        elseif isPity then
            guaranteedSlot = RandomInt(1, 10)
        end
    end

    for i = 1, YOUTH_POOL_SIZE do
        local isLegend = false

        if i == guaranteedSlot then
            -- 保底位置必出传奇
            isLegend = true
        elseif legendCount < LEGEND_MAX_PER_PULL then
            -- 尚未出传奇时才按概率判定（每次十连最多1个传奇）
            local rate = LEGEND_BASE_RATE + (state.pityCounter - 1) * LEGEND_RATE_INCREMENT
            rate = math.min(rate, LEGEND_RATE_CAP)
            if Random() < rate then
                isLegend = true
            end
        end

        if isLegend and #legendPool > 0 and legendCount < LEGEND_MAX_PER_PULL then
            -- 从传奇池随机选一个并移除
            local idx = RandomInt(1, #legendPool)
            local lData = legendPool[idx]
            table.remove(legendPool, idx)  -- 本次十连内不重复

            -- 持久化记录已抽传奇
            local legendKey = lData.full_name_cn or lData.match_name or "传奇"
            table.insert(state.pulledLegends, legendKey)

            local mappedPos = mapPosition(lData.position)
            local candidate = {
                firstName = lData.full_name_cn or lData.match_name or "传奇",
                lastName = lData.full_name_cn or lData.match_name or "球星",
                displayName = lData.full_name_cn or lData.match_name or "传奇球星",
                nationality = lData.football_nation or lData.nationality or "BRA",
                birthYear = gameState.date.year - RandomInt(17, 19),  -- 传奇以年轻体呈现
                position = mappedPos,
                potential = lData.potential or 95,
                overall = RandomInt(55, 70),  -- 年轻体初始能力中等偏上
                attributes = YouthManager._generateAttributes(mappedPos, RandomInt(55, 70)),
                age = RandomInt(17, 19),
                isLegend = true,
                legendName = lData.full_name_cn or lData.match_name,
                legendData = lData,  -- 保留原始数据供弹窗使用
            }
            table.insert(candidates, candidate)
            legendCount = legendCount + 1
        else
            -- 普通青训球员
            local candidate = YouthManager._generateYouthPlayer(gameState, youthDevBonus, facilityYouthBonus)
            table.insert(candidates, candidate)
        end
    end

    -- 更新保底计数
    if legendCount > 0 then
        state.pityCounter = 0  -- 出了传奇，重置保底
    end
    if isFirst then
        state.firstTenPull = false
    end

    -- 设置为当前候选池
    gameState._youthCandidates = candidates

    log:Write(LOG_INFO, string.format(
        "YouthManager: 十连抽完成，出传奇%d名，累计十连%d次，保底计数%d",
        legendCount, state.tenPullCount, state.pityCounter))

    return {
        candidates = candidates,
        legendCount = legendCount,
        isFirstTenPull = isFirst,
        isPity = isPity,
    }
end

return YouthManager
