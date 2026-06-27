#!/usr/bin/env python3
"""Bake Chinese names into second-division JSON (teams + players)."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SECOND = ROOT / "assets" / "Data" / "second"
LOCALIZER = ROOT / "scripts" / "data" / "name_localizer.lua"

SECOND_FILES = [
    "fm2024_championship.json",
    "fm2024_la_liga_2.json",
    "fm2024_serie_b.json",
    "fm2024_bundesliga_2.json",
    "fm2024_ligue_2.json",
]

# Current 90-club roster (includes icon-swap replacements)
TEAM_NAME_CN: dict[str, str] = {
    # Championship
    "blackburn-rovers": "布莱克本流浪者",
    "bristol-city": "布里斯托尔城",
    "cardiff-city": "卡迪夫城",
    "coventry-city": "考文垂城",
    "derby-county": "德比郡",
    "hull-city-afc": "赫尔城",
    "leeds-united": "利兹联",
    "middlesbrough": "米德尔斯堡",
    "millwall": "米尔沃尔",
    "norwich-city": "诺维奇城",
    "birmingham-city": "伯明翰城",
    "preston-north-end": "普雷斯顿北区",
    "queens-park-rangers": "女王公园巡游者",
    "stoke-city": "斯托克城",
    "sunderland-afc": "桑德兰",
    "swansea-city-afc": "斯旺西城",
    "watford": "沃特福德",
    "west-bromwich-albion": "西布罗姆维奇",
    # 2. Bundesliga
    "1-fc-koln": "科隆",
    "hertha-bsc": "柏林赫塔",
    "fc-schalke-04": "沙尔克04",
    "hamburger-sv": "汉堡",
    "hannover-96": "汉诺威96",
    "fortuna-dusseldorf": "杜塞尔多夫",
    "spvgg-greuther-furth": "菲尔特",
    "1-fc-nurnberg": "纽伦堡",
    "karlsruher-sc": "卡尔斯鲁厄",
    "sc-paderborn-07": "帕德博恩",
    "1-fc-magdeburg": "马格德堡",
    "1-fc-kaiserslautern": "凯泽斯劳滕",
    "sv-darmstadt-98": "达姆施塔特98",
    "eintracht-braunschweig": "布伦瑞克",
    "sg-dynamo-dresden": "德累斯顿迪纳摩",
    "dsc-arminia-bielefeld": "比勒费尔德",
    "sc-preussen-munster": "普鲁士明斯特",
    "sv-07-elversberg": "埃尔弗斯贝格",
    # La Liga 2
    "levante-union-deportiva": "莱万特",
    "real-zaragoza": "皇家萨拉戈萨",
    "real-valladolid-club-de-futbol": "皇家巴拉多利德",
    "real-sporting-de-gijon-s-a-d": "希洪竞技",
    "sociedad-deportiva-eibar": "埃瓦尔",
    "real-oviedo": "皇家奥维耶多",
    "elche-club-de-futbol": "埃尔切",
    "albacete-balompie": "阿尔瓦塞特",
    "real-racing-club-de-santander": "桑坦德竞技",
    "ud-las-palmas": "拉斯帕尔马斯",
    "sociedad-deportiva-huesca": "韦斯卡",
    "malaga-cf": "马拉加",
    "futbol-club-andorra": "安道尔FC",
    "rc-deportivo-la-coruna": "拉科鲁尼亚",
    "cd-castellon": "卡斯特利翁",
    "club-deportivo-mirandes": "米兰德斯",
    "cd-leganes": "莱加内斯",
    "granada-cf": "格拉纳达",
    # Ligue 2
    "association-de-la-jeunesse-auxerroise": "欧塞尔",
    "esperance-sportive-troyes-aube-champagne": "特鲁瓦",
    "as-saint-etienne": "圣埃蒂安",
    "amiens-sporting-club-football": "亚眠",
    "fc-nancy": "南锡",
    "rodez-af": "罗德兹",
    "fc-annecy": "阿讷西",
    "grenoble-foot-38": "格勒诺布尔",
    "pau-fc": "波城",
    "fc-de-metz": "梅斯",
    "clermont-foot-63": "克莱蒙",
    "montpellier-hsc": "蒙彼利埃",
    "red-star-fc": "红星",
    "en-avant-guingamp": "甘冈",
    "stade-lavallois-mayenne-fc": "拉瓦勒",
    "sporting-club-de-bastia": "巴斯蒂亚",
    "paris-fc": "巴黎FC",
    "usl-dunkerque": "敦刻尔克",
    # Serie B
    "parma-calcio-1913": "帕尔马",
    "como-1907": "科莫",
    "cremonese": "克雷莫内塞",
    "u-s-citt-di-palermo": "巴勒莫",
    "uc-sampdoria": "桑普多利亚",
    "empoli-fc": "恩波利",
    "modena-fc": "摩德纳",
    "pisa-calcio": "比萨",
    "unione-sportiva-catanzaro-1929": "卡坦扎罗",
    "sudtirol-alto-adige": "南蒂罗尔",
    "carrarese-calcio": "卡拉雷塞",
    "calcio-padova": "帕多瓦",
    "benevento-calcio": "贝内文托",
    "fc-verona": "维罗纳",
    "ascoli-calcio-1898": "阿斯科利",
    "a-c-cesena": "切塞纳",
    "ss-juventus-stabia": "尤文斯塔比亚",
    "venezia-football-club": "威尼斯",
}

TOKEN_CN = {
    "adam": "亚当", "adrian": "阿德里安", "adrián": "阿德里安", "alex": "亚历克斯", "álex": "阿莱士",
    "ander": "安德尔", "andreas": "安德烈亚斯", "andres": "安德烈斯", "andrés": "安德烈斯",
    "angel": "安赫尔", "ángel": "安赫尔", "anthony": "安东尼", "antonio": "安东尼奥",
    "benno": "本诺", "callum": "卡勒姆", "carlos": "卡洛斯", "dani": "达尼", "dejan": "德扬",
    "denis": "丹尼斯", "dennis": "丹尼斯", "dominic": "多米尼克", "dominique": "多米尼克", "edoardo": "爱德华多",
    "enric": "恩里克", "enrico": "恩里科", "eric": "埃里克", "florian": "弗洛里安", "gianluca": "詹卢卡",
    "harry": "哈里", "hayden": "海登", "ivan": "伊万", "iván": "伊万", "jack": "杰克", "jacob": "雅各布",
    "jake": "杰克", "jan": "扬", "jason": "杰森", "joan": "霍安", "joe": "乔", "john": "约翰", "jonas": "约纳斯",
    "jubal": "儒巴尔", "julian": "尤利安", "junior": "儒尼奥尔", "lassine": "拉辛", "leandro": "莱安德罗",
    "leart": "莱亚特", "leopold": "利奥波德", "lewis": "刘易斯", "linton": "林顿", "luca": "卢卡", "marvin": "马文",
    "mark": "马克", "martin": "马丁", "mathias": "马蒂亚斯", "mohammed": "穆罕默德", "nahuel": "纳韦尔",
    "nikola": "尼古拉", "oriol": "奥里奥尔", "pablo": "巴勃罗", "paul": "保罗", "renaud": "雷诺", "rober": "罗伯",
    "roger": "罗杰", "ruben": "鲁本", "rúben": "鲁本", "sam": "萨姆", "sammie": "萨米", "sergio": "塞尔吉奥",
    "simon": "西蒙", "sonny": "桑尼", "stefan": "斯特凡", "steffen": "斯特芬", "thierno": "蒂耶尔诺", "timo": "蒂莫",
    "valentin": "瓦伦丁", "xavier": "哈维尔", "yasser": "亚西尔", "yoan": "约安", "youssouf": "优素福",
    "ayling": "艾林", "cooper": "库珀", "gray": "格雷", "gruev": "格鲁埃夫", "kamara": "卡马拉", "koch": "科赫",
    "llorente": "略伦特", "meslier": "梅利耶", "roca": "罗卡", "sinisterra": "西尼斯特拉", "summerville": "萨默维尔",
    "wober": "沃贝尔", "wöber": "沃贝尔", "schwabe": "施瓦贝", "schwäbe": "施瓦贝", "urbig": "乌尔比希",
    "chabot": "沙博", "hubers": "许贝尔斯", "hübers": "许贝尔斯", "huseinbasic": "侯赛因巴希奇", "huseinbašić": "侯赛因巴希奇",
    "ljubicic": "柳比契奇", "ljubičić": "柳比契奇", "martel": "马特尔", "schmitz": "施密茨", "selke": "塞尔克",
    "thielmann": "蒂尔曼", "tigges": "蒂格斯", "uth": "乌特",
    "bajić": "巴伊奇", "bajic": "巴伊奇", "buckley": "巴克利", "carter": "卡特", "dolan": "多兰", "hyam": "海姆",
    "knight": "奈特", "pickering": "皮克林", "rankin": "兰金", "costello": "科斯特洛", "szmodics": "斯莫迪奇", "travis": "特拉维斯",
    "vale": "维尔", "wahlstedt": "瓦尔施泰特", "wharton": "沃顿",
    "alvarez": "阿尔瓦雷斯", "álvarez": "阿尔瓦雷斯", "bouldini": "布尔迪尼", "brugué": "布鲁格", "bruge": "布鲁格",
    "capa": "卡帕", "cunat": "库尼亚特", "cuñat": "库尼亚特", "femenias": "费梅尼亚斯", "femenías": "费梅尼亚斯",
    "fernandez": "费尔南德斯", "fernández": "费尔南德斯", "fuente": "富恩特", "garcia": "加西亚", "garcía": "加西亚",
    "gomez": "戈麦斯", "gómez": "戈麦斯", "ibanez": "伊巴涅斯", "ibáñez": "伊巴涅斯", "lozano": "洛萨诺",
    "martinez": "马丁内斯", "martínez": "马丁内斯", "munoz": "穆尼奥斯", "muñoz": "穆尼奥斯", "postigo": "波斯蒂戈",
    "rey": "雷伊", "romero": "罗梅罗", "vezo": "韦佐",
    "aye": "阿耶", "ayé": "阿耶", "balde": "巴尔德", "baldé": "巴尔德", "bruus": "布鲁斯", "chavalerin": "沙瓦勒兰",
    "conte": "孔特", "conté": "孔特", "hein": "海因", "joly": "若利", "laiton": "莱顿", "mensah": "门萨", "owusu": "奥乌苏",
    "porozo": "波罗佐", "ripart": "里帕尔", "sakhi": "萨希", "sinayoko": "西纳约科", "ugbo": "乌格博",
    "benedyczak": "贝内迪恰克", "bernabe": "贝尔纳贝", "bernabé": "贝尔纳贝", "bonny": "博尼", "chichizola": "奇奇佐拉",
    "chiara": "基亚拉", "colak": "乔拉克", "čolak": "乔拉克", "corvi": "科尔维", "coulibaly": "库利巴利",
    "delprato": "德尔普拉托", "estevez": "埃斯特维斯", "estévez": "埃斯特维斯", "hernani": "埃尔纳尼", "hernâni": "埃尔纳尼",
    "mihaila": "米哈伊拉", "mihăilă": "米哈伊拉", "partipilo": "帕尔蒂皮洛", "sohm": "索姆", "turk": "图尔克",
    "valenti": "瓦伦蒂", "zagaritis": "扎加里蒂斯",
}

PREFIX_SKIP = {"de", "del", "della", "di", "da", "dos", "das", "van", "von", "la", "le", "el", "al"}

SYLLABLES = [
    ("sch", "施"), ("ch", "奇"), ("sh", "什"), ("th", "特"), ("ph", "夫"), ("son", "森"), ("sen", "森"),
    ("berg", "贝格"), ("man", "曼"), ("al", "阿尔"), ("an", "安"), ("ar", "阿尔"), ("au", "奥"),
    ("ba", "巴"), ("be", "贝"), ("bi", "比"), ("bo", "博"), ("bu", "布"),
    ("ca", "卡"), ("ce", "塞"), ("ci", "奇"), ("co", "科"), ("cu", "库"),
    ("da", "达"), ("de", "德"), ("di", "迪"), ("do", "多"), ("du", "杜"),
    ("fa", "法"), ("fe", "费"), ("fi", "菲"), ("fo", "福"), ("fu", "富"),
    ("ga", "加"), ("ge", "热"), ("gi", "吉"), ("go", "戈"), ("gu", "古"),
    ("ha", "哈"), ("he", "赫"), ("hi", "希"), ("ho", "霍"), ("hu", "胡"),
    ("ja", "雅"), ("je", "杰"), ("ji", "吉"), ("jo", "乔"), ("ju", "朱"),
    ("ka", "卡"), ("ke", "克"), ("ki", "基"), ("ko", "科"), ("ku", "库"),
    ("la", "拉"), ("le", "莱"), ("li", "利"), ("lo", "洛"), ("lu", "卢"),
    ("ma", "马"), ("me", "梅"), ("mi", "米"), ("mo", "莫"), ("mu", "穆"),
    ("na", "纳"), ("ne", "内"), ("ni", "尼"), ("no", "诺"), ("nu", "努"),
    ("pa", "帕"), ("pe", "佩"), ("pi", "皮"), ("po", "波"), ("pu", "普"),
    ("ra", "拉"), ("re", "雷"), ("ri", "里"), ("ro", "罗"), ("ru", "鲁"),
    ("sa", "萨"), ("se", "塞"), ("si", "西"), ("so", "索"), ("su", "苏"),
    ("ta", "塔"), ("te", "特"), ("ti", "蒂"), ("to", "托"), ("tu", "图"),
    ("va", "瓦"), ("ve", "韦"), ("vi", "维"), ("vo", "沃"), ("wa", "瓦"), ("we", "韦"), ("wi", "维"), ("wo", "沃"),
    ("ya", "亚"), ("ye", "耶"), ("yo", "约"), ("yu", "尤"), ("za", "扎"), ("ze", "泽"), ("zi", "齐"), ("zo", "佐"), ("zu", "祖"),
    ("b", "布"), ("c", "克"), ("d", "德"), ("f", "夫"), ("g", "格"), ("h", "赫"), ("j", "杰"), ("k", "克"),
    ("l", "尔"), ("m", "姆"), ("n", "恩"), ("p", "普"), ("r", "尔"), ("s", "斯"), ("t", "特"), ("v", "夫"), ("w", "夫"), ("z", "兹"),
]


def has_chinese(text: str) -> bool:
    if not text:
        return False
    if "·" in text:
        return True
    return bool(re.search(r"[\u4e00-\u9fff]", text))


def normalize_token(token: str) -> str:
    token = token.lower()
    token = re.sub(r"[.,()\[\]{}\"'`’]", "", token)
    return token


def transliterate_unknown(token: str) -> str:
    token = normalize_token(token)
    if not token:
        return ""
    result: list[str] = []
    i = 0
    while i < len(token):
        matched = False
        for pat, text in SYLLABLES:
            if token[i : i + len(pat)] == pat:
                result.append(text)
                i += len(pat)
                matched = True
                break
        if not matched:
            i += 1
    text = "".join(result)
    for a, b in [("尔尔", "尔"), ("斯斯", "斯"), ("恩恩", "恩"), ("特特", "特"), ("德德", "德"), ("克克", "克")]:
        text = text.replace(a, b)
    return text if text else token


def transliterate_part(part: str) -> str:
    chunks: list[str] = []
    for chunk in re.split(r"-", part):
        key = normalize_token(chunk)
        if key and key not in PREFIX_SKIP:
            chunks.append(TOKEN_CN.get(key) or transliterate_unknown(key))
    return "-".join(chunks)


def player_name_cn(full_name: str, fallback: str) -> str:
    if has_chinese(full_name):
        return full_name
    parts: list[str] = []
    for part in full_name.split():
        text = transliterate_part(part)
        if text:
            parts.append(text)
    if len(parts) > 4:
        parts = [parts[0], parts[-3], parts[-2], parts[-1]]
    if not parts:
        return fallback
    return "·".join(parts)


def reorder_team(team: dict) -> dict:
    out: dict = {}
    for key, value in team.items():
        if key == "name_cn":
            continue
        out[key] = value
        if key == "history":
            cn = TEAM_NAME_CN.get(team["id"])
            if cn:
                out["name_cn"] = cn
    if "name_cn" not in out:
        cn = TEAM_NAME_CN.get(team["id"])
        if cn:
            out["name_cn"] = cn
    return out


def reorder_player(player: dict) -> dict:
    out: dict = {}
    for key, value in player.items():
        if key == "full_name_cn":
            continue
        out[key] = value
        if key == "morale_core":
            existing = player.get("full_name_cn")
            if existing and has_chinese(existing):
                out["full_name_cn"] = existing
            else:
                full_name = player.get("full_name") or ""
                match_name = player.get("match_name") or ""
                fallback = match_name if match_name else full_name
                out["full_name_cn"] = player_name_cn(full_name, fallback)
    if "full_name_cn" not in out:
        full_name = player.get("full_name") or ""
        match_name = player.get("match_name") or ""
        fallback = match_name if match_name else full_name
        out["full_name_cn"] = player_name_cn(full_name, fallback)
    return out


def localize_file(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    missing_teams: list[str] = []
    for team in data.get("teams", []):
        tid = team.get("id", "")
        if tid.startswith("fm-"):
            continue
        if tid not in TEAM_NAME_CN:
            missing_teams.append(tid)
    if missing_teams:
        raise SystemExit(f"{path.name}: missing TEAM_NAME_CN for {missing_teams}")

    data["teams"] = [reorder_team(t) for t in data["teams"]]
    data["players"] = [reorder_player(p) for p in data.get("players", [])]
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {
        "file": path.name,
        "teams": len([t for t in data["teams"] if not t["id"].startswith("fm-")]),
        "players": len(data["players"]),
    }


def sync_name_localizer() -> None:
    text = LOCALIZER.read_text(encoding="utf-8")
    lines = ['local TEAM_NAME_CN = {']
    for tid in sorted(TEAM_NAME_CN.keys()):
        lines.append(f'    ["{tid}"] = "{TEAM_NAME_CN[tid]}",')
    lines.append("}")
    new_block = "\n".join(lines)
    updated, n = re.subn(
        r"local TEAM_NAME_CN = \{[\s\S]*?\n\}",
        new_block,
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit("failed to patch name_localizer.lua TEAM_NAME_CN")
    LOCALIZER.write_text(updated, encoding="utf-8")


def main() -> None:
    reports = [localize_file(SECOND / name) for name in SECOND_FILES]
    sync_name_localizer()
    print(json.dumps(reports, ensure_ascii=False, indent=2))
    print(f"TEAM_NAME_CN entries: {len(TEAM_NAME_CN)}")


if __name__ == "__main__":
    main()
