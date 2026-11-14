"""Build the data file for the ForeverMetrics download page.

Usage:
    python tools/bundle.py

Writes download-page/addon-files.json, which the claude.ai download page reads to
build its zips in the browser:
    {"folder": "ForeverMetrics", "version": "...", "files": {name: text},
     "updater": {"folder": "WoW_Forever-Updater", "files": {name: text}}}
Republish the page with this file after every release (see CLAUDE.md).
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "addons" / "ForeverMetrics"
UPDATER = ROOT / "updater"
OUT = ROOT / "download-page" / "addon-files.json"


def read_tree(base: Path) -> dict:
    files = {}
    for f in sorted(base.rglob("*")):
        if f.is_file():
            text = f.read_text(encoding="utf-8")
            if f.suffix in (".bat", ".ps1"):
                text = text.replace("\r\n", "\n").replace("\n", "\r\n")  # Windows line endings
            files[f.relative_to(base).as_posix()] = text
    return files


def main():
    toc = (ADDON / "ForeverMetrics.toc").read_text(encoding="utf-8")
    version = re.search(r"^##\s*Version:\s*(\S+)", toc, re.M).group(1)
    data = {
        "folder": ADDON.name,
        "version": version,
        "files": read_tree(ADDON),
        "updater": {"folder": "WoW_Forever-Updater", "files": read_tree(UPDATER)},
    }
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(data), encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}  (ForeverMetrics {version}, {len(data['files'])} files + updater)")


if __name__ == "__main__":
    main()
