-- data/nation_icon_registry.lua
-- 国家队图标路径解析（assets/image/nation 下的 PNG）

local NationIconRegistry = {}

local ICONS_BY_FIFA_CODE = {
    ALG = "image/nation/Algeria-National-Team-v2019.png",
    ARG = "image/nation/Argentina-National-Team-v2024.png",
    AUS = "image/nation/Australia-National-Team-v2018.png",
    AUT = "image/nation/Austria-National-Team-v2019.png",
    BEL = "image/nation/Belgium-National-Team-v2019.png",
    BIH = "image/nation/Bosnia and Herzegovina national football team-v2013.png",
    BRA = "image/nation/Brazil-National-Team-v2019.png",
    CAN = "image/nation/Canada-national-team-v2009.png",
    CIV = "image/nation/Ivory-Coast-National-Team-v2014.png",
    COD = "image/nation/DR-Congo-National-Team-v2025.png",
    COL = "image/nation/Colombia-National-Team-v2023.png",
    CPV = "image/nation/Cape-Verde-National-Team-v0000.png",
    CRO = "image/nation/Croatia-National-Team-v2014.png",
    CUW = "image/nation/Curacao-National-Team-v0000.png",
    CZE = "image/nation/Czech-National-Football-Team-v2022.png",
    ECU = "image/nation/Ecuador-National-Team-v2020.png",
    EGY = "image/nation/Egypt-National-Team-v1971.png",
    ENG = "image/nation/England-National-Team-v2013.png",
    ESP = "image/nation/Spain-National-Team-v2021.png",
    FRA = "image/nation/France-National-Team-v2024.png",
    GER = "image/nation/Germany-National-Team-v2021.png",
    GHA = "image/nation/Ghana-National-Team-v2001.png",
    HAI = "image/nation/Haiti-National-Team-v0000.png",
    HON = "image/nation/Honduras-National-Team-v2024.png",
    IRN = "image/nation/Iran-National-Team-v1979.png",
    IRQ = "image/nation/Iraq-National-Team-v2021.png",
    JOR = "image/nation/Jordan-National-Team-v2024.png",
    JPN = "image/nation/Japan-National-Team-v2017.png",
    KOR = "image/nation/Korea-National-Team-v2020.png",
    KSA = "image/nation/Saudi-Arabia-National-Team-v2023.png",
    MAR = "image/nation/Morocco-National-Team-v2014.png",
    MEX = "image/nation/Mexico-national-team-v2025.png",
    NED = "image/nation/Netherlands-National-Team-v2014.png",
    NOR = "image/nation/Norway-National-Team-v2015.png",
    NZL = "image/nation/New-Zealand-National-Team-v2022.png",
    PAN = "image/nation/Panama-National-Team-v2024.png",
    PAR = "image/nation/Paraguay-National-Team-v2015.png",
    PER = "image/nation/Peru-National-Team-v2024.png",
    POL = "image/nation/Poland-National-Team-v2024.png",
    POR = "image/nation/Portuguese-National-Team-v1966.png",
    QAT = "image/nation/Qatar-National-Team-v2020.png",
    RSA = "image/nation/South-Africa-National-Team-v2006.png",
    SCO = "image/nation/Scotland-National-Team-v2014.png",
    SEN = "image/nation/Senegal-National-Team-v2016.png",
    SUI = "image/nation/Switzerland-National-Team-v2010.png",
    SWE = "image/nation/Sweden-National-Team-v2017.png",
    TUN = "image/nation/Tunisia-National-Team-v2006.png",
    TUR = "image/nation/Turkey-National-Team-v2010.png",
    URU = "image/nation/Uruguay-National-Team-v2005.png",
    USA = "image/nation/United-States-national-team-v2016.png",
    UZB = "image/nation/Uzbekistan-National-Team-v2017.png",
}

--- 根据 FIFA 国家代码获取国家队图标资源路径
--- @param fifaCode string|nil
--- @return string|nil
function NationIconRegistry.getPathByFifaCode(fifaCode)
    if not fifaCode then return nil end
    return ICONS_BY_FIFA_CODE[fifaCode]
end

return NationIconRegistry
