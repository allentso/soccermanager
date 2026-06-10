-- app/constants.lua
-- 全局常量定义

local Constants = {}

-- 游戏版本
Constants.VERSION = "1.3.2"
Constants.SAVE_VERSION = 4

-- 赛季设置
Constants.SEASON_START_MONTH = 8   -- 8月开始
Constants.SEASON_START_DAY = 10
Constants.MATCHES_PER_WEEK = 1     -- 每周一场比赛

-- 球队配置
Constants.SQUAD_SIZE = 22
Constants.GK_COUNT = 2
Constants.DEF_COUNT = 7
Constants.MID_COUNT = 7
Constants.FWD_COUNT = 6
Constants.STAFF_PER_TEAM = 4
Constants.FREE_STAFF_COUNT = 8

-- 球员属性范围
Constants.ATTR_MIN = 1
Constants.ATTR_MAX = 20
Constants.POTENTIAL_MIN = 40
Constants.POTENTIAL_MAX = 99
Constants.ABILITY_MIN = 20
Constants.ABILITY_MAX = 99

-- 巨星溢出机制：PA >= 95 (9.5+) 的球员可突破普通上限
Constants.SUPERSTAR_POTENTIAL_THRESHOLD = 95  -- PA 阈值
Constants.SUPERSTAR_ATTR_MAX = 21             -- 关键属性上限（普通20）
Constants.SUPERSTAR_OVERALL_MAX = 101         -- 总评上限（普通99→实际计算可达~100+）

-- 传奇球员溢出机制：比巨星更高的天花板
Constants.LEGEND_ATTR_MAX = 23                -- 传奇属性上限（巨星21→传奇23）
Constants.LEGEND_OVERALL_MAX = 103            -- 传奇总评上限

-- 士气范围
Constants.MORALE_MIN = 20
Constants.MORALE_MAX = 100

--- 将士气值 clamp 到合法范围 [20, 100]
---@param value number
---@return number
function Constants.clampMorale(value)
    return math.max(Constants.MORALE_MIN, math.min(Constants.MORALE_MAX, value))
end

-- 年龄范围
Constants.AGE_MIN = 17
Constants.AGE_MAX = 38
Constants.AGE_PEAK_START = 25
Constants.AGE_PEAK_END = 31
Constants.RETIREMENT_MIN_AGE = 33

-- 财务
Constants.WEEKLY_WAGE_MULTIPLIER = 1
Constants.SEASON_END_PRIZE = {80000000, 65000000, 55000000, 45000000, 38000000, 32000000, 27000000, 23000000, 20000000, 18000000, 15000000, 13000000, 11000000, 9500000, 8000000, 7000000, 6000000, 5000000, 4000000, 3000000}

-- 士气默认值
Constants.MORALE_DEFAULT = 60

-- 状态范围
Constants.FITNESS_MIN = 0
Constants.FITNESS_MAX = 100
Constants.FITNESS_DEFAULT = 80

-- 训练强度
Constants.TRAINING_INTENSITY = {
    LOW = "low",
    MEDIUM = "medium",
    HIGH = "high"
}

-- 打法
Constants.PLAY_STYLES = {
    "Balanced", "Attacking", "Defensive",
    "Possession", "Counter", "HighPress"
}

-- 打法中文名
Constants.PLAY_STYLE_NAMES = {
    Balanced = "平衡",
    Attacking = "进攻",
    Defensive = "防守",
    Possession = "控球",
    Counter = "反击",
    HighPress = "高压"
}

-- 阵型
Constants.FORMATIONS = {
    "4-4-2", "4-3-3", "3-5-2", "4-2-3-1", "5-3-2", "4-5-1"
}

