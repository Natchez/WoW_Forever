-- Forever Professions: item tooltips, shown a step at a time
--   hover      one line:  "Crafting: 2 skill-ups · 17 recipes"
--   Shift      the top 3 recipes, then "+ 14 more · 1 to learn at trainer"
--   Alt-click  a panel listing every recipe (UI.lua, FP:ShowUses)
-- Items no recipe uses get nothing.

local ADDON, ns = ...
local FP = ns.FP
local safe = FP.safe

local GOLD, MUTED, FAINT = "|cffe8c27a", "|cffa8977a", "|cff7a6a55"

-- A small coloured square (diff colour) that every font can draw
local SQUARE = {}
for d, hex in pairs(FP.DIFF_COLOR) do
  local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
  SQUARE[d] = ("|TInterface\\Buttons\\WHITE8X8:8:8:0:0:8:8:0:8:0:8:%d:%d:%d|t "):format(r, g, b)
end
local LEARN_SQUARE = "|TInterface\\Buttons\\WHITE8X8:8:8:0:0:8:8:0:8:0:8:232:194:122|t "

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

-- "Crafting: 2 skill-ups · 17 recipes"
local function summaryLine(u)
  local parts = {}
  if u.skillups > 0 then parts[#parts + 1] = plural(u.skillups, "skill-up") end
  if u.known > 0 then parts[#parts + 1] = plural(u.known, "recipe") end
  if u.known == 0 and u.learn > 0 then parts[#parts + 1] = u.learn .. " to learn" end
  if u.known == 0 and u.learn == 0 and u.other > 0 then parts[#parts + 1] = plural(u.other, "recipe") .. " not learned yet" end
  return GOLD .. "Crafting:|r " .. table.concat(parts, "  ·  ")
end

-- Right-hand text for one recipe row: who, then the most useful fact
function FP:EntryNote(e, item)
  local me = self:CharKey()
  local who = (e.key ~= me or self:GetSetting("tipAlts")) and self:CharName(e.key, true) or nil
  local fact
  if e.kind == "learn" then
    fact = "learn " .. self:Money(e.cost or 0)
  elseif e.kind == "other" then
    fact = MUTED .. "not learned|r"
  elseif (e.canMake or 0) > 0 then
    fact = "|cff7fd36bmake " .. e.canMake .. "|r"
  elseif e.altHas and item then
    fact = self:CharName(e.altHas, true) .. MUTED .. " has " .. self:Have(e.altHas, item) .. "|r"
  elseif e.missing and e.missing[1] then
    local m = e.missing[1]
    if m.id == item then
      fact = MUTED .. "need " .. e.need .. (#e.missing > 1 and (" +" .. (#e.missing - 1)) or "") .. "|r"
    else
      fact = MUTED .. "needs " .. self:ItemName(m.id) .. (#e.missing > 1 and (" +" .. (#e.missing - 1)) or "") .. "|r"
    end
  end
  if who and fact then return who .. MUTED .. "  ·  |r" .. fact end
  return who or fact or ""
end

local function recipeLeft(e)
  local col = (e.kind == "learn" and "e8c27a") or (e.kind == "other" and "a8977a") or (e.diff and FP.DIFF_COLOR[e.diff] or "ffffff")
  -- the recipe's icon (or the item it makes), trimmed of its border; the
  -- name's colour shows the difficulty. A coloured square if there's no icon.
  local icon = e.icon or (e.made and FP:ItemIcon(e.made))
  local sq
  if icon and icon ~= 134400 then
    sq = "|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t "
  else
    sq = e.kind == "learn" and LEARN_SQUARE or (SQUARE[e.diff or 3] or SQUARE[3])
  end
  return sq .. "|cff" .. col .. (e.n or "?") .. "|r " .. MUTED .. "×" .. (e.need or 1) .. "|r"
end

-- Crafting materials (and anything a recipe uses) get the "On hand" counts;
-- gear and the like don't, to keep tooltips quiet
local function isMaterial(item, u)
  if u and (u.known + u.learn + u.other) > 0 then return true end
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not f then return false end
  local ok, _, _, _, _, _, classID = pcall(f, item)
  classID = ok and safe(classID) or nil
  return classID == 5 or classID == 7 -- Reagent, Trade Goods
end

-- "On hand: Gene 41 · Ollie 12 · Bobb 3"
local function holdersLine(holders)
  local parts, total = {}, 0
  for i, h in ipairs(holders) do
    total = total + h.total
    if i <= 4 then parts[#parts + 1] = FP:CharName(h.key, true) .. " " .. h.total end
  end
  if #holders > 4 then parts[#parts + 1] = MUTED .. "+" .. (#holders - 4) .. "|r" end
  local line = GOLD .. "On hand:|r " .. table.concat(parts, MUTED .. "  ·  |r")
  if #holders > 1 then line = line .. MUTED .. "  (" .. total .. ")|r" end
  return line
end

local function annotate(tip, item)
  if tip.__fpDone or not item then return end
  local shift = IsShiftKeyDown() and FP:GetSetting("tipShift")
  if not shift and not FP:GetSetting("tipLine") and not FP:GetSetting("tipCounts") and not FP:GetSetting("tipPrice") then return end
  local u = FP:Uses(item)
  local hasUses = u and (u.known + u.learn + u.other) > 0
  local holders = FP:GetSetting("tipCounts") and isMaterial(item, u) and FP:Holders(item) or {}
  local price, age
  if FP:GetSetting("tipPrice") then price, age = FP:Price(item) end
  if not hasUses and #holders == 0 and not price then return end
  tip.__fpDone, tip.__fpItem = true, item
  local priceLine = price and (GOLD .. "AH:|r " .. FP:Money(price) .. MUTED .. " each  ·  " .. FP:Age(age) .. "|r")

  if not shift then
    if priceLine then tip:AddLine(priceLine) end
    if #holders > 0 then tip:AddLine(holdersLine(holders)) end
    if hasUses and FP:GetSetting("tipLine") then tip:AddLine(summaryLine(u)) end
    if FP:GetSetting("tipHint") and FP:GetSetting("tipShift") and (hasUses or #holders > 0) then
      tip:AddLine(FAINT .. "Shift: details|r")
    end
    tip:Show()
    return
  end

  -- Shift: the price (and a stack's worth), then who has it, by bags and bank
  if priceLine then
    tip:AddLine(" ")
    tip:AddLine(priceLine)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, _, _, _, _, _, _, _, stack = pcall(f, item)
    stack = ok and tonumber(safe(stack)) or nil
    if stack and stack > 1 then tip:AddLine(MUTED .. "  a stack of " .. stack .. ": |r" .. FP:Money(price * stack)) end
  end
  if #holders > 0 then
    tip:AddLine(" ")
    tip:AddLine(GOLD .. "On hand|r")
    for _, h in ipairs(holders) do
      local where = {}
      if h.bags > 0 then where[#where + 1] = h.bags .. " bags" end
      if h.bank > 0 then where[#where + 1] = h.bank .. " bank" end
      tip:AddDoubleLine("  " .. FP:CharName(h.key), h.total .. MUTED .. "  (" .. table.concat(where, ", ") .. ")|r", 1, 1, 1, 1, 1, 1)
    end
  end
  if not hasUses then tip:Show(); return end

  tip:AddLine(" ")
  local shown, grey = 0, FP:GetSetting("tipGrey")
  for _, e in ipairs(u.list) do
    if shown >= 3 then break end
    if e.kind == "known" and (grey or e.diff ~= 3) then
      tip:AddDoubleLine(recipeLeft(e), FP:EntryNote(e, item), 1, 1, 1, 1, 1, 1)
      shown = shown + 1
    end
  end
  if shown == 0 then -- only learnable ones
    for _, e in ipairs(u.list) do
      if shown >= 3 then break end
      tip:AddDoubleLine(recipeLeft(e), FP:EntryNote(e, item), 1, 1, 1, 1, 1, 1)
      shown = shown + 1
    end
  end
  local more = u.known - math.min(shown, u.known)
  local tail = {}
  if more > 0 then tail[#tail + 1] = "+ " .. more .. " more" end
  if u.learn > 0 and u.known > 0 then tail[#tail + 1] = u.learn .. " to learn at trainer" end
  if u.other > 0 and (u.known > 0 or u.learn > 0) then tail[#tail + 1] = u.other .. " not learned yet" end
  if #tail > 0 then tip:AddLine(MUTED .. table.concat(tail, "  ·  ") .. "|r") end
  if FP:GetSetting("altClick") then tip:AddLine(FAINT .. "Alt-click: open in Forever Professions|r") end
  tip:Show()
end

local function itemFromTooltip(tip, data)
  if type(data) == "table" and type(safe(data.id)) == "number" then return safe(data.id) end
  if tip.GetItem then
    local ok, _, link = pcall(tip.GetItem, tip)
    link = ok and safe(link) or nil
    if type(link) == "string" then return tonumber(link:match("|Hitem:(%d+)")) end
  end
end

local function onItem(tip, data)
  if not FP:Char() or not tip or not tip.AddLine then return end
  local ok, err = pcall(annotate, tip, itemFromTooltip(tip, data))
  if not ok then FP:Debug("tooltip", err) end
end

local function onCleared(tip) tip.__fpDone, tip.__fpItem = nil, nil end

local TOOLTIPS = { GameTooltip, ItemRefTooltip }
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
  for _, tt in ipairs(TOOLTIPS) do if tt and tt.HookScript then tt:HookScript("OnTooltipCleared", onCleared) end end
else
  for _, tt in ipairs(TOOLTIPS) do
    if tt and tt.HookScript then
      if tt:HasScript("OnTooltipSetItem") then tt:HookScript("OnTooltipSetItem", onItem) end
      tt:HookScript("OnTooltipCleared", onCleared)
    end
  end
end

-- Pressing or releasing Shift redraws a tooltip we added to, by re-running
-- the hovered button's OnEnter (how Blizzard's own tooltips refresh).
FP:On("MODIFIER_STATE_CHANGED", function(key)
  if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
  if not GameTooltip:IsShown() or not GameTooltip.__fpItem or not FP:GetSetting("tipShift") then return end
  local owner = GameTooltip:GetOwner()
  local enter = owner and owner.GetScript and owner:GetScript("OnEnter")
  if enter and owner:IsMouseOver() then pcall(enter, owner) end
end)

---------------------------------------------------------------------------
-- Alt-click an item (bags, bank, chat links) to list every recipe using it
---------------------------------------------------------------------------

local lastAlt = 0
local function altClick(link)
  if not IsAltKeyDown() or not FP:GetSetting("altClick") or not FP:Char() then return end
  if GetTime() - lastAlt < 0.2 then return end -- two hooks can see the same click
  link = safe(link)
  local id = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
  if not id then return end
  local u = FP:Uses(id)
  if not u or #u.list == 0 then return end
  lastAlt = GetTime()
  if FP.ShowUses then FP:ShowUses(id) end
end

if type(HandleModifiedItemClick) == "function" then
  hooksecurefunc("HandleModifiedItemClick", function(link) FP:Try("alt-click", altClick, link) end)
end
if type(ContainerFrameItemButton_OnModifiedClick) == "function" then
  hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self)
    local bag, slot = self:GetParent() and self:GetParent():GetID(), self:GetID()
    local link
    if C_Container and C_Container.GetContainerItemLink then link = C_Container.GetContainerItemLink(bag, slot)
    elseif GetContainerItemLink then link = GetContainerItemLink(bag, slot) end
    FP:Try("alt-click", altClick, link)
  end)
end
