"""Development tool: applies the HEADGROUP| and HEADDUPLICATE...| lines the grouping window logs.

Groups go in src/data/head_groups.lua (dev branch only), where the grouping window finds them: it shows one head of
each, of its most common name. A head can be in several groups. A new group holding the shown head of a saved group
joins it. Duplicates go in the blacklist's `identical` group, its names and constants, and leave listed_heads.lua
(copy that file to main) and listed_heads_models.lua. Lines already applied (by their numbers, which the window
continues from the saved file) are skipped, so a paste can overlap the one before.

To use it: on the dev branch, press the window's log buttons, paste the console into a text file and run:
    python tools/apply_grouping_log.py <that file>
then tools/make_listed_groups.py, for the groups the plugin lists.
"""
import collections
import pathlib
import re
import sys

DATA = pathlib.Path(__file__).resolve().parent.parent / "src" / "data"
QUOTED = r'"((?:[^"\\]|\\.)*)"'
RECORD = r"\{ (\d+), " + QUOTED + ", " + QUOTED
# { group name: constant (id.NPC) of the head it shows }, where the most common name is not the head wanted.
SHOWN_BY_HAND = {"Myreque": "ROUTE_VELIAF_HURTZ",
                 "Demon": "GREATER_DEMON",
                 "Mahjarrat": "MAH1_JHALLAN",
                 "Dagannoth Kings": "JMOD_DAGCAVE_MAGIC_BOSS",
                 "Strykewyrm": "STRYKEWYRM_ICE",
                 "TzHaar": "TZHAAR2_MEJ_AK",
                 "Dragon": "BLACK_DRAGON", "Herald": "UPDATE_ANNOUNCER", "Man": "MAKEOVER_MAGE_NPC_MALE",
                 "Razmire": "RAZMIRE_KEELGAN", "Ulsquire": "ULSQUIRE_SHAUNCY",
                 "Woman": "MAKEOVER_MAGE_NPC_FEMALE", "Apmeken": "QUEST_DESERT_FINALE_APMEKEN",
                 "Barrows Brothers": "TOWN_BARROWS_DHAROK_TRANSMOG", "Snow imp": "VIB2_SNOW_IMP_CLAUS",
                 "Skeleton": "CBTV2CA_TRAINING_DUMMY_PUNCHBAG_MELEE", "Witch": "HETTY",
                 "Zanik": "ARCH_PRE_RELEASE_ZANIK", "Zombie": "PIRATEFINALE_ZOMBIE_HEAD",
                 "Akthanakos": "MAH5_WAVE_AKTHANAKOS", "Azzanadra": "MAH5_WAVE_AZZANDRA",
                 "Enakhra": "MAH5_WAVE_ENAKHRA", "General Khazard": "GENERAL_KHAZARD", "Lucien": "LUC2_LUCIEN",
                 "Zemouregal": "SLISKE2_CUTSCENE_FINAL_SLISKE2_ZEMOUREGAL_CUTSCENE", "Ali": "FEUD_ALI_M",
                 "Amascut the Devourer": "JMOD_AMASCUT_EMPOWERED", "Elf": "ME3_STARVING_ELF2",
                 "Goblin high priests": "LOTG_GOBLIN_SKELETON_HIGH_PRIEST1_DEFEATED",
                 "Anima Creature": "SWORLDS_PET_CURRENCY_RANK9", "Assistant Professor": "ARCH_ASSISTANT_ROAMING_1_F",
                 "Fremennik": "VIKING_BRUNDT", "Gorajo": "RAND_LOREMEL_02",
                 "Bear": "LORE_POLAR_BEAR", "Dog": "MYQ3_DOG_STRAY_01",
                 "Troll": "TROLL_SPECTATOR1", "Hat": "JMOD_BLACK_SANTA_TRANSMOG",
                 "Dedicated miner": "M_S_PRE_RELEASE_GOLEM_OUTFIT_M", "Dragonkin": "DINO_BOSS_DRAGONKIN",
                 "Guthix": "TSD_GUTHIX_MORTAL", "Het": "QUEST_DESERT_FINALE_HET", "Highwayman": "HIGHWAYMAN3",
                 "Tribesman": "TBWCU_TRIBESMAN", "Worker": "SHIPYARDWORKER2",
                 "Abyssal": "POH_MOUNTED_ABYSSAL", "Menaphos cats": "MENAPHOS_COLLECTIONS_CAT1",
                 "White knights": "SIR_AMIK_VARZE", "Desertfolk": "AL_SHABIM", "Bunny": "EASTER15_BUNNY", "Moia": "SLISKE2_MOIA_CHILD",
                 "Animal Collector": "POF_CONTRACT_BUYER_SMALL_CHICKEN",
                 "Artifact Collectors": "ARCH_PRE_RELEASE_VELUCIA", "Fair folk": "MTXFAIR17_PORTALS",
                 "Fisherman": "FISHCOMP_FISHERMAN", "Rune Guardians": "MAGICTRAINING_GUARD_ENTRANCE",
                 "Utu": "ARCH_MOONRISE_MANAGER_ADULT", "Vanstrom Klause": "MYQ3_VANSTROM_KLAUSE_HUMAN",
                 "Postie Pete": "POSTBAG_HOST", "Tool leprechaun": "MYARM_LEPRECHAUN",
                 "Tanner": "ADVISOR_VARROCK_TANNERY_SHOPKEEPER", "God Wars generals": "GODWARS_BANDOS_AVATAR",
                 "Hunter": "DINO_HUNTER_MASTER", "Werewolf": "TOWN_DARKMEYER_WEREWOLF_TRANSMOG",
                 "Crab": "LORE_GIANT_CRAB_1", "Knight Ami": "VKQ1_US_AMI", "Knight Bernard": "VKQ1_BERNARD_CUTSCENE",
                 "Knight Diana": "VKQ1_US_AMI_SISTER",
                 "Knights of the Round Table": "SIR_KAY", "Sir Kay": "KR_CAM_KAY",
                 "Cyclops": "ELR1_MINQ_HEAD_CYCLOPS_CREW_1A", "Omen": "SKILLPETS_NECROMANCY",
                 "Summoning familiar": "LORE_TERRORBIRD",
                 "Druid": "TSD_REWARD_GIVER",
                 "Yeti": "XMAS18_QUEST_YETI_FATHER_HOME",
                 "First Tower Wizards": "ARIANE2_UNAIA_SHRINE_ROOM",
                 "Spirit": "FILLIMAN_TARLOCK_NS",
                 "Dwarf Consortium": "RA5_PALACE_CHAOS_DWARF_DIRECTOR_1",
                 "Red Axe Director": "RA5_PALACE_CHAOS_DWARF_DIRECTOR_7",
                 "Ranger": "QUEST_DAUGHTER2_ACT2_MAGEARENA_CLUE3_ACTIVE",
                 "Menaphite citizen": "MENAPHOS_CITY_MERCHANT_FEMALE_ENTERTAINED_03",
                 "Monk": "SHIPMONK2_C",
                 "Menaphite marketeer": "MENAPHOS_THIEF_10",
                 "Saradominist": "_6AWE1_CUTSCENE_B_07_6AWE1_BATTLEFIELD_FOOTSOLDIER_MAGIC_SARA",
                 "Zamorakian": "_6AWE1_BATTLEFIELD_FOOTSOLDIER_RANGED_VAR2_ZAMMY"}


