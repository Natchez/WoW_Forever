-- Forever Professions: camp feature tooltips
-- Hover a campfire or a camp feature on the ground (or its item in your
-- bags) to see the buff it gives at your level, so you know what a camp
-- offers before sitting at it for a minute. Values are Forever's own, read
-- from its spell data (Wowhead, Forever data set) and scale with your level.
-- Upgraded features (Master Forge, Loom...) give the same buff as the one
-- they replace, plus their own use.

local ADDON, ns = ...
local FP = ns.FP
local safe = FP.safe

-- by level: { below, value } pairs, last value for everyone above
local function byLevel(steps, last)
  return function(lv)
    for _, s in ipairs(steps) do if lv < s[1] then return s[2] end end
    return last
  end
end

local BASE = {
  ["Sharpening Wheel"] = { prof = "Blacksmithing", scales = true, text = function(lv) return ("+%d Strength"):format(byLevel({ { 24, 6 }, { 38, 11 }, { 52, 20 } }, 34)(lv)) end, excl = "Strength of Earth Totem" },
  ["Lodestone"]        = { prof = "Mining",        scales = true, text = function(lv) return ("+%d melee Attack Power"):format(byLevel({ { 12, 12 }, { 22, 20 }, { 32, 32 }, { 42, 49 }, { 52, 67 } }, 90)(lv)) end, excl = "Blessing of Might" },
  ["Enchanted Lute"]   = { prof = "Enchanting",    scales = true, text = function(lv) return ("+%d Armor, up to +13 all stats and +22 all resistances"):format(byLevel({ { 10, 28 }, { 20, 71 }, { 30, 114 }, { 40, 163 }, { 50, 211 }, { 60, 260 } }, 308)(lv)) end, excl = "Mark of the Wild" },
  ["Faction Banner"]   = { prof = "Tailoring",     scales = true, text = function(lv) return ("+%d Spirit (your faction only)"):format(byLevel({ { 40, 14 }, { 50, 19 }, { 60, 27 } }, 32)(lv)) end, excl = "Divine Spirit" },
  ["First Aid Kit"]    = { prof = "First Aid",     scales = true, text = function(lv) return ("+%d Stamina"):format(byLevel({ { 12, 3 }, { 24, 8 }, { 36, 21 }, { 48, 34 }, { 60, 45 } }, 56)(lv)) end, excl = "Power Word: Fortitude" },
  ["Incense Candle"]   = { prof = "Herbalism",     scales = true, text = function(lv) return ("+%d Intellect"):format(byLevel({ { 14, 2 }, { 28, 6 }, { 42, 12 }, { 56, 18 } }, 25)(lv)) end, excl = "Arcane Intellect" },
  ["Mana Well"]        = { prof = "Alchemy",       scales = true, text = function(lv) return ("+%d mana every 5 sec"):format(byLevel({ { 24, 10 }, { 34, 15 }, { 44, 20 }, { 54, 24 } }, 29)(lv)) end, excl = "Blessing of Wisdom" },
  ["Fish Bowl"]        = { prof = "Fishing",       text = function() return "+8% all stats" end, excl = "Blessing of Kings" },
  ["Camp Chair"]       = { prof = "Skinning",      text = function() return "+2% critical strike chance (spells and attacks)" end, excl = "Moonkin Aura" },
  ["Camp Tent"]        = { prof = "Leatherworking", text = function() return "Rested XP topped up to 5% of a level (no effect if you have more)" end },
  ["Reagent Bot"]      = { prof = "Engineering",   text = function() return "Sells reagents to everyone nearby" end },
  ["Iron Oven"]        = { prof = "Cooking",       text = function() return "Needed for the most advanced cooking recipes" end },
  ["Cookie's Feast"]   = { prof = "Cooking",       text = function() return "Stamina-boosting food for the group" end },
}

