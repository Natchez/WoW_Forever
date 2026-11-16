"""Turn a ForeverMetrics SavedVariables file into the stats page's data.

Usage:
    python tools/stats.py path/to/ForeverMetrics.lua[=Owner] [more files...]

Give each player's file an owner name after "=" (for example
"mine.lua=Aaron her.lua=Martha") and the page groups characters by player
and compares the players head to head.

Writes download-page/stats.json, which the download page reads to show the
Stats section. That file holds character names and play history, so it is
gitignored: the repo is public. Pass several files (for example, both
players' copies) and their characters are merged, newest data winning.

SavedVariables are Lua table literals; this has a small parser for exactly
that format, so it needs nothing beyond the standard library.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "download-page" / "stats.json"


# ---------------------------------------------------------------------------
# Lua table literal parser
# ---------------------------------------------------------------------------

class LuaParser:
    def __init__(self, text):
        self.s, self.i, self.n = text, 0, len(text)

    def ws(self):
        while self.i < self.n:
            c = self.s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif self.s.startswith("--", self.i):
                j = self.s.find("\n", self.i)
                self.i = self.n if j < 0 else j + 1
            else:
                break

    def peek(self):
        self.ws()
        return self.s[self.i] if self.i < self.n else ""

    def expect(self, ch):
        if self.peek() != ch:
            raise ValueError(f"expected {ch!r} at {self.i}: {self.s[self.i:self.i + 40]!r}")
        self.i += 1

    def string(self):
        q = self.s[self.i]
        self.i += 1
        out = []
        while True:
            c = self.s[self.i]
            if c == q:
                self.i += 1
                return "".join(out)
            if c == "\\":
                nxt = self.s[self.i + 1]
                esc = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}
                if nxt in esc:
                    out.append(esc[nxt])
                    self.i += 2
                elif nxt.isdigit():
                    m = re.match(r"\d{1,3}", self.s[self.i + 1:])
                    out.append(chr(int(m.group())))
                    self.i += 1 + len(m.group())
                else:
                    out.append(nxt)
                    self.i += 2
            else:
                out.append(c)
                self.i += 1

    def value(self):
        c = self.peek()
        if c == "{":
            return self.table()
        if c in "\"'":
            return self.string()
        m = re.compile(r"-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+)").match(self.s, self.i)
        if m:
            self.i = m.end()
            t = m.group()
            if t.lower().startswith(("0x", "-0x")):
                return int(t, 16)
            return float(t) if any(ch in t for ch in ".eE") else int(t)
        m = re.compile(r"[A-Za-z_]\w*").match(self.s, self.i)
        if m:
            self.i = m.end()
            return {"true": True, "false": False, "nil": None}.get(m.group(), m.group())
        raise ValueError(f"unexpected {c!r} at {self.i}")

    def table(self):
        self.expect("{")
        arr, obj = [], {}
        while self.peek() != "}":
            if self.peek() == "[":
                self.i += 1
                k = self.value()
                self.expect("]")
                self.expect("=")
                obj[k] = self.value()
            else:
                m = re.compile(r"([A-Za-z_]\w*)\s*=(?!=)").match(self.s, self.i)
                if m:
                    self.i = m.end()
                    obj[m.group(1)] = self.value()
                else:
                    arr.append(self.value())
            if self.peek() in ",;":
                self.i += 1
        self.i += 1
        if not obj:
            return arr
        for idx, v in enumerate(arr, 1):
            obj.setdefault(idx, v)
        return obj

    def globals(self):
        out = {}
        while self.peek():
            m = re.compile(r"([A-Za-z_]\w*)\s*=").match(self.s, self.i)
            if not m:
                raise ValueError(f"expected an assignment at {self.i}")
            self.i = m.end()
            out[m.group(1)] = self.value()
        return out


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def as_list(t):
    """Lua arrays come back as lists, or dicts with int keys if mixed."""
    if isinstance(t, list):
        return t
    if isinstance(t, dict):
        return [t[k] for k in sorted(k for k in t if isinstance(k, int))]
    return []


def as_dict(t):
    return t if isinstance(t, dict) else {}


def as_map(t):
    """Number-keyed table that WoW may have written as a list ({nil, 910, ...})."""
    if isinstance(t, list):
        return {i: v for i, v in enumerate(t, 1) if v is not None}
    return as_dict(t)


LINK = re.compile(r"\|cnIQ(\d):\|H[^|]*\|h\[([^\]]+)\]\|h\|r|\|c[0-9a-fA-F]{8}\|H[^|]*\|h\[([^\]]+)\]\|h\|r")


def strip_codes(text):
    """WoW markup to plain text: item links become [Name], colors drop."""
    if not isinstance(text, str):
        return ""
    text = re.sub(r"\|cnIQ\d:\|H[^|]*\|h(\[[^\]]+\])\|h\|r", r"\1", text)
    text = re.sub(r"\|H[^|]*\|h(\[[^\]]+\])\|h", r"\1", text)
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    text = re.sub(r"\|cnIQ\d:", "", text)
    text = text.replace("|r", "")
    text = re.sub(r"\|T[^|]*\|t", "", text)
    return text.strip()


def item(link):
    m = LINK.search(link or "")
    idm = re.search(r"\|Hitem:(\d+)", link or "")
    iid = int(idm.group(1)) if idm else None
    if not m:
        return {"name": strip_codes(link), "q": None, "id": iid}
    if m.group(1):
        return {"name": m.group(2), "q": int(m.group(1)), "id": iid}
    return {"name": m.group(3), "q": None, "id": iid}


def top(d, n):
    pairs = sorted(as_dict(d).items(), key=lambda kv: -(kv[1] or 0))
    return [{"name": k, "value": v} for k, v in pairs[:n] if v]


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

PROFESSIONS = {"Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking", "Mining",
               "Skinning", "Tailoring", "Cooking", "First Aid", "Fishing", "Jewelcrafting", "Inscription"}
REAGENT_CLASSES = {5, 7}  # Reagent, Tradeskill


def inventory(c):
    """Bags and bank merged by item ID, each with how many are in which place."""
    out = {}
    for where in ("bags", "bank"):
        for iid, e in as_dict(as_dict(c.get(where)).get("items")).items():
            e = as_dict(e)
            cur = out.setdefault(int(iid), {"id": int(iid), "n": e.get("n"), "q": e.get("q"), "cls": e.get("cls"),
                                            "bags": 0, "bank": 0})
            cur[where] += e.get("c", 0) or 0
            cur["n"] = cur["n"] or e.get("n")
    return out


def build_profs(c, trainers, inv):
    have = {i: e["bags"] + e["bank"] for i, e in inv.items()}
    have_by_name = {e["n"]: e["bags"] + e["bank"] for e in inv.values() if e.get("n")}
    ranks = {s: as_dict(v).get("rank", 0) for s, v in as_dict(c.get("skills")).items()}
    saved = as_dict(c.get("prof"))
    # a scan taken before the profession window finished loading can be saved under ""
    names = [n for n in saved if n] + [n for n in ranks if n in PROFESSIONS and n not in saved]
    out, reagent_ids = [], set()
    for name in names:
        P = as_dict(saved.get(name))
        rank = P.get("rank") or ranks.get(name, 0)
        recipes, known_spells, known_names = [], set(), set()
        for r in as_dict(P.get("recipes")).values():
            r = as_dict(r)
            reags = []
            can = None
            for g in as_list(r.get("reagents")):
                g = as_dict(g)
                got = have.get(g.get("id")) if g.get("id") else have_by_name.get(g.get("n"))
                got = got or 0
                need = g.get("c", 1) or 1
                reags.append({"n": g.get("n"), "id": g.get("id"), "c": need, "have": got})
                if g.get("id"):
                    reagent_ids.add(g["id"])
                times = got // need
                can = times if can is None else min(can, times)
            recipes.append({"n": r.get("n"), "spell": r.get("spell"), "item": r.get("item"), "diff": r.get("diff"),
                            "reagents": reags, "canMake": can or 0})
            if r.get("spell"):
                known_spells.add(r["spell"])
            known_names.add(r.get("n"))
        order = {"optimal": 0, "medium": 1, "easy": 2, "trivial": 3}
        recipes.sort(key=lambda r: (order.get(r["diff"], 4), r["n"] or ""))
        missing, upcoming = [], []
        T = as_dict(as_dict(trainers.get(name)).get("recipes"))
        for t in T.values():
            t = as_dict(t)
            if (t.get("spell") and t["spell"] in known_spells) or t.get("n") in known_names:
                continue
            entry = {"n": t.get("n"), "r": t.get("r"), "spell": t.get("spell"), "skill": t.get("skill", 0),
                     "lv": t.get("lv"), "cost": t.get("cost", 0)}
            if (t.get("skill") or 0) > rank:
                upcoming.append(entry)
            elif recipes:
                # only trustworthy once we know which recipes this character has
                missing.append(entry)
        missing.sort(key=lambda x: (x["skill"], x["n"] or ""))
        upcoming.sort(key=lambda x: (x["skill"], x["n"] or ""))
        out.append({"name": name, "rank": rank, "max": P.get("max"), "scanned": P.get("scanned"),
                    "recipes": recipes, "missing": missing, "upcoming": upcoming[:30],
                    "trainerKnown": bool(T)})
    out.sort(key=lambda p: -(p["rank"] or 0))
    return out, reagent_ids


def build_char(key, c, trainers=None):
    s = as_dict(c.get("stats"))
    loot = as_dict(c.get("loot"))
    q = as_map(loot.get("q"))
    gathering = {}
    for g, d in as_dict(c.get("gathering")).items():
        d = as_dict(d)
        if d.get("nodes"):
            gathering[g] = {"nodes": d["nodes"], "items": top(d.get("items"), 8)}
    notable = []
    for n in as_list(loot.get("notable")):
        n = as_dict(n)
        it = item(n.get("link"))
        notable.append({"name": it["name"], "id": it["id"], "q": n.get("q", it["q"]), "mob": n.get("mob"), "zone": n.get("zone"),
                        "t": n.get("t"), "kill": n.get("kill")})
    return {
        "key": key,
        "name": c.get("name"),
        "realm": c.get("realm"),
        "class": c.get("class"),
        "level": c.get("level"),
        "played": c.get("played", 0),
        "created": c.get("created"),
        "lastSeen": c.get("lastSeen"),
        "stats": {k: s.get(k, 0) for k in ("kills", "deaths", "quests", "levels", "xp", "goldLooted", "goldEarned", "goldSpent")},
        "kills": top(c.get("kills"), 8),
        "skills": sorted(({"name": k, "rank": as_dict(v).get("rank", 0)} for k, v in as_dict(c.get("skills")).items()),
                         key=lambda x: -x["rank"]),
        "gathering": gathering,
        "loot": {"q": {int(k): v for k, v in q.items()}, "cloth": top(loot.get("cloth"), 6), "notable": notable[-40:],
                 "items": sorted(({"name": as_dict(v).get("n"), "id": as_dict(v).get("id"), "q": as_dict(v).get("q"),
                                   "c": as_dict(v).get("c", 0)} for v in as_dict(loot.get("items")).values()),
                                 key=lambda x: (-(x["c"] or 0), x["name"] or "")),
                 "longestDry": loot.get("longestDry", 0)},
        **profs_and_bags(c, trainers or {}),
    }


def profs_and_bags(c, trainers):
    inv = inventory(c)
    profs, reagent_ids = build_profs(c, trainers, inv)
    reagents = [e for e in inv.values() if e.get("cls") in REAGENT_CLASSES or e["id"] in reagent_ids]
    reagents.sort(key=lambda e: (-(e["bags"] + e["bank"]), e["n"] or ""))
    return {
        "profs": profs,
        "reagents": reagents,
        "bagsSeen": as_dict(c.get("bags")).get("t"),
        "bankSeen": as_dict(c.get("bank")).get("t"),
    }


def build_duo(db):
    duo = as_dict(db.get("duo"))
    out = []
    for pid, p in as_dict(duo.get("partners")).items():
        p = as_dict(p)
        chars = []
        for name, ch in as_dict(p.get("chars")).items():
            ch = as_dict(ch)
            st = as_dict(ch.get("stats"))
            chars.append({"name": ch.get("name", name), "class": ch.get("class"), "level": ch.get("level"),
                          "played": st.get("p", 0), "kills": st.get("k", 0), "quests": st.get("q", 0),
                          "deaths": st.get("d", 0), "lastSeen": ch.get("lastSeen")})
        acct = as_dict(p.get("acct"))
        feed = [{"t": as_dict(e).get("t"), "k": as_dict(e).get("k"), "x": strip_codes(as_dict(e).get("x")),
                 "who": as_dict(e).get("who")} for e in as_list(p.get("feed"))[-20:]]
        out.append({"id": pid, "nick": p.get("nick"), "added": p.get("added"), "lastSeen": p.get("lastSeen"),
                    "together": as_dict(p.get("together")), "acct": acct, "chars": chars, "feed": feed})
    return out


def merge_trainers(lists):
    """Profession trainers teach the same recipes to everyone, so pool what
    every character on either account has seen: any character with the
    profession gets the full list. Where both saw a recipe, the newer scan wins."""
    out = {}
    for T in lists:
        for prof, P in T.items():
            P = as_dict(P)
            M = out.setdefault(prof, {"recipes": {}, "scanned": 0})
            newer = (P.get("scanned") or 0) >= M["scanned"]
            for k, r in as_dict(P.get("recipes")).items():
                if newer or k not in M["recipes"]:
                    M["recipes"][k] = r
            M["scanned"] = max(M["scanned"], P.get("scanned") or 0)
    return out


def main(args):
    if not args:
        sys.exit(__doc__)
    chars, duo, snapshot, owners = {}, [], 0, []
    files = []
    for arg in args:
        path, _, owner = arg.partition("=")
        owner = owner or Path(path).stem
        if owner not in owners:
            owners.append(owner)
        files.append((owner, LuaParser(Path(path).read_text(encoding="utf-8")).globals().get("ForeverMetricsDB") or {}))
    trainers = merge_trainers(as_dict(db.get("profTrainer")) for _, db in files)
    for owner, db in files:
        for key, c in as_dict(db.get("chars")).items():
            built = build_char(key, as_dict(c), trainers)
            built["owner"] = owner
            old = chars.get(key)
            if not old or (built["lastSeen"] or 0) >= (old["lastSeen"] or 0):
                chars[key] = built
            snapshot = max(snapshot, built["lastSeen"] or 0)
        # each player's file describes the other one as a duo partner: keep the first player's view
        if not duo:
            for d in build_duo(db):
                d["owner"] = owner
                duo.append(d)
    data = {
        "snapshot": snapshot,
        "owners": owners,
        "chars": sorted(chars.values(), key=lambda c: (owners.index(c["owner"]), -(c["level"] or 0), c["name"] or "")),
        "duo": duo,
    }
    OUT.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(chars)} characters ({', '.join(owners)}), {len(duo)} duo view(s)")


if __name__ == "__main__":
    main(sys.argv[1:])
