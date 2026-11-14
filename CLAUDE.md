# WoW_Forever

WoW addons (Lua) for World of Warcraft: Forever, an Era-style Classic client built on the modern (Midnight-era) API. Written for two players: the repo owner and their wife, who play as a duo on the same realm and guild.

## Layout
- `addons/<Addon>/`: one folder per addon, shipped as-is into `Interface\AddOns`. The `.toc` file name must match the folder name.
- `tools/package.py`: `python tools/package.py [Addon]` builds `dist/<Addon>-<version>.zip` (forward-slash paths, one top-level folder). `dist/` is gitignored.

## Releasing
- Bump `## Version:` in the `.toc`, the version in the addon's README heading, and the table in the root README.
- Both duo players should run the same ForeverMetrics version: Duo.lua's message protocol is shared.
- ForeverMetrics has a private claude.ai download page (https://claude.ai/artifact/5uc8EoX6aai9a47DDt3JWb, owned by the repo owner). It serves the addon files as `addon-files.json` (`{"folder": "ForeverMetrics", "files": {name: text}}`) and builds the zip in the browser. After a release, regenerate that JSON from `addons/ForeverMetrics/`, update the version text in the page, and republish it to the same URL.

## Coding notes (ForeverMetrics)
- Nothing can be tested in-game from a cloud session. Ask the user to test and run `/fm debug`, which prints caught errors to chat.
- Forever uses "secret values": wrap any value read from chat events, unit APIs or loot in `safe()` (`issecretvalue` check) before comparing or matching it.
- Forever blocks `COMBAT_LOG_EVENT_UNFILTERED` with a popup pcall can't catch. Don't register it.
- Register events with `pcall(frame.RegisterEvent, ...)` and wrap handlers in pcall, printing errors only when `FM.debug` is on.
- Settings: add a row to `FM.SETTINGS` in Core.lua with a `group`; UI.lua builds the Options pages from it. Read with `FM:GetSetting(key)`, react with `FM:OnSetting(key, fn)`.
- Chat parsing builds patterns from Blizzard's global strings where possible; some parsing (gold looted, AP tooltips) is English-only.
- Saved data is one account-wide SavedVariable, `ForeverMetricsDB`. Never reset or rename existing keys; migrate them.
