-- Forever Metrics: AP to stat tooltips (formerly the standalone APtoStat addon)
-- Adds "= X Strength" style lines to item tooltips that have Attack Power,
-- plus an optional "Total melee AP from item" line for comparing gear.
-- Toggles live in the Settings tab, or use /fm ap and /fm ap total.

local ADDON, ns = ...
local FM = ns.FM

local _, CLASS = UnitClass("player")

-- Ranged AP from Agility for hunters: 2 in Classic Era, 1 in TBC.
-- Forever is Era-style, so anything that isn't the TBC client counts as Era.
local IS_TBC = WOW_PROJECT_BURNING_CRUSADE_CLASSIC and WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC

-- How much melee AP one point of each stat gives (base, before talents/Kings).
local MELEE = {
  WARRIOR = { Strength = 2 },
  PALADIN = { Strength = 2 },
  SHAMAN  = { Strength = 2 },
  DRUID   = { Strength = 2, Agility = 1 }, -- Agility only counts in Cat Form
  ROGUE   = { Agility = 1, Strength = 1 },
  HUNTER  = { Agility = 1, Strength = 1 },
}
local RANGED_AGI = (CLASS == "HUNTER") and (IS_TBC and 1 or 2) or nil

local COLOR = "|cff66ccff"

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function fmt(n)
  if n == math.floor(n) then return tostring(n) end
  return ("%.1f"):format(n)
end

local function convert(ap, ratios)
  local parts = {}
  for _, stat in ipairs({ "Strength", "Agility" }) do
    local r = ratios[stat]
    if r then
      local label = stat
      if CLASS == "DRUID" and stat == "Agility" then label = "Agility (Cat)" end
      parts[#parts + 1] = fmt(ap / r) .. " " .. label
    end
  end
  if #parts == 0 then return nil end
  return COLOR .. "  " .. ap .. " AP = " .. table.concat(parts, " or ") .. "|r"
end

-- Read the tooltip's own text so it works for "Equip: +X Attack Power." lines.
local function scan(tooltip)
  local name = tooltip:GetName()
  local melee, ranged, str, agi = 0, 0, 0, 0
  if not name then return melee, ranged, str, agi end
  for i = 2, tooltip:NumLines() do
    local fs = _G[name .. "TextLeft" .. i]
    local t = fs and safe(fs:GetText())
    if t then
      local lower = t:lower()
      -- Skip conditional AP (vs Undead/Demons, feral forms) to avoid overstating.
      if not lower:find("when fighting") and not lower:find("cat, bear") and not lower:find("forms only") then
        local n = lower:match("%+(%d+) ranged attack power")
        if n then
          ranged = ranged + tonumber(n)
        else
          n = lower:match("%+(%d+) attack power")
          if n then melee = melee + tonumber(n) end
        end
      end
      local s = t:match("^%+(%d+) Strength$")
      if s then str = str + tonumber(s) end
      local a = t:match("^%+(%d+) Agility$")
      if a then agi = agi + tonumber(a) end
    end
  end
  return melee, ranged, str, agi
end

local function onItem(tooltip)
  if not FM:GetSetting("apTooltip") then return end
  if not tooltip or not tooltip.NumLines or tooltip.__fmApDone then return end
  local ratios = MELEE[CLASS]
  if not ratios then return end
  local ok, melee, ranged, str, agi = pcall(scan, tooltip)
  if not ok then return end
  local added = false

  if melee > 0 then
    local line = convert(melee, ratios)
    if line then tooltip:AddLine(line); added = true end
  end
  if ranged > 0 and RANGED_AGI then
    tooltip:AddLine(COLOR .. "  " .. ranged .. " Ranged AP = " .. fmt(ranged / RANGED_AGI) .. " Agility|r")
    added = true
  end

  -- Total AP this item gives you (AP + stats converted), handy for comparing gear.
  if FM:GetSetting("apTotal") and (melee > 0 or str > 0 or agi > 0) then
    local total = melee + str * (ratios.Strength or 0)
    if CLASS ~= "DRUID" then total = total + agi * (ratios.Agility or 0) end
    if total > 0 and (str > 0 or agi > 0) then
      tooltip:AddLine(COLOR .. "  Total melee AP from item: " .. fmt(total) .. "|r")
      added = true
    end
  end

  if added then
    tooltip.__fmApDone = true
    tooltip:Show()
  end
end

local function clear(tooltip) tooltip.__fmApDone = nil end

local TOOLTIPS = { GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
  for _, tt in ipairs(TOOLTIPS) do
    if tt and tt.HookScript then tt:HookScript("OnTooltipCleared", clear) end
  end
else
  for _, tt in ipairs(TOOLTIPS) do
    if tt and tt.HookScript then
      if tt:HasScript("OnTooltipSetItem") then tt:HookScript("OnTooltipSetItem", onItem) end
      tt:HookScript("OnTooltipCleared", clear)
    end
  end
end

-- /fm ap [total]
function FM:APCommand(rest)
  if (rest or "") == "total" then
    FM:SetSetting("apTotal", not FM:GetSetting("apTotal"))
    print("Forever Metrics: total AP line " .. (FM:GetSetting("apTotal") and "on" or "off"))
  else
    FM:SetSetting("apTooltip", not FM:GetSetting("apTooltip"))
    print("Forever Metrics: AP to stat tooltips " .. (FM:GetSetting("apTooltip") and "on" or "off")
      .. "  (/fm ap total toggles the total line)")
  end
end

-- Keep the old command working
SLASH_FMAPTOSTAT1 = "/ap2s"
SlashCmdList.FMAPTOSTAT = function(msg) FM:APCommand((msg or ""):lower()) end