class Group(list):
    """The records of a group, and what the plugin calls it."""
    name = None


def read(name):
    return (DATA / name).read_bytes().decode("utf-8").replace("\r\n", "\n")


def write(name, text):
    (DATA / name).write_bytes(text.replace("\n", "\r\n").encode("utf-8"))


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def parse_records(text):
    records = []
    for piece in text.split("~"):
        match = re.fullmatch(r"(\d+)=(.*)@([^@]*)", piece)
        if match is None:
            sys.exit("Not a head: " + piece)
        records.append((int(match[1]), match[2], match[3]))
    return records


def parse_log(path):
    """{ tag: { number: { line number: (lines in all, records) } } }, and { batch: original head }."""
    parts, originals = {"HEADGROUP": {}, "HEADDUPLICATES": {}}, {}
    for line in pathlib.Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.search(r"(HEADGROUP|HEADDUPLICATES)\|(\d+)\|(\d+)/(\d+)\|(.*)$", line)
        if match:
            number, part, total = int(match[2]), int(match[3]), int(match[4])
            entry = (total, parse_records(match[5]))
            if parts[match[1]].setdefault(number, {}).setdefault(part, entry) != entry:
                sys.exit(f"{match[1]} {number} is logged twice with different heads: a reload reused its number")
        match = re.search(r"HEADDUPLICATEOF\|(\d+)\|(.*)$", line)
        if match:
            original = parse_records(match[2])[0]
            if originals.setdefault(int(match[1]), original) != original:
                sys.exit(f"HEADDUPLICATEOF {match[1]} names two heads: a reload reused its number")
    return parts, originals