-- 阵型变体 (每个基础阵型对应多种位置配置)
-- 每个变体：key=唯一标识, name=简称, desc=中文描述, slots=11人位置列表
Constants.FORMATION_VARIANTS = {
    ["4-4-2"] = {
        {
            key = "flat",
            name = "平行中场",
            desc = "两CM平行站位，攻守均衡",
            slots = {"GK", "RB", "CB", "CB", "LB", "RM", "CM", "CM", "LM", "ST", "ST"},
        },
        {
            key = "diamond",
            name = "菱形中场",
            desc = "一CDM一CAM，中路纵深",
            slots = {"GK", "RB", "CB", "CB", "LB", "RM", "CDM", "CAM", "LM", "ST", "ST"},
        },
        {
            key = "hold",
            name = "双后腰",
            desc = "两CDM加固中场防守",
            slots = {"GK", "RB", "CB", "CB", "LB", "RM", "CDM", "CDM", "LM", "ST", "ST"},
        },
    },

    ["4-3-3"] = {
        {
            key = "hold",
            name = "正三角",
            desc = "单CDM双CM，防守稳固",
            slots = {"GK", "RB", "CB", "CB", "LB", "CM", "CDM", "CM", "RW", "ST", "LW"},
        },
        {
            key = "attack",
            name = "倒三角",
            desc = "双CM单CAM，进攻厚度",
            slots = {"GK", "RB", "CB", "CB", "LB", "CM", "CM", "CAM", "RW", "ST", "LW"},
        },
        {
            key = "flat",
            name = "平行三中场",
            desc = "三CM平行，覆盖面广",
            slots = {"GK", "RB", "CB", "CB", "LB", "CM", "CM", "CM", "RW", "ST", "LW"},
        },
    },

    ["3-5-2"] = {
        {
            key = "default",
            name = "经典",
            desc = "单CDM双CM，翼卫拉边",
            slots = {"GK", "CB", "CB", "CB", "RM", "CM", "CDM", "CM", "LM", "ST", "ST"},
        },
        {
            key = "attack",
            name = "进攻",
            desc = "单CDM加CAM，中路进攻",
            slots = {"GK", "CB", "CB", "CB", "RM", "CAM", "CDM", "CM", "LM", "ST", "ST"},
        },
        {
            key = "dhold",
            name = "双后腰",
            desc = "双CDM加固中场，更稳固",
            slots = {"GK", "CB", "CB", "CB", "RM", "CM", "CDM", "CDM", "LM", "ST", "ST"},
        },
    },

    ["4-2-3-1"] = {
        {
            key = "wide",
            name = "宽边锋",
            desc = "RW/LW拉边冲击，经典4231",
            slots = {"GK", "RB", "CB", "CB", "LB", "CDM", "CDM", "CAM", "RW", "LW", "ST"},
        },
        {
            key = "narrow",
            name = "窄前腰",
            desc = "三CAM收窄，中路渗透",
            slots = {"GK", "RB", "CB", "CB", "LB", "CDM", "CDM", "CAM", "CAM", "CAM", "ST"},
        },
        {
            key = "asym",
            name = "不对称",
            desc = "一侧边锋一侧前腰，左右不同",
            slots = {"GK", "RB", "CB", "CB", "LB", "CDM", "CDM", "CAM", "RW", "CAM", "ST"},
        },
    },

    ["5-3-2"] = {
        {
            key = "flat",
            name = "平行中场",
            desc = "三CM平行，攻守均衡",
            slots = {"GK", "RB", "CB", "CB", "CB", "LB", "CM", "CM", "CM", "ST", "ST"},
        },
        {
            key = "hold",
            name = "一后腰",
            desc = "单CDM双CM，稳中求进",
            slots = {"GK", "RB", "CB", "CB", "CB", "LB", "CM", "CDM", "CM", "ST", "ST"},
        },
        {
            key = "attack",
            name = "一前腰",
            desc = "单CAM双CM，支援前场",
            slots = {"GK", "RB", "CB", "CB", "CB", "LB", "CM", "CM", "CAM", "ST", "ST"},
        },
    },

    ["4-5-1"] = {
        {
            key = "default",
            name = "经典",
            desc = "单CDM双CM翼卫，均衡覆盖",
            slots = {"GK", "RB", "CB", "CB", "LB", "RM", "CM", "CDM", "CM", "LM", "ST"},
        },
        {
            key = "diamond",
            name = "菱形中场",
            desc = "CDM+双CM+CAM，中路纵深",
            slots = {"GK", "RB", "CB", "CB", "LB", "RM", "CDM", "CAM", "CM", "LM", "ST"},
        },
        {
            key = "flat",
            name = "五平中场",
            desc = "无后腰全CM，纯平压制",
            slots = {"GK", "RB", "CB", "CB", "LB", "RM", "CM", "CM", "CM", "LM", "ST"},
        },
    },
}

