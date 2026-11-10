"""Development tool: writes src/data/dedicated_animations.lua, the sets of chat animations of races' and characters'
own, and the heads that play each.

The sets (SETS below) are made by hand, from the chat animations the game names (tools/chatprobe.txt: the animation
probe's list) and the heads found by group, name and constant (tools/allnpcs.tsv: every known NPC with its id, name,
constant and blacklist status), keeping only heads in src/data/listed_heads.lua. Run it after
tools/make_listed_groups.py, then copy dedicated_animations.lua to main:
    python tools/make_dedicated.py tools/chatprobe.txt tools/allnpcs.tsv src/data/head_groups.lua
        src/data/dedicated_animations.lua src/data/animation_list.lua
"""
import re, sys
sys.stdout.reconfigure(encoding="utf-8")
probe, allnpcs, headgroups, out, animlist = sys.argv[1:6]
names = [line.split("=", 1)[1].strip() for line in open(probe, encoding="utf-8") if "=" in line]

# Every NPC the plugin knows of: id -> (name, constant, status: listed / bl:blank / bl:identical / bl:manual).
npcs_known = {}
for line in open(allnpcs, encoding="utf-8"):
    i, n, c, s = line.rstrip("\n").split("\t")
    npcs_known[int(i)] = (n, c, s)
by_constant = {c: i for i, (n, c, s) in npcs_known.items()}

# The heads the plugin lists (listed_heads.lua beside head_groups.lua): a set keeps only those, as only they can be
# chosen; the blacklisted copies are left out (user: the debug window that showed them is unlikely to be needed again).
listed_heads_path = headgroups.replace("\\", "/").rsplit("/", 1)[0] + "/listed_heads.lua"
listed_constants = set(re.findall(r'"([A-Z0-9_]+)"', open(listed_heads_path, encoding="utf-8").read()))

# The hand-made groups (by name) and the duplicates (identical heads) of each listed head.
groups_text = open(headgroups, encoding="utf-8").read()
groups, dupes = {}, {}
current = None
section = "groups"
for line in groups_text.splitlines():
    if re.match(r"\s*duplicates = \{", line):
        section = "duplicates"
    m = re.match(r'\s*name = "((?:[^"\\]|\\.)*)",', line)
    if m and section == "groups":
        current = groups.setdefault(m[1], [])
        continue
    m = re.match(r'\s*\{ (\d+), "(?:[^"\\]|\\.)*", "([^"]*)"(?:, (\d+))? \},', line)
    if m:
        if section == "groups" and current is not None:
            current.append(int(m[1]))
        elif section == "duplicates" and m[3]:
            dupes.setdefault(int(m[3]), []).append(int(m[1]))

H = "HUMAN_UPDATE_CHATHEAD_"
HUMAN = {
    "ANGRY": "ANGRY_NORMAL_LEN1", "ANG": "ANGRY_NORMAL_LEN1",
    "BORED": "BORED_LEN1", "CONFUSED": "CONFUSED_LEN1", "CON": "CONFUSED_LEN1",
    "HAPPY": "HAPPY_NORMAL_LEN1", "HAP": "HAPPY_NORMAL_LEN1", "HAPPY_SUBTLE": "HAPPY_SUBTLE_LEN1",
    "IDLE": "NEUTRAL_IDLE", "IDLE2": "NEUTRAL_IDLE", "WEARY_IDLE": "NEUTRAL_IDLE", "IDLE_NO_MOUTH": "NEUTRAL_IDLE",
    "IDLE_NO_SCALE": "NEUTRAL_IDLE", "IDLENEU": "NEUTRAL_IDLE",
    "NEUTRAL": "NEUTRAL_LEN1", "NEU": "NEUTRAL_LEN1", "TALK": "NEUTRAL_TALK", "TALKER": "NEUTRAL_TALK",
    "LAUGH": "LAUGH_NORMAL_LEN_ALL", "EVIL_LAUGH": "EVIL_LAUGH_LEN_ALL",
    "QUIZZICAL": "QUIZZICAL_LEN1", "QUIZICAL": "QUIZZICAL_LEN1", "QUIZ": "QUIZZICAL_LEN1",
    "SAD": "SAD_NORMAL_LEN1", "SAD_SUBTLE": "SAD_SUBTLE_LEN1",
    "SCARED": "FEAR_NORMAL_LEN1", "FEAR": "FEAR_NORMAL_LEN1",
    "SHIFTY": "SHIFTY_LEN1", "SHOCK": "SURPRISED_NORMAL_LEN1", "SHOCKED": "SURPRISED_NORMAL_LEN1",
    "SHOCK_SUBTLE": "SURPRISED_SUBTLE_LEN1", "DRUNK": "DRUNK_LEN_ALL", "CHANT": "CHANT_LEN_ALL",
    "WEAK": "SAD_SUBTLE_LEN1", "CRY": "SAD_EXTREME_LEN1",
}

