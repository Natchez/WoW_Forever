-- Forever Metrics: gathering skill on tooltips
-- Hover a beast or skinnable corpse, a mining node or an herb and the
-- tooltip shows the skill it needs against yours:
--   S(120/112)  Skinning     M(65/40)  Mining     H(70/50)  Herbalism
-- Green if you can gather it, red if not. On a character without the skill
-- it shows just what's needed, in gold: S(120).
-- Skinning follows Classic's rule (up to level 10 needs 1, levels 11-20
-- need (level-10) x 10, above 20 level x 5); nodes use Classic's table.

local ADDON, ns = ...
local FM = ns.FM

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function skinNeed(level)
  if level <= 10 then return 1 end
  if level <= 20 then return (level - 10) * 10 end
  return level * 5
end
FM.SkinNeed = skinNeed -- for the stand-in test

local NODES = {
  Mining = {
    ["Copper Vein"] = 1, ["Tin Vein"] = 65, ["Incendicite Mineral Vein"] = 65,
    ["Silver Vein"] = 75, ["Ooze Covered Silver Vein"] = 75, ["Lesser Bloodstone Deposit"] = 75,
    ["Iron Deposit"] = 125, ["Indurium Mineral Vein"] = 150,
    ["Gold Vein"] = 155, ["Ooze Covered Gold Vein"] = 155,
    ["Mithril Deposit"] = 175, ["Ooze Covered Mithril Deposit"] = 175,
    ["Truesilver Deposit"] = 230, ["Ooze Covered Truesilver Deposit"] = 230, ["Dark Iron Deposit"] = 230,
    ["Small Thorium Vein"] = 245, ["Ooze Covered Thorium Vein"] = 245,
    ["Rich Thorium Vein"] = 275, ["Ooze Covered Rich Thorium Vein"] = 275, ["Hakkari Thorium Vein"] = 275,
    ["Small Obsidian Chunk"] = 305, ["Large Obsidian Chunk"] = 305,
  },
  Herbalism = {
    ["Peacebloom"] = 1, ["Silverleaf"] = 1, ["Earthroot"] = 15, ["Mageroyal"] = 50,
    ["Briarthorn"] = 70, ["Stranglekelp"] = 85, ["Bruiseweed"] = 100, ["Wild Steelbloom"] = 115,
    ["Grave Moss"] = 120, ["Kingsblood"] = 125, ["Liferoot"] = 150, ["Fadeleaf"] = 160,
    ["Goldthorn"] = 170, ["Khadgar's Whisker"] = 185, ["Wintersbite"] = 195, ["Firebloom"] = 205,
    ["Purple Lotus"] = 210, ["Arthas' Tears"] = 220, ["Sungrass"] = 230, ["Blindweed"] = 235,
    ["Ghost Mushroom"] = 245, ["Gromsblood"] = 250, ["Golden Sansam"] = 260, ["Dreamfoil"] = 270,
    ["Mountain Silversage"] = 280, ["Plaguebloom"] = 285, ["Icecap"] = 290, ["Black Lotus"] = 300,
  },
}
local LETTER = { Skinning = "S", Mining = "M", Herbalism = "H" }

local ranks = {} -- skill -> your rank (missing = you don't have it)

local function readRanks()
  ranks = {}
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() or 0 do
      local name, header, _, r = GetSkillLineInfo(i)
      name = safe(name)
      if not header and LETTER[name] then ranks[name] = safe(r) end
    end
  end
  if GetProfessions and GetProfessionInfo then
    for _, idx in ipairs({ GetProfessions() }) do
      if idx then
        local ok, name, _, r = pcall(GetProfessionInfo, idx)
        name = ok and safe(name)
        if name and LETTER[name] and not ranks[name] then ranks[name] = safe(r) end
      end
    end
  end
end

-- "S(120/112)" in green or red, or "S(120)" in gold without the skill
local function label(skill, req)
  local r = ranks[skill]
  local L = LETTER[skill]
  if type(r) ~= "number" then return ("|cffe8c27a%s(%s)|r"):format(L, req or "??") end
  local col = (req and r >= req) and "|cff7fd36b" or "|cffff5555"
  return ("%s%s(%s/%d)|r"):format(col, L, req or "??", r)
end

local function add(tip, text)
  tip.__fmGather = true
  tip:AddLine(text)
  tip:Show()
end

local SKINNABLE = UNIT_SKINNABLE_LEATHER or "Skinnable"

local function markedSkinnable(tip)
  local name = tip:GetName()
  if not name then return false end
  for i = 2, tip:NumLines() do
    local fs = _G[name .. "TextLeft" .. i]
    if fs and safe(fs:GetText()) == SKINNABLE then return true end
  end
  return false
end

local function onUnit(tip)
  if tip.__fmGather or not FM:GetSetting("skinTip") or not tip.GetUnit then return end
  local _, unit = tip:GetUnit()
  unit = safe(unit)
  if not unit or UnitIsPlayer(unit) then return end
  local marked = markedSkinnable(tip)
  local beast = safe(UnitCreatureType(unit)) == "Beast" -- English client
  if not beast and not marked then return end
  if UnitIsDead(unit) and not marked then return end -- already skinned, or nothing to skin
  local level = safe(UnitLevel(unit))
  if type(level) ~= "number" then return end
  add(tip, label("Skinning", level >= 0 and skinNeed(level) or nil))
end

-- Mining nodes and herbs: world objects, matched by the tooltip's name line
local function onObject(tip)
  if tip.__fmGather or not FM:GetSetting("skinTip") then return end
  local name = tip.GetName and tip:GetName()
  local fs = name and _G[name .. "TextLeft1"]
  local text = fs and safe(fs:GetText())
  if type(text) ~= "string" then return end
  for skill, list in pairs(NODES) do
    if list[text] then return add(tip, label(skill, list[text])) end
  end
end

local function try(fn, tip)
  local ok, err = pcall(fn, tip)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics gathering tooltip|r", err) end
end

local T = TooltipDataProcessor and Enum and Enum.TooltipDataType
if T and T.Unit then
  TooltipDataProcessor.AddTooltipPostCall(T.Unit, function(tip) try(onUnit, tip) end)
elseif GameTooltip:HasScript("OnTooltipSetUnit") then
  GameTooltip:HookScript("OnTooltipSetUnit", function(tip) try(onUnit, tip) end)
end
if T and T.Object then
  TooltipDataProcessor.AddTooltipPostCall(T.Object, function(tip) try(onObject, tip) end)
end
-- clients without an Object tooltip type: check any tooltip that isn't a unit or item
GameTooltip:HookScript("OnShow", function(tip)
  if tip.__fmGather then return end
  local hasUnit = tip.GetUnit and select(2, tip:GetUnit())
  local hasItem = tip.GetItem and select(2, tip:GetItem())
  if not hasUnit and not hasItem then try(onObject, tip) end
end)
GameTooltip:HookScript("OnTooltipCleared", function(tip) tip.__fmGather = nil end)

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function() pcall(readRanks) end)
for _, e in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" }) do pcall(ev.RegisterEvent, ev, e) end

-- for the stand-in test
FM.GatherLabel, FM.GatherNodes = label, NODES
