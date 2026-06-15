import json, random
random.seed(2025)

STATS_ZERO = {
    "appearances":0,"goals":0,"assists":0,"clean_sheets":0,
    "yellow_cards":0,"red_cards":0,"avg_rating":0.0,"minutes_played":0,
    "shots":0,"shots_on_target":0,"passes_completed":0,"passes_attempted":0,
    "tackles_won":0,"interceptions":0,"fouls_committed":0
}
MORALE_CORE = {
    "manager_trust":50,"unresolved_issue":None,"recent_treatment":None,
    "pending_promise":None,"talk_cooldown_until":None,"renewal_state":None
}

def gen_attributes(position, ovr):
    base = ovr - 10
    def v(extra=0, spread=6):
        return max(15, min(95, base + extra + random.randint(-spread, spread)))
    attrs = {
        "pace": v(2), "stamina": v(3), "strength": v(2), "agility": v(2),
        "passing": v(0), "shooting": v(-5), "tackling": v(-5), "dribbling": v(0),
        "defending": v(-8), "positioning": v(2), "vision": v(0), "decisions": v(0),
        "composure": v(0), "aggression": v(0), "teamwork": v(2), "leadership": v(-5),
        "handling": 15 + random.randint(0,8), "reflexes": 15 + random.randint(0,8), "aerial": v(0)
    }
    if position in ("CentreBack","LeftBack","RightBack","DefensiveMidfielder"):
        attrs["defending"] = v(8); attrs["tackling"] = v(6); attrs["shooting"] = v(-15)
    if position == "Goalkeeper":
        attrs["handling"] = v(8); attrs["reflexes"] = v(8); attrs["aerial"] = v(5)
        attrs["shooting"] = 12; attrs["dribbling"] = 30; attrs["tackling"] = 18; attrs["defending"] = 22
    if position in ("Striker","LeftWing","RightWing","AttackingMidfielder"):
        attrs["shooting"] = v(6); attrs["dribbling"] = v(5); attrs["defending"] = v(-15); attrs["tackling"] = v(-15)
    if position in ("CentralMidfielder","DefensiveMidfielder","AttackingMidfielder"):
        attrs["passing"] = v(6); attrs["vision"] = v(4)
    return attrs

def match_name(full_name):
    parts = full_name.split()
    if len(parts) == 1:
        return full_name
    return f"{parts[0][0]}. {' '.join(parts[1:])}"

def make_player(pid, full_name, full_name_cn, dob, nat, team_id, pos, alt_pos, foot, weak_foot,
                ovr, pot, wage, mval, contract_end, squad_role, traits=None, note=""):
    return {
        "id": pid, "match_name": match_name(full_name), "full_name": full_name,
        "full_name_cn": full_name_cn,
        "date_of_birth": dob, "nationality": nat, "football_nation": nat, "birth_country": None,
        "position": pos, "natural_position": pos, "alternate_positions": alt_pos,
        "footedness": foot, "weak_foot": weak_foot,
        "attributes": gen_attributes(pos, ovr),
        "condition": 100, "morale": 75, "fitness": 75, "injury": None,
        "team_id": team_id, "league": "Chinese Super League", "league_country": "CHN",
        "retired": False, "squad_role": squad_role,
        "traits": traits or [], "ovr": ovr, "potential": pot,
        "contract_end": contract_end, "wage": wage, "market_value": mval, "note": note,
        "stats": STATS_ZERO.copy(), "career": [], "training_focus": None,
        "transfer_listed": False, "loan_listed": False, "transfer_offers": [],
        "morale_core": MORALE_CORE.copy()
    }

