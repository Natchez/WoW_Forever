-- Forever Metrics: Core
-- Tracks stats + an activity feed per character. All characters share one
-- account-wide SavedVariable (ForeverMetricsDB), which is what lets you swap
-- between characters and see totals across your whole account.

local ADDON, ns = ...
local FM = {}
ns.FM = FM
_G.ForeverMetrics = FM

local FEED_MAX = 300      -- activity entries kept per character
local SESSIONS_MAX = 20   -- session summaries kept per character
local TICK = 10           -- seconds between time-played/zone ticks

FM.GATHER_TYPES = { "Mining", "Herbalism", "Skinning", "Fishing" }

-- Spell name -> gathering type. Matched by name so we don't depend on
-- spell IDs, which may differ in Forever.
local GATHER_SPELLS = {
  ["Mining"] = "Mining",
  ["Herb Gathering"] = "Herbalism",
  ["Herbalism"] = "Herbalism",
  ["Skinning"] = "Skinning",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Forever uses Midnight's "secret values" system. A secret value can't be
-- read or compared by addons, so we treat it as missing.
local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

-- Turn a Blizzard format string such as "Your skill in %s has increased to %d."
-- into a Lua pattern. Using the game's own global strings keeps the parsing
-- closer to locale-proof.
local function fmtToPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
  return "^" .. p
end

local PAT_SKILL   = fmtToPattern(SKILL_RANK_UP) or "^Your skill in (.+) has increased to (%d+)"
local PAT_XPKILL  = fmtToPattern(COMBATLOG_XPGAIN_FIRSTPERSON) or "^(.+) dies, you gain (%d+) experience"
local PAT_LOOT    = fmtToPattern(LOOT_ITEM_SELF) or "^You receive loot: (.+)%."
local PAT_LOOT_M  = fmtToPattern(LOOT_ITEM_SELF_MULTIPLE) or "^You receive loot: (.+)x(%d+)%."

local function GetSpellNameCompat(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function GetItemQualityCompat(link)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not f then return nil end
  local ok, _, _, q = pcall(f, link)
  if ok then return q end
end

local function ZoneName()
  return safe(GetRealZoneText and GetRealZoneText()) or "Unknown"
end

local function ensureGather(char)
  char.gathering = char.gathering or {}
  for _, g in ipairs(FM.GATHER_TYPES) do
    char.gathering[g] = char.gathering[g] or { nodes = 0, items = {} }
  end
end

-- Loot tracking (corpse loot only, not gathering): quality counts, cloth,
-- per-mob / per-zone drop stats, notable finds and dry streaks.
FM.CLOTH = { "Linen Cloth", "Wool Cloth", "Silk Cloth", "Mageweave Cloth", "Runecloth", "Felcloth" }
local CLOTH_SET = {}
for _, n in ipairs(FM.CLOTH) do CLOTH_SET[n] = true end
local NOTABLE_MAX = 200

local function ensureLoot(c)
  c.loot = c.loot or {}
  local L = c.loot
  L.q = L.q or {}             -- quality -> number of drops
  L.cloth = L.cloth or {}     -- cloth name -> total quantity
  L.mobs = L.mobs or {}       -- mob -> { kills, greens, blues, purples }
  L.zones = L.zones or {}     -- zone -> { kills, greens, blues, purples }
  L.notable = L.notable or {} -- green+ finds, oldest first
  L.lastGreenKill = L.lastGreenKill or c.stats.kills
  L.lastBlueKill = L.lastBlueKill or c.stats.kills
  L.longestDry = L.longestDry or 0
  L.startKills = L.startKills or c.stats.kills  -- kills before loot tracking existed
end
FM.EnsureLoot = ensureLoot

local function bump(tbl, key, field, n)
  local e = tbl[key]
  if not e then e = { kills = 0, greens = 0, blues = 0, purples = 0 }; tbl[key] = e end
  e[field] = (e[field] or 0) + (n or 1)
end

local function newChar(name, realm)
  local c = {
    name = name, realm = realm, created = time(),
    played = 0, level = 1,
    stats = { kills = 0, deaths = 0, quests = 0, levels = 0, xp = 0,
              goldLooted = 0, goldEarned = 0, goldSpent = 0 },
    kills = {},      -- mob name -> count
    skills = {},     -- skill name -> { rank, gains }
    zones = {},      -- zone -> seconds spent
    levelTimes = {}, -- level -> seconds it took to reach
    feed = {},
    sessions = {},
  }
  ensureGather(c)
  return c
end

---------------------------------------------------------------------------
-- Public API (used by UI.lua)
---------------------------------------------------------------------------

function FM:Char() return self.char end
function FM:CharKey() return self.key end
function FM:DB() return ForeverMetricsDB end
function FM:Session() return self.session end

-- Theme: warm brown panels, soft gold trim, rounded (tooltip-style) corners.
FM.THEME = {
  bg     = { 0.12, 0.085, 0.055, 0.90 },  -- dark leather brown
  border = { 0.66, 0.51, 0.31, 0.95 },  -- worn gold trim
  bar    = { 0.88, 0.67, 0.30, 1 },     -- amber progress
  rested = { 0.48, 0.58, 0.80, 0.50 },  -- muted blue for rested
  hl     = { 0.88, 0.67, 0.30, 0.18 },  -- selection highlight
}

function FM:Skin(f, opts)
  if not f or not f.SetBackdrop then return end
  opts = opts or {}
  local edge = opts.edge or 12
  local inset = math.floor(edge / 4 + 0.5)
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = edge,
    insets = { left = inset, right = inset, top = inset, bottom = inset },
  })
  local bg, br = self.THEME.bg, self.THEME.border
  f:SetBackdropColor(bg[1], bg[2], bg[3], opts.alpha or bg[4])
  f:SetBackdropBorderColor(br[1], br[2], br[3], br[4])