# The human animation for the same emotion, or "" when there is none (the left head then plays nothing).
def human_for(emotion):
    return H + HUMAN[emotion] if emotion in HUMAN else ""

# (name, animation pattern: group 1 is the emotion, or a whole name; the NPCs shown first, in order;
#  the other matching heads: hand-made groups, a display-name pattern, a constant pattern, an exclusion pattern
#  over name and constant)
SETS = [
    ("Troll", r"TROLL_UPDATE_CHATHEAD_(.+)_LEN\d",
     ["TROLLROMANCE_UG", "TROLL_CHAMPION", "I_TROLL_GUARD", "FRIS_TROLL_KING_TRUE", "TROLL"],
     dict(groups=["Troll"], name=r"\btrolls?\b", exclude=r"POH_SERVANT_MIND_CONTROL_MONKEY_BUTLER")),  # (human anims)
    ("Cat", r"CAT_REWORK_(.+)_WITH_CHAT", ["GROWNCAT", "KITTENPET1", "LAZYCAT", "WILEYCAT"],
     dict(groups=["Cat"], name=r"\b(cat|kitten|kitty)\b", exclude=r"Cat Craft|TRH162_PET_CAT")),
    ("Penguin", r"PENG_CHAT_(.+)", ["PENGUIN", "PENG_GENERIC", "LORE_PENGUIN_1"],
     dict(groups=["Penguin"], name=r"\bpenguins?\b", exclude=r"keeper")),
    # (user: the monkeys and these outliers play the nod and shake as well as the human animations; the pet monkeys
    #  play only their own set, and the rune guardian ARIANE1_RUNE_GUARDIAN not this one)
    ("Nod and shake (Monkey Madness)", r"MONKEY_CHATHEAD_(.+)", ["MM_MONKEY_GUARD", "MM_MONKEY_CHILD", "MONKEY"],
     dict(groups=["Monkey", "Rune Guardians", "Strykewyrm", "Rue", "Sifu", "Vorkath"], alsoHuman=True,
          name=r"\bmonkeys?\b|^(sheep|snail|turkey|(scared |mad )?skavid)$",
          const=r"(JMOD_)?REXKINGS_(MAGIC|MELEE|RANGED)_BOSS|POH_SS_GANODERMIC_RUNT|MALAK|POH_AQUA_SHARK_PET.*"
                r"|MM16_SOCK_PUPPET|LORE_XMAS11_REWARD_TINSEL_SNAKE|THRANTAX|HAUNTEDMINE_BOSS_GHOST"
                r"|MTX_PET_RHINO_WHITE|GOEBIE1_SPIRIT_GUARDIAN|(_100_)?MM_AWOWOGEI_CUTSCENE(_WANDER)?",
          exclude=r"minder|^(LORE_MONKEY|LORE_BABY_MONKEY|HUNTING_BABY_MONKEY|POH_MONKEY)_\d+$"
                  r"|^ARIANE1_RUNE_GUARDIAN$",
          # (monkeys that play only the human animations: user)
          excludeIDs=[4663, 19281, 21088, 22713, 23003, 29490, 29961, 32214,
                      13608, 19282, 22714])),  # (copies of 4663, 19281, 22713 the duplicates don't record)
    # (19036, 19039, 21761, 25853 and Jerrod 20670, 20671 play the human animations, not the werewolf set: user)
    ("Werewolf", r"WEREWOLF_UPDATE_(.+)_CHATHEAD", ["WAA_WEREWOLF_GUARD"],
     dict(groups=["Werewolf"], name=r"\bwerewol(f|ves)\b", excludeIDs=[19036, 19039, 21761, 25853, 20670, 20671])),
    ("Gatekeeper (mindslayer fairy)", r"FAIRY_MINDSLAYER_(.+)_CHAT", ["FAIRY_MINDSLAYER"],
     dict(const=r"FAIRY_MINDSLAYER.*")),
    ("Balance Elemental", r"ELEMENT_OF_BALANCE_CHATHEAD_(.+)", ["LUC2_EOB_MAGIC", "DOM_BALANCE_ELEMENTAL_SAFE"],
     dict(name=r"^balance elemental$")),
    ("Eek the Spider", r"HW09_EEK_CHATHEAD_(.+)", ["HW09_EEK"], dict(const=r"HW09_EEK.*")),
    ("Snowman", r"XMAS_07_SNOWMAN_CHAT_(.+)", ["XMAS07_SNOWMAN_TRADITIONAL", "XMAS07_SNOWMAN_DWARF"],
     dict(groups=["Snowman"], name=r"\bsnowm[ae]n\b",  # (the excluded ones don't play the set: user)
          exclude=r"JMOD_SNOWMAN_LOOTBEAM_TRANSMOG|VIB2_SNOWMAN_HENCHMEN|PENG_SPY_SNOWMAN")),
    ("Seeker (on the stalker creatures)", r"RAND_SEEKER_CHATHEAD_(.+)", ["POH_SEEKER_ADULT"],
     dict(groups=["Stalker creature"], const=r".*SEEKER.*", only=r".*SEEKER.*")),
    ("Muspah (nightmare creature)", r"MAH1_NIGHTMARE_CREATURE_CHATHEAD_(.+)", ["MAH1_NIGHTMARE_CREATURE"],
     dict(const=r"MAH1_NIGHTMARE_CREATURE.*")),  # (only this Muspah and its duplicate: user)
    # (MAH4_ZAROS_CHAT_IDLE works on that head alone, and is the only animation that works on it: user)
    ("Zaros (MAH4_ZAROS_CHAT)", r"(MAH4_ZAROS_CHAT_IDLE)", ["MAH4_ZAROS_CHAT"], dict()),
    ("Valluta (void guardian)", r"VKQ3_GUARDIAN_CHAT_(.+)", ["VKQ3_GUARDIAN"], dict(const=r"VKQ3_GUARDIAN.*")),
    ("Void leech", r"(VKQ2_VOID_PEST_CHAT)", ["VKQ2_PEST_CHATHEAD"], dict(name=r"^void leech$")),
    ("Easter Bunny Jr", r"(EASTER09_BUNNY_JR_TONGUE_CHAT)", ["EASTER09_EBJR", "EASTER09_EBJR_SUITED"],
     dict(name=r"^easter bunny jr$")),
    ("Easter bird", r"(EASTER09_BIRD_SLEEPING_CHAT)", ["EASTER09_BIRD_ASLEEP"], dict(alsoHuman=True)),  # (user)
    ("Elder golem (on Kipple)", r"(QUEST_ELDER_GOLEM_CHAT)", ["EGQ_BIK_GOLEM"], dict(name=r"^kipple$")),
    ("Crawling hand", r"(POH_CHAT_CRAWLING_HAND_TALK)", ["POH_MOUNTED_CRAWLING_HAND"],
     dict(name=r"^crawling hand$", exclude=r"SLAYER_CRAWLING_HAND_1")),  # (a blank head, though blacklisted by hand)
    ("Kklik (fairy dragon)", r"(FAIRY_DRAGON_CHATHEAD)", ["CHICKENQUEST_FAIRY_DRAGON"], dict()),
    ("Insectoid", r"(SCAB_INSECTOID_PRIEST_CRAZY_CHAT)", ["SMKI_SCABARITE"], dict(name=r"\binsectoid\b")),
    ("Talking sack", r"(RAG2_BONE_SACK_CHAT)", ["TALKING_SACK"], dict()),
]
LORE = [
    ("Spirit spider", "ARACHNID", ["LORE_SPIDER"]),
    ("Bloated leech", "BLOATED_LEECH", ["LORE_LEECH"]), ("Chameleon", "CHAMELEON", ["LORE_CHAMELEON_GRASS"]),
    ("Spirit cockatrice", "COCKATRICE", ["LORE_COCKATRICE"]), ("Compost mound", "COMPOST_MOUND", ["LORE_COMPOST_MOUND"]),
    ("Smoke devil", "DUST_DEVIL", ["LORE_DUST_DEVIL"]), ("Giant ent", "ENT", ["LORE_ENT"]),
    ("Fire titan", "FIRE_TITAN", ["LORE_FIRE_TITAN"]), ("Forge regent", "FLAMING_PRINCE", ["LORE_FLAMING_PRINCE"]),
    ("Geyser titan", "GEYSER", ["LORE_GEYSER_TITAN"]), ("Hydra", "HYDRA", ["LORE_HYDRA"]),
    ("Spirit jelly", "JELLY", ["LORE_JELLY"]), ("Karam overlord", "KARAMTHULU", ["LORE_KARAMTHULHU"]),
    ("Lava titan", "LAVA_TITAN", ["LORE_LAVA_TITAN"]), ("Gecko", "LIZARD", ["LORE_GECKO_1", "LORE_BABY_GECKO_1"]),
    ("Monkey (pet)", "MONKEY", ["LORE_MONKEY_1", "LORE_BABY_MONKEY_1"]), ("Spirit mosquito", "MOSQUITO", ["LORE_MOSQUITO"]),
    ("Moss titan", "MOSS_TITAN", ["LORE_MOSS_TITAN"]), ("Obsidian golem", "OBSIDIAN", ["LORE_OBSIDIAN_GOLEM"]),

    ("Albino rat", "RODENT", ["LORE_GIANT_RAT", "LORE_SQUIRREL_1", "LORE_BABY_SQUIRREL_1"]),
    ("Void shifter", "SHIFTER", ["LORE_SHIFTER"]), ("Thorny snail", "SNAIL", ["LORE_SNAIL"]),
    ("Void spinner", "SPINNER", ["LORE_SPINNER"]), ("Swamp titan", "SWAMP_TITAN", ["LORE_SWAMP_TITAN"]),
    ("Titan", "TITAN", ["LORE_STEEL_TITAN", "LORE_ICE_TITAN", "LORE_IRON_TITAN", "LORE_ABYSSAL_TITAN"]),
    ("Spirit Tz-Kih", "TZKIH", ["LORE_TZ_KIH"]), ("Wolf (on Mohegan)", "WOLF", ["WOF51_SPIRIT_WOLF"]),
    # (last: a familiar with animations of its own plays those, not the bird's: user)
    ("Lore bird", "BIRD", ["LORE_BIRD_SARA", "LORE_RAVEN_1"]),
]
# Hand-made groups a familiar's set also plays on (user: the spirit spider's on every spider).
LORE_GROUPS = {"ARACHNID": dict(groups=["Spider"], exclude=r"^(HW09_EEK|SB_.*)$"),  # (those don't play it: user)
                "MONKEY": dict(also=r"(HUNTING_BABY_MONKEY|POH_MONKEY)_\d+"),  # (copies of the pet monkeys)
                # (the hand-made Bird group: the birds the user found play it, without identical copies)
                "BIRD": dict(groups=["Bird"])}
