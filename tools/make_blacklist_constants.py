"""Development tool: makes src/data/head_blacklist_constants.lua (dev branch only) from the BLACKCONST| lines the plugin
logs, so that the blacklist's ids (src/data/head_blacklist.lua) have their constants (id.NPC) on record: if ids shift
in a game update, the constants show where each id moved to.

On the dev branch: reload the plugin, open its page and press "Debug: log the blacklisted heads' constants (next page)"
until it says all is logged, pasting the console into one text file after each press (add to it, do not replace it).
Then run:  python tools/make_blacklist_constants.py <that file>
Needs the lupa package (pip install lupa).
"""
import os
import re
import sys
from lupa import LuaRuntime

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
lines, total = {}, None
for raw in open(sys.argv[1], encoding="utf8", errors="replace"):
    m = re.search(r"BLACKCONST\|(\d+)/(\d+)\|(.*)$", raw.rstrip("\r\n"))
    if m:
        lines.setdefault(int(m.group(1)), m.group(3))
        total = int(m.group(2))
missing = [i for i in range(1, (total or 0) + 1) if i not in lines]
if total is None or missing:
    sys.exit(f"incomplete: {len(lines)} of {total} lines (missing {missing[:10]}...)")

constant_of, unconfirmed = {}, []
for i in range(1, total + 1):
    for record in lines[i].split("~"):
        npc_id, constant = record.split("=", 1)
        if constant.startswith("!"):
            unconfirmed.append(int(npc_id))
            constant = constant[1:]
        constant_of[int(npc_id)] = constant

path = os.path.join(root, "src", "data", "head_blacklist.lua")
blacklist = LuaRuntime().execute(open(path, encoding="utf8").read())
out = ["-- DEVELOPMENT ONLY (dev branch): the constant (id.NPC) of every blacklisted NPC id in head_blacklist.lua, by group, as",
       "-- the game gave them when this file was made (tools/make_blacklist_constants.py). The plugin never reads this: if a",
       "-- game update shifts NPC ids, these show where each blacklisted id moved to. \"?\": the game gave no constant.",
       "return {"]
absent = 0
for group in ("blank", "identical", "manual"):
    ids = blacklist[group]
    out.append(f"    {group} = {{")
    for k in range(1, len(ids) + 1):
        npc_id = ids[k]
        if npc_id not in constant_of:
            absent += 1
        out.append('        [%d] = "%s",' % (npc_id, constant_of.get(npc_id, "?")))
    out.append("    },")
out += ["}", ""]
open(os.path.join(root, "src", "data", "head_blacklist_constants.lua"), "w", encoding="utf8", newline="\r\n").write("\n".join(out))
print(f"written: {len(constant_of)} constants; not in the log: {absent}; "
      f"not giving their id back: {len(unconfirmed)} {unconfirmed[:20]}")
