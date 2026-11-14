# WoW_Forever

Our addons for World of Warcraft: Forever.

## Addons

| Addon | Version | What it does |
|---|---|---|
| [ForeverMetrics](addons/ForeverMetrics) | 0.10.1 | Stats, activity feed, loot luck, XP pill, level-up pop-up and duo mode. Type `/fm` in game. See its [README](addons/ForeverMetrics/README.md). |

## Layout

```
addons/
  ForeverMetrics/        one folder per addon, exactly as it goes in Interface\AddOns
    ForeverMetrics.toc   the .toc name must match the folder name
    ...
updater/
  Update WoW Addons.bat  double-click to install or update every addon from GitHub
  update-addons.ps1      the script it runs
download-page/           the claude.ai download page for ForeverMetrics
tools/
  package.py             builds dist/<Addon>-<version>.zip
  bundle.py              builds the download page's data file
dist/                    built zips (not committed)
```

To add another addon, make a new folder under `addons/` with a matching `.toc` inside.

## Installing

**Easiest (Windows):** download this repo once (Code > Download ZIP, or the updater from our download page), then double-click `updater\Update WoW Addons.bat`. The first time, it finds your AddOns folder or asks you to pick it, and remembers it. Run it again whenever there's an update. It pulls from the `main` branch, so anything merged to `main` is what you get.

**By hand:**
1. Get the zip: download it from our download page, or build it with `python tools/package.py`.
2. Close WoW, then unzip into your game's `Interface\AddOns` folder. You should end up with `AddOns\ForeverMetrics\ForeverMetrics.toc`, not a folder inside a folder.
3. When updating, replace the old addon folder. Saved stats live in the `WTF` folder and are kept.

## Releasing an update

1. Change the code under `addons/<Addon>/`.
2. Bump `## Version:` in the `.toc`, and the version in the addon's README and the table above.
3. Merge to `main`. The updater picks it up from there.
4. For ForeverMetrics, also refresh the download page (see CLAUDE.md).
