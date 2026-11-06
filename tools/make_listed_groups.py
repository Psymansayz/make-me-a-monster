"""Development tool: writes src/data/listed_heads.lua, the groups the plugin lists, from src/data/head_groups.lua.

Every head in listed_heads_models.lua is listed: in its groups, or as an entry of its own if it has none. Run it after
tools/apply_grouping_log.py, then copy listed_heads.lua to main:
    python tools/make_listed_groups.py
"""
import pathlib
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from apply_grouping_log import QUOTED, load_saved, lua_string, read, unescape, write  # noqa: E402

HEADER = [
    "-- The NPC heads the plugin lists, saved so that nothing has to be scanned or checked when it runs, each by its",
    "-- name in the game (id.NPC; ids can differ between game builds). Made by tools/make_listed_groups.py.",
    "-- groups = { { name, members = { { member name, { NPC name... } }... } }... }, in the order of the dropdown.",
    "-- The first NPC of a group is the head shown for it. A head can be in several groups.",
]


def repaired(name):
    """The name with the garbling of being saved through a console undone, however many times: "NaÃ¯ve" is "Naïve"."""
    while True:
        try:
            fixed = name.encode("cp1252").decode("utf-8")
        except UnicodeError:
            return name
        if fixed == name:
            return name
        name = fixed


def main():
    record = r"^    \[(\d+)\] = \{ " + QUOTED + r", \{ [\d, ]* \}, " + QUOTED
    rows = re.findall(record, read("listed_heads_models.lua"), re.M)
    heads = {int(npc_id): (repaired(unescape(name)), unescape(constant)) for npc_id, name, constant in rows}
    entries = []
    grouped = set()
    for group in load_saved()[2]:
        ids = [record[0] for record in group]
        grouped.update(ids)
        entries.append((repaired(group.name), ids))
    entries += [(heads[npc_id][0], [npc_id]) for npc_id in heads if npc_id not in grouped]
    entries.sort(key=lambda entry: (min(entry[1]), entry[0]))

    lines = [*HEADER, "return {", "    groups = {"]
    for name, ids in entries:
        members = {}
        for npc_id in ids:
            members.setdefault(heads[npc_id][0], []).append(heads[npc_id][1])
        listed = ", ".join("{ %s, { %s } }" % (lua_string(member), ", ".join(map(lua_string, constants)))
                           for member, constants in members.items())
        lines.append(f"        {{ name = {lua_string(name)}, members = {{ {listed} }} }},")
    lines += ["    },", "}", ""]
    write("listed_heads.lua", "\n".join(lines))
    print(f"Listed {len(entries)} entries: {len(grouped)} heads in {len(entries) - len(heads) + len(grouped)} groups, "
          f"{len(heads) - len(grouped)} on their own.")


if __name__ == "__main__":
    main()
