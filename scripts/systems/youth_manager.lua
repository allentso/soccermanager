-- systems/youth_manager.lua
-- 青训系统：青年球员刷新、签入、提拔至一线队

local Constants = require("scripts/app/constants")
local Player = require("scripts/domain/player")
local Team = require("scripts/domain/team")
local StaffManager = require("scripts/systems/staff_manager")
local MessageManager = require("scripts/systems/message_manager")
local EventBus = require("scripts/app/event_bus")
local PotentialSystem = require("scripts/systems/potential_system")
local TrainingManager = require("scripts/systems/training_manager")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local FinanceManager = require("scripts/systems/finance_manager")
local Nationality = require("scripts/domain/nationality")

local YouthManager = {}

------------------------------------------------------
-- 常量
------------------------------------------------------
local YOUTH_REFRESH_INTERVAL = 3   -- 每3个月刷新一批（processMonthly每月调用一次）
local YOUTH_POOL_SIZE = 10         -- 每次刷新10名候选
local MAX_YOUTH_SQUAD = 18         -- AI 球队青训上限
local MAX_YOUTH_SQUAD_PLAYER = 30  -- 玩家球队青训上限
local INITIAL_YOUTH_COUNT = 10     -- 每队初始青训人数
local AI_TIER2_YOUTH_COUNT = 7     -- 次级 AI 队青训目标，降低长档球员总量
local YOUTH_MIN_AGE = 15
local YOUTH_MAX_AGE = 18
local YOUTH_WAGE = 500             -- 青训球员固定周薪

-- AI 自动提拔 OVR 门槛（按球队声望）
local AI_PROMOTE_MIN_OVR_BY_REP = {
    { minRep = 900, ovr = 70 },
    { minRep = 800, ovr = 65 },
    { minRep = 700, ovr = 60 },
    { minRep = 620, ovr = 57 },
    { minRep = 0,   ovr = 55 },
}
local AI_PROMOTE_HIGH_POT_90_AGE = 20
local AI_PROMOTE_HIGH_POT_85_AGE = 19
local AI_PROMOTE_GEM_MIN_OVR = 68   -- 潜力≥90 妖人最低即战力

-- 青训设施分层生成（Lv1~5；对外仍暴露 youthQuality 乘数，内部按等级查表）
YouthManager.YOUTH_FACILITY_TIERS = {
    -- 潜力三角分布 potLo / potMode / potHi（按声望档分级）：
    --   低声望(L1) = 低均值 + 高方差（多数平庸，偶出妖人，"搏一搏"）
    --   高声望(L5) = 高均值 + 低方差（稳定产出好苗，少出废品）
    -- floorLift：当前 OVR 下限微调（高声望青训"出道即更高"）
    { potLo = 42, potMode = 54, potHi = 88, floorLift = 0 },  -- L1 社区青训点
    { potLo = 45, potMode = 60, potHi = 90, floorLift = 1 },  -- L2 区级
    { potLo = 50, potMode = 67, potHi = 91, floorLift = 3 },  -- L3 市级
    { potLo = 56, potMode = 74, potHi = 92, floorLift = 5 },  -- L4 省级精英
    { potLo = 63, potMode = 81, potHi = 92, floorLift = 7 },  -- L5 国家级营
}

YouthManager.YOUTH_FACILITY_NAMES = {
    "社区青训点", "区级青训中心", "市级青训学院", "省级精英基地", "国家级青训营",
}

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
        { "许嘉树" }, { "沈逸凡" }, { "曹宇轩" }, { "邓子豪" }, { "彭思齐" },
        { "曾文博" }, { "彭宇航" }, { "吕晨阳" }, { "丁梓睿" }, { "任天佑" },
        { "姜皓轩" }, { "范子谦" }, { "方嘉懿" }, { "石锦程" }, { "姚启航" },
        { "谭俊豪" }, { "邱子墨" }, { "秦宇辰" }, { "江浩然" }, { "汪明轩" },
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
        { "藤原苍" }, { "原田陆" }, { "三浦悠" }, { "冈田飒" }, { "内田航" },
        { "福田莲斗" }, { "西村悠真" }, { "石川大辉" }, { "上田苍太" }, { "后藤骏" },
    },
    -- 韩国球员（中文汉字）
    KR = {
        { "金民俊" }, { "李在成" }, { "朴志勋" }, { "崔英杰" }, { "郑宇成" },
        { "姜秀赫" }, { "赵俊浩" }, { "韩尚勋" }, { "尹载元" }, { "吴承民" },
        { "申东赫" }, { "权赫俊" }, { "黄仁成" }, { "孙兴浩" }, { "裴镇宇" },
        { "南泰旭" }, { "柳在石" }, { "洪正浩" }, { "文尚允" }, { "白承训" },
        { "安志勋" }, { "车宇彬" }, { "卢尚贤" }, { "严俊宇" }, { "方泰成" },
        { "成志浩" }, { "元尚勋" }, { "河俊锡" }, { "都承佑" }, { "鲜于航" },
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

-- 使用完整姓名条目（不再拼接名·姓）
local YOUTH_FULL_NAME_NATIONS = { CHN = true, CN = true, JP = true, KR = true }

-- 名·姓 组合用的名字池（与姓氏池组合，扩大唯一组合数）
local YOUTH_GIVEN_NAMES = {
    "加布里埃尔", "卢卡斯", "马特奥", "迭戈", "莱昂", "尼古拉斯", "塞巴斯蒂安",
    "费德里科", "马可", "安德烈", "斯特凡", "扬", "皮埃尔", "安东尼", "维克托",
    "丹尼尔", "胡安", "米格尔", "卡洛斯", "佩德罗", "拉斐尔", "布鲁诺", "蒂亚戈",
    "恩佐", "阿德里安", "伊尼亚基", "马尔科", "达尼", "亚历克斯", "托马斯",
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
    "CHN",                                                          -- 中国 1/50 = 2%
}

-- 导出常量供 UI 使用
YouthManager.MAX_YOUTH_SQUAD = MAX_YOUTH_SQUAD
YouthManager.MAX_YOUTH_SQUAD_PLAYER = MAX_YOUTH_SQUAD_PLAYER
YouthManager.YOUTH_POOL_SIZE = YOUTH_POOL_SIZE
YouthManager.INITIAL_YOUTH_COUNT = INITIAL_YOUTH_COUNT
YouthManager.AI_TIER2_YOUTH_COUNT = AI_TIER2_YOUTH_COUNT

--- 获取指定球队的青训名额上限（玩家 30，AI 18）
---@param gameState table
---@param teamOrId table|number|string
---@return number
function YouthManager.getMaxYouthSquad(gameState, teamOrId)
    if not gameState then return MAX_YOUTH_SQUAD end
    local teamId = teamOrId
    if type(teamOrId) == "table" then
        teamId = teamOrId.id
    end
    if gameState.playerTeamId and teamId == gameState.playerTeamId then
        return MAX_YOUTH_SQUAD_PLAYER
    end
    return MAX_YOUTH_SQUAD
end

------------------------------------------------------
-- 传奇球星池抽卡配置
------------------------------------------------------
local LEGEND_UNLOCK_ADS = 10        -- 看10次广告解锁传奇池
local LEGEND_PULL_PER_AD = 3        -- 解锁后每次广告获得3次抽取
local LEGEND_TEN_PULL_ADS = 3       -- 3次广告 = +15抽
local LEGEND_BASE_RATE = 0.047      -- 单抽传奇基础概率 4.7%（十连实际≈38%）
local LEGEND_RATE_INCREMENT = 0.002 -- 每次未出传奇十连 +0.2%
local LEGEND_RATE_CAP = 0.053       -- 概率上限5.3%（十连实际≈42%封顶）
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
    LeftMidfielder = "LM",
    RightMidfielder = "RM",
    LeftWing = "LW",
    RightWing = "RW",
    Striker = "ST",
    CentreForward = "CF",
}