for label, creature, npcs in LORE:
    # The familiar's variants: its constants with a suffix (_COMBAT, _2...), never LORE_WOLF (a human-rig head).
    prefixes = "|".join(re.escape(n.rstrip("_1")) if n.endswith("_1") else re.escape(n) for n in npcs
                        if n.startswith("LORE_"))
    spec = dict(const=r"(" + prefixes + r")(_.*)?") if prefixes else dict(const=r"WOF51_SPIRIT_WOLF.*")
    extra = dict(LORE_GROUPS.get(creature, {}))
    if "also" in extra:
        spec["const"] += "|" + extra.pop("also")
    spec.update(extra)
    SETS.append((label, r"LORE_" + creature + r"_CHAT(?:HEAD)?_(.+)", npcs, spec))

NEVER = {"LORE_WOLF", "LORE_WOLF_COMBAT", "SFA_LORE_WOLF"}  # human-rig heads misnamed as wolves (user)
SKIPPED_ANIMATIONS = {"LORE_WOLF_CHATHEAD_IDLE_NO_SCALE"}  # not to be used (user)

def matching_heads(npcs, spec):
    """The constants to show: the chosen ones first, then every other match in id order, without blank heads."""
    chosen = [c for c in npcs if c not in NEVER]
    ids = set()
    for groupName in spec.get("groups", []):
        for npc_id in groups.get(groupName, []):
            ids.add(npc_id)
    for npc_id, (n, c, s) in npcs_known.items():
        if spec.get("name") and re.search(spec["name"], n, re.I):
            ids.add(npc_id)
        if spec.get("const") and re.fullmatch(spec["const"], c):
            ids.add(npc_id)
    for npc_id in list(ids):
        ids.update(dupes.get(npc_id, []))
    for npc_id in spec.get("excludeIDs", []):  # (by id, with their identical copies)
        ids.discard(npc_id)
        ids.difference_update(dupes.get(npc_id, []))
    exclude, only = spec.get("exclude"), spec.get("only")  # (only: a constant pattern every head must match)
    rest = []
    for npc_id in sorted(ids):
        n, c, s = npcs_known.get(npc_id, ("?", None, "?"))
        if c is None or c == "?" or c in chosen or c in NEVER or s == "bl:blank":
            continue
        if spec.get("noManual") and s == "bl:manual":
            continue
        if exclude and (re.search(exclude, n, re.I) or re.search(exclude, c)):
            continue
        if only and not re.fullmatch(only, c):
            continue
        rest.append(c)
    # The chosen ones stay even when blank: a set whose heads are all blank still has one to show.
    return chosen + rest