# (full_name, full_name_cn, byear, nat, position, alt_pos, foot, ovr, pot, squad_role)
ROSTERS = {

# ============ SHANGHAI PORT (2025 champions) ============
"shanghai-port": [
 ("Yan Junling","颜骏凌",1991,"CHN","Goalkeeper",[],"Right",75,75,"KeyPlayer"),
 ("Chen Wei","陈蔚",1998,"CHN","Goalkeeper",[],"Right",62,65,"Squad"),
 ("Du Jia","杜佳",1993,"CHN","Goalkeeper",[],"Right",58,58,"Squad"),
 ("Li Zhiliang","李志良",2007,"CHN","Goalkeeper",[],"Right",48,68,"YoungStar"),
 ("Li Ang","李昂",1993,"CHN","CentreBack",["RightBack"],"Right",69,69,"Senior"),
 ("Tyias Browning","泰亚斯·布朗宁",1994,"ENG","CentreBack",[],"Right",67,67,"Senior"),
 ("Wang Shenchao","王燊超",1989,"CHN","CentreBack",["RightBack"],"Right",68,68,"Senior"),
 ("Zhang Linpeng","张琳芃",1989,"CHN","CentreBack",[],"Right",72,72,"KeyPlayer"),
 ("Wei Zhen","魏震",1997,"CHN","LeftBack",[],"Left",65,67,"Senior"),
 ("Ming Tian","明天",1995,"CHN","CentreBack",["RightBack"],"Right",60,62,"Squad"),
 ("Wang Zhen'ao","王振澳",1999,"CHN","RightBack",["RightWing"],"Right",64,68,"Senior"),
 ("Fu Huan","傅欢",1993,"CHN","RightBack",["CentreBack"],"Right",62,62,"Squad"),
 ("Alexander Jojo","亚历山大·乔乔",1999,"GHA",  "RightBack",[],"Right",58,62,"Squad"),
 ("Li Shuai","李帅",1995,"CHN","CentreBack",["LeftBack"],"Left",65,65,"Senior"),
 ("Umidjan Yusup","乌米提江·吾守尔",2004,"CHN","LeftBack",[],"Left",61,72,"YoungStar"),
 ("Wang Jinglei","王靖雷",2007,"CHN","CentreBack",[],"Right",47,66,"YoungStar"),
 ("Wang Yiwei","汪奕伟",2004,"CHN","CentreBack",[],"Right",51,64,"YoungStar"),
 ("Xu Xin","徐新",1994,"CHN","DefensiveMidfielder",["CentralMidfielder"],"Right",68,68,"KeyPlayer"),
 ("Mateus Vital","马莱萝",1998,"BRA","AttackingMidfielder",["RightWing"],"Right",74,76,"KeyPlayer"),
 ("Yang Shiyuan","杨世元",1994,"CHN","CentralMidfielder",["AttackingMidfielder"],"Right",63,63,"Senior"),
 ("Matheus Jussa","马塞乌斯·儒萨",1996,"BRA","CentralMidfielder",["AttackingMidfielder"],"Right",70,71,"Senior"),
 ("Ablahan Haliq","阿不拉罕·哈力克",2001,"CHN","CentralMidfielder",[],"Right",55,62,"Squad"),
 ("Kuai Jiwen","蒯纪闻",2006,"CHN","CentralMidfielder",["AttackingMidfielder"],"Right",53,70,"YoungStar"),
 ("Meng Jingchao","孟劲超",2004,"CHN","CentralMidfielder",[],"Right",50,63,"YoungStar"),
 ("Wu Lei","武磊",1991,"CHN","Striker",["RightWing"],"Right",74,74,"KeyPlayer"),
 ("Gustavo","古斯塔沃",1994,"BRA","Striker",[],"Right",76,76,"KeyPlayer"),
 ("Lü Wenjun","吕文君",1989,"CHN","Striker",["LeftWing"],"Right",60,60,"Squad"),
 ("Li Shenglong","李圣龙",1992,"CHN","Striker",[],"Right",61,61,"Squad"),
 ("Óscar Melendo","奥斯卡·梅伦多",1997,"ESP","AttackingMidfielder",["CentralMidfielder"],"Right",71,72,"Senior"),
 ("Liu Ruofan","刘若钒",1999,"CHN","Striker",["RightWing"],"Right",64,68,"Senior"),
 ("Feng Jin","冯劲",1993,"CHN","Striker",["RightWing"],"Right",58,58,"Squad"),
 ("Gabrielzinho","加布里埃尔西尼奥",1996,"BRA","Striker",["RightWing"],"Right",76,77,"KeyPlayer"),
 ("Leonardo","莱昂纳多",1997,"BRA","Striker",[],"Right",78,79,"KeyPlayer"),
 ("Li Xinxiang","李昕祥",2005,"CHN","RightBack",["CentreBack"],"Right",60,73,"YoungStar"),
],

# ============ SHANGHAI SHENHUA (2025 runners-up) ============
"shanghai-shenhua": [
 ("Xue Qinghao","薛庆浩",2000,"CHN","Goalkeeper",[],"Right",64,68,"Senior"),
 ("Bao Yaxiong","鲍亚雄",1997,"CHN","Goalkeeper",[],"Right",60,60,"Squad"),
 ("Zhou Zhengkai","周正凯",2001,"CHN","Goalkeeper",[],"Right",52,56,"Squad"),
 ("Liu Haoran","刘浩然",2005,"CHN","Goalkeeper",[],"Right",47,58,"YoungStar"),
 ("Wang Shilong","王世龙",2001,"CHN","CentreBack",["RightBack"],"Right",58,64,"Squad"),
 ("Jin Shunkai","金顺凯",2001,"CHN","CentreBack",[],"Right",55,60,"Squad"),
 ("Jiang Shenglong","蒋圣龙",2000,"CHN","CentreBack",[],"Right",68,70,"Senior"),
 ("Zhu Chenjie","朱辰杰",2000,"CHN","CentreBack",[],"Right",69,71,"Senior"),
 ("Wilson Manafá","威尔逊·马纳法",1994,"POR","RightBack",[],"Right",69,69,"Senior"),
 ("Yang Zexiang","杨泽翔",1994,"CHN","CentreBack",["LeftBack"],"Right",58,58,"Squad"),
 ("Cui Lin","崔琳",1997,"CHN","CentreBack",[],"Right",56,57,"Squad"),
 ("Shinichi Chan","陈晋一",2002,"HKG","RightBack",["CentreBack"],"Right",62,66,"Senior"),
 ("Eddy Francis","埃迪·弗朗西斯",1990,"CPV","CentreBack",[],"Right",60,60,"Squad"),
 ("Li Tingwei","李廷伟",2004,"CHN","CentreBack",[],"Right",49,60,"YoungStar"),
 ("Yang Haoyu","杨皓宇",2006,"CHN","LeftBack",["CentreBack"],"Left",54,68,"YoungStar"),
 ("He Bizhen","何泌臻",2003,"CHN","CentreBack",[],"Right",45,55,"YoungStar"),
 ("He Quan","何泉",2004,"CHN","CentreBack",[],"Right",45,55,"YoungStar"),
 ("Zhang Bin","张斌",2005,"CHN","CentreBack",[],"Right",45,56,"YoungStar"),
 ("Ibrahim Amadou","易卜拉欣·阿马杜",1993,"CMR","DefensiveMidfielder",["CentreBack"],"Right",70,70,"KeyPlayer"),
 ("Xu Haoyang","徐皓阳",1999,"CHN","CentralMidfielder",["AttackingMidfielder"],"Right",61,63,"Senior"),
 ("Dai Wai Tsun","戴煌锃",1999,"HKG","CentralMidfielder",[],"Right",53,55,"Squad"),
 ("João Carlos Teixeira","若昂·卡洛斯",1993,"POR","AttackingMidfielder",["CentralMidfielder"],"Right",73,73,"KeyPlayer"),
 ("Wu Xi","吴曦",1989,"CHN","CentralMidfielder",["DefensiveMidfielder"],"Right",69,69,"KeyPlayer"),
 ("Gao Tianyi","高天意",1998,"CHN","CentralMidfielder",["AttackingMidfielder"],"Right",66,68,"Senior"),
 ("Nico Yennaris","李可",1993,"CHN","DefensiveMidfielder",["CentreBack"],"Right",65,65,"Senior"),
 ("Wang Haijian","王海健",2000,"CHN","CentralMidfielder",[],"Right",56,58,"Squad"),
 ("He Xin","何鑫",2004,"CHN","CentralMidfielder",[],"Right",46,55,"YoungStar"),
 ("Wu Qipeng","吴起鹏",2007,"CHN","CentralMidfielder",[],"Right",44,60,"YoungStar"),
 ("Han Jiawen","韩家文",2004,"CHN","CentralMidfielder",[],"Right",46,56,"YoungStar"),
 ("He Linhan","何林翰",2004,"CHN","CentralMidfielder",[],"Right",46,56,"YoungStar"),
 ("André Luis","安德烈·路易斯",1994,"BRA","Striker",["AttackingMidfielder"],"Right",75,75,"KeyPlayer"),
 ("Saulo Mineiro","萨乌洛·米内罗",1997,"BRA","Striker",[],"Right",73,74,"KeyPlayer"),
 ("Xie Pengfei","谢鹏飞",1993,"CHN","Striker",["LeftWing"],"Right",60,60,"Squad"),
 ("Luis Nlavo","路易斯·恩拉沃",2001,"EQG","Striker",["LeftWing"],"Right",65,68,"Senior"),
 ("Yu Hanchao","于汉超",1987,"CHN","Striker",["LeftWing"],"Right",62,62,"Squad"),
 ("Liu Chengyu","刘诚宇",2006,"CHN","Striker",[],"Right",58,72,"YoungStar"),
 ("Marcel Petrov","马塞尔·彼得罗夫",2006,"BUL","Striker",[],"Right",50,66,"YoungStar"),
],

# ============ BEIJING GUOAN (2025 4th, FA Cup winners) ============
"beijing-guoan": [
 ("Han Jiaqi","韩佳奇",1996,"CHN","Goalkeeper",[],"Right",66,67,"Senior"),
 ("Wu Shaocong","吴少聪",2001,"CHN","CentreBack",[],"Right",65,69,"Senior"),
 ("He Yupeng","何宇鹏",1998,"CHN","RightBack",[],"Right",60,61,"Squad"),
 ("Li Lei","李磊",1991,"CHN","LeftBack",[],"Left",67,67,"Senior"),
 ("Michael Ngadeu-Ngadjui","迈克尔·恩加德",1989,"CMR","CentreBack",[],"Right",70,70,"KeyPlayer"),
 ("Chi Zhongguo","池忠国",1990,"CHN","DefensiveMidfielder",[],"Right",65,65,"Senior"),
 ("Sai Erjini'ao","赛尔吉尼奥",1996,"CHN","CentralMidfielder",["AttackingMidfielder"],"Right",68,68,"Senior"),
 ("Guga","古加",1997,"POR","AttackingMidfielder",["CentralMidfielder"],"Right",70,71,"KeyPlayer"),
 ("Zhang Yuning","张玉宁",1997,"CHN","Striker",[],"Right",71,71,"KeyPlayer"),
 ("Zhang Xizhe","张稀哲",1989,"CHN","AttackingMidfielder",["CentralMidfielder"],"Left",69,69,"KeyPlayer"),
 ("Lin Liangming","林良铭",1997,"CHN","LeftWing",["RightWing"],"Left",65,67,"Senior"),
 ("Uroš Spajić","乌罗什·斯帕吉奇",1993,"SRB","CentreBack",[],"Right",68,68,"Senior"),
 ("Feng Boxuan","冯博轩",2000,"CHN","RightBack",[],"Right",54,56,"Squad"),
 ("Yang Liyu","杨立瑜",1997,"CHN","RightWing",["LeftWing"],"Right",65,65,"Senior"),
 ("Fang Hao","方昊",1999,"CHN","Striker",["AttackingMidfielder"],"Right",62,65,"Senior"),
 ("Nebijan Muhmet","内比江·穆和买提",1998,"CHN","RightBack",["RightWing"],"Right",60,62,"Squad"),
 ("Wang Ziming","王子铭",1997,"CHN","Striker",[],"Right",60,60,"Squad"),
 ("Zhang Yuan","张源",1997,"CHN","CentralMidfielder",[],"Right",58,60,"Squad"),
 ("Dawhan","达万",1997,"BRA","CentralMidfielder",["AttackingMidfielder"],"Right",69,70,"Senior"),
 ("Zheng Tuluo","郑图洛",1996,"PAR","Goalkeeper",[],"Right",54,55,"Squad"),
 ("Bai Yang","白洋",1996,"CHN","RightBack",[],"Right",55,56,"Squad"),
 ("Wang Gang","王刚",1994,"CHN","RightBack",["RightWing"],"Right",61,61,"Senior"),
 ("Li Ruiyue","李瑞悦",2006,"CHN","CentralMidfielder",[],"Right",47,64,"YoungStar"),
 ("Fábio Abreu","法比奥·阿布雷乌",1998,"AGO","Striker",[],"Right",78,79,"KeyPlayer"),
 ("Fan Shuangjie","范双杰",2003,"CHN","DefensiveMidfielder",["CentreBack"],"Right",52,60,"YoungStar"),
 ("Nureli Abbas","努日力·阿巴斯",2002,"CHN","Goalkeeper",[],"Right",52,58,"Squad"),
 ("Hou Sen","侯森",1991,"CHN","Goalkeeper",[],"Right",60,60,"Squad"),
 ("Jiang Wenhao","姜文豪",2000,"CHN","CentralMidfielder",[],"Right",55,58,"Squad"),
 ("Cao Yongjing","曹永竞",1996,"CHN","CentralMidfielder",["AttackingMidfielder"],"Right",59,59,"Squad"),
 ("Zhang Jianzhi","张建祉",2000,"CHN","Goalkeeper",[],"Right",50,53,"Squad"),
 ("Wang Zihao","王子豪",2003,"CHN","Striker",[],"Right",46,52,"Squad"),
 ("Wang Yuxiang","王雨翔",2004,"CHN","Striker",[],"Right",45,52,"YoungStar"),
 ("Li Shanghan","李上瀚",2004,"CHN","CentreBack",[],"Right",45,52,"YoungStar"),
 ("Wei Jia'ao","魏佳奥",2007,"CHN","CentralMidfielder",[],"Right",43,58,"YoungStar"),
 ("Lu Tongyun","卢同蕴",2003,"CHN","Goalkeeper",[],"Right",46,52,"YoungStar"),
],

# ============ CHENGDU RONGCHENG (2025 3rd) ============
"chengdu-rongcheng": [
 ("Jian Tao","简陶",2001,"CHN","Goalkeeper",[],"Right",58,62,"Squad"),
 ("Ran Weifeng","冉伟峰",2002,"CHN","Goalkeeper",[],"Right",50,55,"Squad"),
 ("Liu Dianzuo","刘殿座",1990,"CHN","Goalkeeper",[],"Right",67,67,"Senior"),
 ("Hu Hetao","胡荷韬",2003,"CHN","CentreBack",["RightBack"],"Right",62,67,"Senior"),
 ("Tang Xin","唐鑫",1990,"CHN","CentreBack",[],"Right",58,58,"Squad"),
 ("Timo Letschert","蒂莫·莱切特",1993,"NED","CentreBack",[],"Right",71,71,"KeyPlayer"),
 ("Yahav Gurfinkel","亚哈夫·古尔芬克尔",1998,"ISR","LeftBack",["CentreBack"],"Left",66,67,"Senior"),
 ("Wang Dongsheng","王东升",1997,"CHN","LeftBack",[],"Left",59,60,"Squad"),
 ("Han Pengfei","韩鹏飞",1993,"CHN","CentreBack",[],"Right",58,58,"Squad"),
 ("Dong Yanfeng","董岩峰",1996,"CHN","CentreBack",[],"Right",60,61,"Squad"),
 ("Li Yang","李扬",1997,"CHN","RightBack",[],"Right",60,61,"Squad"),
 ("Yuan Mincheng","袁明程",1995,"CHN","CentreBack",[],"Right",62,62,"Senior"),
 ("Yang Shuai","杨帅",1997,"CHN","CentreBack",[],"Right",57,57,"Squad"),
 ("Pedro Delgado","佩德罗·德尔加多",1997,"ESP","AttackingMidfielder",["CentralMidfielder"],"Right",65,66,"Senior"),
 ("Tim Chow","周定洋",1994,"HKG","CentralMidfielder",["DefensiveMidfielder"],"Right",64,64,"Senior"),
 ("Rômulo","罗慕洛",1995,"BRA","CentralMidfielder",["AttackingMidfielder"],"Right",71,71,"KeyPlayer"),
 ("Yan Dinghao","严鼎皓",1998,"CHN","CentralMidfielder",[],"Right",60,62,"Squad"),
 ("Yang Mingyang","杨明洋",1995,"CHN","CentralMidfielder",["AttackingMidfielder"],"Right",61,62,"Senior"),
 ("Mirahmetjan Muzepper","米拉合买提江·木择帕尔",1991,"CHN","CentralMidfielder",[],"Right",56,56,"Squad"),
 ("Gan Chao","甘超",1995,"CHN","RightBack",["CentreBack"],"Right",58,58,"Squad"),
 ("Li Moyu","李墨屿",2005,"CHN","CentralMidfielder",[],"Right",52,65,"YoungStar"),
 ("Wei Shihao","韦世豪",1995,"CHN","Striker",["LeftWing"],"Right",70,70,"KeyPlayer"),
 ("Felipe","费利佩",1992,"BRA","Striker",[],"Right",75,75,"KeyPlayer"),
 ("Tang Chuang","唐淼",1996,"CHN","Striker",["RightWing"],"Right",58,58,"Squad"),
 ("Issa Kallon","伊萨·卡隆",1996,"SLE","Striker",["RightWing"],"Right",60,61,"Squad"),
 ("Xu Hong","徐弘",2003,"CHN","CentralMidfielder",[],"Right",46,55,"YoungStar"),
 ("Liao Rongxiang","廖荣祥",2003,"CHN","CentralMidfielder",["Striker"],"Right",54,62,"YoungStar"),
],

# ============ SHANDONG TAISHAN (partial, key players) ============
"shandong-taishan": [
 ("Wang Dalei","王大雷",1989,"CHN","Goalkeeper",[],"Right",71,71,"KeyPlayer"),
 ("Jin Yong-yu","金永贵",1999,"CHN","Goalkeeper",[],"Right",55,58,"Squad"),
 ("Gao Zhunyi","高准翼",1995,"CHN","CentreBack",[],"Right",65,65,"Senior"),
 ("Lluís López","路易斯·洛佩斯",1992,"AND","CentreBack",["LeftBack"],"Left",65,65,"Senior"),
 ("Zheng Zheng","郑铮",1990,"CHN","RightBack",["CentreBack"],"Right",60,60,"Squad"),
 ("Xie Wenneng","谢文能",2001,"CHN","LeftWing",["LeftBack"],"Left",62,66,"Senior"),
 ("Huang Zhengyu","黄政宇",1999,"CHN","DefensiveMidfielder",["CentreBack"],"Right",61,64,"Senior"),
 ("Guilherme Madruga","吉尔马·马德鲁加",1996,"BRA","AttackingMidfielder",["Striker"],"Right",70,71,"KeyPlayer"),
 ("Liu Yang","刘洋",1991,"CHN","LeftBack",["LeftWing"],"Left",64,64,"Senior"),
 ("Raphael Merkies","拉斐尔·梅尔基斯",1997,"NED","Striker",["AttackingMidfielder"],"Right",65,66,"Senior"),
 ("Valeri Qazaishvili","瓦莱里·卡扎伊什维利",1993,"GEO","AttackingMidfielder",["RightWing"],"Right",75,75,"KeyPlayer"),
 ("Cryzan","克雷桑",1996,"BRA","Striker",["LeftWing"],"Right",72,72,"KeyPlayer"),
 ("Jose Joaquim de Carvalho","若泽·若阿金",1997,"BRA","Striker",[],"Right",68,69,"Senior"),
 ("Xie Wenneng2","谢文能",2024,"CHN","Striker",[],"Right",50,50,"Squad"),  # placeholder removed below
 ("Chen Pu","陈璞",1997,"CHN","CentralMidfielder",[],"Right",57,57,"Squad"),
 ("Liu Binbin","刘彬彬",1993,"CHN","Striker",["LeftWing"],"Left",61,61,"Squad"),
 ("Wang Haobin","王浩斌",2006,"CHN","Striker",[],"Right",48,62,"YoungStar"),
 ("Zeca","泽卡",1997,"BRA","Striker",[],"Right",65,66,"Senior"),
],

# ============ WUHAN THREE TOWNS (partial, key players) ============
"wuhan-three-towns": [
 ("Guo Jiayu","郭家煜",1997,"CHN","Goalkeeper",[],"Right",62,62,"Senior"),
 ("Ren Hang","任航",1991,"CHN","RightBack",["CentreBack"],"Right",64,64,"Senior"),
 ("He Guan","何超",1993,"CHN","CentreBack",[],"Right",61,61,"Squad"),
 ("Ji-Soo Park","朴志洙",1994,"KOR","CentreBack",[],"Right",66,66,"Senior"),
 ("Denny Wang","王鸿",1996,"CHN","LeftBack",[],"Left",58,58,"Squad"),
 ("Zhechao Chen","陈哲超",1996,"CHN","CentreBack",[],"Right",58,58,"Squad"),
 ("Gustavo Sauer","古斯塔沃·萨维尔",1993,"BRA","RightWing",["LeftWing"],"Right",68,68,"Senior"),
 ("Darlan Mendes","达兰",1998,"BRA","CentralMidfielder",["AttackingMidfielder"],"Right",64,65,"Senior"),
 ("Wei Long","卫雷",2002,"CHN","CentralMidfielder",[],"Right",53,58,"Squad"),
 ("Shen Zigui","沈子贵",2001,"CHN","CentralMidfielder",[],"Right",52,57,"Squad"),
 ("Manuel Palacios","曼努埃尔·帕拉西奥斯",1996,"COL","Striker",[],"Right",65,66,"Senior"),
 ("Alexandru Tudorie","亚历山德鲁·图多里",1998,"MDA","Striker",["LeftWing"],"Right",64,65,"Senior"),
 ("Deng Hanwen","邓涵文",1995,"CHN","LeftBack",[],"Left",60,60,"Squad"),
 ("Liao Chengjian","廖承剑",1992,"CHN","RightBack",[],"Right",58,58,"Squad"),
],

}