--- 获取指定阵型的默认变体key
function Constants.getDefaultVariant(formation)
    local variants = Constants.FORMATION_VARIANTS[formation]
    if variants and variants[1] then
        return variants[1].key
    end
    return "default"
end

--- 根据阵型和变体key查找变体数据
function Constants.getVariant(formation, variantKey)
    local variants = Constants.FORMATION_VARIANTS[formation]
    if not variants then return nil end
    for _, v in ipairs(variants) do
        if v.key == variantKey then return v end
    end
    return variants[1] -- fallback到第一个
end

-- 位置
Constants.POSITIONS = {
    GK = "GK",
    CB = "CB", LB = "LB", RB = "RB",
    CM = "CM", LM = "LM", RM = "RM", CDM = "CDM", CAM = "CAM",
    LW = "LW", RW = "RW", ST = "ST", CF = "CF"
}

-- 位置中文名
Constants.POSITION_NAMES = {
    GK = "门将", CB = "中卫", LB = "左后卫", RB = "右后卫",
    CM = "中场", LM = "左中场", RM = "右中场",
    CDM = "后腰", CAM = "前腰",
    LW = "左边锋", RW = "右边锋", ST = "前锋", CF = "中锋"
}

-- 位置分类
Constants.POSITION_GROUPS = {
    GK = {"GK"},
    DEF = {"CB", "LB", "RB"},
    MID = {"CM", "LM", "RM", "CDM", "CAM"},
    FWD = {"LW", "RW", "ST", "CF"}
}