def lua(s):
    return '"' + s + '"'

def wrapped(items, indent, width=120):
    lines, line = [], indent
    for item in items:
        piece = item + ","
        if len(line) + len(piece) + 1 > width and line.strip():
            lines.append(line.rstrip())
            line = indent
        line += piece + " "
    if line.strip():
        lines.append(line.rstrip())
    return lines

lines = []
used = set()
model_total = 0

# The emotion of a dedicated animation's token (the part of its name the set's pattern leaves), or None.
DEDICATED_EMOTION = {
    "ANGRY": "ANGRY", "BORED": "BORED", "CONFUSED": "CONFUSED", "HAPPY": "HAPPY", "HAPPY_SUBTLE": "HAPPY",
    "IDLE": "IDLE", "IDLE2": "IDLE", "WEARY_IDLE": "IDLE", "IDLE_NO_MOUTH": "IDLE",
    "NEUTRAL": "NEUTRAL", "TALK": "TALK", "LAUGH": "LAUGH",
    "QUIZZICAL": "QUIZZICAL", "QUIZICAL": "QUIZZICAL", "QUIZ": "QUIZZICAL",
    "SAD": "SAD", "SAD_SUBTLE": "SAD", "SCARED": "SCARED", "SHIFTY": "SHIFTY", "SHOCK": "SHOCK", "SHOCKED": "SHOCK",
    "EASTER09_BIRD_SLEEPING_CHAT": "SLEEPING", "MAH4_ZAROS_CHAT_IDLE": "IDLE",
    "POH_CHAT_CRAWLING_HAND_TALK": "TALK", "VKQ2_VOID_PEST_CHAT": "TALK", "QUEST_ELDER_GOLEM_CHAT": "TALK",
    "RAG2_BONE_SACK_CHAT": "TALK", "FAIRY_DRAGON_CHATHEAD": "TALK", "SCAB_INSECTOID_PRIEST_CRAZY_CHAT": "TALK",
    "EASTER09_BUNNY_JR_TONGUE_CHAT": "TALK",
}
# The listed human animation an emotion goes back to on an ordinary head.
HUMAN_OF_EMOTION = {
    "ANGRY": "ANGRY_NORMAL_LEN1", "BORED": "BORED_LEN1", "CONFUSED": "CONFUSED_LEN1", "HAPPY": "HAPPY_NORMAL_LEN1",
    "IDLE": "NEUTRAL_IDLE", "NEUTRAL": "NEUTRAL_LEN1", "TALK": "NEUTRAL_TALK", "LAUGH": "LAUGH_NORMAL_LEN_ALL",
    "QUIZZICAL": "QUIZZICAL_LEN1", "SAD": "SAD_NORMAL_LEN1", "SCARED": "FEAR_NORMAL_LEN1",
    "SHIFTY": "SHIFTY_LEN1", "SHOCK": "SURPRISED_NORMAL_LEN1", "SLEEPING": "SLEEPING",
}
# Labels of whole-name animations (the rest are labelled by their token).
WHOLE_LABELS = {
    "EASTER09_BIRD_SLEEPING_CHAT": "SLEEPING", "MAH4_ZAROS_CHAT_IDLE": "IDLE", "POH_CHAT_CRAWLING_HAND_TALK": "TALK",
    "VKQ2_VOID_PEST_CHAT": "TALK", "QUEST_ELDER_GOLEM_CHAT": "TALK", "RAG2_BONE_SACK_CHAT": "TALK",
    "FAIRY_DRAGON_CHATHEAD": "TALK", "SCAB_INSECTOID_PRIEST_CRAZY_CHAT": "CRAZY TALK",
    "EASTER09_BUNNY_JR_TONGUE_CHAT": "TONGUE OUT",
}