end

-- Settings (account-wide). The Options pages in /fm are built from these
-- lists: each setting names its group, and UI.lua decides which page shows
-- which group. To add a toggle, add a line here and read it with
-- FM:GetSetting(key).
--
-- Row types:
--   default = true/false        a checkbox
--   action = "Method"           a button that runs FM:Method()
--   choices = { {v, "Label"} }  a button that cycles through values
--   cvar = "name"               reads/writes a game CVar instead of our
--                               SavedVariables (hidden if the game lacks it)
FM.SETTING_GROUPS = {
  { key = "pill",     label = "XP Pill" },
  { key = "feed",     label = "Activity Feed" },
  { key = "levelup",  label = "Level Up" },
  { key = "duo",      label = "Duo" },
  { key = "fct",      label = "Floating Gains" },
  { key = "fctBlizz", label = "Blizzard Combat Text" },
  { key = "tooltip",  label = "Tooltips" },
  { key = "chat",     label = "Chat" },
  { key = "qol",      label = "Quality of Life" },
}

FM.SETTINGS = {
  { group = "pill",    key = "pill",           label = "Show XP pill",                          default = true },
  { group = "pill",    key = "xpPopups",       label = "XP gain pop-ups",                       default = true },
  { group = "pill",    key = "pillCombatFade", label = "Dim XP pill in combat",                 default = true },
  { group = "pill",    key = "hideXPBar",      label = "Hide Blizzard's XP bar",                default = false },
  { group = "feed",    key = "feed",           label = "Show activity feed",                    default = true },
  { group = "levelup", key = "levelModal",     label = "Celebrate level-ups with a pop-up",     default = true },
  { group = "levelup", key = "hideBlizzLevelUp", label = "Hide Blizzard's level-up banner (otherwise ours waits for it)", default = false },
  { group = "levelup", key = "levelSkills",    label = "List new skills to train",              default = true },
  -- Rows with `action` are buttons: clicking runs FM:<action>() instead of toggling
  { group = "levelup", key = "replayLevelUp",  label = "Replay your last level-up",             action = "ReplayLevelUp", button = "Replay" },
  { group = "duo",     key = "duo",            label = "Duo mode (share with your partner)",    default = true },
  { group = "duo",     key = "duoFeed",        label = "Partner's highlights in the feed",      default = true },
  { group = "duo",     key = "duoBar",         label = "Partner's XP under the pill",           default = true },

  -- Our own floating text for gains (FCT.lua)
  { group = "fct", key = "fct",            label = "Show floating gains above your character", default = true },
  { group = "fct", key = "fctGold",        label = "Money (+1g 20s)",                default = true },
  { group = "fct", key = "fctLoot",        label = "Items looted",                   default = true },
  { group = "fct", key = "fctLootQuality", label = "Items to show",                  default = 1,
    choices = { { 0, "All items" }, { 1, "Common and better" }, { 2, "Green and better" }, { 3, "Blue and better" } } },
  { group = "fct", key = "fctRep",         label = "Reputation",                     default = true },
  { group = "fct", key = "fctSkill",       label = "Skill-ups",                      default = true },
  { group = "fct", key = "fctCasts",       label = "Spells you cast (icon and name)",  default = true },
  { group = "fct", key = "fctAtTarget",    label = "Show damaging spells above your target (needs enemy nameplates)", default = true },
  { group = "fct", key = "fctHits",        label = "Spell hits on your target (icon and damage, best guess)", default = false },
  { group = "fct", key = "fctXP",          label = "Experience (the XP pill already pops these)", default = false },
  { group = "fct", key = "fctCombatHide",  label = "Hide during combat",             default = false },
  { group = "fct", key = "fctScale",       label = "Text size",                      default = 1,
    choices = { { 0.8, "Small" }, { 1, "Normal" }, { 1.25, "Large" }, { 1.5, "Huge" } } },
  { group = "fct", key = "fctSpacing",     label = "Space between lines",            default = 8,
    choices = { { 2, "Tight" }, { 8, "Normal" }, { 16, "Roomy" }, { 26, "Extra roomy" } } },
  { group = "fct", key = "fctTest",        label = "Show sample floating text",      action = "FCTTest", button = "Test" },
  -- Blizzard's built-in floating combat text (game CVars)
  { group = "fctBlizz", key = "bzDamage",    cvar = "floatingCombatTextCombatDamage",          label = "Your damage numbers over enemies" },
  { group = "fctBlizz", key = "bzDots",      cvar = "floatingCombatTextCombatLogPeriodicSpells", label = "Damage over time ticks" },
  { group = "fctBlizz", key = "bzPetMelee",  cvar = "floatingCombatTextPetMeleeDamage",        label = "Pet melee damage" },
  { group = "fctBlizz", key = "bzPetSpell",  cvar = "floatingCombatTextPetSpellDamage",        label = "Pet spell damage" },
  { group = "fctBlizz", key = "bzHealing",   cvar = "floatingCombatTextCombatHealing",         label = "Your healing numbers" },
  { group = "fctBlizz", key = "bzSize",      cvar = "WorldTextScale",                          label = "Damage number size",
    choices = { { 0.75, "Small" }, { 1, "Normal" }, { 1.25, "Large" }, { 1.5, "Huge" }, { 2, "Massive" } } },
  { group = "fctBlizz", key = "bzIncoming",  cvar = "enableFloatingCombatText",                label = "Combat text on your character (incoming)" },
  { group = "fctBlizz", key = "bzDirection", cvar = "floatingCombatTextFloatMode",             label = "Incoming text direction",
    choices = { { 1, "Scroll up" }, { 2, "Scroll down" }, { 3, "Arc" } } },
  { group = "fctBlizz", key = "bzAvoid",     cvar = "floatingCombatTextDodgeParryMiss",        label = "Dodge, parry and miss" },
  { group = "fctBlizz", key = "bzReduce",    cvar = "floatingCombatTextDamageReduction",       label = "Resists and absorbs" },
  { group = "fctBlizz", key = "bzState",     cvar = "floatingCombatTextCombatState",           label = "Entering and leaving combat" },
  { group = "fctBlizz", key = "bzReactive",  cvar = "floatingCombatTextReactives",             label = "Spell alerts (Overpower, Revenge...)" },
  { group = "fctBlizz", key = "bzLow",       cvar = "floatingCombatTextLowManaHealth",         label = "Low health and mana warnings" },
  { group = "fctBlizz", key = "bzEnergy",    cvar = "floatingCombatTextEnergyGains",           label = "Mana, rage and energy gains" },
  { group = "fctBlizz", key = "bzAuras",     cvar = "floatingCombatTextAuras",                 label = "Buffs and debuffs gained or lost" },
  { group = "fctBlizz", key = "bzCombo",     cvar = "floatingCombatTextComboPoints",           label = "Combo points" },
  { group = "fctBlizz", key = "bzRep",       cvar = "floatingCombatTextRepChanges",            label = "Reputation changes" },
  { group = "fctBlizz", key = "bzHonor",     cvar = "floatingCombatTextHonorGains",            label = "Honor gains" },
  { group = "tooltip", key = "apTooltip",      label = "Show AP as Strength/Agility",           default = true },
  { group = "tooltip", key = "apTotal",        label = "Show total melee AP from item",         default = true },
  { group = "chat",    key = "hideChatBg",     label = "Hide the chat window background",       default = false },
  { group = "chat",    key = "hideChatButtons", label = "Hide chat buttons (keeps the tabs)",   default = false },
  { group = "qol",     key = "sellJunk",       label = "Sell grey items at vendors",            default = false },
  { group = "qol",     key = "autoRepair",     label = "Repair gear at vendors",                default = false },
  { group = "qol",     key = "fastLoot",       label = "Faster auto loot",                      default = false },
  { group = "qol",     key = "declineDuels",   label = "Decline duel requests",                 default = false },
}
local settingHooks = {}

