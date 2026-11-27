# Forever Metrics (v0.17.13)

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
- `/fm stats test` (temporary, v0.17.13) prints which stats pane this client uses, whether addons can add rows to it, and what each stat function returns (hit, weapon skill, armor, spell power, item level...). Run it with the character window open and a mob targeted.
- `/fm minimap test` (temporary, v0.17.3) lists every minimap tracking option the game offers addons, to check whether Forever can track vendors, repair and trainers on the minimap.
- `/fm threat test` (temporary, v0.16.9) prints what the game's threat functions return for your target, for you, your pet and your party, and marks any value the game hides from addons as SECRET. `/fm threat watch` (from v0.16.10) puts one compact line in the on-screen feed whenever threat changes while you fight, like `[T] Kolkar Wrangler: Kil'hala 100% tank · You 72% · Lindabelcher secret`, and a count of threat events after each fight. These lines aren't saved to your activity history. With the feed turned off they go to chat. This is to check whether a threat meter can work on Forever.

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

The window title shows the installed version, like "Forever Metrics v0.17.13", and so does the "loaded" line in chat at login.

`<` and `>` at the top right switch characters (including "All Characters") on pages that show one character's data. `/fm settings` opens straight to the Options pages.

## XP pill
A small pill shows your level and current XP, with a thin progress bar along the bottom. The bar is gold, and turns blue while you have rested XP (from v0.16.3, on the dashboard's Next level bar too); a fainter blue strip past it shows how far your rested XP reaches. Hover it, or bind "Expand / collapse XP pill" to a key or controller button, to open the details: XP to level, rested XP, xp/hr, estimated time to ding, and session stats. Every XP gain pops a "+245 xp" beside it that grows, then fades away. It dims in combat.

- `/fm pill` turns it on or off. `/fm pill scale 1.2`, `/fm pill reset`, and `/fm pill test` are also available.
- `/fm xpbar` hides or shows Blizzard's XP bar.

## Activity
The Activity section has three tabs:
- **Feed**: everything that's happened, newest first. Blues and epics get a "RARE FIND!" tag.
- **Loot log**: how many drops of each quality you've looted, cloth totals (linen, wool, silk...), and recent green-or-better finds with the mob, zone, and kill number they dropped on.
- **Luck**: your drop rates (like "1 green per 42 kills"), kills since your last green and blue, your longest drought, your luckiest zones, your most-hunted mobs, and a log of every blue you've found.
- **Waylaid Crates (v0.17.9)**: the Luck tab shows how many crates you've looted and how often ("1 per 431 kills"), counting ones looted before this version, plus Craftsman's Writs, the zones that dropped them, and kills since your last crate. Each crate also gets a feed line with the kills since the previous one.

Loot tracking counts each corpse once and skips gathering nodes. From v0.16.1 it also tallies every item you loot by name, quality and count, so the stats page can list loot of every quality, poor and common included. It started with v0.4.0, so older kills don't count toward your rates.

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
From v0.15.0 the pop-up has two columns: your new level, how long the last one took, stat gains and talent points on the left, and a scrolling list of skills on the right: what's new this level, then everything coming at the next level that brings new skills, with each skill's training cost. From v0.16.5 each section heading shows its training cost on the right: **New this level** totals what you haven't trained up to this level ("incl. skipped" means it counts skills you skipped at earlier levels too), and **Next up** shows the next level's cost and the total of both. On a controller, the D-pad scrolls the list.

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

## Professions and inventory (new in v0.16.0)
Forever Metrics now remembers, for each character, what the stats page needs to show your crafting:
- **Recipes:** every recipe you know, with its icon, what it makes and its reagents. Saved when you open a profession window (Enchanting's too).
- **Trainer recipes:** when you open a profession trainer, every recipe it teaches and the skill each needs. That's how the page lists what you could learn now and what's coming up.
- **Bags and bank:** what you're carrying, refreshed as your bags change. The bank is saved when you open it.

Nothing new shows in game. To fill the page in: open each profession window once, visit each profession trainer once, open your bank once, then log out and send your saved-variables file.

## Unit frames (new in v0.13.0)
Options > **Unit Frames** has switches for Blizzard's own player, target and party frames:
- **Always show health and mana numbers**, instead of only when you hover the bar
- **Health and mana text:** numbers, percent, both, or only on hover (on clients that have this setting)
- **Show health and mana as a percent** (on clients that have this setting instead)
- **Show target of target** and **Show your target's cast bar**

These are game settings, so WoW saves them itself. Options this client doesn't have are hidden, and they can't be changed in combat. The text updates right away; if it doesn't, type `/reload`.

## Chat (new in v0.8.0)
- **Hide chat buttons (keeps the tabs):** hides the chat menu, channel, voice, and social buttons, each chat window's scroll buttons and bar, and the combat log filter bar. The chat tabs stay visible. The buttons stay hidden even when chat fades in on hover, and turning the option off brings them back.
- **Hide chat until you mouse over it or type (new in v0.16.2):** chat windows, tabs and chat buttons stay fully invisible. They fade in while your mouse is over a chat window or its tabs, or while you're typing (press Enter), and fade out about 1.5 seconds after. New messages don't bring chat back on their own, so check it now and then for whispers. Links in invisible chat can still be clicked.
- **Hide the chat window background:** makes every chat window's background fully transparent, so you see just the text. It uses WoW's own chat opacity setting, and turning it off restores the opacity you had before. Blizzard may still briefly show the background while your mouse is over the chat.

## Threat meter (new in v0.17.0)
A small list of threat on your target, shown in combat with a hostile target and hidden after. It uses the game's own threat numbers, since Forever blocks the combat log.
- **Rows:** you, your pet and your party, highest threat first, in class colours. `[T]` and `[H]` mark the group's tank and healer when roles are set; otherwise it's just names and classes. A gold edge marks whoever the mob is attacking. Your row has a gold outline and turns yellow, orange, then red as you near the warning point.
- **Warning:** when you don't have aggro and reach 90% (or the % you pick), a "PULLING AGGRO" banner shows mid-screen and a `[T]` line goes into the feed, with an optional sound. It shows once per climb and re-arms when you drop back down.
- **Options > Threat Meter:** on/off, everyone or just you, the warning and its %, sound, hide when solo with no pet, and size.
- **Moving it:** Edit Mode (it shows sample rows), or `/fm threat move` to unlock and lock it.
- `/fm threat test` and `/fm threat watch` still print the raw numbers, for checking.

## Talent planner (new in v0.17.5)
Try talent builds without spending a point. Open it with the **Plan** and **Plan lv 60** buttons beside Blizzard's talent window, or `/fm talents` (your level's points) and `/fm talents 60` (a full 51-point build).
- Your class's three trees with the real talents. Left-click adds a point, right-click takes one back, following the game's rules: 5 points in a tree per tier before the next, and talents that need another maxed first. Talents you can't take yet are greyed; hover one to see why.
- The header shows points used of your budget and the split per tree (like 31 / 0 / 20). **Start from my talents** copies your real build in, **Clear** empties it, and the level button switches between your level and a level 60 build.
- Plans are saved per character. Your real talents are never changed.
- `/fm talents test` (v0.17.6) prints what this client's talent functions return, for when the planner can't read the trees.

## Shops on the minimap (new in v0.17.4)
Options > Minimap switches on Blizzard's town tracking, so shop icons show on the minimap: Repair, Food & Drink, Innkeeper, Flight Master, Mailbox, Banker, Auctioneer and the trainers are on by default; Stable Master, Ammunition, Poisons, Reagents and Item Upgrade are there to tick. Types this game doesn't have are hidden.
- **Only in towns:** shop icons show while you're resting (a city or an inn) and clear away outside.
- Gathering tracking (herbs, minerals) isn't touched. For the shop types listed, this page wins over the minimap's own tracking menu.

## Quality of Life (new in v0.7.0)
These Leatrix-style toggles are all off by default, except mail contacts and zone levels.
- **Zone levels on the world map (new in v0.17.1, on by default):** hover a zone on a continent map, or open a zone's map, and its level range shows at the top, under the map's own zone name, like "Levels 10-20". The range is coloured against your level the way quests are: red or orange too high, yellow about right, green easy, grey far below. It uses the game's own zone levels when it has them, otherwise the standard Classic ranges, which Forever may have changed in places. Find them under Options > Quality of Life.
- **Mail contacts (new in v0.16.7, on by default):** a list beside the Send Mail tab with the people you've mailed recently, everyone on your friends list (offline friends too, greyed; the game's own name suggestions only offer online ones), and your other characters on this realm. Click a name to fill in "To:". Right-click a recent name to forget it. Recent names are saved per realm, the last 15.
  - Full names (from v0.16.8): mail needs Forever's first and last name. Your current character's is read at login from your player frame. Any mail that goes through teaches the full name of that alt or friend. A name whose surname isn't known yet has a "…" after it; clicking fills in "First " so you can type the surname, and it's remembered from then on.
- **Sell grey items at vendors:** sells your junk when you open a merchant and tells you what it earned.
- **Repair gear at vendors:** repairs everything with your own gold whenever the merchant can repair.
- **Faster auto loot:** grabs all the loot at once. It follows your Auto Loot game setting and the key that flips it.
- **Decline duel requests:** automatically declines duels.

## AP to stat tooltips (new in v0.6.0, formerly APtoStat)
Item tooltips with Attack Power get an extra blue line showing what that AP is worth in Strength or Agility for your class, like "40 AP = 20 Strength". Items with Strength or Agility also get a "Total melee AP from item" line, which makes comparing gear easier.

- Uses base ratios, before talents and buffs. Conditional AP (vs Undead/Demons, feral forms only) is skipped so it doesn't overstate an item.
- Hunters also see ranged AP converted to Agility.
- `/fm ap` turns it on or off, and `/fm ap total` toggles the total line. The old `/ap2s` command still works. Both toggles are also under Options > Tooltips.

## Gathering skill on tooltips (new in v0.17.9)
Hover a beast (alive or dead), a corpse marked "Skinnable", a mining node or an herb and the tooltip adds the skill it needs against yours (needed/yours): **S(120/112)** for Skinning, **M(65/40)** for Mining, **H(70/50)** for Herbalism. Green means you can gather it, red means you can't yet. On a character without that skill it shows just what's needed, in gold: **S(120)**. Skinning uses Classic's rule (up to level 10 needs 1, levels 11-20 need (level - 10) x 10, above that level x 5) and nodes use Classic's skill table, which Forever is assumed to share. Turn it off under Options > Tooltips.

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
