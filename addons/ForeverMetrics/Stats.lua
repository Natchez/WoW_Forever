-- Forever Metrics: extra rows in the character stats pane
-- Forever uses the modern stats list (PAPERDOLL_STATINFO / _STATCATEGORIES),
-- which addons can add rows to. This adds, each with a hover tooltip:
--   Armor reduction   under Armor: what your armor saves against your target
--   Weapon skill      main · off hand, against your level's cap
--   Hit               your hit against the cap for a boss (3 levels above you)
--   Miss vs target    special-attack miss chance against your target (or a boss)
--   Spell hit         for casters, instead of the melee rows
--   Item level, Durability   with the general stats (health, movement speed)
-- Toggle each under Options > Character. Melee maths follows Classic's rules:
-- a mob's defense is level x 5; miss is 5% + 0.1% per point of defense over
-- your weapon skill (0.2% past 10 points, plus 1% of your hit not counting),
-- or 5% - 0.04% per point of skill over its defense;
-- dual wielding adds 19% to white hits.

local ADDON, ns = ...
local FM = ns.FM

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function pct(n) return ("%.1f%%"):format(n) end
local WHITE, GOLD, GREEN, GREY = "|cffffffff", "|cffffd100", "|cff1eff00", "|cff9d9d9d"

local _, CLASS = UnitClass("player")
local CASTER = { MAGE = true, PRIEST = true, WARLOCK = true }
local function melee() return not CASTER[CLASS] end

local function playerLevel() return safe(UnitLevel("player")) or 1 end

-- hostile target's level, or nil (skull-level bosses count as you + 3)
local function targetLevel()
  if not UnitExists("target") or not UnitCanAttack("player", "target") then return nil end
  local lv = safe(UnitLevel("target"))
  if type(lv) ~= "number" then return nil end
  if lv < 0 then return playerLevel() + 3 end
  return lv
end
local function targetName() return safe(UnitName("target")) or "target" end

---------------------------------------------------------------------------
-- Weapon skill: from the skill list, by the equipped weapon's type
---------------------------------------------------------------------------

local function skillValue(name)
  if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
  for i = 1, GetNumSkillLines() or 0 do
    local n, header, _, rank, temp, mod = GetSkillLineInfo(i)
    if not header and safe(n) == name then
      return (safe(rank) or 0) + (safe(temp) or 0) + (safe(mod) or 0)
    end
  end
end

-- item subtype ("One-Handed Swords") -> skill line ("Swords")
local function weaponSkill(slot)
  local link = GetInventoryItemLink("player", slot)
  if not link then return nil end
  local info = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  if not info then return nil end
  local _, _, sub, _, _, classID = info(link)
  sub = safe(sub)
  if type(sub) ~= "string" or safe(classID) ~= 2 then return nil end -- 2 = weapons
  local name = sub:gsub("^One%-Handed ", "")
  if name == "Fishing Poles" or name == "Miscellaneous" then return nil end
  return name, skillValue(name)
end
FM.WeaponSkill = weaponSkill

---------------------------------------------------------------------------
-- Classic hit tables
---------------------------------------------------------------------------

-- yellow (special attack) miss chance, before your hit
local function baseMiss(skill, level)
  local diff = level * 5 - skill
  if diff > 10 then return 5 + diff * 0.2, 1 end -- and 1% of your hit doesn't count
  if diff < 0 then return math.max(0, 5 + diff * 0.04), 0 end -- skill over its defense
  return 5 + diff * 0.1, 0
end

local function hitBonus() return safe(GetHitModifier and GetHitModifier()) or 0 end

local function missVs(level)
  local _, skill = weaponSkill(16)
  skill = skill or playerLevel() * 5
  local base, suppressed = baseMiss(skill, level)
  local hit = math.max(0, hitBonus() - suppressed)
  local yellow = math.max(0, base - hit)
  local dual = GetInventoryItemLink("player", 17) and weaponSkill(17) ~= nil
  local white = dual and math.max(0, base + 19 - hit) or yellow
  local diff = level * 5 - skill
  local dodge = math.max(0, 5 + diff * (diff < 0 and 0.04 or 0.1))
  local glance = math.max(0, math.min(40, 10 + (level * 5 - math.min(skill, playerLevel() * 5)) * 2))
  if level < playerLevel() then glance = 0 end
  return { yellow = yellow, white = white, dual = dual, dodge = dodge, glance = glance,
           cap = base + suppressed, whiteCap = base + suppressed + 19, skill = skill }
end
FM.MissVs = missVs -- for the stand-in test

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function set(frame, label, text, tip, tip2)
  PaperDollFrame_SetLabelAndText(frame, label, text, false, 0)
  frame.tooltip = WHITE .. tip .. "|r"
  frame.tooltip2 = tip2
  frame:Show()