def joined(number_parts, tag, number):
    """The records of one group or batch, which must have all its lines."""
    total = next(iter(number_parts.values()))[0]
    if sorted(number_parts) != list(range(1, total + 1)):
        sys.exit(f"{tag} {number} is missing lines: paste it again")
    return [record for part in sorted(number_parts) for record in number_parts[part][1]]


def load_saved():
    if not (DATA / "head_groups.lua").exists():
        return 0, 0, [], []
    text = read("head_groups.lua")
    groups_at, duplicates_at = text.index("    groups = {"), text.index("    duplicates = {")
    groups = []
    for block in re.findall(r"^        \{\n(.*?)^        \},$", text[groups_at:duplicates_at], re.S | re.M):
        group = Group((int(a), unescape(b), unescape(c)) for a, b, c in re.findall(RECORD, block))
        name = re.search(r"^ +name = " + QUOTED + ",$", block, re.M)
        group.name = unescape(name[1]) if name else None
        groups.append(group)
    duplicates = [(int(a), unescape(b), unescape(c), int(d))
                  for a, b, c, d in re.findall(RECORD + r", (\d+) \}", text[duplicates_at:])]
    return (int(re.search(r"groupsLogged = (\d+)", text)[1]), int(re.search(r"batchesLogged = (\d+)", text)[1]),
            groups, duplicates)


def unescape(text):
    return re.sub(r"\\(.)", r"\1", text)


def listed_models():
    """{ id: its model list in any order } from listed_heads_models.lua."""
    rows = re.findall(r"^    \[(\d+)\] = \{ " + QUOTED + r", \{ ([\d, ]*) \}", read("listed_heads_models.lua"), re.M)
    return {int(npc_id): sorted(map(int, re.findall(r"\d+", models))) for npc_id, _, models in rows}


def shown_head_first(group, models, taken=()):
    """The group in id order with the head shown first: a head of the most common name, if one name is the most
    common, with the models most common among that name's heads. Otherwise, or on a tie of models, the lowest id.
    A head in `taken` is passed over while the group has another."""
    group = sorted(group, key=lambda record: record[0])
    names = collections.Counter(record[1] for record in group).most_common(2)
    preferred = []
    if len(names) == 1 or names[0][1] != names[1][1]:
        named = [record for record in group if record[1] == names[0][0]]
        model_counts = collections.Counter(tuple(models[record[0]]) for record in named)
        preferred = sorted(named, key=lambda record: -model_counts[tuple(models[record[0]])])  # (stable: lowest id)
    candidates = preferred + group
    shown = next((record for record in candidates if record[0] not in taken), candidates[0])
    return [shown] + [record for record in group if record != shown]


def head_shown_by_hand(group):
    """The record of the head SHOWN_BY_HAND has for this group, or None."""
    constant = SHOWN_BY_HAND.get(getattr(group, "name", None))
    return next((record for record in group if record[2] == constant), None)