-- upgrade = { base it replaces, what it adds }
local UPGRADE = {
  ["Master Forge"] = { "Sharpening Wheel", "Usable for recipes that need a Master Forge" },
  ["Molten Foundry"] = { "Lodestone", "Usable for recipes that need a Molten Foundry" },
  ["Rock Garden"] = { "Lodestone", "Spawns a common mining node over time" },
  ["Arcane Salvager"] = { "Enchanted Lute", "More efficient disenchanting" },
  ["Loom"] = { "Faction Banner", "Usable for recipes that need a Loom" },
  ["Spinning Wheel"] = { "Faction Banner", "Creates certain reagents" },
  ["Plague Doctor's Laboratory"] = { "First Aid Kit", "Contains healing potions and poultices" },
  ["Toxin Study"] = { "First Aid Kit", "Contains healing potions and anti-venom" },
  ["Greenhouse"] = { "Incense Candle", "Grows herbs over time from planted seeds" },
  ["Seed Hybridizer"] = { "Incense Candle", "Multiplies or combines seeds into rarer tiers" },
  ["Fermenter"] = { "Mana Well", "Creates certain reagents" },
  ["Fishing Hut"] = { "Fish Bowl", "Catch rare fish for 1 hour, Fishing Skill lures" },
  ["Fishing Rack"] = { "Fish Bowl", "Catch uncommon fish for 1 hour, Fishing Skill lures" },
  ["Field Guide"] = { "Camp Chair", "Read it to gain Track Beasts" },
  ["Trapper's Workbench"] = { "Camp Chair", "Contains a trap" },
  ["Sewing Machine"] = { "Camp Tent", "Usable for recipes that need a Sewing Machine" },
  ["Tanning Rack"] = { "Camp Tent", "Creates certain reagents" },
  ["Repair Bot"] = { "Reagent Bot", "Also repairs gear" },
}

local FIRES = { ["Basic Campfire"] = 3, ["Journeyman Campfire"] = 5, ["Expert Campfire"] = 10 }

local GOLD, GREEN, MUTED = "|cffe8c27a", "|cff7fd36b", "|cffa8977a"

local function campLines(name)
  if type(name) ~= "string" then return nil end
  name = name:gsub(" Kit$", "") -- "Basic Campfire Kit" is the item that builds a "Basic Campfire"
  local lv = UnitLevel("player") or 1
  if FIRES[name] then
    return { GOLD .. "Camp:|r holds " .. FIRES[name] .. " camp features. Sit or craft nearby for 1 min to get their buffs for 1 hour." }
  end
  local up = UPGRADE[name]
  local base = BASE[up and up[1] or name]
  if not base then return nil end
  local lines = { GOLD .. "Camp:|r " .. GREEN .. base.text(lv) .. "|r" .. (base.scales and MUTED .. "  (at your level)|r" or "") }
  if up then lines[#lines + 1] = MUTED .. "  Same buff as a " .. up[1] .. ", plus: " .. up[2] .. "|r" end
  if base.excl then lines[#lines + 1] = MUTED .. "  Doesn't stack with " .. base.excl .. "|r" end
  return lines
end

local function firstLine(tip)
  local name = tip.GetName and tip:GetName()
  local fs = name and _G[name .. "TextLeft1"]
  return fs and safe(fs:GetText())
end

local function annotate(tip, name)
  if tip.__fpCamp or not FP:GetSetting("campTips") then return end
  local lines = campLines(name or firstLine(tip))
  if not lines then return end
  tip.__fpCamp = true
  for _, l in ipairs(lines) do tip:AddLine(l, 1, 1, 1, true) end
  tip:Show()
end

local function onItem(tip, data)
  if not tip or not tip.AddLine then return end
  local name
  if tip.GetItem then
    local ok, n = pcall(tip.GetItem, tip)
    name = ok and safe(n) or nil
  end
  FP:Try("camp item tooltip", annotate, tip, name)
end

local function onObject(tip)
  if not tip or not tip.AddLine then return end
  FP:Try("camp tooltip", annotate, tip, nil)
end

local function cleared(tip) tip.__fpCamp = nil end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
  if Enum.TooltipDataType.Object then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, onObject) end
else
  if GameTooltip:HasScript("OnTooltipSetItem") then GameTooltip:HookScript("OnTooltipSetItem", onItem) end
end
GameTooltip:HookScript("OnTooltipCleared", cleared)
-- World objects on clients without an Object tooltip type: check the
-- name line whenever a tooltip with no item or unit shows
GameTooltip:HookScript("OnShow", function(tip)
  if tip.__fpCamp then return end
  local hasUnit = tip.GetUnit and select(2, tip:GetUnit())
  local hasItem = tip.GetItem and select(2, tip:GetItem())
  if not hasUnit and not hasItem then onObject(tip) end
end)

-- for the stand-in test
FP.CampLines = campLines