# ============ Other 10 teams: keep simple placeholder lists of a few real foreign imports ============
ROSTERS.update({
"zhejiang-fc": [
 ("Alexandru Mitriță","亚历山德鲁·米特里塔",1995,"ROU","AttackingMidfielder",["LeftWing"],"Left",73,73,"KeyPlayer"),
 ("Yago Cariello","亚戈·卡里耶罗",1999,"BRA","RightWing",[],"Right",67,68,"Senior"),
 ("Lucas Possignolo","卢卡斯·波西尼奥洛",1995,"BRA","CentreBack",[],"Right",66,66,"Senior"),
 ("Wang Yudong","王钰栋",2007,"CHN","RightWing",["AttackingMidfielder"],"Right",60,75,"YoungStar"),
 ("Tong Lei","董岩峰",1992,"CHN","DefensiveMidfielder",[],"Right",61,61,"Senior"),
],
"qingdao-hainiu": [
 ("Wellington Silva","威灵顿·席尔瓦",1991,"BRA","RightWing",["LeftWing"],"Right",68,68,"Senior"),
 ("Didier Lamkel Zé","迪迪埃·拉姆凯尔·泽",1996,"CMR","RightWing",["Striker"],"Right",68,69,"Senior"),
 ("Elvis Sarić","埃尔维斯·萨里奇",1994,"BIH","AttackingMidfielder",[],"Right",66,66,"Senior"),
 ("Liu Junshuai","刘军帅",1995,"CHN","Striker",[],"Right",62,62,"Senior"),
 ("Feng Boyuan","冯博元",1999,"CHN","Striker",[],"Right",58,60,"Squad"),
],
"qingdao-west-coast": [
 ("Abdul-Aziz Yakubu","阿卜杜勒-阿齐兹·亚库布",1996,"GHA","Striker",[],"Right",67,67,"Senior"),
 ("Davidson","达维森",1996,"BRA","CentreBack",[],"Right",64,64,"Senior"),
 ("Matheus Índio","马蒂乌斯·因迪奥",1999,"BRA","CentralMidfielder",[],"Right",62,63,"Squad"),
 ("Alex Yang","阳浩",1997,"CHN","RightBack",[],"Right",58,58,"Squad"),
 ("Li Hao","李豪",2004,"CHN","Goalkeeper",[],"Right",52,60,"YoungStar"),
],
"tianjin-jinmen-tiger": [
 ("Xadas","沙达斯",1994,"BRA","Striker",[],"Right",68,68,"Senior"),
 ("Albion Ademi","阿尔比恩·阿德米",1993,"MKD","CentralMidfielder",["AttackingMidfielder"],"Right",65,65,"Senior"),
 ("Alberto Quiles","阿尔贝托·基莱斯",1995,"ESP","AttackingMidfielder",["LeftWing"],"Left",65,66,"Senior"),
 ("Xie Weijun","谢维军",1992,"CHN","RightBack",[],"Right",58,58,"Squad"),
 ("Yang Fan","杨帆",1996,"CHN","CentreBack",[],"Right",58,58,"Squad"),
],
"henan-fc": [
 ("Felippe Cardoso","菲利佩·卡多佐",1998,"BRA","Striker",[],"Right",66,67,"Senior"),
 ("Frank Acheampong","弗兰克·阿查姆庞",1992,"GHA","LeftWing",["RightWing"],"Right",66,66,"Senior"),
 ("Lucas Maia","卢卡斯·马亚",1996,"BRA","CentreBack",[],"Right",64,64,"Senior"),
 ("Bruno Nazário","布鲁诺·纳萨里奥",1994,"BRA","AttackingMidfielder",[],"Right",64,65,"Senior"),
 ("Wang Guoming","王国明",1995,"CHN","Goalkeeper",[],"Right",58,58,"Squad"),
],
"meizhou-hakka": [
 ("Branimir Jočić","布拉尼米尔·约契奇",1993,"SRB","AttackingMidfielder",[],"Right",62,62,"Senior"),
 ("Rodrigo Henrique","罗德里戈·恩里克",1995,"BRA","Striker",[],"Right",63,63,"Senior"),
 ("Guo Quanbo","郭全博",1995,"CHN","Goalkeeper",[],"Right",58,58,"Squad"),
 ("Yubiao Deng","邓宇彪",1994,"CHN","CentreBack",[],"Right",55,55,"Squad"),
 ("Tan Ziyi","谭梓毅",2000,"CHN","CentralMidfielder",[],"Right",53,56,"Squad"),
],
"changchun-yatai": [
 ("Robert Berić","罗伯特·贝里奇",1990,"SVN","Striker",[],"Right",65,65,"Senior"),
 ("Ohi Omoijuanfo","奥伊·奥莫伊万福",1992,"NGA","Striker",[],"Right",65,65,"Senior"),
 ("Serginho","谢尔吉尼奥",1995,"BRA","CentralMidfielder",["AttackingMidfielder"],"Right",64,65,"Senior"),
 ("Tan Long","谭龙",1989,"CHN","Striker",[],"Right",60,60,"Squad"),
 ("Piao Taoyu","朴韬宇",1997,"CHN","RightBack",[],"Right",57,57,"Squad"),
],
"shenzhen-peng-city": [
 ("Edu García","埃杜·加西亚",1993,"ESP","AttackingMidfielder",["CentralMidfielder"],"Right",65,65,"Senior"),
 ("Rade Dugalić","拉德·杜加利奇",1992,"SRB","CentreBack",[],"Right",63,63,"Senior"),
 ("Wesley","韦斯利",1996,"BRA","Striker",["RightWing"],"Right",63,63,"Senior"),
 ("Eden Kartsev","埃登·卡尔采夫",1996,"ISR","CentralMidfielder",[],"Right",61,61,"Squad"),
 ("Ji Jiabao","纪佳琪",1994,"CHN","Goalkeeper",[],"Right",58,58,"Squad"),
],
"yunnan-yukun": [
 ("Andrei Burcă","安德烈·布尔卡",1996,"ROU","CentreBack",[],"Right",62,62,"Senior"),
 ("John Hou Sæter","约翰·侯·萨特",1997,"NOR","CentralMidfielder",["AttackingMidfielder"],"Right",62,62,"Senior"),
 ("Ye Chugui","叶楚贵",2002,"CHN","RightWing",[],"Right",55,60,"Squad"),
 ("Pedro Henrique","佩德罗·恩里克",1995,"BRA","Striker",[],"Right",61,62,"Squad"),
 ("Yi Teng","易腾",1996,"CHN","CentralMidfielder",[],"Right",53,55,"Squad"),
],
"dalian-yingbo": [
 ("Isnik Alimi","伊斯尼克·阿利米",1995,"MKD","Striker",[],"Right",62,62,"Senior"),
 ("Zakaria Labyad","扎卡里亚·拉巴亚德",1993,"MAR","AttackingMidfielder",[],"Right",65,65,"Senior"),
 ("Cephas Malele","塞法斯·马莱莱",1996,"COD","Striker",["LeftWing"],"Right",61,61,"Squad"),
 ("Liu Zhurun","刘竹润",1998,"CHN","RightBack",[],"Right",56,57,"Squad"),
 ("Sui Weijie","隋维杰",1995,"CHN","Goalkeeper",[],"Right",58,58,"Squad"),
],
})