def head_of_group_name(group, taken):
    """A head with the very name of its group, that no other group shows, or None: Goblin shows a Goblin."""
    name = getattr(group, "name", None)
    # (in the group's order: a saved group starts with its head shown, which so stays)
    return next((record for record in group if name is not None and record[0] not in taken
                 and record[1].casefold() == name.casefold()), None)


def with_shown_heads(groups, models):
    """The groups in the order of their shown heads, each named after that head if it has no name. Heads set by hand
    are kept for their groups; then the smallest groups choose first, a head of the group's own name if there is one,
    and no two groups show one head while another can be shown: a head chosen in the window then means one group."""
    taken, done = {record[0] for record in map(head_shown_by_hand, groups) if record}, []
    for group in sorted(groups, key=lambda group: (len(group), sorted(record[0] for record in group))):
        chosen = head_shown_by_hand(group) or head_of_group_name(group, taken)
        ordered = Group([chosen] + [record for record in sorted(group, key=lambda record: record[0])
                                    if record != chosen] if chosen else shown_head_first(group, models, taken))
        ordered.name = getattr(group, "name", None) or ordered[0][1]
        taken.add(ordered[0][0])
        done.append(ordered)
    return sorted(done, key=lambda group: group[0][0])


def save_groups(groups_logged, batches_logged, groups, duplicates):
    lines = [
        "-- DEVELOPMENT ONLY (dev branch): the groups and duplicates made by hand in the grouping window",
        "-- (src/debug/head_grouping_window.lua, tools/apply_grouping_log.py), with names, races and jobs, and same",
        "-- models last. tools/make_listed_groups.py makes the plugin's list from this. The window shows only the",
        "-- first head of each group and goes on from the numbers here. The duplicates are in the blacklist too.",
        "return {",
        f"    groupsLogged = {groups_logged},",
        f"    batchesLogged = {batches_logged},",
        "    -- { { name = what the plugin calls it, { id, name, constant }... }... }: the head shown, then id order.",
        "    -- A head can be in several groups.",
        "    groups = {",
    ]
    for group in groups:
        lines.append("        {")
        lines.append(f"            name = {lua_string(group.name)},")
        lines += [f"            {{ {a}, {lua_string(b)}, {lua_string(c)} }}," for a, b, c in group]
        lines.append("        },")
    lines += ["    },", "    -- { id, name, constant, the id of the head it is a duplicate of }.", "    duplicates = {"]
    lines += [f"        {{ {a}, {lua_string(b)}, {lua_string(c)}, {d} }}," for a, b, c, d in duplicates]
    lines += ["    },", "}", ""]
    write("head_groups.lua", "\n".join(lines))


def identical_block(text):
    """Where the `identical` group's lines start and end in a blacklist file."""
    start = text.index("    identical = {\n") + len("    identical = {\n")
    return start, text.index("    },", start)


def add_to_blacklist(duplicates):
    new_ids = sorted(record[0] for record in duplicates)
    text = read("head_blacklist.lua")
    start, end = identical_block(text)
    ids = sorted({int(number) for number in re.findall(r"\d+", text[start:end])} | set(new_ids))
    rows = ["        " + ", ".join(map(str, ids[i:i + 12])) + ",\n" for i in range(0, len(ids), 12)]
    write("head_blacklist.lua", text[:start] + "".join(rows) + text[end:])

    text = read("head_blacklist_names.lua")
    start, end = identical_block(text)
    names = {int(a): b for a, b in re.findall(r"\[(\d+)\]=" + QUOTED, text[start:end])}
    names.update((record[0], record[1].replace("\\", "\\\\").replace('"', '\\"')) for record in duplicates)
    entries = [f'[{npc_id}]="{names[npc_id]}"' for npc_id in sorted(names)]
    rows = ["        " + ", ".join(entries[i:i + 6]) + ",\n" for i in range(0, len(entries), 6)]
    write("head_blacklist_names.lua", text[:start] + "".join(rows) + text[end:])

    text = read("head_blacklist_constants.lua")
    start, end = identical_block(text)
    constants = dict(re.findall(r"^        \[(\d+)\] = (.*),$", text[start:end], re.M))
    constants.update((str(record[0]), lua_string(record[2])) for record in duplicates)
    rows = [f"        [{npc_id}] = {constants[npc_id]},\n" for npc_id in sorted(constants, key=int)]
    write("head_blacklist_constants.lua", text[:start] + "".join(rows) + text[end:])


