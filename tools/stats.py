"""Turn a ForeverMetrics SavedVariables file into the stats page's data.

Usage:
    python tools/stats.py path/to/ForeverMetrics.lua [more files...]

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
    if not m:
        return {"name": strip_codes(link), "q": None}
    if m.group(1):
        return {"name": m.group(2), "q": int(m.group(1))}
    return {"name": m.group(3), "q": None}


def top(d, n):
    pairs = sorted(as_dict(d).items(), key=lambda kv: -(kv[1] or 0))
    return [{"name": k, "value": v} for k, v in pairs[:n] if v]


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def build_char(key, c):
    s = as_dict(c.get("stats"))
    loot = as_dict(c.get("loot"))
    q = as_map(loot.get("q"))
    sessions = []
    for ses in as_list(c.get("sessions")):
        ses = as_dict(ses)
        start, stop = ses.get("start"), ses.get("stop")
        if not start or not stop or stop <= start:
            continue
        dur = stop - start
        if dur < 300:  # quick logins say nothing about pace
            continue
        sessions.append({"start": start, "dur": dur, "xp": ses.get("xp", 0), "kills": ses.get("kills", 0),
                         "quests": ses.get("quests", 0), "levels": ses.get("levels", 0),
                         "best": item(ses.get("bestLoot")) if ses.get("bestLoot") else None})
    gathering = {}
    for g, d in as_dict(c.get("gathering")).items():
        d = as_dict(d)
        if d.get("nodes"):
            gathering[g] = {"nodes": d["nodes"], "items": top(d.get("items"), 8)}
    notable = []
    for n in as_list(loot.get("notable")):
        n = as_dict(n)
        it = item(n.get("link"))
        notable.append({"name": it["name"], "q": n.get("q", it["q"]), "mob": n.get("mob"), "zone": n.get("zone"),
                        "t": n.get("t"), "kill": n.get("kill")})
    feed = []
    for e in as_list(c.get("feed"))[-40:]:
        e = as_dict(e)
        feed.append({"t": e.get("t"), "k": e.get("k"), "x": strip_codes(e.get("x"))})
    xp_time = sum(x["dur"] for x in sessions)
    xp_sum = sum(x["xp"] for x in sessions)
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
        "xpPerHour": round(xp_sum / (xp_time / 3600)) if xp_time >= 1800 else None,
        "levelTimes": {int(k): v for k, v in as_map(c.get("levelTimes")).items()},
        "zones": top(c.get("zones"), 8),
        "kills": top(c.get("kills"), 8),
        "skills": sorted(({"name": k, "rank": as_dict(v).get("rank", 0)} for k, v in as_dict(c.get("skills")).items()),
                         key=lambda x: -x["rank"]),
        "gathering": gathering,
        "loot": {"q": {int(k): v for k, v in q.items()}, "cloth": top(loot.get("cloth"), 6), "notable": notable[-12:],
                 "longestDry": loot.get("longestDry", 0)},
        "sessions": sessions,
        "feed": feed,
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


def main(paths):
    if not paths:
        sys.exit(__doc__)
    chars, duo, snapshot = {}, [], 0
    for path in paths:
        db = LuaParser(Path(path).read_text(encoding="utf-8")).globals().get("ForeverMetricsDB") or {}
        for key, c in as_dict(db.get("chars")).items():
            built = build_char(key, as_dict(c))
            old = chars.get(key)
            if not old or (built["lastSeen"] or 0) >= (old["lastSeen"] or 0):
                chars[key] = built
            snapshot = max(snapshot, built["lastSeen"] or 0)
        duo.extend(build_duo(db))
    data = {
        "snapshot": snapshot,
        "chars": sorted(chars.values(), key=lambda c: (-(c["level"] or 0), c["name"] or "")),
        "duo": duo,
    }
    OUT.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(chars)} characters, {len(duo)} duo partner(s)")


if __name__ == "__main__":
    main(sys.argv[1:])
