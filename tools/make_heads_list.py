"""Development tool: makes src/data/heads.lua from the HEADS| lines the plugin logs after a scan.

To make the list again (new NPCs, new blacklisted heads, changed merging rules): move src/data/heads.lua away,
reload the plugin (prl make_me_a_monster), open its page, wait until "HEADS|end" is logged, paste the console
lines into a text file and run:  python tools/make_heads_list.py <that file>
"""
import os
import re
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
lines = {}
total = None
header = None
for raw in open(sys.argv[1], encoding="utf8", errors="replace"):
    m = re.search(r"HEADS\|(\d+)/(\d+)\|(.*)$", raw.rstrip("\r\n"))
    if m:
        lines[int(m.group(1))] = m.group(3)
        total = int(m.group(2))
    m = re.search(r"HEADS\|begin\|(\d+) entries, (\d+) heads, (\d+) lines", raw)
    if m:
        header = tuple(int(x) for x in m.groups())
missing = [i for i in range(1, (total or 0) + 1) if i not in lines]
if total is None or missing or (header and header[2] != total):
    sys.exit(f"incomplete: {len(lines)} of {total} lines (missing {missing[:10]}...)")

groups = []
for i in range(1, total + 1):
    for record in lines[i].split("~"):
        name, rest = record.split("=", 1)
        members = []
        for member in rest.split(";"):
            mname, ids = member.rsplit(":", 1)
            members.append((mname, [int(x) for x in ids.split(",")]))
        groups.append((name, members))
heads = sum(len(ids) for _, ms in groups for _, ids in ms)
if header and (header[0], header[1]) != (len(groups), heads):
    sys.exit(f"counts differ: log says {header[:2]}, parsed {(len(groups), heads)}")

def q(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'

out = ["-- The NPC heads the plugin lists, saved so that nothing has to be scanned or checked when it runs. NPCs added to",
       "-- the game later are not listed until this file is made again (tools/make_heads_list.py).",
       "-- groups = { { name, members = { { member name, { id... } }... } }... }, in the order of the dropdown.",
       "return {", "    groups = {"]
for name, members in groups:
    parts = ", ".join("{ %s, { %s } }" % (q(n), ", ".join(map(str, ids))) for n, ids in members)
    out.append("        { name = %s, members = { %s } }," % (q(name), parts))
out += ["    },", "}", ""]
open(os.path.join(root, "src", "data", "heads.lua"), "w", encoding="utf8").write("\n".join(out))
print(f"written: {len(groups)} entries, {heads} heads")