-- 球员角色（每个位置的细分职责）
-- 每个角色: key=标识, name=中文名, desc=描述, modifiers=属性加权修正
-- posOffset = {dx, dy}: 球场视图站位偏移(百分比), dx=左右(正=右), dy=前后(正=前)
Constants.POSITION_ROLES = {
    GK = {
        { key = "default",    name = "标准门将",   desc = "均衡扑救与出击" },
        { key = "sweeper",    name = "出击门将",   desc = "积极出击，擅长脚下球",
          modifiers = { speed = 1.2, passing = 1.3, positioning = 0.9 },
          posOffset = {0, 4} },
    },
    CB = {
        { key = "default",    name = "标准中卫",   desc = "均衡防守" },
        { key = "ballPlaying", name = "出球中卫",  desc = "擅长长传转移，参与组织",
          modifiers = { passing = 1.3, vision = 1.2, defending = 0.9 },
          posOffset = {0, 3} },
        { key = "stopper",    name = "盯人中卫",   desc = "激进抢断，硬度拉满",
          modifiers = { tackling = 1.3, strength = 1.2, passing = 0.8 },
          posOffset = {0, 4} },
        { key = "sweeper",    name = "清道夫",     desc = "拖后补位，阅读比赛",
          modifiers = { positioning = 1.3, decisions = 1.2, speed = 1.1, tackling = 0.9 },
          posOffset = {0, -4} },
    },
    RB = {
        { key = "default",    name = "标准边后卫", desc = "攻守均衡" },
        { key = "wingBack",   name = "进攻翼卫",   desc = "频繁前插助攻",
          modifiers = { speed = 1.2, dribbling = 1.2, stamina = 1.1, defending = 0.85 },
          posOffset = {0, 10} },
        { key = "defensive",  name = "防守型边后卫", desc = "专注防守，较少前插",
          modifiers = { tackling = 1.2, positioning = 1.2, dribbling = 0.8 },
          posOffset = {0, -3} },
    },
    LB = {
        { key = "default",    name = "标准边后卫", desc = "攻守均衡" },
        { key = "wingBack",   name = "进攻翼卫",   desc = "频繁前插助攻",
          modifiers = { speed = 1.2, dribbling = 1.2, stamina = 1.1, defending = 0.85 },
          posOffset = {0, 10} },
        { key = "defensive",  name = "防守型边后卫", desc = "专注防守，较少前插",
          modifiers = { tackling = 1.2, positioning = 1.2, dribbling = 0.8 },
          posOffset = {0, -3} },
    },
    CDM = {
        { key = "default",    name = "标准后腰",   desc = "屏障型防守中场" },
        { key = "anchor",     name = "扫荡型后腰", desc = "站位稳固，拦截覆盖",
          modifiers = { positioning = 1.3, tackling = 1.2, passing = 0.9 },
          posOffset = {0, -4} },
        { key = "deepLying",  name = "组织型后腰", desc = "拖后出球，节奏控制",
          modifiers = { passing = 1.3, vision = 1.3, tackling = 0.85 },
          posOffset = {0, 3} },
    },
    CM = {
        { key = "default",    name = "标准中场",   desc = "攻守均衡" },
        { key = "boxToBox",   name = "B2B中场",    desc = "大范围跑动，攻守兼备",
          modifiers = { stamina = 1.3, speed = 1.1, tackling = 1.1, shooting = 1.1 },
          posOffset = {0, 0} },
        { key = "deepLying",  name = "深层组织者", desc = "拖后出球，控制节奏",
          modifiers = { passing = 1.3, vision = 1.2, decisions = 1.1, speed = 0.9 },
          posOffset = {0, -6} },
        { key = "advanced",   name = "前插中场",   desc = "频繁插上，支援前场",
          modifiers = { shooting = 1.2, composure = 1.2, speed = 1.1, defending = 0.8 },
          posOffset = {0, 8} },
    },
    CAM = {
        { key = "default",    name = "标准前腰",   desc = "创造力核心" },
        { key = "shadow",     name = "影子前锋",   desc = "隐蔽跑位，致命一击",
          modifiers = { shooting = 1.3, composure = 1.2, passing = 0.85 },
          posOffset = {0, 7} },
        { key = "playmaker",  name = "古典前腰",   desc = "持球组织，最后一传",
          modifiers = { passing = 1.3, vision = 1.3, dribbling = 1.1, speed = 0.85 },
          posOffset = {0, -4} },
    },
    RM = {
        { key = "default",    name = "标准右中场", desc = "攻守兼备" },
        { key = "winger",     name = "边路突击手", desc = "贴边快速突破",
          modifiers = { speed = 1.3, dribbling = 1.2, defending = 0.8 },
          posOffset = {4, 7} },
        { key = "wide",       name = "宽幅中场",   desc = "拉边接应，传中为主",
          modifiers = { passing = 1.2, stamina = 1.2, shooting = 0.85 },
          posOffset = {5, 0} },
    },
    LM = {
        { key = "default",    name = "标准左中场", desc = "攻守兼备" },
        { key = "winger",     name = "边路突击手", desc = "贴边快速突破",
          modifiers = { speed = 1.3, dribbling = 1.2, defending = 0.8 },
          posOffset = {-4, 7} },
        { key = "wide",       name = "宽幅中场",   desc = "拉边接应，传中为主",
          modifiers = { passing = 1.2, stamina = 1.2, shooting = 0.85 },
          posOffset = {-5, 0} },
    },
    RW = {
        { key = "default",    name = "标准右边锋", desc = "突破与射门兼具" },
        { key = "inverted",   name = "内切射手",   desc = "内切到中路射门",
          modifiers = { shooting = 1.3, composure = 1.2, dribbling = 1.1, passing = 0.85 },
          posOffset = {-8, -2} },
        { key = "touchline",  name = "贴边边锋",   desc = "走外线传中",
          modifiers = { speed = 1.3, passing = 1.2, shooting = 0.8 },
          posOffset = {4, 0} },
    },
    LW = {
        { key = "default",    name = "标准左边锋", desc = "突破与射门兼具" },
        { key = "inverted",   name = "内切射手",   desc = "内切到中路射门",
          modifiers = { shooting = 1.3, composure = 1.2, dribbling = 1.1, passing = 0.85 },
          posOffset = {8, -2} },
        { key = "touchline",  name = "贴边边锋",   desc = "走外线传中",
          modifiers = { speed = 1.3, passing = 1.2, shooting = 0.8 },
          posOffset = {-4, 0} },
    },
    ST = {
        { key = "default",    name = "标准前锋",   desc = "全能射手" },
        { key = "poacher",    name = "禁区猎手",   desc = "专注射门得分",
          modifiers = { composure = 1.3, shooting = 1.2, passing = 0.7, defending = 0.5 },
          posOffset = {0, 5} },
        { key = "targetMan",  name = "支点前锋",   desc = "背身做球，策应队友",
          modifiers = { strength = 1.3, heading = 1.2, passing = 1.1, speed = 0.85 },
          posOffset = {0, -4} },
        { key = "falseNine",  name = "伪九号",     desc = "回撤组织，拉扯空间",
          modifiers = { passing = 1.3, vision = 1.2, dribbling = 1.1, shooting = 0.85 },
          posOffset = {0, -10} },
    },
    CF = {
        { key = "default",    name = "标准中锋",   desc = "禁区终结者" },
        { key = "poacher",    name = "禁区猎手",   desc = "专注射门得分",
          modifiers = { composure = 1.3, shooting = 1.2, passing = 0.7, defending = 0.5 },
          posOffset = {0, 5} },
        { key = "targetMan",  name = "支点前锋",   desc = "背身做球，策应队友",
          modifiers = { strength = 1.3, heading = 1.2, passing = 1.1, speed = 0.85 },
          posOffset = {0, -4} },
    },
}

