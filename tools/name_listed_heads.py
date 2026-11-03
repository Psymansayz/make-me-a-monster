"""Development tool: puts the NPCs' names in the game (configName, as id.NPC knows them) in place of their ids in
src/data/listed_heads.lua and in AnimationList.headsOnPlayerRig (src/data/animation_list.lua), from the NPCNAMES| lines
the plugin logs. Ids can differ between game builds and between the dev worlds and the live game; the names do not.

On the dev branch, with listed_heads.lua holding ids (as tools/make_heads_list.py writes it): reload the plugin, open its
page, press "Debug: log the listed heads' game names (id.NPC)" (a scan logs them by itself after HEADS|end), paste the
console into a text file and run:
    python tools/name_listed_heads.py <that file>
Then copy both files to main. Needs the lupa package (pip install lupa).
"""
import os
import re
import sys
from lupa import LuaRuntime

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
lines, total, header, problems = {}, None, None, None
for raw in open(sys.argv[1], encoding="utf8", errors="replace"):
    raw = raw.rstrip("\r\n")
    m = re.search(r"NPCNAMES\|(\d+)/(\d+)\|(.*)$", raw)
    if m:
        lines.setdefault(int(m.group(1)), m.group(3))  # (newest first: the first seen is the latest press)
        total = int(m.group(2))
    m = re.search(r"NPCNAMES\|begin\|(\d+) heads, (\d+) lines", raw)
    if m and header is None:
        header = (int(m.group(1)), int(m.group(2)))
missing = [i for i in range(1, (total or 0) + 1) if i not in lines]
if total is None or missing or (header and header[1] != total):
    sys.exit(f"incomplete: {len(lines)} of {total} lines (missing {missing[:10]}...)")

name_of, bad = {}, []
for i in range(1, total + 1):
    for record in lines[i].split("~"):
        npc_id, name = record.split("=", 1)
        if name.startswith("!") or not name:
            bad.append(f"{npc_id}={name}")
        else:
            name_of[int(npc_id)] = name
if header and header[0] != len(name_of) + len(bad):
    sys.exit(f"counts differ: log says {header[0]} heads, parsed {len(name_of) + len(bad)}")

lua = LuaRuntime()


def read(rel):
    return open(os.path.join(root, rel), encoding="utf8").read().replace("\r\n", "\n")


def write(rel, text):
    open(os.path.join(root, rel), "w", encoding="utf8", newline="\r\n").write(text)


def q(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


listed = lua.execute(read("src/data/listed_heads.lua"))
animation_text = read("src/data/animation_list.lua")
rig_match = re.search(r"(    headsOnPlayerRig = \{\n)(.*?)(\n    \},\n)", animation_text, re.S)
rig_ids = [int(x) for x in re.findall(r"\[(\d+)\] = true", rig_match.group(2))]

needed = set(rig_ids)
groups = []
for g in range(1, len(listed["groups"]) + 1):
    group = listed["groups"][g]
    members = []
    for m in range(1, len(group["members"]) + 1):
        member = group["members"][m]
        ids = [member[2][k] for k in range(1, len(member[2]) + 1)]
        if any(isinstance(x, str) for x in ids):
            sys.exit("listed_heads.lua already holds names")
        needed.update(ids)
        members.append((member[1], ids))
    groups.append((group["name"], members))
unnamed = sorted(i for i in needed if i not in name_of)
if unnamed or bad:
    sys.exit(f"no usable name for {len(unnamed)} listed ids {unnamed[:20]}; logged problems: {bad[:20]}")

out = ["-- The NPC heads the plugin lists, saved so that nothing has to be scanned or checked when it runs, each by its name",
       "-- in the game (id.NPC; ids can differ between game builds). NPCs added to the game later are not listed until",
       "-- this file is made again (tools/make_heads_list.py, then tools/name_listed_heads.py).",
       "-- groups = { { name, members = { { member name, { NPC name... } }... } }... }, in the order of the dropdown.",
       "return {", "    groups = {"]
for name, members in groups:
    parts = ", ".join("{ %s, { %s } }" % (q(n), ", ".join(q(name_of[i]) for i in ids)) for n, ids in members)
    out.append("        { name = %s, members = { %s } }," % (q(name), parts))
out += ["    },", "}", ""]
write("src/data/listed_heads.lua", "\n".join(out))

rig_lines = ["        %s," % q(name_of[i]) for i in rig_ids]
animation_text = animation_text.replace(rig_match.group(0),
                                        rig_match.group(1) + "\n".join(rig_lines) + rig_match.group(3))
write("src/data/animation_list.lua", animation_text)
print(f"named: {sum(len(ids) for _, ms in groups for _, ids in ms)} listed heads, {len(rig_ids)} player-rig heads")
