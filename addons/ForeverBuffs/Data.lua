-- Forever Buffs: which buffs each class should keep up.
--
-- Everything the addon reminds about lives in this table, so adjusting a
-- class means editing a few lines here. Each class has a list of reminders.
-- A reminder is satisfied when ANY of its spells (or `counts` names) is on you.
--
-- Fields of a reminder:
--   key      unique id within the class (also used to remember your choice)
--   label    name shown in tooltips and /fb list
--   spells   { spellID, "English name" } pairs. Matching is by name, so every
--            rank counts; the ID is only used to get the name in your game's
--            language, the icon and the tooltip. The first spell you know is
--            the one a click casts, unless you were last seen using another.
--   counts   extra buff names that also satisfy it but that you don't cast
--            yourself from here (group versions, e.g. Arcane Brilliance)
--   weapon   "main" or "off": check a temporary weapon enchant with
--            GetWeaponEnchantInfo() instead of a buff
--   poison   true: the fix is a poison from your bags (rogues), not a spell
--   gate     name of an extra check in Core.lua (FB.GATES) that must pass
--   minRage  only remind when you have at least this much rage (shouts)

local ADDON, ns = ...
local FB = {}
ns.FB = FB

FB.BUFFS = {
  MAGE = {
    { key = "int", label = "Arcane Intellect",
      spells = { { 1459, "Arcane Intellect" } },
      counts = { { 23028, "Arcane Brilliance" } } },
    { key = "armor", label = "Armor",
      spells = { { 6117, "Mage Armor" }, { 7302, "Ice Armor" }, { 168, "Frost Armor" } } },
  },

  WARRIOR = {
    -- Shouts cost rage, which drains out of combat, so this only shows while
    -- you have enough rage to cast it.
    { key = "shout", label = "Battle Shout", minRage = 10,
      spells = { { 6673, "Battle Shout" } } },
  },

  DRUID = {
    { key = "motw", label = "Mark of the Wild",
      spells = { { 1126, "Mark of the Wild" } },
      counts = { { 21849, "Gift of the Wild" } } },
    { key = "thorns", label = "Thorns",
      spells = { { 467, "Thorns" } } },
  },

  SHAMAN = {
    { key = "shield", label = "Lightning Shield",
      spells = { { 324, "Lightning Shield" } } },
    { key = "imbue", label = "Weapon imbue", weapon = "main",
      spells = { { 8232, "Windfury Weapon" }, { 8024, "Flametongue Weapon" },
                 { 8017, "Rockbiter Weapon" }, { 8033, "Frostbrand Weapon" } } },
  },

  ROGUE = {
    { key = "mhPoison", label = "Main-hand poison", weapon = "main", poison = true, gate = "poisons" },
    { key = "ohPoison", label = "Off-hand poison", weapon = "off", poison = true, gate = "poisons" },
  },

  PRIEST = {
    { key = "fort", label = "Power Word: Fortitude",
      spells = { { 1243, "Power Word: Fortitude" } },
      counts = { { 21562, "Prayer of Fortitude" } } },
    { key = "innerFire", label = "Inner Fire",
      spells = { { 588, "Inner Fire" } } },
  },

  PALADIN = {
    { key = "blessing", label = "Blessing",
      spells = { { 19740, "Blessing of Might" }, { 19742, "Blessing of Wisdom" },
                 { 20217, "Blessing of Kings" }, { 1038, "Blessing of Salvation" },
                 { 19977, "Blessing of Light" }, { 20911, "Blessing of Sanctuary" } },
      counts = { { 25782, "Greater Blessing of Might" }, { 25894, "Greater Blessing of Wisdom" },
                 { 25898, "Greater Blessing of Kings" }, { 25895, "Greater Blessing of Salvation" },
                 { 25890, "Greater Blessing of Light" }, { 25899, "Greater Blessing of Sanctuary" } } },
    { key = "aura", label = "Aura",
      spells = { { 465, "Devotion Aura" }, { 7294, "Retribution Aura" },
                 { 19746, "Concentration Aura" }, { 20218, "Sanctity Aura" },
                 { 19876, "Shadow Resistance Aura" }, { 19888, "Frost Resistance Aura" },
                 { 19891, "Fire Resistance Aura" } } },
  },

  HUNTER = {
    { key = "aspect", label = "Aspect",
      spells = { { 13165, "Aspect of the Hawk" }, { 13163, "Aspect of the Monkey" },
                 { 5118, "Aspect of the Cheetah" }, { 13159, "Aspect of the Pack" },
                 { 13161, "Aspect of the Beast" }, { 20043, "Aspect of the Wild" } } },
  },

  WARLOCK = {
    { key = "armor", label = "Demon Armor",
      spells = { { 706, "Demon Armor" }, { 687, "Demon Skin" } } },
  },
}

-- Rogue poisons, by English item-name prefix, in the order we pick them for
-- each hand. Rank (I, II, ...) doesn't matter; the best one in your bags wins.
FB.POISONS = {
  main = { "Instant Poison", "Deadly Poison", "Wound Poison", "Crippling Poison", "Mind-numbing Poison" },
  off  = { "Deadly Poison", "Instant Poison", "Crippling Poison", "Mind-numbing Poison", "Wound Poison" },
}

-- The rogue "Poisons" skill, learned at level 20.
FB.POISONS_SPELL = { 2842, "Poisons" }

-- Shown by /fb test and in Edit Mode
FB.SAMPLES = {
  { 1459, "Arcane Intellect" },
  { 168, "Frost Armor", 42 },
  { 6673, "Battle Shout" },
}