-- key -> setting definition
local defByKey
local function findDef(key)
  if not defByKey then
    defByKey = {}
    for _, d in ipairs(FM.SETTINGS) do defByKey[d.key] = d end
  end
  return defByKey[key]
end
FM.FindSetting = function(_, key) return findDef(key) end

-- Game CVars. Wrapped in pcall: older clients error on unknown names.
local function cvarGet(name)
  local ok, v = pcall(function()
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return GetCVar(name)
  end)
  if ok then return v end
end
local function cvarSet(name, value)
  return pcall(function()
    if C_CVar and C_CVar.SetCVar then return C_CVar.SetCVar(name, value) end
    return SetCVar(name, value)
  end)
end
function FM:CVarExists(name) return cvarGet(name) ~= nil end

function FM:GetSetting(key)
  local d = findDef(key)
  if d and d.cvar then
    local v = cvarGet(d.cvar)
    if v == nil then return nil end
    if d.choices then return tonumber(v) or v end
    return v == "1"
  end
  local s = ForeverMetricsDB and ForeverMetricsDB.settings
  if s and s[key] ~= nil then return s[key] end
  return d and d.default
end

function FM:SetSetting(key, value)
  local d = findDef(key)
  if d and d.cvar then
    if InCombatLockdown() then
      print("|cffe8c27aForever Metrics|r game settings can't be changed in combat. Try again after the fight.")
    else
      cvarSet(d.cvar, d.choices and tostring(value) or (value and "1" or "0"))
    end
  else
    ForeverMetricsDB.settings = ForeverMetricsDB.settings or {}
    ForeverMetricsDB.settings[key] = value
  end
  for _, fn in ipairs(settingHooks[key] or {}) do pcall(fn, value) end
  if self.OnUpdateUI then self:OnUpdateUI() end
