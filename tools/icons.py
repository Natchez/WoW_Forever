"""Fetch the WoW icons the stats page shows, and record which icon goes where.

Usage:
    python tools/icons.py        # after tools/stats.py

Reads download-page/stats.json, finds every spell and item ID it mentions
(recipes, reagents, loot) plus classes and professions, looks up each
one's icon name on Wowhead (Classic data), downloads the 56px icons to
download-page/icons/, and writes the mapping back into stats.json as
"icons": {"spell:133": "spell_fire_flamebolt", "item:2589": ..., "class:MAGE": ...}.

Lookups are cached in download-page/icons/cache.json, so reruns only fetch
what's new. Icons are Blizzard's art: they're gitignored and only published
with the private page. Needs network access to nether.wowhead.com and
wow.zamimg.com.
"""
import json
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGE = ROOT / "download-page"
STATS = PAGE / "stats.json"
ICONS = PAGE / "icons"
CACHE = ICONS / "cache.json"

CLASS_ICONS = {c: "classicon_" + c.lower() for c in
               ("WARRIOR", "MAGE", "ROGUE", "SHAMAN", "DRUID", "PRIEST", "PALADIN", "HUNTER", "WARLOCK")}
PROF_ICONS = {
    "Alchemy": "trade_alchemy", "Blacksmithing": "trade_blacksmithing", "Enchanting": "trade_engraving",
    "Engineering": "trade_engineering", "Herbalism": "trade_herbalism", "Leatherworking": "trade_leatherworking",
    "Mining": "trade_mining", "Skinning": "inv_misc_pelt_wolf_01", "Tailoring": "trade_tailoring",
    "Cooking": "inv_misc_food_15", "First Aid": "spell_holy_sealofsacrifice", "Fishing": "trade_fishing",
    "Jewelcrafting": "inv_misc_gem_01", "Inscription": "inv_inscription_tradeskill01",
}
UA = {"User-Agent": "Mozilla/5.0 (stats page icon fetch)"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=20) as r:
        return r.read()


def lookup(kind, iid, cache):
    key = f"{kind}:{iid}"
    if key in cache:
        return cache[key]
    name = None
    try:
        data = json.loads(get(f"https://nether.wowhead.com/tooltip/{kind}/{iid}?dataEnv=4&locale=0"))
        name = data.get("icon")
    except Exception:
        pass
    cache[key] = name
    time.sleep(0.1)
    return name


def download(name):
    path = ICONS / f"{name}.jpg"
    if path.exists():
        return True
    try:
        path.write_bytes(get(f"https://wow.zamimg.com/images/wow/icons/large/{name}.jpg"))
        time.sleep(0.05)
        return True
    except Exception:
        return False


def main():
    ICONS.mkdir(exist_ok=True)
    data = json.loads(STATS.read_text(encoding="utf-8"))
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    spells, items = set(), set()
    classes, profs = set(), set()
    for c in data["chars"]:
        classes.add(c.get("class"))
        for n in c["loot"]["notable"]:
            if n.get("id"):
                items.add(n["id"])
        for e in c.get("reagents", []):
            items.add(e["id"])
        for p in c.get("profs", []):
            profs.add(p["name"])
            for r in p["recipes"]:
                if r.get("spell"):
                    spells.add(r["spell"])
                if r.get("item"):
                    items.add(r["item"])
                for g in r["reagents"]:
                    if g.get("id"):
                        items.add(g["id"])
            for r in p["missing"] + p["upcoming"]:
                if r.get("spell"):
                    spells.add(r["spell"])
    for P in data.get("duo", []):
        for ch in P.get("chars", []):
            classes.add(ch.get("class"))

    icons = {}
    for cl in filter(None, classes):
        if cl in CLASS_ICONS:
            icons[f"class:{cl}"] = CLASS_ICONS[cl]
    for p in profs:
        if p in PROF_ICONS:
            icons[f"prof:{p}"] = PROF_ICONS[p]
    for kind, ids in (("spell", spells), ("item", items)):
        for iid in sorted(ids):
            name = lookup(kind, iid, cache)
            if name:
                icons[f"{kind}:{iid}"] = name
    CACHE.write_text(json.dumps(cache))

    # names -> icons, for things saved by name only (gathering materials)
    named = {}
    for c in data["chars"]:
        for n in c["loot"]["notable"]:
            named[n.get("name")] = n.get("id")
        for e in c.get("reagents", []):
            named[e.get("n")] = e["id"]
        for p in c.get("profs", []):
            for r in p["recipes"]:
                for g in r["reagents"]:
                    named[g.get("n")] = g.get("id")
    for nm, iid in named.items():
        if nm and iid and f"item:{iid}" in icons:
            icons[f"name:{nm}"] = icons[f"item:{iid}"]

    missing = [k for k, name in icons.items() if not download(name)]
    for k in missing:
        icons.pop(k, None)
    data["icons"] = icons
    STATS.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    files = len(list(ICONS.glob("*.jpg")))
    print(f"{len(icons)} icons mapped, {files} image files in {ICONS.relative_to(ROOT)}"
          + (f", {len(missing)} not found: {missing}" if missing else ""))


if __name__ == "__main__":
    main()