# The emotion of a listed human (NPC) animation, or None.
def human_emotion(name):
    if name.startswith("SLUG3_HUMAN_CHATHEAD_"):
        return {"FEAR": "SCARED", "HAPPY": "HAPPY"}.get(name.split("_")[3])
    if not name.startswith(H):
        return None
    token = name[len(H):]
    token = re.sub(r"_LEN(_ALL|\d)$", "", token)
    token = re.sub(r"_(SUBTLE|NORMAL|EXTREME)$", "", token)
    return {"ANGRY": "ANGRY", "BORED": "BORED", "CONFUSED": "CONFUSED", "HAPPY": "HAPPY", "NEUTRAL": "NEUTRAL",
            "NEUTRAL_IDLE": "IDLE", "NEUTRAL_TALK": "TALK", "LAUGH": "LAUGH", "EVIL_LAUGH": "LAUGH",
            "QUIZZICAL": "QUIZZICAL", "SAD": "SAD", "FEAR": "SCARED", "SURPRISED": "SHOCK", "SHIFTY": "SHIFTY",
            "SLEEPING": "SLEEPING"}.get(token)

listed_human = re.findall(r'\{ name = "([A-Z0-9_]+)", label', open(animlist, encoding="utf-8").read()
                          .split("player = {")[0])
