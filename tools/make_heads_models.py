"""Development tool: makes src/data/listed_heads_models.lua (dev branch only) from the MODELS| lines the plugin logs.

The file records, for every listed NPC id, its name, its head's model ids and its constant (id.NPC), so that after a
game update that shifts ids the new ids can be matched to these. To make it: on the dev branch, reload the plugin, open its page, press
"Debug: log the listed heads' names and models", paste the console into a text file and run:
    python tools/make_heads_models.py <that file>
The console keeps only about a thousand lines and shows the newest first: the tool checks every line is there.
"""
import os
import re
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
lines = {}
total = None
header = None
for raw in open(sys.argv[1], encoding="utf8", errors="replace"):
    m = re.search(r"MODELS\|(\d+)/(\d+)\|(.*)$", raw.rstrip("\r\n"))
    if m:
        lines.setdefault(int(m.group(1)), m.group(3))  # (newest first: the first seen is the latest press)
        total = int(m.group(2))
    m = re.search(r"MODELS\|begin\|(\d+) heads, (\d+) lines", raw)
    if m and header is None:
        header = (int(m.group(1)), int(m.group(2)))
missing = [i for i in range(1, (total or 0) + 1) if i not in lines]
if total is None or missing or (header and header[1] != total):
    sys.exit(f"incomplete: {len(lines)} of {total} lines (missing {missing[:10]}...)")

heads = {}
for i in range(1, total + 1):
    for record in lines[i].split("~"):
        npc_id, rest = record.split("=", 1)
        rest, constant = rest.rsplit("@", 1)
        name, models = rest.rsplit(":", 1)
        heads[int(npc_id)] = (name, [int(x) for x in models.split(",") if x], constant)
if header and header[0] != len(heads):
    sys.exit(f"counts differ: log says {header[0]} heads, parsed {len(heads)}")


def q(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


out = ["-- DEVELOPMENT ONLY (dev branch): the name, head model ids and constant (id.NPC) of every listed NPC id, made by",
       "-- tools/make_heads_models.py from the plugin's MODELS| log. The plugin never reads this. If a game update shifts",
       "-- NPC ids, these show where each listed id moved to. { [npc id] = { name, { model id... }, constant } }.",
       "return {"]
for npc_id in sorted(heads):
    name, models, constant = heads[npc_id]
    out.append("    [%d] = { %s, { %s }, %s }," % (npc_id, q(name), ", ".join(map(str, models)), q(constant)))
out += ["}", ""]
path = os.path.join(root, "src", "data", "listed_heads_models.lua")
open(path, "w", encoding="utf8").write("\n".join(out))
print(f"written: {len(heads)} heads to {os.path.relpath(path, root)}")
