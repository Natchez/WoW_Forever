"""Build the data file for the download page's addon dropdown.

Usage:
    python tools/bundle.py                      # every addon in addons/
    python tools/bundle.py path/to/OtherAddon   # plus addon folders from elsewhere
                                                # (e.g. one still on a branch)

Writes download-page/addons.json, which the page reads to list the addons
and build each zip in the browser (artifacts can't serve .zip files):
    {"addons": [{"folder", "title", "version", "notes", "files": {name: text}}]}
Republish the page with this file after every release (see CLAUDE.md).
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "download-page" / "addons.json"


def toc_field(toc, field):
    m = re.search(r"^##\s*" + field + r":\s*(.+?)\s*$", toc, re.M)
    return m.group(1) if m else None


def read_addon(folder: Path) -> dict:
    toc_path = folder / f"{folder.name}.toc"
    toc = toc_path.read_text(encoding="utf-8")
    files = {}
    for f in sorted(folder.rglob("*")):
        if f.is_file():
            files[f.relative_to(folder).as_posix()] = f.read_text(encoding="utf-8")
    return {
        "folder": folder.name,
        "title": toc_field(toc, "Title") or folder.name,
        "version": toc_field(toc, "Version") or "?",
        "notes": toc_field(toc, "Notes") or "",
        "files": files,
    }


def main(extra):
    folders = sorted(p for p in (ROOT / "addons").iterdir() if p.is_dir())
    folders += [Path(p).resolve() for p in extra]
    addons, seen = [], set()
    for folder in folders:
        if folder.name in seen:
            continue
        seen.add(folder.name)
        addons.append(read_addon(folder))
    OUT.write_text(json.dumps({"addons": addons}), encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: " + ", ".join(f"{a['folder']} {a['version']}" for a in addons))


if __name__ == "__main__":
    main(sys.argv[1:])
