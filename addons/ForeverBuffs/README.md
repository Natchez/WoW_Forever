# Forever Buffs (v0.1.0)

A small row of icons for the self-buffs you should have up but don't. It stays hidden when nothing is missing. Click an icon to cast that buff.

## Install
1. Exit WoW.
2. Put the `ForeverBuffs` folder in your `Interface\AddOns\` folder, so you end up with `AddOns\ForeverBuffs\ForeverBuffs.toc`.
3. Log in. If a buff is missing, its icon shows below the middle of the screen. Use Edit Mode or `/fb move` to put it somewhere else.

## What it reminds you about
Only spells your character knows are checked. Buffs are matched by name, so any rank counts, and so do buffs someone else cast on you.

| Class | Reminders |
|---|---|
| Mage | Arcane Intellect (Arcane Brilliance counts); one armor: Frost, Ice or Mage Armor |
| Warrior | Battle Shout, only while you have 10+ rage (it costs rage, which drains out of combat) |
| Druid | Mark of the Wild (Gift of the Wild counts); Thorns |
| Shaman | Lightning Shield; a main-hand imbue: Rockbiter, Flametongue, Frostbrand or Windfury Weapon |
| Rogue | A poison on the main hand and on the off hand, once you have Poisons (level 20) |
| Priest | Power Word: Fortitude (Prayer of Fortitude counts); Inner Fire |
| Paladin | Any Blessing (Greater ones count); any Aura |
| Hunter | Any Aspect |
| Warlock | Demon Armor or Demon Skin |

When a reminder has a choice (mage armor, shaman imbue, paladin aura...), the icon casts the one you used last, or the best one you know.

A buff with less than 60 seconds left also shows, with the time left on the icon.

Weapon reminders only show when there's a weapon in that hand.

## Click to cast
- Spells are cast on yourself.
- Rogue poisons: the icon uses a poison from your bags on the right weapon (Instant first on the main hand, Deadly first on the off hand). If you have no poison, the icon is grey and only reminds you.

## When it checks
Out of combat only: when your buffs or gear change, when you learn a spell, when combat ends, and once a second for buffs about to run out. During combat the icons stay as they were (WoW doesn't let addons change clickable buttons in combat).

It hides while you're dead, on a flight path or in a vehicle. Optionally it also hides while resting in a city or inn.

## Commands
- `/fb` turns reminders on or off
- `/fb move` unlocks the icons for dragging (run it again to lock). Edit Mode works too.
- `/fb reset` puts the icons back in the default spot and size
- `/fb scale 1.2` sets the size (0.5 to 2)
- `/fb city` toggles "Only remind outside cities" (off by default)
- `/fb glow` toggles the gentle pulse around missing buffs
- `/fb test` shows sample icons for 15 seconds
- `/fb list` prints what's tracked for this character and which spells it thinks you know
- `/fb options` opens the options panel (Esc > Options > AddOns > Forever Buffs)
- `/fb debug` prints errors in chat. Turn this on if something looks wrong.

Settings and position are saved for your whole account in `ForeverBuffsDB`.

## Limits
- Untested in game at release. If something is off, run `/fb debug` and `/fb list` and share what they print.
- Rogue poison detection looks for "Poison" in the item name, so it only works in English.
- No reminders for buffs cast on others, food buffs, or pets.
- Changes made in combat (for example a buff falling off) show up once combat ends.
