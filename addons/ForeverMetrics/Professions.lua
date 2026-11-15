-- Forever Metrics: professions and inventory
-- Remembers, per character:
--   prof[<profession>]  rank, max rank, and every known recipe with its icon,
--                       crafted item and reagents. Read when you open the
--                       profession window (trade skills, and the Craft window
--                       Classic uses for Enchanting).
--   bags / bank         what you're carrying (and what's in the bank, read
--                       when you open it), by item: name, count, quality,
--                       icon, and whether it's a crafting material.
-- Profession trainers are read in LevelUp.lua (it shares the trainer code)
-- into the account-wide ForeverMetricsDB.profTrainer, so the stats page can
-- list recipes you're missing and the ones coming up.
--
-- All of this is for the stats page; nothing here shows in game.

local ADDON, ns = ...
local FM = ns.FM

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function idFromLink(link, kind)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|H" .. kind .. ":(%d+)"))
end

-- "spell:123" or "enchant:123" (Classic writes recipe links either way)
local function spellFromLink(link)
  return idFromLink(link, "spell") or idFromLink(link, "enchant")
end

local function nameFromLink(link)
  return type(link) == "string" and link:match("%[(.-)%]") or nil
end

local function profDB(name)
  local c = FM:Char()
  if not c or not name then return end
  c.prof = c.prof or {}
  c.prof[name] = c.prof[name] or { recipes = {} }
  return c.prof[name]
end

---------------------------------------------------------------------------
-- Recipes: the trade skill window (most professions)
---------------------------------------------------------------------------

local function scanTradeSkills()
  if not (GetTradeSkillLine and GetNumTradeSkills) then return false end
  local name, rank, max = GetTradeSkillLine()
  name, rank, max = safe(name), tonumber(safe(rank)), tonumber(safe(max))
  if not name or name == "UNKNOWN" then return false end
  if ExpandTradeSkillSubClass then pcall(ExpandTradeSkillSubClass, 0) end -- open collapsed groups

  local P = profDB(name)
  if not P then return false end
  P.rank, P.max, P.scanned = rank, max, time()
  local found = {}
  for i = 1, GetNumTradeSkills() or 0 do
    local rname, kind = GetTradeSkillInfo(i)
    rname, kind = safe(rname), safe(kind)
    if rname and kind ~= "header" and kind ~= "subheader" then
      local itemLink = GetTradeSkillItemLink and safe(GetTradeSkillItemLink(i))
      local recipeLink = GetTradeSkillRecipeLink and safe(GetTradeSkillRecipeLink(i))
      local r = {
        n = rname,
        diff = kind,                                   -- optimal / medium / easy / trivial
        icon = GetTradeSkillIcon and safe(GetTradeSkillIcon(i)),
        spell = spellFromLink(recipeLink),
        item = idFromLink(itemLink, "item"),
        reagents = {},
      }
      for j = 1, (GetTradeSkillNumReagents and GetTradeSkillNumReagents(i)) or 0 do
        local rn, ricon, need = GetTradeSkillReagentInfo(i, j)
        local rlink = GetTradeSkillReagentItemLink and safe(GetTradeSkillReagentItemLink(i, j))
        r.reagents[#r.reagents + 1] = { n = safe(rn), icon = safe(ricon), c = tonumber(safe(need)) or 1,
                                        id = idFromLink(rlink, "item") }
      end
      found[r.spell and ("s" .. r.spell) or rname] = r
    end
  end
  P.recipes = found
  return true
end

---------------------------------------------------------------------------
-- Recipes: the Craft window (Enchanting in Classic)
---------------------------------------------------------------------------

local function scanCrafts()
  if not (GetCraftDisplaySkillLine and GetNumCrafts) then return false end
  local name, rank, max = GetCraftDisplaySkillLine()
  name, rank, max = safe(name), tonumber(safe(rank)), tonumber(safe(max))
  if not name then return false end
  if ExpandCraftSkillLine then pcall(ExpandCraftSkillLine, 0) end

  local P = profDB(name)
  if not P then return false end
  P.rank, P.max, P.scanned = rank, max, time()
  local found = {}
  for i = 1, GetNumCrafts() or 0 do
    local rname, sub, kind = GetCraftInfo(i)
    rname, kind = safe(rname), safe(kind)
    if rname and kind ~= "header" then
      local itemLink = GetCraftItemLink and safe(GetCraftItemLink(i))
      local recipeLink = GetCraftRecipeLink and safe(GetCraftRecipeLink(i))
      local r = {
        n = rname, diff = kind,
        icon = GetCraftIcon and safe(GetCraftIcon(i)),
        spell = spellFromLink(recipeLink) or spellFromLink(itemLink),
        item = idFromLink(itemLink, "item"),
        reagents = {},
      }
      for j = 1, (GetCraftNumReagents and GetCraftNumReagents(i)) or 0 do
        local rn, ricon, need = GetCraftReagentInfo(i, j)
        local rlink = GetCraftReagentItemLink and safe(GetCraftReagentItemLink(i, j))
        r.reagents[#r.reagents + 1] = { n = safe(rn), icon = safe(ricon), c = tonumber(safe(need)) or 1,
                                        id = idFromLink(rlink, "item") }
      end
      found[r.spell and ("s" .. r.spell) or rname] = r
    end
  end
  P.recipes = found
  return true