def remove_from_lists(duplicates):
    text = read("listed_heads.lua")
    for _, _, constant, *_ in duplicates:
        quoted = lua_string(constant)
        if quoted not in text:
            sys.exit(f"{constant} is not in listed_heads.lua")
        for form in (quoted + ", ", ", " + quoted, quoted):  # (in every group it is in)
            text = text.replace(form, "")
    # A member left empty goes, and a group left empty with it.
    text = re.sub(r"\{ " + QUOTED + r", \{  \} \}(, )?", "", text)
    text = re.sub(r", (\} \} ?,?)$", r" \1", text, flags=re.M)
    text = re.sub(r"^.*members = \{  \} \},\n", "", text, flags=re.M)
    write("listed_heads.lua", text)

    text = read("listed_heads_models.lua")
    for record in duplicates:
        text, count = re.subn(rf"^    \[{record[0]}\] = .*\n", "", text, flags=re.M)
        if count != 1:
            sys.exit(f"{record[0]} is in listed_heads_models.lua {count} times")
    write("listed_heads_models.lua", text)


def main():
    parts, originals = parse_log(sys.argv[1])
    groups_logged, batches_logged, groups, duplicates = load_saved()

    new_duplicates = []
    for batch in sorted(number for number in parts["HEADDUPLICATES"] if number > batches_logged):
        if batch not in originals:
            sys.exit(f"Batch {batch} has no HEADDUPLICATEOF line: paste it again")
        new_duplicates += [(*record, originals[batch][0])
                           for record in joined(parts["HEADDUPLICATES"][batch], "HEADDUPLICATES", batch)]

    new_groups = 0
    for number in sorted(n for n in parts["HEADGROUP"] if n > groups_logged):
        members = joined(parts["HEADGROUP"][number], "HEADGROUP", number)
        ids = {record[0] for record in members}
        # (a head can be in several groups: only a group's shown head, the one the window offers, means that group)
        joining = [group for group in groups if group[0][0] in ids]
        groups = [group for group in groups if group not in joining]
        merged = Group(sorted(set(members).union(*joining), key=lambda record: record[0]))
        merged.name = max(joining, key=len).name if joining else None
        groups.append(merged)
        new_groups += 1

    # An original that is a duplicate itself: the head at the end of the chain. A group keeps no blacklisted head.
    duplicates = duplicates + new_duplicates
    original_of = {record[0]: record[3] for record in duplicates}
    def final(npc_id):
        while npc_id in original_of:
            npc_id = original_of[npc_id]
        return npc_id
    duplicates = sorted(((a, b, c, final(d)) for a, b, c, d in duplicates), key=lambda record: record[0])
    kept = []
    for group in groups:
        left = Group(record for record in group if record[0] not in original_of)
        left.name = group.name
        if left:
            kept.append(left)
    groups = with_shown_heads(kept, listed_models())

    if new_duplicates:
        remove_from_lists(new_duplicates)
        add_to_blacklist(new_duplicates)
    save_groups(max([groups_logged, *parts["HEADGROUP"]]), max([batches_logged, *parts["HEADDUPLICATES"]]),
                groups, duplicates)
    print(f"Applied {new_groups} new groups and {len(new_duplicates)} new duplicates.")
    print(f"Saved: {len(groups)} groups of {sum(map(len, groups))} heads, {len(duplicates)} duplicates.")


if __name__ == "__main__":
    main()
