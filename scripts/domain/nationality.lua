-- domain/nationality.lua
-- 球员 nationality 代码规范化（FIFA 三字码 / ISO 码 / 历史别名统一）

local Nationality = {}

-- FIFA 国家代码 → 球员数据 nationality 标准代码
local FIFA_TO_PLAYER_NAT = {
    ALB = "AL", ALG = "DZ", ARG = "AR", AUS = "AU", AUT = "AT", BEL = "BE", BIH = "BA",
    BRA = "BR", CAN = "CA", CHN = "CHN", CIV = "CI", COD = "CD", COL = "CO",
    CPV = "CAP", CRO = "HR", CUW = "CUW", CZE = "CZ", DEN = "DK", ECU = "EC",
    EGY = "EG", ENG = "ENG", ESP = "ES", FRA = "FR", GEO = "GE", GER = "DE",
    GHA = "GH", HAI = "HT", HON = "HN", HUN = "HU", IRN = "IR", IRQ = "IRQ",
    ITA = "IT", JOR = "JOR", JPN = "JP", KOR = "KR", KSA = "KSA", MAR = "MA",
    MEX = "MX", NED = "NL", NOR = "NO", NZL = "NZ", PAN = "PA",
    PAR = "PY", PER = "PE", POL = "PL", POR = "PT", QAT = "QAT",
    ROU = "RO", RSA = "ZA", SCO = "SCO", SEN = "SN", SRB = "RS",
    SUI = "CH", SVK = "SK", SVN = "SI", SWE = "SE",
    TUN = "TN", TUR = "TR", UKR = "UA", URU = "UY", USA = "US", UZB = "UZB",
}

-- 别名 → 标准代码（含青训/旧存档特殊码）
local PLAYER_NAT_ALIASES = {
    CN = "CHN",
    NGA = "NG",
}
for fifaCode, playerNat in pairs(FIFA_TO_PLAYER_NAT) do
    if fifaCode ~= playerNat then
        PLAYER_NAT_ALIASES[fifaCode] = playerNat
    end
end

--- 将 FIFA 国家代码转为球员 nationality 标准代码
function Nationality.toPlayerNat(fifaCode)
    return FIFA_TO_PLAYER_NAT[fifaCode] or fifaCode
end

--- 将任意 nationality 代码规范化为标准代码
function Nationality.normalize(code)
    if not code then return code end
    return PLAYER_NAT_ALIASES[code] or code
end

--- 判断两个 nationality 代码是否指同一国家
function Nationality.matches(playerNat, targetNat)
    return Nationality.normalize(playerNat) == Nationality.normalize(targetNat)
end

return Nationality
