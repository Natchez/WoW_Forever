# WoW_Forever

WoW addons (Lua) for World of Warcraft: Forever, an Era-style Classic client built on the modern (Midnight-era) API. Written for two players: the repo owner and their wife, who play as a duo on the same realm and guild.

## Layout
- `addons/<Addon>/`: one folder per addon, shipped as-is into `Interface\AddOns`. The `.toc` file name must match the folder name.
- `tools/package.py`: `python tools/package.py [Addon]` builds `dist/<Addon>-<version>.zip` (forward-slash paths, one top-level folder). `dist/` is gitignored.
- `download-page/`: source of the ForeverMetrics page: stats from the players' saved data, with the addon download in a dialog.
- `tools/stats.py`: `python tools/stats.py <ForeverMetrics.lua> [more...]` turns uploaded SavedVariables (from `WTF\Account\<ACCOUNT>\SavedVariables\`) into `download-page/stats.json`, then publish the page with `files: {"stats.json": "download-page/stats.json"}`. That JSON holds character names and play history, so it's gitignored: the repo is public. Never commit players' SavedVariables or stats data.

## Releasing
- Bump `## Version:` in the `.toc`, the version in the addon's README heading, and the table in the root README.
- Both duo players should run the same ForeverMetrics version: Duo.lua's message protocol is shared.
- A release is a merge to `main`. Players install by hand from the download page or a zip, or with a Claude Code session on their own PC.
- Installing on a player's PC (local session only): find their `World of Warcraft\_<version>_\Interface\AddOns` folder (ask if more than one exists), then replace `AddOns\<Addon>` with `addons/<Addon>` from `main`. Never touch the `WTF` folder, which holds their saved data. Tell them to `/reload` if WoW is open.
- Keep the ForeverMetrics download page current after every change to `addons/ForeverMetrics/`. It is a private claude.ai artifact owned by the repo owner: https://claude.ai/artifact/5uc8EoX6aai9a47DDt3JWb. Run `python tools/bundle.py` (writes the gitignored `download-page/addon-files.json`), then publish `download-page/forever-metrics.html` with the Artifact tool using `url` set to that link and `files: {"addon-files.json": "download-page/addon-files.json"}`. Files left out of `files` stay as they were, so the published `stats.json` is kept. The page reads the version from the JSON, so the HTML only needs editing for wording changes. The page builds the zips in the browser because artifacts can't serve .zip files.

## Coding notes (ForeverMetrics)
- Nothing can be tested in-game from a cloud session. Ask the user to test and run `/fm debug`, which prints caught errors to chat.
- Forever uses "secret values": wrap any value read from chat events, unit APIs or loot in `safe()` (`issecretvalue` check) before comparing or matching it.
- Forever blocks `COMBAT_LOG_EVENT_UNFILTERED` with a popup pcall can't catch. Don't register it.
- Register events with `pcall(frame.RegisterEvent, ...)` and wrap handlers in pcall, printing errors only when `FM.debug` is on.
- Settings: add a row to `FM.SETTINGS` in Core.lua with a `group`; UI.lua builds the Options pages from it. Read with `FM:GetSetting(key)`, react with `FM:OnSetting(key, fn)`.
- Chat parsing builds patterns from Blizzard's global strings where possible; some parsing (gold looted, AP tooltips) is English-only.
- Saved data is one account-wide SavedVariable, `ForeverMetricsDB`. Never reset or rename existing keys; migrate them.