end

---------------------------------------------------------------------------
-- Recipes: modern profession window (only if the Classic API is missing)
---------------------------------------------------------------------------

local function scanModern()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetBaseProfessionInfo) then return false end
  local ok, info = pcall(T.GetBaseProfessionInfo)
  if not ok or type(info) ~= "table" or not info.professionName then return false end
  local P = profDB(info.professionName)
  if not P then return false end
  P.rank, P.max, P.scanned = info.skillLevel, info.maxSkillLevel, time()
  local found = {}
  for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local ok2, r = pcall(T.GetRecipeInfo, id)
    if ok2 and type(r) == "table" and r.learned then
      local rec = { n = r.name, icon = r.icon, spell = id, diff = r.relativeDifficulty, reagents = {} }
      if T.GetRecipeSchematic then
        local ok3, sch = pcall(T.GetRecipeSchematic, id, false)
        if ok3 and type(sch) == "table" then
          rec.item = sch.outputItemID
          for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
            local first = slot.reagents and slot.reagents[1]
            if first and first.itemID then
              rec.reagents[#rec.reagents + 1] = { id = first.itemID, c = slot.quantityRequired or 1 }
            end
          end
        end
      end
      found["s" .. id] = rec
    end
  end
  P.recipes = found
  return true
end

local function scanRecipes(which)
  local ok, res
  if which == "craft" then ok, res = pcall(scanCrafts)
  else
    ok, res = pcall(scanTradeSkills)
    if ok and not res then ok, res = pcall(scanModern) end
  end
  if not ok and FM.debug then print("|cffff5555ForeverMetrics profession scan error|r", res) end
end

---------------------------------------------------------------------------
-- Inventory: bags and bank
---------------------------------------------------------------------------

local function numSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
  return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function slotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local i = C_Container.GetContainerItemInfo(bag, slot)
    if not i then return end
    return safe(i.itemID), safe(i.stackCount), safe(i.quality), safe(i.iconFileID), safe(i.hyperlink)
  end
  if GetContainerItemInfo then
    local icon, count, _, quality, _, _, link = GetContainerItemInfo(bag, slot)
    return idFromLink(safe(link), "item"), safe(count), safe(quality), safe(icon), safe(link)
  end
end

-- Item class: 7 = Tradeskill (trade goods), 5 = Reagent, 9 = Recipe
local function itemClass(id)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not f then return nil end
  local ok, _, _, _, _, _, classID, subID = pcall(f, id)
  if ok then return safe(classID), safe(subID) end
end

local function scanContainers(bags)
  local items = {}
  for _, bag in ipairs(bags) do
    for slot = 1, numSlots(bag) do
      local id, count, quality, icon, link = slotItem(bag, slot)
      if id then
        local e = items[id]
        if not e then
          local cls, sub = itemClass(id)
          e = { n = nameFromLink(link), c = 0, q = quality, icon = icon, cls = cls, sub = sub }
          items[id] = e
        end
        e.c = e.c + (tonumber(count) or 1)
      end
    end
  end
  return items
end

local function scanBags()
  local c = FM:Char()
  if not c then return end
  local bags = {}
  for b = 0, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = b end
  c.bags = { t = time(), items = scanContainers(bags) }
end

local function scanBank()
  local c = FM:Char()
  if not c then return end
  local bags = { BANK_CONTAINER or -1 }
  local first = (NUM_BAG_SLOTS or 4) + 1
  for b = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do bags[#bags + 1] = b end
  c.bank = { t = time(), items = scanContainers(bags) }
end

local bagQueued = false
local function queueBags()
  if bagQueued then return end
  bagQueued = true
  C_Timer.After(2, function()
    bagQueued = false
    local ok, err = pcall(scanBags)
    if not ok and FM.debug then print("|cffff5555ForeverMetrics bag scan error|r", err) end
  end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local H = {}
local bankOpen = false

function H.PLAYER_LOGIN() queueBags() end
function H.BAG_UPDATE_DELAYED() queueBags() end
function H.TRADE_SKILL_SHOW() C_Timer.After(0.5, function() scanRecipes("trade") end) end
function H.TRADE_SKILL_UPDATE() scanRecipes("trade") end
function H.CRAFT_SHOW() C_Timer.After(0.5, function() scanRecipes("craft") end) end
function H.CRAFT_UPDATE() scanRecipes("craft") end
function H.BANKFRAME_OPENED() bankOpen = true; C_Timer.After(0.5, function() pcall(scanBank) end) end
function H.BANKFRAME_CLOSED() bankOpen = false end
function H.PLAYERBANKSLOTS_CHANGED() if bankOpen then pcall(scanBank) end end

ev:SetScript("OnEvent", function(_, event, ...)
  if event ~= "PLAYER_LOGIN" and not FM:Char() then return end
  local ok, err = pcall(H[event], ...)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics professions error|r", event, err) end
end)
for event in pairs(H) do pcall(ev.RegisterEvent, ev, event) end