--- 将传奇数据中的英文位置转换为游戏简写
local function mapPosition(pos)
    if not pos then return "ST" end
    return POSITION_MAP[pos] or pos
end

--- 收集某队青训/候选池已占用的 displayName
---@param gameState table
---@param teamId number|nil
---@param extraUsed table|nil
---@return table used set
local function _collectYouthUsedNames(gameState, teamId, extraUsed)
    local used = {}
    local function mark(name)
        if name and name ~= "" then used[name] = true end
    end
    if extraUsed then
        for name in pairs(extraUsed) do mark(name) end
    end
    local team = teamId and gameState.teams[teamId]
    if team then
        for _, pid in ipairs(team._youthPlayerIds or {}) do
            local p = gameState.players[pid]
            if p then mark(p.displayName) end
        end
    end
    for _, c in ipairs(gameState._youthCandidates or {}) do
        mark(c.displayName)
    end
    return used
end

--- 从国籍对应名字池抽取未占用的 displayName，并写入 usedNames
---@param nationality string
---@param usedNames table|nil
---@return string displayName
local function _pickYouthDisplayName(nationality, usedNames)
    usedNames = usedNames or {}
    local maxAttempts = 120

    if YOUTH_FULL_NAME_NATIONS[nationality] then
        local pool = YOUTH_NAMES_BY_NATION[nationality] or YOUTH_NAMES_BY_NATION.CN
        for _ = 1, maxAttempts do
            local name = pool[RandomInt(1, #pool)][1]
            if not usedNames[name] then
                usedNames[name] = true
                return name
            end
        end
    else
        local pool = YOUTH_NAMES_BY_NATION[nationality] or YOUTH_NAMES_BY_NATION.BRA
        for _ = 1, maxAttempts do
            local given = YOUTH_GIVEN_NAMES[RandomInt(1, #YOUTH_GIVEN_NAMES)]
            local surname = pool[RandomInt(1, #pool)][1]
            local name = given .. "·" .. surname
            if not usedNames[name] then
                usedNames[name] = true
                return name
            end
        end
    end

    -- 极端情况：在名后追加一字变体（仍保持中文姓名风格）
    local variants = { "翔", "彦", "太", "也", "树", "真", "斗", "人", "介", "一" }
    for _ = 1, 40 do
        if YOUTH_FULL_NAME_NATIONS[nationality] then
            local pool = YOUTH_NAMES_BY_NATION[nationality] or YOUTH_NAMES_BY_NATION.CN
            local base = pool[RandomInt(1, #pool)][1]
            local name = base:sub(1, 2) .. variants[RandomInt(1, #variants)] .. base:sub(3)
            if not usedNames[name] then
                usedNames[name] = true
                return name
            end
        else
            local pool = YOUTH_NAMES_BY_NATION[nationality] or YOUTH_NAMES_BY_NATION.BRA
            local given = YOUTH_GIVEN_NAMES[RandomInt(1, #YOUTH_GIVEN_NAMES)]
            local surname = pool[RandomInt(1, #pool)][1]
            local name = given .. variants[RandomInt(1, #variants)] .. "·" .. surname
            if not usedNames[name] then
                usedNames[name] = true
                return name
            end
        end
    end

    local fallback = "青训" .. tostring(RandomInt(1000, 9999))
    usedNames[fallback] = true
    return fallback
end

--- displayName → firstName / lastName（lastName 取 · 后段，供阵型短标签）
local function _formatYouthNameFields(displayName)
    local last = displayName:match("·(.+)$") or displayName
    return displayName, last
end

------------------------------------------------------
-- 青训名单辅助
------------------------------------------------------

--- 球员是否仍属于本队青训编制（含租借在外）
local function _belongsToYouthSquad(player, teamId)
    if not player then return false end
    return player.teamId == teamId or player._loanOriginTeamId == teamId
end

local function _isInFirstTeam(team, playerId)
    for _, pid in ipairs(team.playerIds or {}) do
        if pid == playerId then return true end
    end
    return false
end

local function _indexYouthRefs(team)
    local seen = {}
    for _, pid in ipairs(team._youthPlayerIds or {}) do
        seen[pid] = true
    end
    return seen
end

--- 球员是否在该队青训名单（含仅 _youthPlayerIds、未进一线队的情况）
---@param gameState table
---@param playerId number
---@param teamId number|nil
---@return boolean
function YouthManager.isOnTeamYouthSquad(gameState, playerId, teamId)
    if not gameState or not playerId or not teamId then return false end
    local team = gameState.teams[teamId]
    if not team then return false end
    for _, pid in ipairs(team._youthPlayerIds or {}) do
        if pid == playerId then return true end
    end
    return false
end

--- 已签入青训队、可走转会流程的球员（非 _youthCandidates）
---@param gameState table
---@param player table|nil
---@return boolean
function YouthManager.isYouthSquadPlayer(gameState, player)
    if not player or not player.isYouth or not player.teamId then return false end
    local team = gameState and gameState.teams and gameState.teams[player.teamId]
    if team then
        YouthManager.reconcileYouthRefsForTeam(gameState, team)
    end
    return YouthManager.isOnTeamYouthSquad(gameState, player.id, player.teamId)
end

--- 清除球队青训名单中的残留引用（与 Housekeeping.purgeStaleYouthRefs 规则对齐）
local function _purgeStaleYouthRefsForTeam(gameState, team)
    team._youthPlayerIds = team._youthPlayerIds or {}
    for i = #team._youthPlayerIds, 1, -1 do
        local pid = team._youthPlayerIds[i]
        local p = gameState.players[pid]
        local stillOurs = _belongsToYouthSquad(p, team.id)
        -- 已转会离队，或已是一线队球员（转会/提拔完成）→ 清除残留
        local alreadyFirstTeam = stillOurs and p and not p.isYouth and _isInFirstTeam(team, pid)
        if not stillOurs or alreadyFirstTeam then
            table.remove(team._youthPlayerIds, i)
        end
    end
end

--- 修复仍属于本队但缺失 _youthPlayerIds 引用的青训球员（旧版满员提拔失败会造成）
local function _restoreMissingYouthRefsForTeam(gameState, team)
    team._youthPlayerIds = team._youthPlayerIds or {}
    local seen = _indexYouthRefs(team)
    local maxSquad = YouthManager.getMaxYouthSquad(gameState, team)
    local restored = 0

    for pid, player in pairs(gameState.players or {}) do
        local playerId = player.id or pid
        if not seen[playerId]
            and player.isYouth
            and _belongsToYouthSquad(player, team.id)
            and not _isInFirstTeam(team, playerId)
            and #team._youthPlayerIds < maxSquad then
            table.insert(team._youthPlayerIds, playerId)
            seen[playerId] = true
            restored = restored + 1
        end
    end

    return restored
end

function YouthManager.reconcileYouthRefsForTeam(gameState, team)
    if not gameState or not team then return 0 end
    _purgeStaleYouthRefsForTeam(gameState, team)
    return _restoreMissingYouthRefsForTeam(gameState, team)
end

function YouthManager.reconcileYouthRefs(gameState)
    if not gameState then return 0 end
    local restored = 0
    for _, team in pairs(gameState.teams or {}) do
        restored = restored + YouthManager.reconcileYouthRefsForTeam(gameState, team)
    end
    return restored
end

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 每月处理：刷新青训候选池（玩家球队）+ AI 球队青训管理
---@param gameState table
function YouthManager.processMonthly(gameState)
    YouthManager.purgeOverageYouth(gameState)

    -- 玩家球队候选刷新
    gameState._youthCandidates = gameState._youthCandidates or {}
    gameState._youthRefreshCounter = (gameState._youthRefreshCounter or 0) + 1

    if gameState._youthRefreshCounter >= YOUTH_REFRESH_INTERVAL then
        gameState._youthRefreshCounter = 0
        YouthManager._refreshCandidates(gameState)
    end

    -- AI 球队青训管理（每月执行一次简化逻辑）
    YouthManager._processAITeamsMonthly(gameState)

    -- 青训在训球员工资随能力缓慢上调
    YouthManager.syncYouthAcademyWages(gameState)
end

--- 同步所有球队青训在训球员周薪
function YouthManager.syncYouthAcademyWages(gameState)
    for teamId, team in pairs(gameState.teams or {}) do
        for _, pid in ipairs(team._youthPlayerIds or {}) do
            local player = gameState.players[pid]
            if player and player.teamId == teamId then
                local newWage = FinanceManager.estimateYouthAcademyWage(player, team, gameState)
                if newWage > (player.wage or 0) then
                    player.wage = newWage
                end
            end
        end
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
    local maxSquad = YouthManager.getMaxYouthSquad(gameState, team)
    if #team._youthPlayerIds >= maxSquad then
        return false, string.format("青训名额已满(%d人)", maxSquad)
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
        nationality = Nationality.normalize(candidate.nationality),
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
        legendTag = candidate.legendTag,
    }
    local player = gameState:addPlayer(playerData)

    -- 设置球队归属
    player.teamId = team.id
    player.wage = FinanceManager.estimateYouthAcademyWage(player, team, gameState)

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

    YouthManager.reconcileYouthRefsForTeam(gameState, team)

    -- 检查是否在青训队
    team._youthPlayerIds = team._youthPlayerIds or {}
    local youthIndex = nil
    for i, yid in ipairs(team._youthPlayerIds) do
        if yid == playerId then
            youthIndex = i
            break
        end
    end
    if not youthIndex then return false, "该球员不在青训队中" end

    local player = gameState.players[playerId]
    if not player then return false, "球员不存在" end
    if player.listedForSale then return false, "请先取消挂牌出售" end
    if player.listedForLoan then return false, "请先取消外租挂牌" end

    -- 归属校验：防止残留引用误覆盖已转会球员的合同（BUG-20260611-06 玩家手动提拔路径）
    if player.teamId ~= team.id then
        return false, "该球员已不属于本队"
    end

    local alreadyFirstTeam = _isInFirstTeam(team, playerId)
    if not alreadyFirstTeam and team:isSquadFullFor(gameState) then
        return false, string.format("一线队已满员（最多 %d 人）", team:getEffectiveSquadMax(gameState))
    end
    table.remove(team._youthPlayerIds, youthIndex)
    if not alreadyFirstTeam then
        table.insert(team.playerIds, playerId)
    end

    player.isYouth = false
    player.teamId = team.id

    -- 已在一线队（如转会后残留引用）：仅清除青训身份，保留现有合同
    if not alreadyFirstTeam then
        player.contractEnd = {year = gameState.date.year + 3, month = 6, day = 30}
        player.wage = FinanceManager.estimateYouthPromoteWage(player, team, gameState)
        MessageManager.send(gameState, "youth_promoted", {player.displayName})
        EventBus.emit("youth_promoted", {teamId = team.id, playerId = playerId})
    end

    return true
end

--- 从首发/替补名单移除球员
local function _removeFromLineup(team, playerId)
    if team.startingXI then
        for slot, pid in pairs(team.startingXI) do
            if pid == playerId then team.startingXI[slot] = nil end
        end
    end
    if team.benchIds then
        for i = #team.benchIds, 1, -1 do
            if team.benchIds[i] == playerId then
                table.remove(team.benchIds, i)
            end
        end
    end
end

--- 检查一线队球员是否可下放至青训队
---@param gameState table
---@param playerId number
---@param teamId number|nil 默认玩家球队
---@return boolean ok
---@return string|nil error
function YouthManager.canDemoteToYouth(gameState, playerId, teamId)
    local team = teamId and gameState.teams[teamId] or gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    YouthManager.reconcileYouthRefsForTeam(gameState, team)

    local player = gameState.players[playerId]
    if not player then return false, "球员不存在" end
    if player.teamId ~= team.id then return false, "该球员不属于本队" end
    if player.squadRole == "loaned" then return false, "外租中球员无法下放" end
    if player.isYouth or YouthManager.isOnTeamYouthSquad(gameState, playerId, team.id) then
        return false, "该球员已在青训队"
    end
    if not _isInFirstTeam(team, playerId) then return false, "该球员不在一线队" end

    local age = player:getAge(gameState.date.year)
    if age > Constants.YOUTH_PHASE_MAX_AGE then
        return false, string.format("%d岁以上球员无法下放至青训队", Constants.YOUTH_PHASE_MAX_AGE)
    end
    if player.isLegend then return false, "传奇球员无法下放至青训队" end
    if player.listedForSale then return false, "请先取消挂牌出售" end
    if player.listedForLoan then return false, "请先取消外租挂牌" end

    local TransferManager = require("scripts/systems/transfer_manager")
    if TransferManager.hasPendingIncomingBid(gameState, playerId) then
        return false, "该球员有活跃转会报价，请先处理"
    end

    team._youthPlayerIds = team._youthPlayerIds or {}
    local maxSquad = YouthManager.getMaxYouthSquad(gameState, team)
    if #team._youthPlayerIds >= maxSquad then
        return false, string.format("青训名额已满(%d人)", maxSquad)
    end

    local safe, reason = FinanceManager.checkSquadSafety(gameState, playerId)
    if not safe then return false, reason end

    return true, nil
end

--- 将一线队年轻球员下放至青训队（promote 的逆操作）
---@param gameState table
---@param playerId number
---@return boolean success, string|nil error
function YouthManager.demoteToYouth(gameState, playerId)
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    YouthManager.reconcileYouthRefsForTeam(gameState, team)

    local ok, err = YouthManager.canDemoteToYouth(gameState, playerId, team.id)
    if not ok then return false, err end

    local player = gameState.players[playerId]

    for i, pid in ipairs(team.playerIds) do
        if pid == playerId then
            table.remove(team.playerIds, i)
            break
        end
    end
    _removeFromLineup(team, playerId)

    team._youthPlayerIds = team._youthPlayerIds or {}
    table.insert(team._youthPlayerIds, playerId)

    player.isYouth = true
    player.squadRole = "youth"
    player.teamId = team.id
    player.wage = FinanceManager.estimateYouthAcademyWage(player, team, gameState)
    player.listedForSale = false
    player.listedForLoan = false

    MessageManager.send(gameState, "youth_demoted", {player.displayName})
    EventBus.emit("youth_demoted", {teamId = team.id, playerId = playerId})

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

    YouthManager.reconcileYouthRefsForTeam(gameState, team)

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
    if player and player.teamId ~= team.id then
        return false, "该球员已不属于本队"
    end
    if player then
        if player.listedForSale then return false, "请先取消挂牌出售" end
        local TransferManager = require("scripts/systems/transfer_manager")
        if TransferManager.hasPendingIncomingBid(gameState, playerId) then
            TransferManager.delistPlayer(gameState, player)
        end

        player.listedForSale = false
        player.listedForLoan = false
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

    YouthManager.reconcileYouthRefsForTeam(gameState, team)

    team._youthPlayerIds = team._youthPlayerIds or {}
    local result = {}
    for _, pid in ipairs(team._youthPlayerIds) do
        local p = gameState.players[pid]
        if p and p.isYouth and _belongsToYouthSquad(p, team.id) then
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

--- 22+ 仍在青训名单：自动解约并删库 / 转自由球员（全队含 AI）
---@param gameState table
---@return number purged
function YouthManager.purgeOverageYouth(gameState)
    local seasonYear = TrainingManager.getSeasonStartYear(gameState)
    local purged = 0

    for _, team in pairs(gameState.teams or {}) do
        team._youthPlayerIds = team._youthPlayerIds or {}
        for i = #team._youthPlayerIds, 1, -1 do
            local pid = team._youthPlayerIds[i]
            local player = gameState.players[pid]
            if player and player:getAge(seasonYear) > Constants.YOUTH_PHASE_MAX_AGE then
                table.remove(team._youthPlayerIds, i)
                player.isYouth = false
                player.teamId = nil
                player.contractEnd = nil
                player.wage = 0

                local rawPotential = player.potential or 0
                if rawPotential >= 70 then
                    player.isFreeAgent = true
                    player.releasedDate = {
                        year = gameState.date.year,
                        month = gameState.date.month,
                        day = gameState.date.day,
                    }
                else
                    gameState.players[pid] = nil
                end
                purged = purged + 1
            end
        end
    end

    return purged
end

--- 对单个球队执行青训球员训练（与一线队同 schedule / 同公式 + 微调加成）
local function _trainTeamYouth(gameState, team, youthBonus)
    if not TrainingManager.isTrainingDay(team, gameState.dayOfWeek) then
        return
    end

    team._youthPlayerIds = team._youthPlayerIds or {}
    local FinanceManager = require("scripts/systems/finance_manager")
    local facilityBonus = FinanceManager.getFacilityBonuses(team).trainingGain or 1.0
    local staffMult = 1.0 + (youthBonus or 0.05) * 5.0
    local intensityConfig = TrainingManager._getIntensity().medium
    local seasonStartYear = TrainingManager.getSeasonStartYear(gameState)

    local legendPositions = {}
    for _, pid in ipairs(team._youthPlayerIds) do
        local p = gameState.players[pid]
        if p and p.isLegend then legendPositions[p.position] = true end
    end
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and p.isLegend then legendPositions[p.position] = true end
    end

    for _, pid in ipairs(team._youthPlayerIds) do
        local player = gameState.players[pid]
        if player and player.teamId == team.id and player.attributes then
            if TrainingManager.getSeasonAge(player, seasonStartYear) <= Constants.YOUTH_PHASE_MAX_AGE then
                TrainingManager._trainPlayer(
                    gameState, team, player, intensityConfig,
                    staffMult * facilityBonus, legendPositions,
                    {
                        useYouthGap = true,
                        trainingBonusMult = Constants.YOUTH_TRAINING_BONUS,
                        skipInjuryAndFitness = true,
                    })
            end
        end
    end
end

--- AI 球队按声望的自动提拔 OVR 门槛
---@param team table
---@return number
function YouthManager._getAIPromoteMinOvr(team)
    local rep = team and team.reputation or 600
    for _, tier in ipairs(AI_PROMOTE_MIN_OVR_BY_REP) do
        if rep >= tier.minRep then return tier.ovr end
    end
    return 55
end

--- 是否满足 AI 自动提拔条件（含高潜延迟）
---@param gameState table
---@param team table
---@param player table
---@return boolean
function YouthManager._shouldAIPromoteYouth(gameState, team, player)
    if not player or not team then return false end
    local age = gameState.date.year - (player.birthYear or 2000)
    if age < 18 then return false end

    local minOvr = YouthManager._getAIPromoteMinOvr(team)
    local ovr = player.overall or 0
    local pot = player.actualPotential or player.potential or 0

    if pot >= 90 then
        if age < AI_PROMOTE_HIGH_POT_90_AGE then return false end
        minOvr = math.max(minOvr, AI_PROMOTE_GEM_MIN_OVR)
    elseif pot >= 85 then
        if age < AI_PROMOTE_HIGH_POT_85_AGE then return false end
    end

    return ovr >= minOvr
end

--- 每日训练：所有球队青训球员成长
function YouthManager.processDailyTraining(gameState)
    for teamId, team in pairs(gameState.teams) do
        team._youthPlayerIds = team._youthPlayerIds or {}
        if #team._youthPlayerIds > 0 then
            local youthBonus = 0.05
            local ok, bonus = pcall(StaffManager.getYouthDevBonus, gameState, teamId)
            if ok and bonus then youthBonus = bonus end
            _trainTeamYouth(gameState, team, youthBonus)
        end
    end
end

------------------------------------------------------
-- 内部函数
------------------------------------------------------

--- 声望 → 青训设施等级（开局初始值，所有球队统一）
function YouthManager._reputationToYouthFacilityLevel(reputation)
    local rep = reputation or 500
    if rep >= 860 then return 5
    elseif rep >= 770 then return 4
    elseif rep >= 680 then return 3
    elseif rep >= 580 then return 2
    else return 1
    end
end

--- 按声望初始化青训设施（仅一次；之后财务页手动升级不再被覆盖）
function YouthManager._ensureYouthFacilityFromReputation(team)
    if not team then return end
    FinanceManager.ensureFacilities(team)
    if not team._youthFacilityFromRep then
        team.facilities.youth = YouthManager._reputationToYouthFacilityLevel(team.reputation)
        team._youthFacilityFromRep = true
    end
end

--- 获取某队青训生成加成（职员 + 设施分层）
function YouthManager._getTeamYouthGenBonuses(gameState, teamId)
    local team = gameState.teams[teamId]
    if not team then return 0.05, 1.0 end

    local youthDevBonus = 0.05
    local ok, bonus = pcall(StaffManager.getYouthDevBonus, gameState, teamId)
    if ok and bonus then youthDevBonus = bonus end

    YouthManager._ensureYouthFacilityFromReputation(team)
    local facilityBonuses = FinanceManager.getFacilityBonuses(team)
    return youthDevBonus, facilityBonuses.youthQuality or 1.0
end

function YouthManager._refreshCandidates(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    local youthDevBonus, facilityYouthBonus = YouthManager._getTeamYouthGenBonuses(gameState, team.id)

    local candidates = {}
    local usedNames = _collectYouthUsedNames(gameState, team.id)

    for _ = 1, YOUTH_POOL_SIZE do
        local candidate = YouthManager._generateYouthPlayer(gameState, youthDevBonus, facilityYouthBonus, usedNames, team.country)
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

--- 从 getFacilityBonuses 的 youthQuality 反推设施等级（1~5）
function YouthManager._facilityLevelFromBonus(facilityYouthBonus)
    local bonus = facilityYouthBonus or 1.0
    local level = math.floor((bonus - 1.0) / 0.10 + 1.5)
    return math.max(1, math.min(#YouthManager.YOUTH_FACILITY_TIERS, level))
end

-- 三角分布采样（lo..hi，峰值在 mode）：中间稠密、两端稀疏，
-- 天然实现"妖人/废品都罕见、且越靠近 mode 越常见"。
local function _triangular(lo, mode, hi)
    if hi <= lo then return lo end
    if mode < lo then mode = lo elseif mode > hi then mode = hi end
    local u = Random()
    local c = (mode - lo) / (hi - lo)
    if u < c then
        return lo + math.sqrt(u * (hi - lo) * (mode - lo))
    else
        return hi - math.sqrt((1 - u) * (hi - lo) * (hi - mode))
    end
end

--- 按声望档（设施等级）抽样潜力：
---   低档 = 低均值 + 高方差（搏一搏，偶出妖人）；高档 = 高均值 + 低方差（稳定出货）
function YouthManager._rollYouthPotential(youthMods, facilityLevel, youthDevBonus)
    local tier = YouthManager.YOUTH_FACILITY_TIERS[facilityLevel]
        or YouthManager.YOUTH_FACILITY_TIERS[1]
    local potMax = youthMods.potentialMax or 90
    local hi = math.min(tier.potHi, potMax)
    local lo = math.max(40, math.min(tier.potLo, hi - 1))
    local mode = math.max(lo, math.min(tier.potMode, hi))

    local basePotential = _triangular(lo, mode, hi)
    local coachAdd = (youthDevBonus or 0) * 15
    return math.max(40, math.min(99, math.floor(basePotential + coachAdd + 0.5)))
end

function YouthManager._generateYouthPlayer(gameState, youthDevBonus, facilityYouthBonus, usedNames, teamCountry)
    facilityYouthBonus = facilityYouthBonus or 1.0
    local positions = {"GK", "CB", "LB", "RB", "CM", "CDM", "CAM", "LW", "RW", "ST"}
    local position = positions[RandomInt(1, #positions)]

    -- 难度修正：青训质量影响年龄和潜力范围
    local youthMods = DifficultySettings.getYouthModifiers()
    local age = RandomInt(youthMods.minAge, youthMods.maxAge)
    local birthYear = gameState.date.year - age

    local facilityLevel = YouthManager._facilityLevelFromBonus(facilityYouthBonus)
    local tier = YouthManager.YOUTH_FACILITY_TIERS[facilityLevel]

    local potential = YouthManager._rollYouthPotential(youthMods, facilityLevel, youthDevBonus)

    -- 当前能力：基于潜力线性映射；设施仅微调 OVR 下限，不再整段抬高
    local overallFloor = youthMods.overallMin + tier.floorLift
    overallFloor = math.max(20, overallFloor)
    local overallCap = math.min(youthMods.overallMax,
        math.max(overallFloor, math.floor(potential * 0.8)))
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

    -- 先随机国籍，再从对应名字池取名（本批/本队 usedNames 去重）
    -- 根据球队所属国家偏向本国国籍（中超球队85%中国球员）
    local nationality
    if teamCountry == "CHN" then
        if RandomInt(1, 100) <= 85 then
            nationality = "CHN"
        else
            nationality = YOUTH_NATIONALITIES[RandomInt(1, #YOUTH_NATIONALITIES)]
        end
    else
        nationality = YOUTH_NATIONALITIES[RandomInt(1, #YOUTH_NATIONALITIES)]
    end
    local displayName = _pickYouthDisplayName(nationality, usedNames)
    local firstName, lastName = _formatYouthNameFields(displayName)

    return {
        firstName = firstName,
        lastName = lastName,
        displayName = displayName,
        nationality = Nationality.normalize(nationality),
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
-- 传奇签入：在青训能力模板上叠加该传奇的"属性轮廓"
--
-- 设计：仅在 calculateOverallFromAttrs 实际计入的属性集合内做"按偏离均值
-- 的重分配"。均值守恒 → base_score 不变 → 总评仍锚定青训档位（不破坏平衡），
-- 但高光/弱项的相对形态来自 JSON 展示属性，让穆勒(射门/跑位高、速度低)、
-- 贝克汉姆(传球高、防守低)等保留个人特色。JSON 属性本身不直接签入。
------------------------------------------------------
-- 与 Player.calculateOverallFromAttrs 的 allAttrs 一致（场员不含 handling/reflexes）
local LEGEND_SHAPE_KEYS_OUTFIELD = {
    "speed", "stamina", "strength", "agility", "passing", "shooting",
    "tackling", "dribbling", "defending", "positioning", "vision",
    "decisions", "composure", "aggression", "teamwork", "leadership", "aerial",
}
local LEGEND_SHAPE_KEYS_GK = {
    "handling", "reflexes", "positioning", "aerial",
    "composure", "decisions", "agility", "strength", "speed",
}
local LEGEND_SHAPE_BLEND = 0.55          -- JSON 轮廓融合强度（0=纯青训模板, 1=全量轮廓）
local LEGEND_SHAPE_SCALE = 20.0 / 99.0   -- FM 1-99 尺度 → 局内 1-20 尺度

--- 在已生成的 1-20 属性上叠加传奇 JSON 的相对轮廓（原地修改并返回）
---@param attrs table 已由 _generateAttributes 生成的属性
---@param lData table 传奇 JSON 数据（含 attributes）
---@param position string 局内简写位置
---@return table attrs
function YouthManager._applyLegendShape(attrs, lData, position)
    local src = lData and lData.attributes
    if type(src) ~= "table" then return attrs end

    local keys = (position == "GK") and LEGEND_SHAPE_KEYS_GK or LEGEND_SHAPE_KEYS_OUTFIELD
    local function jsonAttr(k)
        if k == "speed" then return src.speed or src.pace end
        return src[k]
    end

    -- JSON 属性均值（仅统计本位置参与总评的属性）
    local sum, n = 0, 0
    for _, k in ipairs(keys) do
        local v = jsonAttr(k)
        if v then sum = sum + v; n = n + 1 end
    end
    if n == 0 then return attrs end
    local jsonMean = sum / n

    -- 按偏离均值重分配（Σ偏离≈0 → 均值守恒）
    for _, k in ipairs(keys) do
        local v = jsonAttr(k)
        if v and attrs[k] then
            attrs[k] = attrs[k] + (v - jsonMean) * LEGEND_SHAPE_SCALE * LEGEND_SHAPE_BLEND
        end
    end

    -- 夹取范围并取整（仅处理参与重分配的键，其余保持 _generateAttributes 结果）
    for _, k in ipairs(keys) do
        attrs[k] = math.max(1, math.min(20, math.floor((attrs[k] or 1) + 0.5)))
    end
    return attrs
end

--- 生成传奇签入属性：青训能力模板 + JSON 轮廓（重锚定后总评仍等于青训档位）
---@param position string 局内简写位置
---@param overall number 青训档位 OVR
---@param lData table 传奇 JSON 数据
---@return table attrs
function YouthManager._generateLegendAttributes(position, overall, lData)
    local attrs = YouthManager._generateAttributes(position, overall)
    local targetOvr = Player.calculateOverallFromAttrs(position, attrs)

    YouthManager._applyLegendShape(attrs, lData, position)

    -- 重锚定：shape 让擅长项被位置权重放大可能抬高总评，这里用轮转单键微调拉回
    -- 青训档位（每次只调一个键、轮流处理 → 近似均匀位移，相对轮廓保留、平衡不破坏）
    local keys = (position == "GK") and LEGEND_SHAPE_KEYS_GK or LEGEND_SHAPE_KEYS_OUTFIELD
    local idx, stagnant = 0, 0
    for _ = 1, 200 do
        local cur = Player.calculateOverallFromAttrs(position, attrs)
        if math.abs(cur - targetOvr) <= 1 then break end
        local step = (cur > targetOvr) and -1 or 1
        idx = (idx % #keys) + 1
        local k = keys[idx]
        local nv = math.max(1, math.min(20, attrs[k] + step))
        if nv ~= attrs[k] then
            attrs[k] = nv
            stagnant = 0
        else
            stagnant = stagnant + 1
            if stagnant >= #keys then break end  -- 全部键都触顶/触底，无法继续
        end
    end
    return attrs
end

------------------------------------------------------
-- 初始化：为所有球队填充青训到 INITIAL_YOUTH_COUNT 人
------------------------------------------------------

function YouthManager.getAIYouthTarget(gameState, teamId, team)
    if not gameState or teamId == gameState.playerTeamId then
        return INITIAL_YOUTH_COUNT
    end

    local ok, RealDataLoader = pcall(require, "scripts/data/real_data_loader")
    if ok and RealDataLoader and RealDataLoader.getTeamLeague then
        local _, leagueKey = RealDataLoader.getTeamLeague(gameState, teamId)
        local league = gameState.leagues and leagueKey and gameState.leagues[leagueKey]
        if league and (league.tier or 1) >= 2 then
            return AI_TIER2_YOUTH_COUNT
        end
    end

    return INITIAL_YOUTH_COUNT
end

--- 为单队补齐青训至目标人数（已有 wonderkids 只补差额）
---@return number generated
local function _fillTeamYouthToInitial(gameState, teamId, team)
    team._youthPlayerIds = team._youthPlayerIds or {}
    local target = YouthManager.getAIYouthTarget(gameState, teamId, team)
    local needed = target - #team._youthPlayerIds
    if needed <= 0 then return 0 end

    local generated = 0
    local youthDevBonus, facilityYouthBonus =
        YouthManager._getTeamYouthGenBonuses(gameState, teamId)
    local usedNames = _collectYouthUsedNames(gameState, teamId)

    for _ = 1, needed do
        local candidate = YouthManager._generateYouthPlayer(
            gameState, youthDevBonus, facilityYouthBonus, usedNames, team.country)

        local playerData = {
            firstName = candidate.firstName,
            lastName = candidate.lastName,
            displayName = candidate.displayName,
            nationality = Nationality.normalize(candidate.nationality),
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
        player.paRating = PotentialSystem.rawToRating(player.potential)
        player.actualPotential = PotentialSystem.generateActualPotential(
            player.paRating, (gameState.potentialSeed or 0) + player.id * 7919)
        table.insert(team._youthPlayerIds, player.id)
        generated = generated + 1
    end
    return generated
end

--- 为所有球队填充青训球员至初始人数
--- 已有的 wonderkids 不会被覆盖，只补齐差额
---@param gameState table
function YouthManager.fillAllTeamsYouth(gameState)
    local totalGenerated = 0
    for teamId, team in pairs(gameState.teams) do
        totalGenerated = totalGenerated + _fillTeamYouthToInitial(gameState, teamId, team)
    end
    log:Write(LOG_INFO, "YouthManager: 为所有球队填充青训完毕，生成 " .. totalGenerated .. " 名球员")
end

--- 老档读档一次性迁移：仅补齐 AI 队青训名单（不动玩家队，不每周重复）
---@param gameState table
---@return number generated
function YouthManager.bootstrapLegacyAIYouthOnce(gameState)
    if gameState._aiYouthRosterBootstrapped then return 0 end

    local totalGenerated = 0
    local playerTeamId = gameState.playerTeamId
    for teamId, team in pairs(gameState.teams or {}) do
        if teamId ~= playerTeamId then
            totalGenerated = totalGenerated + _fillTeamYouthToInitial(gameState, teamId, team)
        end
    end

    gameState._aiYouthRosterBootstrapped = true
    if totalGenerated > 0 then
        log:Write(LOG_INFO, "YouthManager: 老档 AI 青训名单一次性补齐，生成 " .. totalGenerated .. " 名球员")
    end
    return totalGenerated
end

------------------------------------------------------
-- 传奇球星池抽卡系统（叙事标签分池）
------------------------------------------------------

local LegendTagPools = require("scripts/data/legend_tag_pools")

--- 获取抽卡状态
---@param gameState table
---@return table state
function YouthManager.getLegendGachaState(gameState)
    gameState._legendGacha = gameState._legendGacha or {}
    local s = gameState._legendGacha
    -- 逐项补全：兼容旧档/残缺档，避免 nil 参与运算
    if s.adsWatched == nil then s.adsWatched = 0 end
    if s.unlocked == nil then s.unlocked = false end
    if s.pulls == nil then s.pulls = 0 end
    if s.tenPullCount == nil then s.tenPullCount = 0 end
    if s.pityCounter == nil then s.pityCounter = 0 end
    if s.firstTenPull == nil then s.firstTenPull = true end
    if s.singlePullCounter == nil then s.singlePullCounter = 0 end
    if s.pullAdProgress == nil then s.pullAdProgress = 0 end
    if not s.selectedPoolId or not LegendTagPools.isValidPoolId(s.selectedPoolId) then
        s.selectedPoolId = LegendTagPools.getDefaultPoolId()
    end
    s.pulledLegends = s.pulledLegends or {}
    s.pulledLegendIds = s.pulledLegendIds or {}
    return s
end

--- 全部叙事标签池定义
---@return table[]
function YouthManager.getLegendTagPools()
    return LegendTagPools.getAllPools()
end

--- 当前选中的标签池 id
---@param gameState table
---@return string poolId
function YouthManager.getSelectedLegendPoolId(gameState)
    local state = YouthManager.getLegendGachaState(gameState)
    return state.selectedPoolId
end

--- 当前选中的标签池详情
---@param gameState table
---@return table|nil
function YouthManager.getSelectedLegendPool(gameState)
    return LegendTagPools.getPool(YouthManager.getSelectedLegendPoolId(gameState))
end

--- 切换标签池（解锁后可随时切换，不消耗次数）
---@param gameState table
---@param poolId string
---@return boolean ok
function YouthManager.setSelectedLegendPool(gameState, poolId)
    if not LegendTagPools.isValidPoolId(poolId) then
        return false
    end
    local state = YouthManager.getLegendGachaState(gameState)
    state.selectedPoolId = poolId
    return true
end

---@param state table gacha state
---@return table set
local function _getPulledLegendSet(state)
    local set = {}
    for _, id in ipairs(state.pulledLegendIds or {}) do
        set[id] = true
    end
    for _, name in ipairs(state.pulledLegends or {}) do
        set[name] = true
    end
    return set
end

---@param set table
---@param lData table
---@return boolean
local function _isLegendPulled(set, lData)
    if lData.id and set[lData.id] then return true end
    local key = lData.full_name_cn or lData.match_name
    return key and set[key] or false
end

---@param state table
---@param lData table
local function _markLegendPulled(state, lData)
    if lData.id then
        local dup = false
        for _, id in ipairs(state.pulledLegendIds) do
            if id == lData.id then dup = true break end
        end
        if not dup then
            table.insert(state.pulledLegendIds, lData.id)
        end
    end
    local key = lData.full_name_cn or lData.match_name or "传奇"
    local nameDup = false
    for _, name in ipairs(state.pulledLegends) do
        if name == key then nameDup = true break end
    end
    if not nameDup then
        table.insert(state.pulledLegends, key)
    end
end

--- 某标签池收集进度
---@param gameState table
---@param poolId string|nil 默认当前池
---@return table { total, remaining, collected, exhausted }
function YouthManager.getLegendPoolProgress(gameState, poolId)
    poolId = poolId or YouthManager.getSelectedLegendPoolId(gameState)
    local state = YouthManager.getLegendGachaState(gameState)
    local pulledSet = _getPulledLegendSet(state)
    local members = LegendTagPools.getPoolPlayers(poolId)
    local remaining = 0
    for _, p in ipairs(members) do
        if not _isLegendPulled(pulledSet, p) then
            remaining = remaining + 1
        end
    end
    local total = #members
    return {
        total = total,
        remaining = remaining,
        collected = total - remaining,
        exhausted = total > 0 and remaining == 0,
    }
end

--- 某标签池全部成员及收集状态（供"查看名单"展示）
---@param gameState table
---@param poolId string|nil 默认当前池
---@return table[] list { data = legendData, collected = boolean }
function YouthManager.getLegendPoolMembers(gameState, poolId)
    poolId = poolId or YouthManager.getSelectedLegendPoolId(gameState)
    local state = YouthManager.getLegendGachaState(gameState)
    local pulledSet = _getPulledLegendSet(state)
    local out = {}
    for _, p in ipairs(LegendTagPools.getPoolPlayers(poolId)) do
        table.insert(out, {
            data = p,
            collected = _isLegendPulled(pulledSet, p),
        })
    end
    return out
end

--- 构建当前标签池可抽传奇列表（排除全局已拥有）
---@param gameState table
---@return table[] legendPool
---@return string poolId
local function _buildLegendPoolForPull(gameState)
    local state = YouthManager.getLegendGachaState(gameState)
    local poolId = state.selectedPoolId
    local pulledSet = _getPulledLegendSet(state)
    local legendPool = {}
    for _, p in ipairs(LegendTagPools.getPoolPlayers(poolId)) do
        if not _isLegendPulled(pulledSet, p) then
            table.insert(legendPool, p)
        end
    end
    return legendPool, poolId
end

---@param gameState table
---@param lData table
---@return table candidate
local function _makeLegendCandidate(gameState, lData)
    local mappedPos = mapPosition(lData.position)
    local legendYouthMods = DifficultySettings.getYouthModifiers()
    local legendAge = RandomInt(legendYouthMods.legendMinAge, legendYouthMods.legendMaxAge)
    local legendOverall = RandomInt(legendYouthMods.legendOverallMin, legendYouthMods.legendOverallMax)
    local legendAttrs = YouthManager._generateLegendAttributes(mappedPos, legendOverall, lData)
    local preCalcOverall = Player.calculateOverallFromAttrs(mappedPos, legendAttrs)
    return {
        firstName = lData.full_name_cn or lData.match_name or "传奇",
        lastName = lData.full_name_cn or lData.match_name or "球星",
        displayName = lData.full_name_cn or lData.match_name or "传奇球星",
        nationality = Nationality.normalize(lData.football_nation or lData.nationality or "BRA"),
        birthYear = gameState.date.year - legendAge,
        position = mappedPos,
        potential = lData.potential or 95,
        overall = preCalcOverall,
        attributes = legendAttrs,
        age = legendAge,
        isLegend = true,
        legendName = lData.full_name_cn or lData.match_name,
        legendData = lData,
        legendTag = lData.legendTag or YouthManager.getSelectedLegendPoolId(gameState),
    }
end

--- 是否已收集该传奇（全局去重，跨标签池）
---@param gameState table
---@param lData table
---@return boolean
function YouthManager.isLegendCollected(gameState, lData)
    local state = YouthManager.getLegendGachaState(gameState)
    return _isLegendPulled(_getPulledLegendSet(state), lData)
end

--- 标记传奇已收集（签入/补偿/抽卡后调用）
---@param gameState table
---@param lData table
function YouthManager.markLegendCollected(gameState, lData)
    local state = YouthManager.getLegendGachaState(gameState)
    _markLegendPulled(state, lData)
end

-- 漏签补偿：传奇 JSON 索引（lazy）
local _legendById = nil
local _legendByName = nil

local function _ensureLegendIndex()
    if _legendById then return end
    local LegendsLoader = require("scripts/data/legends_loader")
    _legendById = {}
    _legendByName = {}
    for _, p in ipairs(LegendsLoader.loadAllPlayers()) do
        if p.id then _legendById[p.id] = p end
        local name = p.full_name_cn or p.match_name
        if name then _legendByName[name] = p end
    end
end

--- 按 id 或中文名查找传奇 JSON 数据
---@param idOrName string
---@return table|nil lData
function YouthManager.findLegendData(idOrName)
    if not idOrName or idOrName == "" then return nil end
    _ensureLegendIndex()
    return _legendById[idOrName] or _legendByName[idOrName]
end

---@param set table
---@param lData table
---@return boolean
local function _legendKeysPresent(set, lData)
    if lData.id and set[lData.id] then return true end
    local name = lData.full_name_cn or lData.match_name
    return name and set[name] or false
end

---@param gameState table
---@return table set
local function _collectLegendKeysFromPlayers(gameState)
    local set = {}
    for _, p in pairs(gameState.players or {}) do
        if p.isLegend then
            if p.legendData and p.legendData.id then set[p.legendData.id] = true end
            if p.legendName then set[p.legendName] = true end
        end
    end
    return set
end

---@param gameState table
---@return table set
local function _collectLegendKeysFromCandidates(gameState)
    local set = {}
    for _, c in ipairs(gameState._youthCandidates or {}) do
        if c.isLegend then
            if c.legendData and c.legendData.id then set[c.legendData.id] = true end
            if c.legendName then set[c.legendName] = true end
        end
    end
    return set
end

--- 已抽但未签入、且存档中无对应 Player 实体的传奇（漏签）
---@param gameState table
---@return table[] lData list
function YouthManager.getOrphanedPulledLegends(gameState)
    local state = YouthManager.getLegendGachaState(gameState)
    local entityKeys = _collectLegendKeysFromPlayers(gameState)
    local pendingKeys = _collectLegendKeysFromCandidates(gameState)
    local seen = {}
    local out = {}

    local function tryAdd(lData)
        if not lData then return end
        local dedupeKey = lData.id or (lData.full_name_cn or lData.match_name)
        if not dedupeKey or seen[dedupeKey] then return end
        if _legendKeysPresent(entityKeys, lData) then return end
        if _legendKeysPresent(pendingKeys, lData) then return end
        seen[dedupeKey] = true
        table.insert(out, lData)
    end

    for _, id in ipairs(state.pulledLegendIds or {}) do
        tryAdd(YouthManager.findLegendData(id))
    end
    for _, name in ipairs(state.pulledLegends or {}) do
        tryAdd(YouthManager.findLegendData(name))
    end
    return out
end

--- 补签漏签传奇：重建候选并直接签入青训队
---@param gameState table
---@param lData table
---@return boolean ok
---@return string|nil err
function YouthManager.reclaimOrphanedLegend(gameState, lData)
    if not lData then return false, "无效的传奇数据" end

    local stillOrphan = false
    for _, o in ipairs(YouthManager.getOrphanedPulledLegends(gameState)) do
        if lData.id and o.id == lData.id then
            stillOrphan = true
            break
        end
        local a = lData.full_name_cn or lData.match_name
        local b = o.full_name_cn or o.match_name
        if a and b and a == b then
            stillOrphan = true
            break
        end
    end
    if not stillOrphan then
        return false, "该传奇无需补签或已在候选/队中"
    end

    local candidate = _makeLegendCandidate(gameState, lData)
    gameState._youthCandidates = gameState._youthCandidates or {}
    table.insert(gameState._youthCandidates, candidate)
    local idx = #gameState._youthCandidates
    local ok, err = YouthManager.signCandidate(gameState, idx)
    if not ok then
        table.remove(gameState._youthCandidates, idx)
        return false, err
    end
    return true
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
        -- 解锁赠送30连抽
        state.pulls = state.pulls + 30
        log:Write(LOG_INFO, "YouthManager: 传奇池已解锁，赠送30次抽取")
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

    -- 看满3次，额外奖励6次（本轮合计 3+3+3+6=15）
    if state.pullAdProgress >= LEGEND_TEN_PULL_ADS then
        local bonus = 6
        state.pulls = state.pulls + bonus
        added = added + bonus
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
    local youthDevBonus, facilityYouthBonus = 0.05, 1.0
    if team then
        youthDevBonus, facilityYouthBonus =
            YouthManager._getTeamYouthGenBonuses(gameState, team.id)
    end

    -- 判断是否出传奇
    local isLegend = false
    local isPity = (state.pityCounter >= LEGEND_PITY_COUNT)

    local legendPool = _buildLegendPoolForPull(gameState)

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

        _markLegendPulled(state, lData)
        candidate = _makeLegendCandidate(gameState, lData)

        -- 出传奇重置保底
        state.pityCounter = 0
        state.singlePullCounter = 0
        if state.firstTenPull then
            state.firstTenPull = false
        end
    else
        local usedNames = team and _collectYouthUsedNames(gameState, team.id) or {}
        candidate = YouthManager._generateYouthPlayer(gameState, youthDevBonus, facilityYouthBonus, usedNames, team and team.country)
    end

    -- 追加到当前候选池
    gameState._youthCandidates = gameState._youthCandidates or {}
    table.insert(gameState._youthCandidates, candidate)

    log:Write(LOG_INFO, string.format(
        "YouthManager: 单抽完成(%s)，池=%s，剩余%d次，保底计数%d",
        isLegend and "传奇" or "普通",
        state.selectedPoolId or "?",
        state.pulls, state.pityCounter))

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

    local legendPool = _buildLegendPoolForPull(gameState)

    local team = gameState:getPlayerTeam()
    local youthDevBonus, facilityYouthBonus = 0.05, 1.0
    if team then
        youthDevBonus, facilityYouthBonus =
            YouthManager._getTeamYouthGenBonuses(gameState, team.id)
    end

    local candidates = {}
    local legendCount = 0
    local guaranteedSlot = 0  -- 保底传奇放在第几个位置
    local usedNames = team and _collectYouthUsedNames(gameState, team.id) or {}

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
            -- 从当前标签池随机选一个并移除
            local idx = RandomInt(1, #legendPool)
            local lData = legendPool[idx]
            table.remove(legendPool, idx)  -- 本次十连内不重复

            _markLegendPulled(state, lData)

            local candidate = _makeLegendCandidate(gameState, lData)
            table.insert(candidates, candidate)
            usedNames[candidate.displayName] = true
            legendCount = legendCount + 1
        else
            -- 普通青训球员
            local candidate = YouthManager._generateYouthPlayer(
                gameState, youthDevBonus, facilityYouthBonus, usedNames, team and team.country)
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
        "YouthManager: 十连抽完成，池=%s，出传奇%d名，累计十连%d次，保底计数%d",
        state.selectedPoolId or "?", legendCount, state.tenPullCount, state.pityCounter))

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

            -- 1. 自动提拔：年满 18 岁且达到声望分档 OVR 门槛（高潜延迟）
            local toPromote = {}
            if not team:isFirstTeamFull() then
                for i, pid in ipairs(team._youthPlayerIds) do
                    local player = gameState.players[pid]
                    if player and player.teamId == teamId then
                        if YouthManager._shouldAIPromoteYouth(gameState, team, player) then
                            table.insert(toPromote, i)
                        end
                    end
                end
            end
            -- 从后向前移除避免索引错位
            for i = #toPromote, 1, -1 do
                if team:isFirstTeamFull() then break end
                local idx = toPromote[i]
                local pid = team._youthPlayerIds[idx]
                local player = gameState.players[pid]
                table.remove(team._youthPlayerIds, idx)
                if player then
                    player.isYouth = false
                    player.teamId = teamId
                    player.contractEnd = {year = gameState.date.year + 3, month = 6, day = 30}
                    player.wage = FinanceManager.estimateYouthPromoteWage(player, team, gameState)
                    if team:addPlayer(pid) then
                        -- promoted
                    end
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

            -- 3. 自动补员：每3个月生成新球员补齐至分级青训目标
            team._aiYouthRefresh = (team._aiYouthRefresh or 0) + 1
            if team._aiYouthRefresh >= YOUTH_REFRESH_INTERVAL then
                team._aiYouthRefresh = 0
                local targetYouth = YouthManager.getAIYouthTarget(gameState, teamId, team)
                local needed = targetYouth - #team._youthPlayerIds
                if needed > 0 then
                    local youthDevBonus, facilityYouthBonus =
                        YouthManager._getTeamYouthGenBonuses(gameState, teamId)
                    local usedNames = _collectYouthUsedNames(gameState, teamId)

                    for _ = 1, needed do
                        local candidate = YouthManager._generateYouthPlayer(
                            gameState, youthDevBonus, facilityYouthBonus, usedNames, team.country)
                        local playerData = {
                            firstName = candidate.firstName,
                            lastName = candidate.lastName,
                            displayName = candidate.displayName,
                            nationality = Nationality.normalize(candidate.nationality),
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