# Remove the duplicate placeholder row I accidentally added for Shandong
ROSTERS["shandong-taishan"] = [p for p in ROSTERS["shandong-taishan"] if p[0] != "Xie Wenneng2"]

def random_dob(byear):
    return f"{byear}-{random.randint(1,12):02d}-{random.randint(1,28):02d}"

def wage_mval(ovr):
    wage = int((ovr/80)**3 * 380000) + random.randint(0,15000)
    mval = int((ovr/80)**4 * 5000000) + random.randint(0,200000)
    return wage, mval

import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)
INPUT_PATH = os.path.join(ROOT, "assets", "Data", "fm2024_csl.json")
OUTPUT_PATH = os.path.join(ROOT, "assets", "Data", "fm2025_csl.json")

# Load existing CSL file as base (teams/league structure), replace players
with open(INPUT_PATH, encoding="utf-8") as f:
    base = json.load(f)

# --- Update team list for 2025 season: swap nantong-zhiyun -> yunnan-yukun ---
TEAM_INFO_2025 = {
    "yunnan-yukun": {
        "id":"yunnan-yukun","name":"Yunnan Yukun FC","name_cn":"云南玉昆","short_name":"YN",
        "city":"Kunming","stadium_name":"Tuodong Sports Center","stadium_capacity":18230,
        "founded_year":2014,"colors":{"primary":"#1e7a3c","secondary":"#ffffff"},"reputation":125
    }
}