end

local ROWS = {}

ROWS.FM_ARMORREDUCE = {
  setting = "csArmor",
  update = function(frame)
    local _, armor = UnitArmor("player")
    armor = safe(armor) or 0
    local lv = targetLevel() or playerLevel()
    local red = PaperDollFrame_GetArmorReduction(armor, lv)
    local lines = {
      ("Against level %d (%s): %s"):format(lv, targetLevel() and targetName() or "your level", pct(red)),
      ("Against a level %d boss: %s"):format(playerLevel() + 3, pct(PaperDollFrame_GetArmorReduction(armor, playerLevel() + 3))),
      ("Against level 60: %s"):format(pct(PaperDollFrame_GetArmorReduction(armor, 60))),
    }
    set(frame, "Armor reduction", pct(red), ("Armor reduction %s"):format(pct(red)),
      "Physical damage your armor stops.\n" .. table.concat(lines, "\n"))
  end,
  avail = function() return PaperDollFrame_GetArmorReduction ~= nil and UnitArmor ~= nil end,
}

ROWS.FM_WEAPONSKILL = {
  setting = "csSkill",
  update = function(frame)
    local cap = playerLevel() * 5
    local parts, lines = {}, {}
    for _, slot in ipairs({ 16, 17, 18 }) do
      local name, v = weaponSkill(slot)
      if name and v then
        if slot ~= 18 or CLASS == "HUNTER" then parts[#parts + 1] = tostring(v) end
        lines[#lines + 1] = ("%s (%s): %d / %d%s"):format(({ [16] = "Main hand", [17] = "Off hand", [18] = "Ranged" })[slot],
          name, v, cap, v < cap and (GREY .. "  " .. (cap - v) .. " to go|r") or "")
      end
    end
    local text = #parts > 0 and (table.concat(parts, " · ") .. GREY .. " / " .. cap .. "|r") or "-"
    set(frame, "Weapon skill", text, "Weapon skill",
      table.concat(lines, "\n") .. "\nBelow the cap you miss more and glancing blows hit softer. It goes up as you fight with the weapon.")
  end,
  avail = melee,
}

ROWS.FM_HIT = {
  setting = "csHit",
  update = function(frame)
    local m = missVs(playerLevel() + 3)
    local hit = hitBonus()
    local col = hit >= m.cap and GREEN or WHITE
    set(frame, "Hit", ("%s%s|r%s / %s|r"):format(col, pct(hit), GREY, pct(m.cap)), ("Hit %s"):format(pct(hit)),
      ("You need %s to never miss special attacks against a boss (level %d)%s.\nWith %d weapon skill; more skill lowers the cap.")
        :format(pct(m.cap), playerLevel() + 3, m.dual and (", and " .. pct(m.whiteCap) .. " for dual-wield white hits") or "", m.skill))
  end,
  avail = melee,
}

ROWS.FM_MISS = {
  setting = "csMiss",
  update = function(frame)
    local lv = targetLevel()
    local who = lv and ("%s (%d)"):format(targetName(), lv) or ("a boss (%d)"):format(playerLevel() + 3)
    local m = missVs(lv or playerLevel() + 3)
    local out = { ("Special attacks: %s miss"):format(pct(m.yellow)) }
    if m.dual then out[#out + 1] = ("White hits (dual wield): %s miss"):format(pct(m.white)) end
    out[#out + 1] = ("Dodged: %s"):format(pct(m.dodge))
    if m.glance > 0 then out[#out + 1] = ("Glancing: %s"):format(pct(m.glance)) end
    set(frame, lv and "Miss vs target" or "Miss vs boss", pct(m.yellow), "Against " .. who,
      table.concat(out, "\n") .. "\n" .. GREY .. "Estimated with Classic's hit tables.|r")
  end,
  avail = melee,
}

ROWS.FM_SPELLHIT = {
  setting = "csHit",
  update = function(frame)
    local hit = safe(GetSpellHitModifier and GetSpellHitModifier()) or 0
    local cap = 16 -- 17% base miss against +3, 1% always misses
    set(frame, "Spell hit", ("%s%s|r / %s"):format(hit >= cap and GREEN or WHITE, pct(hit), pct(cap)), ("Spell hit %s"):format(pct(hit)),
      "Bosses resist 17% of spells; 16% hit brings that down to the 1% that always misses.")
  end,
  avail = function() return CASTER[CLASS] and GetSpellHitModifier ~= nil end,
}

ROWS.FM_ILVL = {
  setting = "csIlvl",
  update = function(frame)
    local avg, eq = nil, nil
    if GetAverageItemLevel then avg, eq = GetAverageItemLevel() end
    avg, eq = safe(avg), safe(eq)
    if not eq then -- add it up from what you're wearing
      local sum, n = 0, 0
      for slot = 1, 18 do
        if slot ~= 4 then
          local link = GetInventoryItemLink("player", slot)
          local lv = link and ((C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)) or select(4, GetItemInfo(link)))
          lv = safe(lv)
          if lv then sum, n = sum + lv, n + 1 end
        end
      end
      eq = n > 0 and sum / n or 0
    end
    set(frame, "Item level", ("%d"):format(eq + 0.5), ("Item level %.1f"):format(eq), "The average item level of what you're wearing.")
  end,
}

local SLOT_NAMES = { [1] = "Head", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
  [9] = "Wrist", [10] = "Hands", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged" }

ROWS.FM_DURABILITY = {
  setting = "csDurability",
  update = function(frame)
    local cur, max, low, lowSlot = 0, 0, 1, nil
    for slot in pairs(SLOT_NAMES) do
      local c, m = GetInventoryItemDurability(slot)
      c, m = safe(c), safe(m)
      if c and m and m > 0 then
        cur, max = cur + c, max + m
        if c / m < low then low, lowSlot = c / m, slot end
      end
    end
    local p = max > 0 and cur / max * 100 or 100
    local col = p < 25 and "|cffff5555" or (p < 50 and "|cffffd100" or WHITE)
    set(frame, "Durability", col .. pct(p) .. "|r", "Durability " .. pct(p),
      lowSlot and ("Most worn: %s at %s"):format(SLOT_NAMES[lowSlot], pct(low * 100)) or "Nothing worn down.")
  end,
  avail = function() return GetInventoryItemDurability ~= nil end,
}

-- where each row goes: after this Blizzard stat, in the first category that
-- has it (some stats appear in two categories); each row is placed once
local PLACE = {
  { after = "ARMOR", rows = { "FM_ARMORREDUCE" } },
  { after = "OFFHAND_DAMAGE", rows = { "FM_WEAPONSKILL", "FM_HIT", "FM_MISS" } },
  { after = "MAINHAND_DAMAGE", rows = { "FM_WEAPONSKILL", "FM_HIT", "FM_MISS" } }, -- if no off-hand row
  { after = "HITCHANCE", rows = { "FM_SPELLHIT" } },
  { after = "MOVESPEED", rows = { "FM_ILVL", "FM_DURABILITY" } },
}

local function install()
  if type(PAPERDOLL_STATINFO) ~= "table" or type(PAPERDOLL_STATCATEGORIES) ~= "table"
     or not PaperDollFrame_SetLabelAndText then return false end
  for key, r in pairs(ROWS) do
    PAPERDOLL_STATINFO[key] = { updateFunc = function(frame)
      local ok, err = pcall(r.update, frame)
      if not ok then
        PaperDollFrame_SetLabelAndText(frame, "?", "-", false, 0)
        if FM.debug then print("|cffff5555ForeverMetrics stats|r", key, err) end
      end
    end }
  end
  local placed = {}
  local cats = {}
  for k, cat in pairs(PAPERDOLL_STATCATEGORIES) do
    if type(cat) == "table" and type(cat.stats) == "table" then cats[#cats + 1] = { k = k, stats = cat.stats } end
  end
  table.sort(cats, function(a, b) return tostring(a.k) < tostring(b.k) end)
  for _, p in ipairs(PLACE) do
    if not placed[p.rows[1]] then
      for _, cat in ipairs(cats) do
        local stats, at = cat.stats, nil
        for i, st in ipairs(stats) do if type(st) == "table" and st.stat == p.after then at = i end end
        if at then
          for j = #p.rows, 1, -1 do
            local key = p.rows[j]
            local r = ROWS[key]
            table.insert(stats, at + 1, { stat = key, showFunc = function()
              return FM:GetSetting("charStats") and FM:GetSetting(r.setting) and (not r.avail or r.avail()) and true or false
            end })
            placed[key] = true
          end
          break
        end
      end
    end
  end
  return true
end

-- re-draw the pane when the target changes (miss chance and armor reduction follow it)
local function refresh()
  if CharacterFrame and CharacterFrame:IsShown() and PaperDollFrame_UpdateStats then pcall(PaperDollFrame_UpdateStats) end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local ok, res = pcall(install)
    if FM.debug then print("|cff888888FM stats:|r rows added:", ok and res, ok and "" or res) end
    for _, k in ipairs({ "charStats", "csArmor", "csSkill", "csHit", "csMiss", "csIlvl", "csDurability" }) do
      FM:OnSetting(k, refresh)
    end
  else
    refresh()
  end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED", "SKILL_LINES_CHANGED", "UPDATE_INVENTORY_DURABILITY" }) do
  pcall(ev.RegisterEvent, ev, e)
end
