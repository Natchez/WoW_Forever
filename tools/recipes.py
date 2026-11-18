"""Build ForeverProfessions' recipe table (addons/ForeverProfessions/Data.lua).

Usage:
    python tools/recipes.py path/to/ForeverMetrics.lua [ForeverProfessions.lua ...]

The game only tells an addon the materials for recipes a character already
knows. To show what an unlearned recipe needs (trainer recipes, other
characters' recipes), the addon ships this table.

It collects every recipe spell ID found in the given SavedVariables files
(trainer lists and known recipes, from ForeverMetrics or ForeverProfessions),
looks each one up in Wowhead's Classic tooltip data for its materials and
the item it makes, and writes:

    ForeverProfessions_Data = {
      [2662] = { "Copper Chain Pants", "Blacksmithing", 15, 2852, { 2840, 4 } },
      ...  -- name, profession, skill needed (0 = unknown), item made, {item, count, ...}
    }

Recipes Wowhead doesn't have (some are Forever-only) fall back to what the
saved files recorded. Lookups are cached in dist/recipe-cache.json (dist/ is
gitignored), so reruns only fetch new recipes. Needs nether.wowhead.com.

The table holds recipe facts only (no character names or play data), so it
is committed with the addon.
"""
import html
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from stats import LuaParser, as_dict, as_list  # noqa: E402

OUT = ROOT / "addons" / "ForeverProfessions" / "Data.lua"
CACHE = ROOT / "dist" / "recipe-cache.json"
UA = {"User-Agent": "Mozilla/5.0 (addon recipe table build)"}


def fetch(spell, cache):
    key = str(spell)
    if key in cache and ("names" in cache[key] or cache[key].get("err")):
        return cache[key]
    out = None
    try:
        url = f"https://nether.wowhead.com/tooltip/spell/{spell}?dataEnv=4&locale=0"
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=20) as r:
            data = json.loads(r.read())
        tip = data.get("tooltip") or ""
        reagents = []
        made = None
        part = tip.split("Reagents:", 1)
        if len(part) == 2:
            body, rest = part[1], ""
            # materials sit in the indented block right after "Reagents:"
            m = re.search(r'<div class="indent[^"]*">(.*?)</div>', body, re.S)
            if m:
                block = m.group(1)
                for im in re.finditer(r'item=(\d+)[^>]*>[^<]*</a>(?:&nbsp;\((\d+)\))?', block):
                    reagents.append([int(im.group(1)), int(im.group(2) or 1)])
                rest = body[m.end():]
            mm = re.search(r'item=(\d+)', rest)
            if mm:
                made = int(mm.group(1))
        names = {m.group(1): html.unescape(m.group(2))
                 for m in re.finditer(r'item=(\d+)/[^"]*">([^<]+)</a>', tip)}
        out = {"n": html.unescape(data.get("name") or ""), "r": reagents, "i": made, "names": names}
    except Exception as e:  # not on Wowhead (Forever-only) or a network hiccup
        out = {"err": str(e)[:80]}
    cache[key] = out
    time.sleep(0.1)
    return out


def collect(paths):
    """spell -> {n, p, s, i, r} from every file's trainer lists and known recipes."""
    seen = {}

    def note(spell, prof, name=None, skill=None, item=None, reagents=None):
        if not spell or not prof:
            return
        e = seen.setdefault(int(spell), {"p": prof, "n": None, "s": 0, "i": None, "r": None})
        e["n"] = e["n"] or name
        e["s"] = max(e["s"], skill or 0)
        e["i"] = e["i"] or item
        if reagents and not e["r"]:
            e["r"] = reagents

    for path in paths:
        text = Path(path).read_text(encoding="utf-8")
        g = LuaParser(text).globals()
        for db in (g.get("ForeverMetricsDB"), g.get("ForeverProfessionsDB")):
            db = as_dict(db)
            for prof, T in as_dict(db.get("profTrainer") or db.get("trainers")).items():
                for r in as_dict(as_dict(T).get("recipes")).values():
                    r = as_dict(r)
                    note(r.get("spell"), prof, r.get("n"), r.get("skill"))
            # ForeverProfessions keeps every recipe's materials it has seen, by spell ID
            for spell, r in as_dict(db.get("recipes")).items() if db.get("version") and "trainers" in db else []:
                r = as_dict(r)
                regs = [[as_dict(x).get("id"), as_dict(x).get("c", 1)] for x in as_list(r.get("r"))]
                regs = [x for x in regs if x[0]]
                try:
                    note(int(spell), r.get("p"), r.get("n"), None, r.get("i"), regs or None)
                except (TypeError, ValueError):
                    pass
            for c in as_dict(db.get("chars")).values():
                for prof, P in as_dict(as_dict(c).get("prof")).items():
                    if not prof:
                        continue
                    for r in as_dict(as_dict(P).get("recipes")).values():
                        r = as_dict(r)
                        regs = [[as_dict(x).get("id"), as_dict(x).get("c", 1)] for x in as_list(r.get("reagents"))]
                        regs = [x for x in regs if x[0]]
                        note(r.get("spell"), prof, r.get("n"), None, r.get("item"), regs or None)
    return seen