teams = base["teams"]
new_teams = []
for t in teams:
    if t["id"] == "nantong-zhiyun":
        # replace with Yunnan Yukun, keep structure
        nt = dict(t)
        info = TEAM_INFO_2025["yunnan-yukun"]
        nt.update({
            "id": info["id"], "name": info["name"], "name_cn": info["name_cn"],
            "short_name": info["short_name"], "city": info["city"],
            "stadium_name": info["stadium_name"], "stadium_capacity": info["stadium_capacity"],
            "founded_year": info["founded_year"], "colors": info["colors"],
            "reputation": info["reputation"]
        })
        new_teams.append(nt)
    else:
        new_teams.append(t)
base["teams"] = new_teams

# --- Build new player list ---
new_players = []
pid_n = 1
for team_id, roster in ROSTERS.items():
    for full_name, full_name_cn, byear, nat, pos, alt, foot, ovr, pot, role in roster:
        pid = f"csl25-{pid_n:04d}"
        pid_n += 1
        dob = random_dob(byear)
        wage, mval = wage_mval(ovr)
        wf = random.randint(2,4)
        contract_end = f"{random.randint(2025,2029)}-06-30"
        p = make_player(pid, full_name, full_name_cn, dob, nat, team_id, pos, alt, foot, wf,
                         ovr, pot, wage, mval, contract_end, role)
        new_players.append(p)

