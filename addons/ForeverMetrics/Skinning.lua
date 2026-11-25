-- Forever Metrics: Skinning on unit tooltips
-- Hover a beast (alive or dead) or any corpse marked "Skinnable" and, if you
-- have Skinning, the tooltip shows yours against what it needs:
-- "Skinning 98/105", green if you can skin it, red if not.
-- Classic rule: up to level 10 needs 1, levels 11-20 need (level-10) x 10,
-- above 20 level x 5.

local ADDON, ns = ...
local FM = ns.FM

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function need(level)
  if level <= 10 then return 1 end
  if level <= 20 then return (level - 10) * 10 end
  return level * 5
end

local function maxLevel(skill)
  if skill < 100 then return 10 + math.floor(skill / 10) end
  return math.floor(skill / 5)
end
FM.SkinNeed, FM.SkinMaxLevel = need, maxLevel -- for the stand-in test

local SKINNING = "Skinning"
local rank -- cached; nil = you don't have Skinning

local function readRank()
  rank = nil
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() or 0 do
      local name, header, _, r = GetSkillLineInfo(i)
      if not header and safe(name) == SKINNING then rank = safe(r); return end
    end
  end
  if GetProfessions and GetProfessionInfo then
    for _, idx in ipairs({ GetProfessions() }) do
      if idx then
        local ok, name, _, r = pcall(GetProfessionInfo, idx)
        if ok and safe(name) == SKINNING then rank = safe(r); return end
      end
    end
  end
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
  if tip.__fmSkin or not FM:GetSetting("skinTip") then return end
  if not tip.GetUnit or not rank then return end
  local _, unit = tip:GetUnit()
  unit = safe(unit)
  if not unit or UnitIsPlayer(unit) then return end
  local beast = safe(UnitCreatureType(unit)) == "Beast" -- English client
  if not beast and not markedSkinnable(tip) then return end
  if UnitIsDead(unit) and not markedSkinnable(tip) then return end -- already skinned, or nothing to skin
  local level = safe(UnitLevel(unit))
  if type(level) ~= "number" then return end
  -- "Skinning 112/120": yours / needed, green if you can skin it
  local req = level >= 0 and need(level) or nil
  local col = (req and rank >= req) and "|cff7fd36b" or "|cffff5555"
  local text = ("%sSkinning %d/%s|r"):format(col, rank, req or "??")
  tip.__fmSkin = true
  tip:AddLine(text)
  tip:Show()
end

local function try(tip)
  local ok, err = pcall(onUnit, tip)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics skinning tooltip|r", err) end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, try)
elseif GameTooltip:HasScript("OnTooltipSetUnit") then
  GameTooltip:HookScript("OnTooltipSetUnit", try)
end
GameTooltip:HookScript("OnTooltipCleared", function(tip) tip.__fmSkin = nil end)

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function() pcall(readRank) end)
for _, e in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" }) do pcall(ev.RegisterEvent, ev, e) end