def saved_names(paths):
    """item ID -> name, from bag and reagent entries in the saved files"""
    out = {}
    for path in paths:
        g = LuaParser(Path(path).read_text(encoding="utf-8")).globals()
        for c in as_dict(as_dict(g.get("ForeverMetricsDB")).get("chars")).values():
            c = as_dict(c)
            for where in ("bags", "bank"):
                for iid, e in as_dict(as_dict(c.get(where)).get("items")).items():
                    if isinstance(e, dict) and e.get("n"):
                        out[int(iid)] = e["n"]
            for P in as_dict(c.get("prof")).values():
                for r in as_dict(as_dict(P).get("recipes")).values():
                    for x in as_list(as_dict(r).get("reagents")):
                        x = as_dict(x)
                        if x.get("id") and x.get("n"):
                            out[int(x["id"])] = x["n"]
    return out


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(args):
    if not args:
        sys.exit(__doc__)
    CACHE.parent.mkdir(exist_ok=True)
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    seen = collect(args)
    rows, from_wh, from_saved, empty = [], 0, 0, 0
    item_names = dict(saved_names(args))
    for spell in sorted(seen):
        e = seen[spell]
        w = fetch(spell, cache)
        name, item, regs = e["n"], e["i"], e["r"]
        for k, v in (w or {}).get("names", {}).items():
            item_names[int(k)] = v
        if w and not w.get("err") and w.get("r"):
            name, item, regs = w["n"] or name, w["i"] or item, w["r"]
            from_wh += 1
        elif regs:
            from_saved += 1
        else:
            empty += 1
            regs = []
        flat = ", ".join(f"{i}, {c}" for i, c in regs)
        rows.append(f"  [{spell}] = {{ {lua_str(name or '?')}, {lua_str(e['p'])}, {e['s'] or 0}, {item or 0}, {{ {flat} }} }},")
    CACHE.write_text(json.dumps(cache))
    # keep names only for items the recipes use or make (not everything in players' bags)
    used = set()
    for row in rows:
        m = re.search(r"\{ (\d+(?:, \d+)*) \} \},$", row)
        if m:
            nums = [int(x) for x in m.group(1).split(", ")]
            used.update(nums[0::2])
        mi = re.match(r"  \[\d+\] = \{ .*?, .*?, \d+, (\d+), ", row)
        if mi:
            used.add(int(mi.group(1)))
    item_names = {i: n for i, n in item_names.items() if i in used}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        "-- Forever Professions: recipe table, generated by tools/recipes.py. Don't edit by hand.\n"
        "-- [spell] = { name, profession, skill needed (0 = unknown), item made, { item, count, ... } }\n"
        "ForeverProfessions_Data = {\n" + "\n".join(rows) + "\n}\n\n"
        "-- Names of the materials and items above, for ones the game hasn't loaded yet\n"
        "ForeverProfessions_Items = {\n" + "\n".join(f"  [{i}] = {lua_str(n)}," for i, n in sorted(item_names.items())) + "\n}\n",
        encoding="utf-8",
    )
    print(f"{OUT.relative_to(ROOT)}: {len(rows)} recipes ({from_wh} from Wowhead, "
          f"{from_saved} from saved files, {empty} without materials)")


if __name__ == "__main__":
    main(sys.argv[1:])
