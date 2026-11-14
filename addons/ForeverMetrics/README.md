# Forever Metrics (v0.15.0)

A RuneMetrics-style tracker for World of Warcraft: Forever. It keeps an activity feed and stats for every character, and you can swap between characters or view totals for your whole account.

## Install
1. Exit WoW.
2. Put the `ForeverMetrics` folder in your AddOns folder:
   - Beta: `World of Warcraft\_classic_beta_\Interface\AddOns\`
   - Live (Nov 4): use whatever folder Forever installs into, under `Interface\AddOns\`
3. Log in on each character once. Each character starts tracking from that point on.

## Commands
- `/fm` opens or closes the window
- `/fm session` prints a recap of the current session in chat
- `/fm debug` shows errors in chat, which is useful if something isn't tracking
- `/fm feed` turns the on-screen feed on or off
- `/fm feed lines 5`, `/fm feed hold 60`, `/fm feed scale 1.2` set how many lines stay on screen together, how many seconds the feed stays after the last new entry before fading out, and its size
- `/fm feed test` shows a sample entry and prints whether the feed is on, visible, and on screen. `/fm feed reset` puts it back in its default spot.
- `/fm move` unlocks the feed for dragging without Edit Mode (run it again to lock)

## The window (redesigned in v0.9.0)
`/fm` opens a larger window with a side menu on the left. Some sections have tabs along the top.

- **Home:**
  - **Dashboard:** six cards, refreshed every few seconds:
    - This session: time, XP and XP/hr, kills, quests, nodes, gold, best loot
    - Next level: progress bar, rested XP, time to level
    - Duo: your partner's character, level, zone, and time together (**Open** jumps to the Duo page)
    - Last level-up (**Replay** shows the pop-up again)
    - Recent finds (hover for the item tooltip)
    - This character: lifetime totals
  - **Details:** the full stats page.
- **Activity:** Feed, Loot log, and Luck tabs.
- **Gathering** and **Combat**
- **Duo:** Partner (scoreboard and highlights) and Options tabs.
- **Options:**
  - **Interface:** tabs for XP Pill, Feed, and Level Up
  - **Unit Frames**
  - **Tooltips**
  - **Chat**
  - **Quality of Life**

The window title shows the installed version, like "Forever Metrics v0.15.0", and so does the "loaded" line in chat at login.

`<` and `>` at the top right switch characters (including "All Characters") on pages that show one character's data. `/fm settings` opens straight to the Options pages.

## XP pill
A small pill shows your level and current XP, with a thin progress bar along the bottom (blue is rested XP). Hover it, or bind "Expand / collapse XP pill" to a key or controller button, to open the details: XP to level, rested XP, xp/hr, estimated time to ding, and session stats. Every XP gain pops a "+245 xp" beside it that grows, then fades away. It dims in combat.

- `/fm pill` turns it on or off. `/fm pill scale 1.2`, `/fm pill reset`, and `/fm pill test` are also available.
- `/fm xpbar` hides or shows Blizzard's XP bar.

## Activity
The Activity section has three tabs:
- **Feed**: everything that's happened, newest first. Blues and epics get a "RARE FIND!" tag.
- **Loot log**: how many drops of each quality you've looted, cloth totals (linen, wool, silk...), and recent green-or-better finds with the mob, zone, and kill number they dropped on.
- **Luck**: your drop rates (like "1 green per 42 kills"), kills since your last green and blue, your longest drought, your luckiest zones, your most-hunted mobs, and a log of every blue you've found.

Loot tracking counts each corpse once and skips gathering nodes. It started with v0.4.0, so older kills don't count toward your rates.

## Duo mode (new in v0.5.0)
Play with someone else who runs Forever Metrics and the two addons link up.

- **Pairing:** when someone in your guild or group is running Forever Metrics, a popup asks whether to add them as your duo partner. Accept once on each side. After that, every character on their account is recognized automatically, alts included.
- **Staying connected:** if you share a guild, you reconnect on login even when you aren't grouped. Otherwise you connect once you group up.
- **What you see:**
  - A small pink strip under the XP pill with your partner's character, level, and XP progress. Click it to open the Duo tab.
  - Their level-ups, rare finds, deaths, and skill and gathering milestones in your on-screen feed.
  - A **Duo** tab with what they're playing right now, a head-to-head scoreboard (account totals), "together" stats (time, kills, quests, and levels while grouped), and their recent highlights.
- **Commands:**
  - `/fm duo` lists your partners and whether they're online
  - `/fm duo add Name` sends a pairing request to a character
  - `/fm duo name Nickname` renames your partner (use `/fm duo name Partner Nickname` if you have more than one)
  - `/fm duo remove Name` unpairs
  - `/fm duo ping` looks for your partner again right now
- **Notices:** "is online" and "logged off" notices appear in the on-screen feed, not in chat. When your partner logs out, Forever Metrics notices right away and hides the "No player named X is currently playing" errors its own background updates would otherwise cause.
- Both of you should run the same version of Forever Metrics.

## Level-up celebration (new in v0.7.0)
From v0.15.0 the pop-up has two columns: your new level, how long the last one took, stat gains and talent points on the left, and a scrolling list of skills on the right: what's new this level, then everything coming at the next level that brings new skills, with the training cost underneath. On a controller, the D-pad scrolls the list.

When you ding, a pop-up shows your new level, how long the last level took, your stat gains, any new talent point, and the class skills that just unlocked at your trainer, with their costs and your gold.

- **New skills:** the list comes from three places: your class trainer (visit it once and it remembers the full list, including skills you're too low for), your spellbook (every spell it lists with the level it's learned at), and any spell you learn right around the ding. Each skill shows **learned**, its training cost, or **at trainer**. On a level with nothing new, it shows "New skills at level N" with the next level's skills and their icons (v0.11.3). Upcoming skills come from the trainer, so they need a successful trainer read. Before v0.14.1, each spell kept only its highest rank (Forever's trainer reports skills differently from Classic), so visit each class trainer once after updating to fill in every rank. This keeps it accurate to Forever, with no hard-coded spell lists.
- **In combat:** if you level up mid-fight, the pop-up waits until combat ends.
- **No missed levels (v0.11.5):** levels are tracked by comparing your real level with the last one recorded, after every level event and at the end of each fight. So a ding from a kill, where Forever hides the event's values, is still recorded. If you gained levels while the addon wasn't running, they're logged at login (without a pop-up).
- **Blizzard's banner:** the pop-up waits until Blizzard's own "You've Reached Level N" banner has finished (up to 8 seconds), so they don't overlap. Turn on **Hide Blizzard's level-up banner** under Options > Interface > Level Up to skip Blizzard's and show ours right away (v0.11.4).
- **Closing it:** click "Nice!", or press Esc, A, or B. It also fades out on its own after 30 seconds, and you can drag it to move it.
- **Replay:** to see your last level-up again, click **Replay** on the Home dashboard or under Options > Interface > Level Up, or type `/fm levelup last`. Each character remembers its own last ding, even when the pop-up is turned off. If nothing is saved yet, it rebuilds the pop-up for your current level, without stat gains.
- **Skill tooltips (v0.11.0):** each new skill shows its icon, and hovering it shows the spell's tooltip. Skills saved before v0.11.0 show a short summary until you visit your trainer again. The pop-up stays open while your mouse is over it.
- **Checking the skill list:** `/fm levelup check` shows what each source can see and lists the skills for your current level and the next two. Run it with your class trainer open and it also prints the trainer's first few entries, which shows why a trainer read fails. If reading the trainer fails, a chat message says so once.
- `/fm levelup test` previews it, and `/fm levelup` turns it on or off.

## Combat text (new in v0.10.0)
Options > **Combat Text** has two tabs.

**Floating gains** is our own floating text. It rises above your character, one item at a time so nothing overlaps:
- Money (+1g 20s), items looted with their icon (you choose the quality threshold), reputation (+25 Stormwind), skill-ups (+1 Mining (76)), and optionally XP
- Quick gains, like several coins or kill XP plus quest XP, combine into one total
- New lines come in at the bottom and push older ones up, with a gap between them. "Space between lines" sets the gap (v0.11.0).
- Options for text size and for hiding it during combat
- To move it, use Edit Mode (the "Forever Metrics Floating Text" box) or `/fm fct move`. `/fm fct reset` puts it back.
- `/fm fct test` shows samples, and `/fm fct` turns it on or off.

**Blizzard** has switches for WoW's own combat text:
- Your damage numbers, DoT ticks, pet damage, healing, and damage number size
- Incoming text on your character, and which way it scrolls
- Dodge/parry/miss, resists, entering and leaving combat, spell alerts, low health warnings, resource gains, auras, combo points, reputation, and honor

These are game settings, so WoW saves them itself. Options this client doesn't have are hidden, and they can't be changed in combat.

**No damage text:** Forever blocks addons from reading the combat log, so floating gains don't show damage or spells. For damage numbers, use the Blizzard tab. (Spell cast and hit text was tried in v0.11 and removed in v0.12.0.)

## Unit frames (new in v0.13.0)
Options > **Unit Frames** has switches for Blizzard's own player, target and party frames:
- **Always show health and mana numbers**, instead of only when you hover the bar
- **Health and mana text:** numbers, percent, both, or only on hover (on clients that have this setting)
- **Show health and mana as a percent** (on clients that have this setting instead)
- **Show target of target** and **Show your target's cast bar**

These are game settings, so WoW saves them itself. Options this client doesn't have are hidden, and they can't be changed in combat. The text updates right away; if it doesn't, type `/reload`.

## Chat (new in v0.8.0)
- **Hide chat buttons (keeps the tabs):** hides the chat menu, channel, voice, and social buttons, each chat window's scroll buttons and bar, and the combat log filter bar. The chat tabs stay visible. The buttons stay hidden even when chat fades in on hover, and turning the option off brings them back.
- **Hide the chat window background:** makes every chat window's background fully transparent, so you see just the text. It uses WoW's own chat opacity setting, and turning it off restores the opacity you had before. Blizzard may still briefly show the background while your mouse is over the chat.

## Quality of Life (new in v0.7.0)
These Leatrix-style toggles are all off by default. Find them under Options > Quality of Life.
- **Sell grey items at vendors:** sells your junk when you open a merchant and tells you what it earned.
- **Repair gear at vendors:** repairs everything with your own gold whenever the merchant can repair.
- **Faster auto loot:** grabs all the loot at once. It follows your Auto Loot game setting and the key that flips it.
- **Decline duel requests:** automatically declines duels.

## AP to stat tooltips (new in v0.6.0, formerly APtoStat)
Item tooltips with Attack Power get an extra blue line showing what that AP is worth in Strength or Agility for your class, like "40 AP = 20 Strength". Items with Strength or Agility also get a "Total melee AP from item" line, which makes comparing gear easier.

- Uses base ratios, before talents and buffs. Conditional AP (vs Undead/Demons, feral forms only) is skipped so it doesn't overstate an item.
- Hunters also see ranged AP converted to Agility.
- `/fm ap` turns it on or off, and `/fm ap total` toggles the total line. The old `/ap2s` command still works. Both toggles are also under Options > Tooltips.

## Settings
Every toggle lives under **Options** in the side menu, and `/fm settings` jumps straight there. Each page has a short note at the bottom. Any new settings group added in Core.lua gets its own page automatically.

## On-screen feed + Edit Mode
New activity (level-ups, quests, green+ loot, skill milestones, deaths, new zones, duo notices) appears in a small feed. From v0.14.0 it also shows the same gains as the floating text: XP, money, loot, reputation and skill-ups (turn off with "Also show gains" under Options > Interface > Feed). These lines are only shown, not saved to your history, and they follow the floating text's "Items to show" quality setting. With gains on, `/fm feed lines 8` shows more at once. The last 5 lines stay on screen together, and the feed fades out 60 seconds after the last new entry.

To place it, open **Edit Mode** (Esc > Edit Mode). The feed shows up as a blue box labeled "Forever Metrics Feed" with sample lines. Drag it where you want, then close Edit Mode. The position is saved for all your characters.

## Controller (gamepad) support
- **Bind a button to open it:** go to Options > Keybindings > AddOns > Forever Metrics and bind "Open / close Forever Metrics" to any controller button or combo. There's also a "Print session recap" binding.
- **While the window is open:**
  - D-pad up/down: move through the side menu
  - A (Cross): enter the page. On an options page, D-pad up/down then picks a toggle and A switches it. On other pages, D-pad up/down scrolls.
  - B (Circle): go back to the side menu, or close the window if you're already there
  - LB / RB (L1 / R1) or Y: switch tabs
  - D-pad left/right: switch character on pages that show one
  - Right stick: scroll
  - The hint line at the bottom always shows what each button does
- Any other buttons pass through to the game, and closing the window hands every button back. It won't block your controls in combat.
- If a client ever lacks the gamepad API, the window works normally with mouse and keyboard.

## What it tracks
- **Overview:** time tracked, XP, levels, quests, gold looted/earned/spent, time per level, favorite zones, and the current session
- **Activity:** level-ups, quests, green-or-better loot, skill milestones (every 25 points), deaths, and first-time zone visits
- **Gathering:** mining, herb, skinning, and fishing node counts, plus what came out of them; also skill levels
- **Combat:** kills, deaths, and the mobs you've defeated most

Use the `<` and `>` buttons to cycle through your characters and "All Characters."

## Known limits (v1)
- Kills are counted from "X dies, you gain Y experience" messages, so mobs that give no XP aren't counted.
- Gold-looted parsing is English-only for now.
- Skill levels appear after the first skill-up on each character.
- Forever's controller mode is labeled alpha, so button names may change. If a button stops responding, `/fm debug` will show it.
- Forever beta bug: some addons report that SavedVariables aren't reloaded on login, which would reset your data each session. That's a Blizzard bug and should be fixed by launch.
