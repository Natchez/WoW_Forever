"""Build installable zips for the addons in addons/.

Usage:
    python tools/package.py                 # every addon
    python tools/package.py ForeverMetrics  # just one

Each zip lands in dist/<Addon>-<version>.zip, with the version read from the
addon's .toc file. Inside the zip is a single <Addon>/ folder, so unzipping it
into Interface\\AddOns gives the right layout. Paths always use forward
slashes, which every unzip tool understands.
"""
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDONS = ROOT / "addons"
DIST = ROOT / "dist"
SKIP = {".DS_Store", "Thumbs.db"}


def version_of(addon_dir: Path) -> str:
    toc = addon_dir / f"{addon_dir.name}.toc"
    if not toc.exists():
        sys.exit(f"{addon_dir.name}: missing {toc.name} (the .toc must match the folder name)")
    m = re.search(r"^##\s*Version:\s*(\S+)", toc.read_text(encoding="utf-8"), re.M)
    if not m:
        sys.exit(f"{addon_dir.name}: no '## Version:' line in {toc.name}")
    return m.group(1)


def package(addon_dir: Path) -> Path:
    version = version_of(addon_dir)
    DIST.mkdir(exist_ok=True)
    out = DIST / f"{addon_dir.name}-{version}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(addon_dir.rglob("*")):
            if f.is_file() and f.name not in SKIP:
                z.write(f, f.relative_to(ADDONS).as_posix())
    return out


def main(names):
    dirs = [ADDONS / n for n in names] if names else sorted(p for p in ADDONS.iterdir() if p.is_dir())
    for d in dirs:
        if not d.is_dir():
            sys.exit(f"no addon folder named {d.name} in addons/")
        print(f"{package(d).relative_to(ROOT)}")


if __name__ == "__main__":
    main(sys.argv[1:])