NEUTRAL_FAMILY = ["NEUTRAL", "IDLE", "TALK"]  # (stand in for each other when a set lacks one)

set_of_head = {}
for label, pattern, npcs, spec in SETS:
    entries = []  # (name, label, emotion)
    for name in names:
        m = re.fullmatch(pattern, name) if name not in SKIPPED_ANIMATIONS else None
        if not m:
            continue
        token = m[1] if m.lastindex else name
        length = re.search(r"_LEN(\d)$", name) or re.search(r"_(\d)$", name)
        token = re.sub(r"_\d$", "", token)
        emotion = DEDICATED_EMOTION.get(token)
        entry_label = WHOLE_LABELS.get(name, token.replace("_", " "))
        entries.append([name, entry_label, emotion, length[1] if length else None])
        used.add(name)
    if not entries:
        print("NO ANIMATIONS:", label)
        continue
    # The lengths of an animation are the same animation (user): the first is listed, the others play as it.
    listed, same_as = {}, []
    for entry in entries:
        if entry[1] in listed:
            same_as.append((entry[0], listed[entry[1]][0]))
        else:
            listed[entry[1]] = entry
    entries = list(listed.values())
    by_emotion = {}
    for name, entry_label, emotion, _ in entries:
        if emotion:
            by_emotion.setdefault(emotion, name)  # (the first: LEN1 or 1)
    default = next((by_emotion[e] for e in ["IDLE", "NEUTRAL", "TALK"] if e in by_emotion), entries[0][0])
    from_human = {}
    for human in listed_human:
        emotion = human_emotion(human)
        target = by_emotion.get(emotion)
        if target is None and emotion in NEUTRAL_FAMILY:
            target = next((by_emotion[e] for e in NEUTRAL_FAMILY if e in by_emotion), None)
        if target is not None and target != default:
            from_human[human] = target
    heads = []
    for head in matching_heads(npcs, spec):
        if head in set_of_head:
            print(f"  head {head} in {set_of_head[head]} and {label}: kept in the first")
        else:
            set_of_head[head] = label
            if head in listed_constants:
                heads.append(head)
    if not heads:
        print(f"{label}: no listed head, left out")
        continue
    model_total += len(heads)
    print(f"{label}: {len(heads)} heads, {len(entries)} animations, {len(from_human)} human pairings")
    lines.append("    {")
    lines.append(f"        name = {lua(label)},")
    if spec.get("alsoHuman"):
        lines.append("        alsoHuman = true,")
    lines.append(f"        default = {lua(default)},")
    lines.append("        heads = {")
    lines.extend(wrapped([lua(h) for h in heads], " " * 12))
    lines.append("        },")
    lines.append("        animations = {")
    for name, entry_label, emotion, _ in entries:
        human = HUMAN_OF_EMOTION.get(emotion)
        human_part = f", {lua(H + human)}" if human else ""
        lines.append(f"            {{ {lua(name)}, {lua(entry_label)}{human_part} }},")
    lines.append("        },")
    if same_as:
        lines.append("        sameAs = {")
        for variant, first in same_as:
            lines.append(f"            {{ {lua(variant)}, {lua(first)} }},")
        lines.append("        },")
    lines.append("        fromHuman = {")
    for human, target in from_human.items():
        lines.append(f"            {{ {lua(human)}, {lua(target)} }},")
    lines.append("        },")
    lines.append("    },")
header = """-- Chat-head animations of a race or character's own, which its heads play in place of the human ones (alsoHuman: as
-- well as them). Each set: name; heads (the names in the game, id.NPC, of listed heads); animations { name, label,
-- the human animation for the same emotion }; fromHuman { human animation, the set's version }, else default;
-- sameAs { another length, the listed animation }. A head in several sets plays the first. Made by
-- tools/make_dedicated.py.
return {
"""
open(out, "w", encoding="utf-8", newline="").write((header + "\n".join(lines) + "\n}\n").replace("\n", "\r\n"))
print(lines.count("    {"), "sets,", len(used), "animations,", model_total, "heads")
