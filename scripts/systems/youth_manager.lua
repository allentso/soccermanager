-- systems/youth_manager.lua
-- 青训系统：青年球员刷新、签入、提拔至一线队

local Constants = require("scripts/app/constants")
local Player = require("scripts/domain/player")
local StaffManager = require("scripts/systems/staff_manager")
local MessageManager = require("scripts/systems/message_manager")
local EventBus = require("scripts/app/event_bus")
local PotentialSystem = require("scripts/systems/potential_system")
local TrainingManager = require("scripts/systems/training_manager")
local DifficultySettings = require("scripts/systems/difficulty_settings")

local YouthManager = {}

------------------------------------------------------
-- 常量
------------------------------------------------------
local YOUTH_REFRESH_INTERVAL = 3   -- 每3个月刷新一批（processMonthly每月调用一次）
local YOUTH_POOL_SIZE = 10         -- 每次刷新10名候选
local MAX_YOUTH_SQUAD = 18         -- 最多18名青训球员
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
    -- 巴西球员（常见姓氏音译）
    BRA = {
        { "席尔瓦" }, { "桑托斯" }, { "奥利维拉" }, { "费雷拉" }, { "索萨" },
        { "阿尔梅达" }, { "纳西门托" }, { "利马" }, { "科斯塔" }, { "佩雷拉" },
        { "卡瓦略" }, { "巴博萨" }, { "里贝罗" }, { "贡卡尔维斯" }, { "阿劳若" },
        { "蒙泰罗" }, { "弗雷塔斯" }, { "阿泽维多" }, { "卡多佐" }, { "特谢拉" },
    },
    -- 阿根廷球员（常见姓氏音译）
    ARG = {
        { "冈萨雷斯" }, { "罗德里格斯" }, { "费尔南德斯" }, { "洛佩斯" }, { "马丁内斯" },
        { "加西亚" }, { "罗梅罗" }, { "迪亚斯" }, { "佩雷斯" }, { "桑切斯" },
        { "卡布雷拉" }, { "阿科斯塔" }, { "卡斯特罗" }, { "埃切维里亚" }, { "莫利纳" },
        { "布斯托斯" }, { "梅迪纳" }, { "帕拉西奥斯" }, { "索拉诺" }, { "阿吉雷" },
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
    -- 法国球员（常见姓氏音译）
    FRA = {
        { "杜邦" }, { "莫雷尔" }, { "伯纳德" }, { "佩蒂特" }, { "罗贝尔" },
        { "理查德" }, { "杜瓦尔" }, { "勒鲁瓦" }, { "莫罗" }, { "西蒙" },
        { "洛朗" }, { "米歇尔" }, { "勒费弗尔" }, { "德拉克鲁瓦" }, { "达维" },
        { "吉拉尔" }, { "马丁" }, { "布兰查德" }, { "雷诺" }, { "梅尼耶" },
    },
    -- 德国球员（常见姓氏音译）
    GER = {
        { "穆勒" }, { "施密特" }, { "施奈德" }, { "菲舍尔" }, { "韦伯" },
        { "迈尔" }, { "瓦格纳" }, { "贝克尔" }, { "舒尔茨" }, { "霍夫曼" },
        { "赫尔曼" }, { "柯尼希" }, { "沃尔夫" }, { "哈恩" }, { "里希特" },
        { "克劳斯" }, { "弗兰克" }, { "齐默尔曼" }, { "布劳恩" }, { "哈特曼" },
    },
    -- 西班牙球员（常见姓氏音译）
    ESP = {
        { "加西亚" }, { "马丁内斯" }, { "洛佩斯" }, { "桑切斯" }, { "罗梅罗" },
        { "冈萨雷斯" }, { "费尔南德斯" }, { "佩雷斯" }, { "迪亚斯" }, { "鲁伊斯" },
        { "莫雷诺" }, { "希门尼斯" }, { "纳瓦罗" }, { "多明格斯" }, { "卡斯蒂略" },
        { "奥尔特加" }, { "德尔加多" }, { "伊格莱西亚斯" }, { "帕斯夸尔" }, { "卡尔沃" },
    },
    -- 英格兰球员（常见姓氏音译）
    ENG = {
        { "史密斯" }, { "琼斯" }, { "威廉姆斯" }, { "布朗" }, { "泰勒" },
        { "戴维斯" }, { "威尔逊" }, { "埃文斯" }, { "托马斯" }, { "罗伯茨" },
        { "约翰逊" }, { "怀特" }, { "杰克逊" }, { "伍德" }, { "格林" },
        { "哈里斯" }, { "马丁" }, { "克拉克" }, { "霍尔" }, { "阿伦" },
    },
    -- 荷兰球员（常见姓氏音译）
    NED = {
        { "德扬" }, { "范登贝尔赫" }, { "德弗里斯" }, { "范德林登" }, { "巴克尔" },
        { "斯密特" }, { "扬森" }, { "彼得斯" }, { "博斯" }, { "范霍夫" },
        { "库伊佩尔" }, { "克拉森" }, { "布鲁因" }, { "维瑟" }, { "范赫尔" },
        { "穆尔德" }, { "蒂尔" }, { "范达姆" }, { "赫尔曼斯" }, { "斯洛特" },
    },
    -- 葡萄牙球员（常见姓氏音译）
    POR = {
        { "席尔瓦" }, { "桑托斯" }, { "费雷拉" }, { "科斯塔" }, { "佩雷拉" },
        { "奥利维拉" }, { "罗德里格斯" }, { "马丁斯" }, { "阿尔梅达" }, { "里贝罗" },
        { "卡瓦略" }, { "贡萨尔维斯" }, { "门德斯" }, { "维埃拉" }, { "洛佩斯" },
        { "平托" }, { "索阿雷斯" }, { "特谢拉" }, { "库尼亚" }, { "马查多" },
    },
    -- 意大利球员（常见姓氏音译）
    ITA = {
        { "罗西" }, { "鲁索" }, { "费拉罗" }, { "埃斯波西托" }, { "比安奇" },
        { "科伦坡" }, { "里奇" }, { "马里诺" }, { "格雷科" }, { "布鲁诺" },
        { "孔蒂" }, { "德卢卡" }, { "科斯塔" }, { "焦尔达诺" }, { "曼奇尼" },
        { "隆巴迪" }, { "巴尔贝里" }, { "莫雷蒂" }, { "里佐" }, { "加洛" },
    },
    -- 比利时球员（常见姓氏音译）
    BEL = {
        { "扬森斯" }, { "佩特斯" }, { "马斯" }, { "雅各布斯" }, { "威廉斯" },
        { "克莱斯" }, { "德斯梅特" }, { "亨德里克斯" }, { "范登布鲁克" }, { "沃特斯" },
        { "德沃尔夫" }, { "勒梅尔" }, { "范霍夫" }, { "迪沃斯" }, { "范达姆" },
        { "塞尔斯" }, { "博斯曼斯" }, { "范阿尔斯特" }, { "斯希珀斯" }, { "凯尔曼斯" },
    },
    -- 哥伦比亚球员（常见姓氏音译）
    COL = {
        { "洛佩斯" }, { "加西亚" }, { "马丁内斯" }, { "罗德里格斯" }, { "冈萨雷斯" },
        { "埃尔南德斯" }, { "迪亚斯" }, { "桑切斯" }, { "拉米雷斯" }, { "莫雷诺" },
        { "卡斯蒂略" }, { "奥索里奥" }, { "卡尔德隆" }, { "阿里亚斯" }, { "科尔多巴" },
        { "梅希亚" }, { "贝尔特兰" }, { "门多萨" }, { "卡里略" }, { "帕拉西奥斯" },
    },
    -- 乌拉圭球员（常见姓氏音译）
    URU = {
        { "罗德里格斯" }, { "马丁内斯" }, { "冈萨雷斯" }, { "费尔南德斯" }, { "加西亚" },
        { "洛佩斯" }, { "佩雷斯" }, { "桑切斯" }, { "拉米雷斯" }, { "迪亚斯" },
        { "阿科斯塔" }, { "席尔瓦" }, { "卡布雷拉" }, { "里韦拉" }, { "奥利维拉" },
        { "苏亚索" }, { "莫雷伊拉" }, { "阿尔瓦雷斯" }, { "维尼亚" }, { "戈麦斯" },
    },
    -- 克罗地亚球员（常见姓氏音译）
    CRO = {
        { "霍尔瓦特" }, { "科瓦切维奇" }, { "巴比奇" }, { "马里奇" }, { "诺瓦克" },
        { "尤基奇" }, { "托米奇" }, { "克拉列维奇" }, { "武科维奇" }, { "帕维奇" },
        { "马蒂奇" }, { "博希尼亚克" }, { "斯坦科维奇" }, { "佩里奇" }, { "波波维奇" },
        { "拉迪奇" }, { "佩特科维奇" }, { "伊万诺维奇" }, { "克内热维奇" }, { "米利奇" },
    },
    -- 塞尔维亚球员（常见姓氏音译）
    SRB = {
        { "约万诺维奇" }, { "佩特洛维奇" }, { "尼科利奇" }, { "米洛舍维奇" }, { "斯坦科维奇" },
        { "帕夫洛维奇" }, { "伊利奇" }, { "日夫科维奇" }, { "拉多萨夫列维奇" }, { "马尔科维奇" },
        { "卢基奇" }, { "托多罗维奇" }, { "米哈伊洛维奇" }, { "拉佐维奇" }, { "斯特凡诺维奇" },
        { "约基奇" }, { "马克西莫维奇" }, { "加契诺维奇" }, { "拉伊科维奇" }, { "格鲁伊奇" },
    },
    -- 墨西哥球员（常见姓氏音译）
    MEX = {
        { "埃尔南德斯" }, { "加西亚" }, { "马丁内斯" }, { "洛佩斯" }, { "冈萨雷斯" },
        { "罗德里格斯" }, { "佩雷斯" }, { "桑切斯" }, { "拉米雷斯" }, { "弗洛雷斯" },
        { "托雷斯" }, { "里韦拉" }, { "莫拉莱斯" }, { "克鲁斯" }, { "雷耶斯" },
        { "奥尔蒂斯" }, { "古铁雷斯" }, { "门多萨" }, { "阿吉拉尔" }, { "巴斯克斯" },
    },
    -- 尼日利亚球员（常见姓氏音译）
    NGA = {
        { "阿德巴约" }, { "奥卡福" }, { "恩旺科" }, { "伊布拉希姆" }, { "奥卢瓦" },
        { "阿金耶米" }, { "奥比纳" }, { "乌切" }, { "恩纳马迪" }, { "阿迪贡" },
        { "奥孔科" }, { "恩多卡" }, { "奥杜亚" }, { "阿约拉" }, { "奥科伊" },
        { "埃泽奎" }, { "奇迪贝雷" }, { "阿迪库" }, { "穆罕默德" }, { "乌玛尔" },
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

--- 每月处理：刷新青训候选池（玩家球队）+ AI 球队青训管理
---@param gameState table
function YouthManager.processMonthly(gameState)
    -- 玩家球队候选刷新
    gameState._youthCandidates = gameState._youthCandidates or {}
    gameState._youthRefreshCounter = (gameState._youthRefreshCounter or 0) + 1

    if gameState._youthRefreshCounter >= YOUTH_REFRESH_INTERVAL then
        gameState._youthRefreshCounter = 0
        YouthManager._refreshCandidates(gameState)
    end

    -- AI 球队青训管理（每月执行一次简化逻辑）
    YouthManager._processAITeamsMonthly(gameState)
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

    -- 创建球员实体（birthYear 必须保持为整数，不可被修改）
    -- 传奇球员自带专属特质（从 JSON 数据继承）
    local legendTraits = nil
    if candidate.isLegend and candidate.legendData and candidate.legendData.traits then
        legendTraits = candidate.legendData.traits
    end

    local playerData = {
        firstName = candidate.firstName,
        lastName = candidate.lastName,
        displayName = candidate.displayName,
        nationality = candidate.nationality,
        birthYear = math.floor(candidate.birthYear),
        position = candidate.position,
        attributes = candidate.attributes,
        potential = candidate.potential,
        overall = candidate.overall,
        wage = YOUTH_WAGE,
        isYouth = true,
        contractEnd = {year = gameState.date.year + 3, month = 6, day = 30},
        traits = legendTraits,
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
--- 潜力 raw >= 70 的球员保留为自由球员（可出现在转会市场）
--- 低潜力球员直接从数据库移除以防止数据膨胀
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

    local player = gameState.players[playerId]
    if player then
        player.isYouth = false
        player.teamId = nil

        local rawPotential = player.potential or 0
        if rawPotential >= 70 then
            -- 有潜力的球员释放为自由球员，可出现在转会市场
            -- （自由球员池由 Housekeeping.purgeExcessFreeAgents 控制上限，防止泄漏膨胀）
            player.isFreeAgent = true
            player.releasedDate = {
                year = gameState.date.year,
                month = gameState.date.month,
                day = gameState.date.day,
            }
        else
            -- 低潜力球员直接移除，避免数据库膨胀
            gameState.players[playerId] = nil
        end
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

--- 确定青训球员的训练焦点（复用 TrainingManager 优先级链）
--- 优先级：player.trainingFocus > team.trainingGroups 分组 > team.trainingFocus > "balanced"
---@param team table
---@param player table
---@return string focusKey
local function _resolveYouthFocus(team, player)
    -- 1. 个人训练焦点（UI "个人训练"页面设置）
    if player.trainingFocus and TrainingManager.FOCUS_ATTRS[player.trainingFocus] then
        return player.trainingFocus
    end
    -- 2. 分组训练焦点（UI "分组训练"页面设置）
    if team.trainingGroups then
        for _, group in pairs(team.trainingGroups) do
            if group.playerIds then
                for _, pid in ipairs(group.playerIds) do
                    if pid == player.id then
                        if group.focus and TrainingManager.FOCUS_ATTRS[group.focus] then
                            return group.focus
                        end
                    end
                end
            end
        end
    end
    -- 3. 全队训练焦点（UI "全队训练"页面设置）
    if team.trainingFocus and TrainingManager.FOCUS_ATTRS[team.trainingFocus] then
        return team.trainingFocus
    end
    -- 4. 默认平衡训练
    return "balanced"
end

--- 对单个球队执行青训球员每日训练成长
--- 对接 TrainingManager.FOCUS_ATTRS：根据训练焦点集中增长对应属性
--- v2: 加入年龄修正、潜力差修正、设施加成（与一线队训练对齐）
---@param gameState table
---@param team table
---@param youthBonus number 青训教练加成 (0~0.15)
local function _trainTeamYouth(gameState, team, youthBonus)
    team._youthPlayerIds = team._youthPlayerIds or {}

    -- 青训设施加成（提高训练效率）
    local FinanceManager = require("scripts/systems/finance_manager")
    local facilityBonus = FinanceManager.getFacilityBonuses(team).trainingGain or 1.0

    -- 预计算导师光环：收集青训队中传奇球员的位置集合
    local legendPositions = {}
    for _, pid in ipairs(team._youthPlayerIds) do
        local p = gameState.players[pid]
        if p and p.isLegend then
            legendPositions[p.position] = true
        end
    end
    -- 一线队的传奇球员也可以作为导师
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and p.isLegend then
            legendPositions[p.position] = true
        end
    end

    for _, pid in ipairs(team._youthPlayerIds) do
        local player = gameState.players[pid]
        if player and player.attributes then
            -- 基础增长概率（从难度配置获取）
            local trainingMods = DifficultySettings.getTrainingModifiers()
            local baseChance = trainingMods.baseChance

            -- 青训教练加成（乘性，0.05 → ×1.25, 0.10 → ×1.50, 0.15 → ×1.75）
            local staffMult = 1.0 + youthBonus * 5.0
            baseChance = baseChance * staffMult

            -- 设施加成
            baseChance = baseChance * facilityBonus

            -- 年龄修正（青训球员年轻，成长快）
            local age = player.birthYear and (gameState.date.year - player.birthYear) or 17
            local ageFactor = 1.0
            if age <= 16 then ageFactor = 1.5      -- 16岁及以下：高速成长
            elseif age <= 18 then ageFactor = 1.4   -- 17-18岁：快速成长
            elseif age <= 20 then ageFactor = 1.2   -- 19-20岁：正常偏快
            else ageFactor = 1.0 end
            baseChance = baseChance * ageFactor

            -- 潜力差修正（距离潜力越远成长越容易）
            local potential = player.actualPotential or player.potential or 70
            local overall = player.overall or 50
            local gapFactor = math.max(trainingMods.youthGapFloor, (potential - overall) / trainingMods.youthGapDivisor)
            baseChance = baseChance * gapFactor

            -- 传奇球员训练加速 ×1.5
            if player.isLegend then
                baseChance = baseChance * 1.5
            end

            -- 导师光环：同位置有传奇球员时，非传奇球员 +20% 训练效率
            if not player.isLegend and legendPositions[player.position] then
                baseChance = baseChance * 1.2
            end

            -- 尝试属性增长
            if Random() < baseChance then
                -- 确定训练焦点属性池（跟随一线队设置）
                local focusKey = _resolveYouthFocus(team, player)
                local focusAttrs = TrainingManager.FOCUS_ATTRS[focusKey] or TrainingManager.FOCUS_ATTRS.balanced

                -- 总评已达上限则不再增长
                local overallCap = player:getOverallCap()
                if (player.overall or 0) >= overallCap then
                    -- 到顶了，玩家需要调整策略
                else
                    local attrCap = player:getAttrCap()
                    -- 从焦点属性池中选择（带重试：若选中属性已达上限，换一个）
                    local maxAttempts = #focusAttrs
                    for _ = 1, maxAttempts do
                        local key = focusAttrs[RandomInt(1, #focusAttrs)]
                        if player.attributes[key] and player.attributes[key] < attrCap then
                            player.attributes[key] = player.attributes[key] + 1
                            player:calculateOverall()
                            break
                        end
                    end
                end
            end
        end
    end
end

--- 每日训练：所有球队青训球员成长（受青训加成影响）
---@param gameState table
function YouthManager.processDailyTraining(gameState)
    for teamId, team in pairs(gameState.teams) do
        team._youthPlayerIds = team._youthPlayerIds or {}
        if #team._youthPlayerIds > 0 then
            local youthBonus = 0.05  -- AI 球队默认加成
            local ok, bonus = pcall(StaffManager.getYouthDevBonus, gameState, teamId)
            if ok and bonus then youthBonus = bonus end
            _trainTeamYouth(gameState, team, youthBonus)
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

    -- 难度修正：青训质量影响年龄和潜力范围
    local youthMods = DifficultySettings.getYouthModifiers()
    local age = RandomInt(youthMods.minAge, youthMods.maxAge)
    local birthYear = gameState.date.year - age

    -- 潜力：使用绝对值范围，设施加成提升下限，教练加成提升总值
    local potentialFloor = math.floor(youthMods.potentialMin * facilityYouthBonus)
    potentialFloor = math.max(30, potentialFloor)
    local potentialCeil = youthMods.potentialMax
    potentialCeil = math.min(99, math.max(potentialFloor + 10, potentialCeil))
    local basePotential = RandomInt(potentialFloor, potentialCeil)
    local potential = math.min(99, basePotential + math.floor(youthDevBonus * 30))

    -- 当前能力：基于潜力线性映射到配置的 OVR 范围
    -- 高潜力球员起点更高（pot=max → OVR可达overallMax），低潜力球员起点低
    local overallFloor = youthMods.overallMin
    local overallCap = math.min(youthMods.overallMax,
        math.max(overallFloor, math.floor(potential * 0.8)))
    -- 设施加成：小幅提升下限
    overallFloor = math.floor(overallFloor * facilityYouthBonus)
    overallFloor = math.max(20, overallFloor)
    -- 确保 cap >= floor
    overallCap = math.max(overallFloor, overallCap)

    -- 生成属性并确保实际 overall 不低于下限
    local attributes, actualOverall
    local maxAttempts = 5
    for attempt = 1, maxAttempts do
        local overall = RandomInt(overallFloor, overallCap)
        -- 重试时逐步提高输入 overall，增加达标概率
        if attempt > 1 then
            overall = math.min(overallCap, overall + (attempt - 1) * 2)
        end
        attributes = YouthManager._generateAttributes(position, overall)
        actualOverall = Player.calculateOverallFromAttrs(position, attributes)
        if actualOverall >= overallFloor then
            break
        end
    end
    -- 兜底：如果多次重试仍低于下限，强制 clamp
    if actualOverall < overallFloor then
        actualOverall = overallFloor
    end

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
        overall = actualOverall,
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
                    birthYear = math.floor(candidate.birthYear),
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
--- 每次看广告+2次，看满3次后补满至10次
---@param gameState table
---@return number newPulls 本次新增次数
function YouthManager.watchAdForPulls(gameState)
    local state = YouthManager.getLegendGachaState(gameState)
    if not state.unlocked then return 0 end

    state.pullAdProgress = (state.pullAdProgress or 0) + 1
    local added = LEGEND_PULL_PER_AD
    state.pulls = state.pulls + added

    -- 看满3次，补满到10
    if state.pullAdProgress >= LEGEND_TEN_PULL_ADS then
        if state.pulls < 10 then
            added = added + (10 - state.pulls)
            state.pulls = 10
        end
        state.pullAdProgress = 0
    end
    return added
end

--- 获取当前广告进度
---@param gameState table
---@return number progress 当前进度 (0~2)
---@return number total 总需广告数 (3)
function YouthManager.getPullAdProgress(gameState)
    local state = YouthManager.getLegendGachaState(gameState)
    return state.pullAdProgress or 0, LEGEND_TEN_PULL_ADS
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

--- 执行单抽：消耗1次抽取机会，在候选池中追加1名球员（可出传奇）
---@param gameState table
---@return table|nil candidate 生成的球员，nil表示次数不足
function YouthManager.doSinglePull(gameState)
    local state = YouthManager.getLegendGachaState(gameState)
    if not state.unlocked or state.pulls < 1 then
        return nil
    end

    state.pulls = state.pulls - 1

    -- 单抽计数器（每10次单抽等效一次十连的保底进度）
    state.singlePullCounter = (state.singlePullCounter or 0) + 1
    if state.singlePullCounter >= 10 then
        state.singlePullCounter = 0
        state.pityCounter = state.pityCounter + 1
    end

    local team = gameState:getPlayerTeam()
    local youthDevBonus = 0.05
    if team then
        local ok, bonus = pcall(StaffManager.getYouthDevBonus, gameState, team.id)
        if ok and bonus then youthDevBonus = bonus end
    end

    -- 判断是否出传奇
    local isLegend = false
    local isPity = (state.pityCounter >= LEGEND_PITY_COUNT)

    -- 加载传奇池
    local JsonLoader = require("scripts/data/json_loader")
    local legendData = JsonLoader.loadFromResource("Data/legends_alltime_top50.json")
    local allLegends = (legendData and legendData.players) or {}

    state.pulledLegends = state.pulledLegends or {}
    local pulledSet = {}
    for _, name in ipairs(state.pulledLegends) do
        pulledSet[name] = true
    end

    local legendPool = {}
    for _, p in ipairs(allLegends) do
        local key = p.full_name_cn or p.match_name or ""
        if not pulledSet[key] then
            table.insert(legendPool, p)
        end
    end

    if #legendPool > 0 then
        if isPity then
            isLegend = true
        elseif state.firstTenPull and LEGEND_FIRST_GUARANTEED and state.singlePullCounter == 0 then
            -- 首次保底：第10次单抽（刚归零时）触发
            isLegend = true
        else
            local rate = LEGEND_BASE_RATE + (state.pityCounter) * LEGEND_RATE_INCREMENT
            rate = math.min(rate, LEGEND_RATE_CAP)
            if Random() < rate then
                isLegend = true
            end
        end
    end

    local candidate
    if isLegend and #legendPool > 0 then
        local idx = RandomInt(1, #legendPool)
        local lData = legendPool[idx]

        local legendKey = lData.full_name_cn or lData.match_name or "传奇"
        table.insert(state.pulledLegends, legendKey)

        local mappedPos = mapPosition(lData.position)
        local legendYouthMods = DifficultySettings.getYouthModifiers()
        local legendAge = RandomInt(legendYouthMods.legendMinAge, legendYouthMods.legendMaxAge)
        local legendOverall = RandomInt(legendYouthMods.legendOverallMin, legendYouthMods.legendOverallMax)
        local legendAttrs = YouthManager._generateAttributes(mappedPos, legendOverall)
        local preCalcOverall = Player.calculateOverallFromAttrs(mappedPos, legendAttrs)
        candidate = {
            firstName = lData.full_name_cn or lData.match_name or "传奇",
            lastName = lData.full_name_cn or lData.match_name or "球星",
            displayName = lData.full_name_cn or lData.match_name or "传奇球星",
            nationality = lData.football_nation or lData.nationality or "BRA",
            birthYear = gameState.date.year - legendAge,
            position = mappedPos,
            potential = lData.potential or 95,
            overall = preCalcOverall,
            attributes = legendAttrs,
            age = legendAge,
            isLegend = true,
            legendName = lData.full_name_cn or lData.match_name,
            legendData = lData,
        }

        -- 出传奇重置保底
        state.pityCounter = 0
        state.singlePullCounter = 0
        if state.firstTenPull then
            state.firstTenPull = false
        end
    else
        candidate = YouthManager._generateYouthPlayer(gameState, youthDevBonus, 1.0)
    end

    -- 追加到当前候选池
    gameState._youthCandidates = gameState._youthCandidates or {}
    table.insert(gameState._youthCandidates, candidate)

    log:Write(LOG_INFO, string.format(
        "YouthManager: 单抽完成(%s)，剩余%d次，保底计数%d",
        isLegend and "传奇" or "普通", state.pulls, state.pityCounter))

    return candidate
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
    -- 十连抽重置单抽计数器（十连直接推进保底，不累积零散单抽）
    state.singlePullCounter = 0

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
            -- 难度修正：传奇球星年龄和能力受青训质量影响
            local legendYouthMods = DifficultySettings.getYouthModifiers()
            local legendAge = RandomInt(legendYouthMods.legendMinAge, legendYouthMods.legendMaxAge)
            local legendOverall = RandomInt(legendYouthMods.legendOverallMin, legendYouthMods.legendOverallMax)
            local legendAttrs = YouthManager._generateAttributes(mappedPos, legendOverall)
            -- 预计算签入后的实际 overall，确保候选列表显示与签入后一致
            local preCalcOverall = Player.calculateOverallFromAttrs(mappedPos, legendAttrs)
            local candidate = {
                firstName = lData.full_name_cn or lData.match_name or "传奇",
                lastName = lData.full_name_cn or lData.match_name or "球星",
                displayName = lData.full_name_cn or lData.match_name or "传奇球星",
                nationality = lData.football_nation or lData.nationality or "BRA",
                birthYear = gameState.date.year - legendAge,  -- 传奇以年轻体呈现
                position = mappedPos,
                potential = lData.potential or 95,
                overall = preCalcOverall,  -- 预计算后的真实能力值
                attributes = legendAttrs,
                age = legendAge,
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

------------------------------------------------------
-- AI 球队青训每月管理
------------------------------------------------------

--- AI 球队简化的青训管理：自动补员、提拔、释放
---@param gameState table
function YouthManager._processAITeamsMonthly(gameState)
    local playerTeamId = gameState.playerTeamId

    for teamId, team in pairs(gameState.teams) do
        if teamId ~= playerTeamId then
            team._youthPlayerIds = team._youthPlayerIds or {}

            -- 0. 清除残留引用：球员已被删除或已转会离队（租借在外的保留）
            -- 防止提拔逻辑覆盖已转会球员的 teamId/合同（BUG-20260611-06）
            for i = #team._youthPlayerIds, 1, -1 do
                local pid = team._youthPlayerIds[i]
                local player = gameState.players[pid]
                local stillOurs = player and
                    (player.teamId == teamId or player._loanOriginTeamId == teamId)
                if not stillOurs then
                    table.remove(team._youthPlayerIds, i)
                end
            end

            -- 1. 自动提拔：年满 18 岁且 overall >= 55 的球员提拔至一线队
            -- （仅处理 teamId 归属本队的球员，租借在外的不动）
            local toPromote = {}
            for i, pid in ipairs(team._youthPlayerIds) do
                local player = gameState.players[pid]
                if player and player.teamId == teamId then
                    local age = gameState.date.year - (player.birthYear or 2000)
                    if age >= 18 and (player.overall or 0) >= 55 then
                        table.insert(toPromote, i)
                    end
                end
            end
            -- 从后向前移除避免索引错位
            for i = #toPromote, 1, -1 do
                local idx = toPromote[i]
                local pid = team._youthPlayerIds[idx]
                local player = gameState.players[pid]
                table.remove(team._youthPlayerIds, idx)
                if player then
                    player.isYouth = false
                    player.teamId = teamId
                    player.contractEnd = {year = gameState.date.year + 3, month = 6, day = 30}
                    player.wage = math.max(YOUTH_WAGE * 2, math.floor((player.overall or 50) * 80))
                    table.insert(team.playerIds, pid)
                end
            end

            -- 2. 自动释放：年满 19 岁仍在青训且 overall < 50 的球员
            -- （仅处理 teamId 归属本队的球员，租借在外的不动）
            local toRelease = {}
            for i, pid in ipairs(team._youthPlayerIds) do
                local player = gameState.players[pid]
                if player and player.teamId == teamId then
                    local age = gameState.date.year - (player.birthYear or 2000)
                    if age >= 19 and (player.overall or 0) < 50 then
                        table.insert(toRelease, i)
                    end
                end
            end
            for i = #toRelease, 1, -1 do
                local idx = toRelease[i]
                local pid = team._youthPlayerIds[idx]
                local player = gameState.players[pid]
                table.remove(team._youthPlayerIds, idx)
                if player then
                    player.isYouth = false
                    player.teamId = nil
                    local rawPotential = player.potential or 0
                    if rawPotential >= 70 then
                        player.isFreeAgent = true
                    else
                        gameState.players[pid] = nil
                    end
                end
            end

            -- 3. 自动补员：每3个月生成新球员补齐至 INITIAL_YOUTH_COUNT
            team._aiYouthRefresh = (team._aiYouthRefresh or 0) + 1
            if team._aiYouthRefresh >= YOUTH_REFRESH_INTERVAL then
                team._aiYouthRefresh = 0
                local needed = INITIAL_YOUTH_COUNT - #team._youthPlayerIds
                if needed > 0 then
                    local youthDevBonus = 0.05
                    local ok, bonus = pcall(StaffManager.getYouthDevBonus, gameState, teamId)
                    if ok and bonus then youthDevBonus = bonus end

                    for _ = 1, needed do
                        local candidate = YouthManager._generateYouthPlayer(gameState, youthDevBonus, 1.0)
                        local playerData = {
                            firstName = candidate.firstName,
                            lastName = candidate.lastName,
                            displayName = candidate.displayName,
                            nationality = candidate.nationality,
                            birthYear = math.floor(candidate.birthYear),
                            position = candidate.position,
                            attributes = candidate.attributes,
                            potential = candidate.potential,
                            overall = candidate.overall,
                            wage = YOUTH_WAGE,
                            isYouth = true,
                            teamId = teamId,
                            contractEnd = {year = gameState.date.year + 3, month = 6, day = 30},
                        }
                        local player = gameState:addPlayer(playerData)
                        player.teamId = teamId
                        player.paRating = PotentialSystem.rawToRating(player.potential)
                        player.actualPotential = PotentialSystem.generateActualPotential(
                            player.paRating, (gameState.potentialSeed or 0) + player.id * 7919)
                        table.insert(team._youthPlayerIds, player.id)
                    end
                end
            end
        end
    end
end

return YouthManager
