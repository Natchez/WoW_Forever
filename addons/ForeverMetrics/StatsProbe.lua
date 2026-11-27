-- Forever Metrics: character stats probe (temporary)
-- /fm stats test, with the character window open (and ideally a target),
-- prints what this client offers for extra stats on the character pane:
-- which stats pane it uses (modern scrolling list or Classic dropdowns),
-- whether addons can add rows to it, and what each stat function returns
-- (a number, SECRET, or missing).

local ADDON, ns = ...
local FM = ns.FM

local function say(msg) print("|cffe8c27aForever Metrics stats|r " .. msg) end

local function show(...)
  local n = select("#", ...)
  if n == 0 then return "nothing" end
  local out = {}
  for i = 1, math.min(n, 6) do
    local v = select(i, ...)
    if issecretvalue and issecretvalue(v) then out[i] = "SECRET"
    elseif type(v) == "number" then out[i] = (v == math.floor(v)) and tostring(v) or ("%.2f"):format(v)
    else out[i] = tostring(v) end
  end
  return table.concat(out, ", ")
end

-- call a global function by name, if it exists
local function try(label, fname, ...)
  local fn = _G[fname]
  if type(fn) ~= "function" then say(("  %s: |cffff5555no %s|r"):format(label, fname)); return end
  local res = { pcall(fn, ...) }
  if not res[1] then say(("  %s: |cffff5555error|r %s"):format(label, tostring(res[2]))); return end
  say(("  %s: %s"):format(label, show(unpack(res, 2))))
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function pane()
  say("|cffffff00Stats pane|r")
  say(("  PAPERDOLL_STATINFO: %s · PAPERDOLL_STATCATEGORIES: %s"):format(
    type(PAPERDOLL_STATINFO) == "table" and (count(PAPERDOLL_STATINFO) .. " stats") or "no",
    type(PAPERDOLL_STATCATEGORIES) == "table" and (count(PAPERDOLL_STATCATEGORIES) .. " categories") or "no"))
  if type(PAPERDOLL_STATCATEGORIES) == "table" then
    for k, cat in pairs(PAPERDOLL_STATCATEGORIES) do
      local stats = {}
      for _, s in ipairs(type(cat) == "table" and cat.stats or {}) do
        stats[#stats + 1] = type(s) == "table" and tostring(s.stat) or tostring(s)
      end
      say(("    %s %s: %s"):format(tostring(k), tostring(type(cat) == "table" and (cat.categoryFrame or cat.name) or ""), table.concat(stats, " ")))
    end
  end
  say(("  CharacterStatsPane %s · PaperDollFrame_UpdateStats %s · PaperDollFrame_SetLabelAndText %s"):format(
    type(CharacterStatsPane), type(PaperDollFrame_UpdateStats), type(PaperDollFrame_SetLabelAndText)))
  say(("  Classic pane: PlayerStatFrameLeft1 %s · PlayerStatFrameLeftDropdown %s · CharacterAttributesFrame %s"):format(
    type(PlayerStatFrameLeft1), type(PlayerStatFrameLeftDropdown or PlayerStatFrameLeftDropDown), type(CharacterAttributesFrame)))
  say(("  CharacterFrame %s, shown: %s · width %s"):format(type(CharacterFrame),
    tostring(CharacterFrame and CharacterFrame:IsShown()), CharacterFrame and show(CharacterFrame:GetWidth()) or "-"))
end

local function stats()
  say("|cffffff00Melee and ranged|r")
  try("hit bonus", "GetHitModifier")
  try("melee crit", "GetCritChance")
  try("ranged crit", "GetRangedCritChance")
  try("attack speed", "UnitAttackSpeed", "player")
  try("melee damage", "UnitDamage", "player")
  try("ranged speed/damage", "UnitRangedDamage", "player")
  try("weapon skill (main, off)", "UnitAttackBothHands", "player")
  try("ranged skill", "UnitRangedAttack", "player")
  try("attack power", "UnitAttackPower", "player")
  try("rating: hit", "GetCombatRatingBonus", CR_HIT_MELEE or 6)
  try("expertise", "GetExpertise")
  say("|cffffff00Defense|r")
  try("armor", "UnitArmor", "player")
  try("defense", "UnitDefense", "player")
  try("dodge", "GetDodgeChance")
  try("parry", "GetParryChance")
  try("block", "GetBlockChance")
  local armor = UnitArmor and select(2, UnitArmor("player")) or nil -- effective armor
  try("armor reduction vs lv 60", "PaperDollFrame_GetArmorReduction", armor, 60)
  say("|cffffff00Spells|r")
  try("spell hit bonus", "GetSpellHitModifier")
  try("spell crit (fire)", "GetSpellCritChance", 3)
  try("spell power (fire)", "GetSpellBonusDamage", 3)
  try("healing power", "GetSpellBonusHealing")
  try("mana regen (base, casting)", "GetManaRegen")
  try("power regen", "GetPowerRegen")
  say("|cffffff00General|r")
  try("item level", "GetAverageItemLevel")
  try("speed", "GetUnitSpeed", "player")
  try("head durability", "GetInventoryItemDurability", 1)
  try("chest durability", "GetInventoryItemDurability", 5)
  say(("  C_PaperDollInfo: %s"):format(type(C_PaperDollInfo)))
  if type(C_PaperDollInfo) == "table" then
    local names = {}
    for k in pairs(C_PaperDollInfo) do names[#names + 1] = k end
    table.sort(names)
    say("    " .. table.concat(names, " "))
  end
  say("|cffffff00Target|r")
  if UnitExists("target") then
    try("target level", "UnitLevel", "target")
    try("target armor", "UnitArmor", "target")
    try("target classification", "UnitClassification", "target")
  else
    say("  no target (target a mob and run it again to test target stats)")
  end
end

function FM:StatsCommand(rest)
  if rest ~= "test" then say("type |cffffff00/fm stats test|r with your character window open") return end
  local ok, err = pcall(pane)
  if not ok then say("|cffff5555pane error|r " .. tostring(err)) end
  ok, err = pcall(stats)
  if not ok then say("|cffff5555stats error|r " .. tostring(err)) end
end
