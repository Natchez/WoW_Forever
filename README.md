# WoW_Forever

Our addons for World of Warcraft: Forever.

## Addons

| Addon | Version | What it does |
|---|---|---|
| [ForeverMetrics](addons/ForeverMetrics) | 0.16.10 | Stats, activity feed, loot luck, XP pill, level-up pop-up and duo mode. Type `/fm` in game. See its [README](addons/ForeverMetrics/README.md). |
| [ForeverProfessions](addons/ForeverProfessions) | 0.1.6 | Which recipes use an item (hover, Shift, Alt-click), and every profession across your characters. Type `/fp` in game. See its [README](addons/ForeverProfessions/README.md). |
| [ForeverBuffs](addons/ForeverBuffs) | 0.1.0 | A row of icons for the self-buffs you're missing; click one to cast it. Type `/fb` in game. See its [README](addons/ForeverBuffs/README.md). |

## Layout

```
addons/
  ForeverMetrics/        one folder per addon, exactly as it goes in Interface\AddOns
    ForeverMetrics.toc   the .toc name must match the folder name
    ...
  ForeverBuffs/
download-page/           the claude.ai download page for ForeverMetrics
tools/
  package.py             builds dist/<Addon>-<version>.zip
  bundle.py              builds the download page's addon list
  stats.py               turns players' saved data into the stats page's data
  icons.py               fetches the WoW icons the stats page uses
  recipes.py             builds ForeverProfessions' recipe table (Data.lua) from saved data + Wowhead
dist/                    built zips (not committed)
```

To add another addon, make a new folder under `addons/` with a matching `.toc` inside.

## Installing

**With Claude Code on your PC:** open a Claude Code session in your clone of this repo and ask it to install or update the addons. It copies `addons/<Addon>` into your AddOns folder.

**By hand:**
1. Get the zip: download it from our download page, or build it with `python tools/package.py`.
2. Close WoW, then unzip into your game's `Interface\AddOns` folder. You should end up with `AddOns\ForeverMetrics\ForeverMetrics.toc`, not a folder inside a folder.
3. When updating, replace the old addon folder. Saved stats live in the `WTF` folder and are kept.

## Releasing an update

1. Change the code under `addons/<Addon>/`.
2. Bump `## Version:` in the `.toc`, and the version in the addon's README and the table above.
3. Merge to `main`.
4. For ForeverMetrics, also refresh the download page (see CLAUDE.md).