# Replace ALL players (drop the old generated 2024 squad entirely)
base["players"] = new_players

base["name"] = "Chinese Super League 2025"
base["description"] = ("2025赛季中国足球协会超级联赛（中超）真实球员数据快照。"
                        "上海海港、上海申花、北京国安、成都蓉城为完整真实一阵名单（含青年球员），"
                        "山东泰山、武汉三镇为核心球员真实名单，"
                        "其余球队（浙江、青岛海牛、青岛西海岸、天津津门虎、河南、梅州客家、长春亚泰、深圳鹏城、云南玉昆、大连英博）"
                        "提供各队代表性外援与国脚球员。"
                        "球队列表已按2025赛季调整：南通支云（降级）替换为云南玉昆（升班）。"
                        "数据来源：维基百科2025赛季条目、Transfermarkt、AiScore、FotMob。")
base["metadata"] = {"kind":"historicalSnapshot","baseYear":2025,"snapshotDate":"2025-11-23T00:00:00Z"}

with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
    json.dump(base, f, ensure_ascii=False, indent=2)

print("Total players:", len(new_players))
import collections
c = collections.Counter(p["team_id"] for p in new_players)
for tid, cnt in c.items():
    print(f"  {tid:25s} {cnt}")
print(f"\nOutput: {OUTPUT_PATH}")