--- 根据位置和角色key查找角色数据
function Constants.getPositionRole(position, roleKey)
    local roles = Constants.POSITION_ROLES[position]
    if not roles then return nil end
    if not roleKey or roleKey == "default" then return roles[1] end
    for _, r in ipairs(roles) do
        if r.key == roleKey then return r end
    end
    return roles[1]
end

-- 职员角色
Constants.STAFF_ROLES = {
    ASSISTANT = "assistant",
    COACH = "coach",
    SCOUT = "scout",
    PHYSIO = "physio"
}

Constants.STAFF_ROLE_NAMES = {
    assistant = "助理教练",
    coach = "教练",
    scout = "球探",
    physio = "理疗师"
}

-- 消息分类
Constants.MESSAGE_CATEGORIES = {
    "welcome", "league", "pre_match", "match_result",
    "training", "board", "job", "finance",
    "transfer", "injury", "contract", "scout",
    "media", "system"
}

-- 存档槽
Constants.MAX_SAVE_SLOTS = 3

-- UI颜色主题 (RGBA 0-255数组格式)
-- 设计语言：深蓝黑底 + 语义色高亮 + 层级区分
Constants.COLORS = {
    -- 品牌/主色
    PRIMARY = {62, 166, 255, 255},       -- #3EA6FF 信息蓝
    PRIMARY_DARK = {34, 128, 220, 255},
    SECONDARY = {76, 175, 80, 255},      -- #4CAF50 财务绿/成功
    ACCENT = {212, 175, 55, 255},        -- #D4AF37 冠军金/焦点

    -- 金色主题色（冠军调性）
    GOLD = {212, 175, 55, 255},          -- #D4AF37 主金色
    GOLD_LIGHT = {241, 212, 109, 255},   -- #F1D46D 浅金色
    GOLD_DIM = {160, 130, 40, 255},      -- #A08228 暗金色

    -- 语义色
    MATCH_ORANGE = {255, 176, 32, 255},  -- #FFB020 比赛/赛事
    FINANCE_GREEN = {76, 175, 80, 255},  -- #4CAF50 财务/收入/成功
    DANGER = {255, 82, 82, 255},         -- #FF5252 危险/伤病/亏损
    WARNING = {255, 194, 8, 255},        -- #FFC208 警告/注意
    INFO_BLUE = {62, 166, 255, 255},     -- #3EA6FF 信息/普通

    -- 背景层级（由深到浅）
    BG_DARK = {10, 14, 24, 255},         -- #0A0E18 最深底色（更深）
    BG_CARD = {16, 22, 36, 255},         -- #101624 普通卡片
    BG_CARD_ELEVATED = {22, 30, 48, 255},-- #161E30 高亮卡片/Hero区
    BG_HEADER = {12, 16, 28, 255},       -- #0C101C 导航栏
    BG_SURFACE = {26, 34, 52, 255},      -- #1A2234 按钮/pill底色

    -- 文字
    TEXT_PRIMARY = {255, 255, 255, 255},
    TEXT_SECONDARY = {170, 184, 212, 255},-- 略暖的次要文字
    TEXT_MUTED = {105, 120, 148, 255},

    -- 边框/分割
    BORDER = {32, 42, 64, 255},          -- 更细微的分隔
    BORDER_LIGHT = {44, 56, 82, 255},

    TRANSPARENT = {0, 0, 0, 0},
}

return Constants