end

-- For `choices` rows: the label of the current value, and the next value
local function sameValue(a, b)
  if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 0.001 end
  return a == b
end
function FM:ChoiceLabel(key)
  local d, v = findDef(key), self:GetSetting(key)
  for _, c in ipairs(d and d.choices or {}) do if sameValue(c[1], v) then return c[2] end end
  return v ~= nil and tostring(v) or "?"
end
function FM:CycleChoice(key)
  local d, v = findDef(key), self:GetSetting(key)
  if not d or not d.choices then return end
  local idx = 0
  for i, c in ipairs(d.choices) do if sameValue(c[1], v) then idx = i end end
  self:SetSetting(key, d.choices[(idx % #d.choices) + 1][1])
end

function FM:OnSetting(key, fn)
  settingHooks[key] = settingHooks[key] or {}
  table.insert(settingHooks[key], fn)
end

local function currentLevel()
  local l = safe(UnitLevel("player"))
  return type(l) == "number" and l > 0 and l or nil
end

-- hint: the level from an event (may be hidden); live: it happened just now
-- (false = caught up at login); extra: hp/mp/talents from the event, if readable.
-- Tells other files through FM:OnLevelGained(level, live, extra).
function FM:CheckLevel(hint, live, extra)
  local c = self.char
  if not c then return end
  local now = currentLevel()
  local h = tonumber(safe(hint))
  if h and (not now or h > now) then now = h end
  if not now then return end
  if not c.level or now <= c.level then
    c.level = c.level or now
    return
  end
  for L = c.level + 1, now do
    c.level = L
    c.stats.levels = c.stats.levels + 1
    if self.session then self.session.levels = self.session.levels + 1 end
    if live then
      c.levelTimes[L] = c.played - (c.levelStart or c.played)
      c.levelStart = c.played
      self:Log("level", "Reached level " .. L)
    else
      c.levelStart = c.played
      self:Log("level", ("Reached level %d (while Forever Metrics wasn't running)"):format(L))
    end
    if self.OnLevelGained then
      local ok, err = pcall(self.OnLevelGained, self, L, live, L == now and extra or nil)
      if not ok then print("|cffff5555ForeverMetrics level-up error|r", err) end
    end
  end
end

function FM:Log(kind, text)
  local feed = self.char.feed
  local entry = { t = time(), k = kind, x = text }
  feed[#feed + 1] = entry
  while #feed > FEED_MAX do table.remove(feed, 1) end
  if self.OnUpdateUI then self:OnUpdateUI() end
  if self.OnNewEntry then self:OnNewEntry(entry) end
end

---------------------------------------------------------------------------
-- Event handling
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
FM.frame = f
local H = {}

function H.ADDON_LOADED(name)
  if name ~= ADDON then return end
  ForeverMetricsDB = ForeverMetricsDB or {}
  ForeverMetricsDB.version = 1
  ForeverMetricsDB.chars = ForeverMetricsDB.chars or {}
end

function H.PLAYER_LOGIN()
  local name, realm = UnitName("player"), GetRealmName()
  FM.key = name .. "-" .. realm
  local db = ForeverMetricsDB.chars
  local isNew = not db[FM.key]
  db[FM.key] = db[FM.key] or newChar(name, realm)
  local c = db[FM.key]
  ensureGather(c)
  ensureLoot(c)
  FM.char = c
  FM.seenLoot, FM.seenLootN = {}, 0

  local _, classFile = UnitClass("player")
  c.class = classFile
  c.lastSeen = time()
  c.levelStart = c.levelStart or c.played

  FM.lastXP, FM.lastMaxXP = UnitXP("player"), UnitXPMax("player")
  FM.lastMoney = GetMoney()
  FM.session = { start = time(), xp = 0, kills = 0, nodes = 0, levels = 0,
                 deaths = 0, quests = 0, goldLooted = 0, skillUps = 0,
                 startMoney = GetMoney(), mobs = {}, bestLoot = nil, bestQ = 0 }

  -- A character we've tracked before that's now higher than we last saw
  -- leveled while the addon wasn't recording: log those levels now.
  if isNew then
    c.level = currentLevel() or c.level
  else
    FM:CheckLevel(nil, false)
  end

  C_Timer.NewTicker(TICK, function()
    c.played = c.played + TICK
    local z = ZoneName()
    c.zones[z] = (c.zones[z] or 0) + TICK
  end)

  print("|cffe8c27aForever Metrics|r loaded. Type |cffffff00/fm|r to open.")
end

function H.PLAYER_XP_UPDATE()
  local cur, max = UnitXP("player"), UnitXPMax("player")
  if not FM.lastXP then return end
  local gained
  if cur >= FM.lastXP then gained = cur - FM.lastXP
  else gained = (FM.lastMaxXP - FM.lastXP) + cur end -- wrapped past a level-up
  FM.lastXP, FM.lastMaxXP = cur, max
  if gained > 0 then
    FM.char.stats.xp = FM.char.stats.xp + gained
    FM.session.xp = FM.session.xp + gained
  end
end

-- Level tracking. Forever can hide event values in combat (a ding from a
-- kill), so the level-up event's numbers can't be trusted on their own.
-- Instead every level event, and the end of combat, compares the real
-- level with the last one recorded and logs each level gained, once.
function H.PLAYER_LEVEL_UP(level, hp, mp, talents)
  local extra = { hp = tonumber(safe(hp)), mp = tonumber(safe(mp)), talents = tonumber(safe(talents)) }
  FM:CheckLevel(level, true, extra)
  -- UnitLevel can lag the event by a moment
  C_Timer.After(1, function() FM:CheckLevel(level, true, extra) end)
end
function H.PLAYER_LEVEL_CHANGED(_, newLevel) FM:CheckLevel(newLevel, true) end
function H.UNIT_LEVEL(unit) if unit == "player" then FM:CheckLevel(nil, true) end end
function H.PLAYER_REGEN_ENABLED() FM:CheckLevel(nil, true) end

function H.PLAYER_MONEY()
  local m = GetMoney()
  local d = m - (FM.lastMoney or m)
  FM.lastMoney = m
  if d > 0 then FM.char.stats.goldEarned = FM.char.stats.goldEarned + d
  elseif d < 0 then FM.char.stats.goldSpent = FM.char.stats.goldSpent - d end
end

function H.CHAT_MSG_MONEY(msg)
  msg = safe(msg); if not msg then return end
  local g = tonumber(msg:match("(%d+) Gold")) or 0
  local s = tonumber(msg:match("(%d+) Silver")) or 0
  local cp = tonumber(msg:match("(%d+) Copper")) or 0
  local total = g * 10000 + s * 100 + cp
  FM.char.stats.goldLooted = FM.char.stats.goldLooted + total
  FM.session.goldLooted = FM.session.goldLooted + total
end

function H.CHAT_MSG_COMBAT_XP_GAIN(msg)
  msg = safe(msg); if not msg then return end
  local mob = msg:match(PAT_XPKILL)
  if not mob then return end
  local c = FM.char
  c.stats.kills = c.stats.kills + 1
  c.kills[mob] = (c.kills[mob] or 0) + 1
  FM.session.mobs[mob] = (FM.session.mobs[mob] or 0) + 1
  FM.session.kills = FM.session.kills + 1
  local zone = ZoneName()
  bump(c.loot.mobs, mob, "kills"); bump(c.loot.zones, zone, "kills")
  FM.lastKill = { name = mob, zone = zone, t = GetTime() }
end

function H.CHAT_MSG_LOOT(msg)
  msg = safe(msg); if not msg then return end
  local link, qty = msg:match(PAT_LOOT_M)
  if not link then link = msg:match(PAT_LOOT); qty = 1 end
  if not link then return end
  local q = GetItemQualityCompat(link)
  if q and q >= (FM.session.bestQ or 0) and q >= 1 then -- best (latest of highest quality) this session
    FM.session.bestLoot, FM.session.bestQ = link, q
  end
  if q and q >= 3 then -- blues and better get a little fanfare
    FM:Log("loot", ("|cff0070dd%s FIND!|r %s"):format(q >= 4 and "EPIC" or "RARE", link))
  elseif q and q >= 2 then -- green makes the feed
    local suffix = (tonumber(qty) or 1) > 1 and (" x" .. qty) or ""
    FM:Log("loot", "Looted " .. link .. suffix)
  end
end

function H.CHAT_MSG_SKILL(msg)
  msg = safe(msg); if not msg then return end
  local skill, rank = msg:match(PAT_SKILL)
  if not skill then return end
  rank = tonumber(rank)
  local s = FM.char.skills[skill] or { rank = 0, gains = 0 }
  s.rank, s.gains = rank, s.gains + 1
  FM.char.skills[skill] = s
  FM.session.skillUps = FM.session.skillUps + 1
  if rank % 25 == 0 then -- milestones only, so the feed stays readable
    FM:Log("skill", ("Reached %d %s"):format(rank, skill))
  end
end

function H.QUEST_TURNED_IN(questID)
  local c = FM.char
  c.stats.quests = c.stats.quests + 1
  FM.session.quests = FM.session.quests + 1
  local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
  FM:Log("quest", "Completed " .. (title and ("|cffffd100" .. title .. "|r") or "a quest"))
end

function H.PLAYER_DEAD()
  FM.char.stats.deaths = FM.char.stats.deaths + 1
  FM.session.deaths = FM.session.deaths + 1
  FM:Log("death", "Died in " .. ZoneName())
end

function H.ZONE_CHANGED_NEW_AREA()
  local z = ZoneName()
  if z ~= "Unknown" and not FM.char.zones[z] then
    FM.char.zones[z] = 0
    FM:Log("zone", "Entered " .. z .. " for the first time")
  end
end

-- Gathering: a successful Mining/Herb/Skinning cast marks the next loot
-- window as a gather, then LOOT_OPENED counts the node and its contents.
function H.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
  if unit ~= "player" then return end
  local name = safe(GetSpellNameCompat(spellID))
  local g = name and GATHER_SPELLS[name]
  if g then FM.pendingGather = { type = g, t = GetTime() } end
end

function H.LOOT_OPENED()
  local g
  if IsFishingLoot and IsFishingLoot() then g = "Fishing"
  elseif FM.pendingGather and GetTime() - FM.pendingGather.t < 4 then g = FM.pendingGather.type end
  FM.pendingGather = nil
  if not g then return FM:RecordCorpseLoot() end

  local data = FM.char.gathering[g]
  data.nodes = data.nodes + 1
  FM.session.nodes = FM.session.nodes + 1
  for slot = 1, GetNumLootItems() do
    local _, itemName, qty = GetLootSlotInfo(slot)
    itemName = safe(itemName)
    if itemName and (qty or 0) > 0 then
      data.items[itemName] = (data.items[itemName] or 0) + qty
    end
  end
  if data.nodes % 100 == 0 then
    FM:Log("gather", ("%d %s nodes gathered!"):format(data.nodes, g))
  end
end

function FM:RecordCorpseLoot()
  local c = self.char
  local L = c.loot
  -- Count each corpse once, even if you reopen it
  local guid = GetLootSourceInfo and safe((GetLootSourceInfo(1)))
  if guid then
    if self.seenLoot[guid] then return end
    self.seenLoot[guid] = true
    self.seenLootN = self.seenLootN + 1
    if self.seenLootN > 400 then self.seenLoot, self.seenLootN = { [guid] = true }, 1 end
  end
  local lk = self.lastKill
  local fresh = lk and (GetTime() - lk.t) < 120
  local mob = fresh and lk.name or "Unknown"
  local zone = fresh and lk.zone or ZoneName()

  for slot = 1, GetNumLootItems() do
    local _, name, qty, _, quality = GetLootSlotInfo(slot)
    name, qty, quality = safe(name), safe(qty), safe(quality)
    if name and quality and (qty or 0) > 0 then
      L.q[quality] = (L.q[quality] or 0) + 1
      if CLOTH_SET[name] then L.cloth[name] = (L.cloth[name] or 0) + qty end
      if quality >= 2 then
        local field = quality >= 4 and "purples" or (quality == 3 and "blues" or "greens")
        bump(L.mobs, mob, field); bump(L.zones, zone, field)
        local kills = c.stats.kills
        L.longestDry = math.max(L.longestDry, kills - L.lastGreenKill)
        L.lastGreenKill = kills
        if quality >= 3 then L.lastBlueKill = kills end
        L.notable[#L.notable + 1] = {
          t = time(), q = quality, mob = mob, zone = zone, kill = kills,
          link = (GetLootSlotLink and safe(GetLootSlotLink(slot))) or name,
        }
        while #L.notable > NOTABLE_MAX do table.remove(L.notable, 1) end
      end
    end
  end
  if self.OnUpdateUI then self:OnUpdateUI() end
end

function H.PLAYER_LOGOUT()
  local c, s = FM.char, FM.session
  if not c or not s then return end
  s.stop = time()
  table.insert(c.sessions, s)
  while #c.sessions > SESSIONS_MAX do table.remove(c.sessions, 1) end
end

f:SetScript("OnEvent", function(_, event, ...)
  local h = H[event]
  if not h then return end
  if event ~= "ADDON_LOADED" and event ~= "PLAYER_LOGIN" and not FM.char then return end
  local ok, err = pcall(h, ...)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics error|r", event, err) end
end)

for event in pairs(H) do
  -- Wrapped in pcall in case Forever renames or removes an event.
  pcall(f.RegisterEvent, f, event)
end

---------------------------------------------------------------------------
-- Session recap + slash commands
---------------------------------------------------------------------------

function FM:SessionRecap()
  local s = self.session
  if not s then return "No session yet." end
  local mins = math.floor((time() - s.start) / 60)
  local xph = mins > 0 and math.floor(s.xp / (mins / 60)) or 0
  return ("This session (%dm): %d XP (%d/hr), %d kills, %d levels, %d quests, %d nodes, %d skill-ups, %d deaths, %s looted")
    :format(mins, s.xp, xph, s.kills, s.levels, s.quests, s.nodes, s.skillUps, s.deaths,
            GetCoinTextureString and GetCoinTextureString(s.goldLooted) or (s.goldLooted .. "c"))
end

function FM:PrintSession()
  print("|cffe8c27aForever Metrics|r " .. self:SessionRecap())
end

-- Names shown in Options > Keybindings (works for keyboard or controller buttons)
BINDING_HEADER_FOREVERMETRICS = "Forever Metrics"
BINDING_NAME_FOREVERMETRICS_TOGGLE = "Open / close Forever Metrics"
BINDING_NAME_FOREVERMETRICS_SESSION = "Print session recap"
BINDING_NAME_FOREVERMETRICS_PILL = "Expand / collapse XP pill"

SLASH_FOREVERMETRICS1 = "/fm"
SLASH_FOREVERMETRICS2 = "/fmetrics"
SlashCmdList.FOREVERMETRICS = function(arg)
  local raw = arg or ""
  arg = raw:lower()
  local cmd, rest = arg:match("^(%S*)%s*(.-)$")
  if arg == "session" then
    FM:PrintSession()
  elseif cmd == "duo" then
    -- keep original case so character names and nicknames come through intact
    if FM.DuoCommand then FM:DuoCommand(raw:match("^%s*%S*%s*(.-)$")) end
  elseif cmd == "levelup" or cmd == "ding" then
    if FM.LevelUpCommand then FM:LevelUpCommand(rest) end
  elseif cmd == "fct" then
    if FM.FCTCommand then FM:FCTCommand(rest) end
  elseif cmd == "ap" then
    if FM.APCommand then FM:APCommand(rest) end
  elseif cmd == "feed" then
    if FM.FeedCommand then FM:FeedCommand(rest) end
  elseif cmd == "move" then
    if FM.MoveCommand then FM:MoveCommand() end
  elseif cmd == "pill" then
    if FM.PillCommand then FM:PillCommand(rest) end
  elseif cmd == "xpbar" then
    FM:SetSetting("hideXPBar", not FM:GetSetting("hideXPBar"))
    print("Forever Metrics: Blizzard XP bar", FM:GetSetting("hideXPBar") and "hidden" or "shown")
  elseif cmd == "settings" or cmd == "config" then
    if FM.OpenSettings then FM:OpenSettings() end
  elseif arg == "debug" then
    FM.debug = not FM.debug
    print("Forever Metrics debug:", FM.debug and "on" or "off")
  else
    if FM.ToggleUI then FM:ToggleUI() end
  end
end
