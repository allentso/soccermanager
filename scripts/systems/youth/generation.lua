-- systems/youth/generation.lua
-- 青训候选人生成、姓名池、世界初始化，从 youth_manager.lua 拆分。

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
local LegendGachaCloud = require("scripts/persistence/legend_gacha_cloud")
local TextUtil = require("scripts/app/text_util")
local Helpers = require("scripts/systems/youth/youth_helpers")
local randInt = Helpers.randInt

return function(YouthManager)
    local YOUTH_NAMES_BY_NATION = {
        -- 中国球员（legacy 全名池，CHN/CN 已改姓+名组合生成，此处保留供兼容/兜底）
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

    -- 中国青训：姓 × 名 组合（约 60×80 = 4800 种，避免 50 个固定全名很快用尽）
    local YOUTH_CN_SURNAMES = {
        "李", "王", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴",
        "徐", "孙", "胡", "朱", "高", "林", "何", "郭", "马", "罗",
        "梁", "宋", "郑", "谢", "韩", "唐", "冯", "于", "董", "萧",
        "许", "沈", "曹", "邓", "彭", "曾", "吕", "丁", "任", "姜",
        "范", "方", "石", "姚", "谭", "邱", "秦", "江", "汪", "蔡",
        "袁", "廖", "卢", "傅", "顾", "孟", "龙", "万", "段", "雷",
        "侯", "邵", "孔", "白", "崔", "康", "毛", "钱", "易", "常",
    }

    local YOUTH_CN_GIVEN_NAMES = {
        "浩然", "子轩", "宇航", "梓豪", "俊杰", "天翼", "志远", "博文", "昊天", "瑞祥",
        "嘉伟", "明哲", "晨曦", "逸飞", "鹏程", "思远", "泽宇", "煜城", "星辰", "承恩",
        "铭轩", "睿智", "翰林", "文昊", "致远", "鸿飞", "修远", "凯旋", "子墨", "晋鹏",
        "嘉树", "逸凡", "宇轩", "子豪", "思齐", "文博", "晨阳", "梓睿", "天佑", "皓轩",
        "子谦", "嘉懿", "锦程", "启航", "俊豪", "宇辰", "明轩", "子涵", "一诺", "梓涵",
        "雨泽", "奕辰", "浩宇", "梓轩", "俊熙", "子睿", "明远", "天朗",
        "景行", "维轩", "嘉言", "亦辰", "承泽", "子安", "云帆", "书翰", "正豪", "绍辉",
        "俊凯", "子杰", "宇恒", "嘉诚", "思成", "立轩", "家豪", "柏宇", "瑞霖",
        "泽楷", "奕鸣", "子瑜", "天睿", "弘毅", "文轩", "子骞", "景澄", "铭泽", "宇翔",
    }

    -- 使用完整姓名条目（不再拼接名·姓）
    local YOUTH_FULL_NAME_NATIONS = { JP = true, KR = true }

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

    -- 青训普通球员位置权重：按 22 人一线队结构折算，避免长期等概率抽导致 GK/CAM/CDM 过量、
    -- CB/ST 等多人位置不足。
    local YOUTH_POSITION_ORDER = {"GK", "CB", "LB", "RB", "CM", "CDM", "CAM", "LM", "RM", "LW", "RW", "ST"}
    local YOUTH_POSITION_WEIGHTS = {
        GK = 2,
        CB = 3,
        LB = 2,
        RB = 2,
        CM = 3,
        CDM = 1,
        CAM = 1,
        LM = 1,
        RM = 1,
        LW = 1,
        RW = 1,
        ST = 4,
    }
    local YOUTH_POSITION_WEIGHT_TOTAL = 0
    for _, pos in ipairs(YOUTH_POSITION_ORDER) do
        YOUTH_POSITION_WEIGHT_TOTAL = YOUTH_POSITION_WEIGHT_TOTAL + (YOUTH_POSITION_WEIGHTS[pos] or 0)
    end

    local function _normalizeYouthPosition(pos)
        local normalized = Constants.normalizePosition(pos)
        if normalized and YOUTH_POSITION_WEIGHTS[normalized] then return normalized end
        return nil
    end

    local function _pickWeightedYouthPosition()
        local roll = Random() * YOUTH_POSITION_WEIGHT_TOTAL
        local acc = 0
        for _, pos in ipairs(YOUTH_POSITION_ORDER) do
            acc = acc + (YOUTH_POSITION_WEIGHTS[pos] or 0)
            if roll <= acc then return pos end
        end
        return "CM"
    end

    --- 选择下一名普通青训的生成位置。
    --- 纯按阵容结构权重随机，不根据当前球队缺口纠偏，避免低权重位置被长期压制。
    ---@param gameState table|nil
    ---@param team table|nil
    ---@param plannedPositions string[]|nil 兼容旧调用，纯随机模式不使用
    ---@return string
    function YouthManager._pickYouthPositionForTeam(gameState, team, plannedPositions)
        return _pickWeightedYouthPosition()
    end

    --- 收集某队青训/候选池已占用的 displayName
    ---@param gameState table
    ---@param teamId number|nil
    ---@param extraUsed table|nil
    ---@return table used set
    function YouthManager._collectYouthUsedNames(gameState, teamId, extraUsed)
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
            for _, pid in ipairs(team.playerIds or {}) do
                local p = gameState.players[pid]
                if p then mark(p.displayName) end
            end
        end
        for _, c in ipairs(gameState._youthCandidates or {}) do
            mark(c.displayName)
        end
        return used
    end

    local function _isChineseYouthNation(nationality)
        return nationality == "CHN" or nationality == "CN"
    end

    ---@param usedNames table<string, boolean>
    ---@param maxAttempts number|nil
    ---@return string|nil
    local function _pickChineseYouthDisplayName(usedNames, maxAttempts)
        maxAttempts = maxAttempts or 120
        for _ = 1, maxAttempts do
            local surname = YOUTH_CN_SURNAMES[randInt(1, #YOUTH_CN_SURNAMES)]
            local given = YOUTH_CN_GIVEN_NAMES[randInt(1, #YOUTH_CN_GIVEN_NAMES)]
            local name = surname .. given
            if not usedNames[name] then
                usedNames[name] = true
                return name
            end
        end
        return nil
    end

    --- 从国籍对应名字池抽取未占用的 displayName，并写入 usedNames
    ---@param nationality string
    ---@param usedNames table<string, boolean>|nil
    ---@return string displayName
    local function _pickYouthDisplayName(nationality, usedNames)
        usedNames = usedNames or {}
        local maxAttempts = 120

        if _isChineseYouthNation(nationality) then
            local name = _pickChineseYouthDisplayName(usedNames, maxAttempts)
            if name then return name end
        elseif YOUTH_FULL_NAME_NATIONS[nationality] then
            local pool = YOUTH_NAMES_BY_NATION[nationality] or YOUTH_NAMES_BY_NATION.CN
            for _ = 1, maxAttempts do
                local name = pool[randInt(1, #pool)][1]
                if not usedNames[name] then
                    usedNames[name] = true
                    return name
                end
            end
        else
            local pool = YOUTH_NAMES_BY_NATION[nationality] or YOUTH_NAMES_BY_NATION.BRA
            for _ = 1, maxAttempts do
                local given = YOUTH_GIVEN_NAMES[randInt(1, #YOUTH_GIVEN_NAMES)]
                local surname = pool[randInt(1, #pool)][1]
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
            if _isChineseYouthNation(nationality) then
                local surname = YOUTH_CN_SURNAMES[randInt(1, #YOUTH_CN_SURNAMES)]
                local given = YOUTH_CN_GIVEN_NAMES[randInt(1, #YOUTH_CN_GIVEN_NAMES)]
                local name = surname .. variants[randInt(1, #variants)] .. given
                if not usedNames[name] then
                    usedNames[name] = true
                    return name
                end
            elseif YOUTH_FULL_NAME_NATIONS[nationality] then
                local pool = YOUTH_NAMES_BY_NATION[nationality] or YOUTH_NAMES_BY_NATION.CN
                local base = pool[randInt(1, #pool)][1]
                local name = base:sub(1, 2) .. variants[randInt(1, #variants)] .. base:sub(3)
                if not usedNames[name] then
                    usedNames[name] = true
                    return name
                end
            else
                local pool = YOUTH_NAMES_BY_NATION[nationality] or YOUTH_NAMES_BY_NATION.BRA
                local given = YOUTH_GIVEN_NAMES[randInt(1, #YOUTH_GIVEN_NAMES)]
                local surname = pool[randInt(1, #pool)][1]
                local name = given .. variants[randInt(1, #variants)] .. "·" .. surname
                if not usedNames[name] then
                    usedNames[name] = true
                    return name
                end
            end
        end

        local fallback = "青训" .. tostring(randInt(1000, 9999))
        usedNames[fallback] = true
        return fallback
    end

    --- displayName → firstName / lastName（lastName 取 · 后段，供阵型短标签）
    local function _formatYouthNameFields(displayName)
        local last = displayName:match("·(.+)$") or displayName
        return displayName, last
    end
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
        if team._youthFacilityFromRep then return end

        local repLevel = YouthManager._reputationToYouthFacilityLevel(team.reputation)
        local current = team.facilities.youth or 1
        -- 取较高值：声望初始化不覆盖财务页已升级等级（含旧存档缺 flag 的情况）
        team.facilities.youth = math.max(current, repLevel)
        team._youthFacilityFromRep = true
    end

    --- 获取某队青训候选生成加成（仅设施；职员不影响候选潜力）
    function YouthManager._getTeamYouthFacilityBonus(gameState, teamId)
        local team = gameState.teams[teamId]
        if not team then return 1.0 end

        YouthManager._ensureYouthFacilityFromReputation(team)
        local facilityBonuses = FinanceManager.getFacilityBonuses(team)
        return facilityBonuses.youthQuality or 1.0
    end

    function YouthManager._refreshCandidates(gameState)
        local team = gameState:getPlayerTeam()
        if not team then return end

        local facilityYouthBonus = YouthManager._getTeamYouthFacilityBonus(gameState, team.id)

        local candidates = {}
        local usedNames = YouthManager._collectYouthUsedNames(gameState, team.id)

        for _ = 1, YouthManager.YOUTH_POOL_SIZE do
            local candidate = YouthManager._generateYouthPlayer(
                gameState, facilityYouthBonus, usedNames, team.country)
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
    function YouthManager._rollYouthPotential(youthMods, facilityLevel)
        local tier = YouthManager.YOUTH_FACILITY_TIERS[facilityLevel]
            or YouthManager.YOUTH_FACILITY_TIERS[1]
        local potMax = youthMods.potentialMax or 90
        local hi = math.min(tier.potHi, potMax)
        local lo = math.max(40, math.min(tier.potLo, hi - 1))
        local mode = math.max(lo, math.min(tier.potMode, hi))

        local basePotential = _triangular(lo, mode, hi)
        return math.max(40, math.min(99, math.floor(basePotential + 0.5)))
    end

    ---@param overrides table|nil { displayName?: string, nationality?: string }
    function YouthManager._generateYouthPlayer(gameState, facilityYouthBonus, usedNames, teamCountry, targetPosition, overrides)
        overrides = overrides or {}
        facilityYouthBonus = facilityYouthBonus or 1.0
        local position = _normalizeYouthPosition(targetPosition) or _pickWeightedYouthPosition()

        -- 难度修正：青训质量影响年龄和潜力范围
        local youthMods = DifficultySettings.getYouthModifiers()
        local age = randInt(youthMods.minAge, youthMods.maxAge)
        local birthYear = gameState.date.year - age

        local facilityLevel = YouthManager._facilityLevelFromBonus(facilityYouthBonus)
        local tier = YouthManager.YOUTH_FACILITY_TIERS[facilityLevel]

        local potential = YouthManager._rollYouthPotential(youthMods, facilityLevel)

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
            local overall = randInt(overallFloor, overallCap)
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
        if overrides.nationality then
            nationality = Nationality.normalize(overrides.nationality)
        elseif teamCountry == "CHN" then
            if randInt(1, 100) <= 85 then
                nationality = "CHN"
            else
                nationality = YOUTH_NATIONALITIES[randInt(1, #YOUTH_NATIONALITIES)]
            end
        else
            nationality = YOUTH_NATIONALITIES[randInt(1, #YOUTH_NATIONALITIES)]
        end

        local displayName, firstName, lastName
        if overrides.displayName then
            displayName = overrides.displayName
            firstName, lastName = _formatYouthNameFields(displayName)
        else
            displayName = _pickYouthDisplayName(nationality, usedNames)
            firstName, lastName = _formatYouthNameFields(displayName)
        end

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
            speed = baseVal + randInt(-2, 3),
            stamina = baseVal + randInt(-2, 3),
            strength = baseVal + randInt(-2, 3),
            agility = baseVal + randInt(-2, 3),
            passing = baseVal + randInt(-2, 3),
            shooting = baseVal + randInt(-2, 3),
            tackling = baseVal + randInt(-2, 3),
            dribbling = baseVal + randInt(-2, 3),
            defending = baseVal + randInt(-2, 3),
            positioning = baseVal + randInt(-2, 3),
            vision = baseVal + randInt(-2, 3),
            decisions = baseVal + randInt(-2, 3),
            composure = baseVal + randInt(-2, 3),
            aggression = baseVal + randInt(-2, 3),
            teamwork = baseVal + randInt(-2, 3),
            leadership = baseVal + randInt(-2, 3),
            aerial = baseVal + randInt(-2, 3),
            handling = 1,
            reflexes = 1,
        }

        -- 位置专精
        if position == "GK" then
            attrs.handling = baseVal + randInt(2, 5)
            attrs.reflexes = baseVal + randInt(2, 5)
            attrs.positioning = attrs.positioning + randInt(1, 3)
            attrs.composure = attrs.composure + randInt(1, 2)
        elseif position == "CB" then
            attrs.defending = attrs.defending + randInt(2, 4)
            attrs.tackling = attrs.tackling + randInt(2, 4)
            attrs.strength = attrs.strength + randInt(1, 3)
            attrs.aerial = attrs.aerial + randInt(1, 3)
        elseif position == "LB" or position == "RB" then
            attrs.defending = attrs.defending + randInt(1, 3)
            attrs.speed = attrs.speed + randInt(2, 4)
            attrs.stamina = attrs.stamina + randInt(1, 3)
        elseif position == "CDM" then
            attrs.tackling = attrs.tackling + randInt(2, 4)
            attrs.defending = attrs.defending + randInt(1, 3)
            attrs.passing = attrs.passing + randInt(1, 3)
        elseif position == "CM" or position == "CAM" then
            attrs.passing = attrs.passing + randInt(2, 4)
            attrs.vision = attrs.vision + randInt(1, 3)
            attrs.dribbling = attrs.dribbling + randInt(1, 3)
        elseif position == "LM" or position == "RM" then
            attrs.passing = attrs.passing + randInt(1, 3)
            attrs.speed = attrs.speed + randInt(1, 3)
            attrs.stamina = attrs.stamina + randInt(1, 3)
            attrs.dribbling = attrs.dribbling + randInt(1, 2)
            attrs.tackling = attrs.tackling + randInt(0, 2)
        elseif position == "LW" or position == "RW" then
            attrs.speed = attrs.speed + randInt(2, 4)
            attrs.dribbling = attrs.dribbling + randInt(2, 3)
            attrs.agility = attrs.agility + randInt(1, 3)
        elseif position == "ST" then
            attrs.shooting = attrs.shooting + randInt(2, 4)
            attrs.composure = attrs.composure + randInt(1, 3)
            attrs.speed = attrs.speed + randInt(1, 3)
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
            return YouthManager.INITIAL_YOUTH_COUNT
        end

        local ok, RealDataLoader = pcall(require, "scripts/data/real_data_loader")
        if ok and RealDataLoader and RealDataLoader.getTeamLeague then
            local _, leagueKey = RealDataLoader.getTeamLeague(gameState, teamId)
            local league = gameState.leagues and leagueKey and gameState.leagues[leagueKey]
            if league and (league.tier or 1) >= 2 then
                return YouthManager.AI_TIER2_YOUTH_COUNT
            end
        end

        return YouthManager.INITIAL_YOUTH_COUNT
    end

    --- 为单队补齐青训至目标人数（已有 wonderkids 只补差额）
    ---@return number generated
    local function _fillTeamYouthToInitial(gameState, teamId, team)
        team._youthPlayerIds = team._youthPlayerIds or {}
        local target = YouthManager.getAIYouthTarget(gameState, teamId, team)
        local needed = target - #team._youthPlayerIds
        if needed <= 0 then return 0 end

        local generated = 0
        local facilityYouthBonus = YouthManager._getTeamYouthFacilityBonus(gameState, teamId)
        local usedNames = YouthManager._collectYouthUsedNames(gameState, teamId)

        for _ = 1, needed do
            local candidate = YouthManager._generateYouthPlayer(
                gameState, facilityYouthBonus, usedNames, team.country)

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
                wage = YouthManager.YOUTH_WAGE,
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
end
