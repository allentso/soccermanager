-- app/constants.lua
-- 全局常量定义

local Constants = {}

-- 游戏版本
Constants.VERSION = "0.1.0"
Constants.SAVE_VERSION = 1

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

-- 年龄范围
Constants.AGE_MIN = 17
Constants.AGE_MAX = 38
Constants.AGE_PEAK_START = 25
Constants.AGE_PEAK_END = 31
Constants.RETIREMENT_MIN_AGE = 33

-- 财务
Constants.WEEKLY_WAGE_MULTIPLIER = 1
Constants.SEASON_END_PRIZE = {500000, 400000, 300000, 200000, 150000}

-- 士气范围
Constants.MORALE_MIN = 0
Constants.MORALE_MAX = 100
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
Constants.COLORS = {
    PRIMARY = {33, 150, 243, 255},
    PRIMARY_DARK = {23, 120, 209, 255},
    SECONDARY = {76, 175, 80, 255},
    ACCENT = {255, 153, 0, 255},
    DANGER = {229, 57, 53, 255},
    WARNING = {255, 194, 8, 255},
    BG_DARK = {18, 23, 38, 255},
    BG_CARD = {28, 36, 56, 255},
    BG_HEADER = {23, 28, 46, 255},
    TEXT_PRIMARY = {255, 255, 255, 255},
    TEXT_SECONDARY = {179, 191, 217, 255},
    TEXT_MUTED = {115, 128, 153, 255},
    BORDER = {51, 61, 89, 255},
    TRANSPARENT = {0, 0, 0, 0},
}

return Constants
