-- Forever Professions: reading the game
--   skill ranks       from the skill list, at login and whenever it changes
--   recipes           when you open a profession window (Classic trade skill
--                     window, Classic craft window for Enchanting, or the
--                     modern profession window, whichever this client has)
--   bags and bank     item counts; bank when you open it
--   trainers          recipes a profession trainer teaches, with skill and cost
-- Every recipe seen also saves its materials to db.recipes, shared by all
-- characters, so alts know what a recipe needs.

local ADDON, ns = ...
local FP = ns.FP
local safe = FP.safe

local function idFromLink(link, kind)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|H" .. kind .. ":(%d+)"))
end
local function spellFromLink(link) return idFromLink(link, "spell") or idFromLink(link, "enchant") end

local DIFF = { optimal = 0, medium = 1, easy = 2, trivial = 3, difficult = 0 }
local function diffNum(d)
  if type(d) == "number" then return math.max(0, math.min(3, d)) end
  return DIFF[d]
end

---------------------------------------------------------------------------
-- Skill ranks
---------------------------------------------------------------------------

local function setSkill(name, rank, max)
  local c = FP:Char()
  if not (c and name and FP.PROFESSIONS[name]) then return end
  local s = c.skills[name] or {}
  c.skills[name] = s
  s.rank, s.max = rank or s.rank, max or s.max
  local P = c.prof[name]
  if P then P.rank, P.max = s.rank or P.rank, s.max or P.max end
  FP:Changed()
end

-- Modern clients list professions with GetProfessions/GetProfessionInfo
local function scanProfessions()
  if not (GetProfessions and GetProfessionInfo) then return end
  for _, idx in ipairs({ GetProfessions() }) do
    if idx then
      local ok, name, _, rank, max = pcall(GetProfessionInfo, idx)
      if ok then setSkill(safe(name), tonumber(safe(rank)), tonumber(safe(max))) end
    end
  end
end

local function scanSkills()
  local c = FP:Char()
  if c then pcall(scanProfessions) end
  if not c or not GetNumSkillLines or not GetSkillLineInfo then return end
  for i = 1, GetNumSkillLines() or 0 do
    local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
    name, rank, max = safe(name), tonumber(safe(rank)), tonumber(safe(max))
    if name and not safe(isHeader) and FP.PROFESSIONS[name] and rank then
      c.skills[name] = { rank = rank, max = max }
      if c.prof[name] then c.prof[name].rank, c.prof[name].max = rank, max or c.prof[name].max end
    end
  end
end

-- "Your skill in Blacksmithing has increased to 92."
local SKILL_PAT
do
  local f = type(SKILL_RANK_UP) == "string" and SKILL_RANK_UP or "Your skill in %s has increased to %d."
  SKILL_PAT = "^" .. f:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
end

---------------------------------------------------------------------------
-- Learning something at a trainer (or from a recipe item) counts at once,
-- without waiting for the profession window: a recipe is added to what this
-- character knows (colour unknown until the window is opened), and
-- "Journeyman Blacksmithing" and the like raise the skill cap.
---------------------------------------------------------------------------

local RANK_CAP = { Apprentice = 75, Journeyman = 150, Expert = 225, Artisan = 300 }

function FP:MarkLearned(spell)
  local c = self:Char()
  spell = tonumber(spell)
  if not c or not spell then return end
  local db = self:DB()
  local prof, t
  for p, T in pairs(db.trainers) do
    local e = T.recipes and T.recipes["s" .. spell]
    if e then prof, t = p, e; break end
  end
  local R = self:Recipe(spell)
  prof = prof or (R and R.p)
  local name = (t and t.n) or (R and R.n)
  if not name then
    local f = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    name = f and safe((f(spell)))
  end
  if not prof or not name then return end
  local title, of = name:match("^(%a+) (.+)$")
  if title and RANK_CAP[title] and self.PROFESSIONS[of or ""] then
    setSkill(of, nil, RANK_CAP[title])
    return
  end
  local P = c.prof[prof] or { recipes = {} }
  c.prof[prof] = P
  P.recipes = P.recipes or {}
  if P.recipes["s" .. spell] then return end
  for k, r in pairs(P.recipes) do if r.n == name then return end end
  local regs = {}
  for _, g in ipairs(R and R.r or {}) do regs[#regs + 1] = { id = g.id, c = g.c } end
  P.recipes["s" .. spell] = { n = name, spell = spell, item = R and R.i, icon = t and t.icon, reagents = regs }
  self:Changed()
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

-- Save one profession's recipes for this character, and every recipe's
-- materials account-wide.
local function saveRecipes(prof, rank, max, list)
  local c = FP:Char()
  if not c or not prof or prof == "" or prof == "UNKNOWN" then return false end
  local P = c.prof[prof] or {}
  c.prof[prof] = P
  P.rank, P.max, P.scanned = rank or P.rank, max or P.max, time()
  P.recipes = list
  FP.lastProf = prof
  c.skills[prof] = { rank = P.rank, max = P.max }
  local shared = FP:DB().recipes
  for _, r in pairs(list) do
    if r.spell and #r.reagents > 0 then
      shared[r.spell] = { n = r.n, p = prof, i = r.item, r = r.reagents }
    end
  end
  FP:Changed()
  return true
end

local function scanTradeSkills()
  if not (GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo) then return false end
  local name, rank, max = GetTradeSkillLine()
  name, rank, max = safe(name), tonumber(safe(rank)), tonumber(safe(max))
  if not name or name == "" or name == "UNKNOWN" then return false end
  if ExpandTradeSkillSubClass then pcall(ExpandTradeSkillSubClass, 0) end
  local list = {}
  for i = 1, GetNumTradeSkills() or 0 do
    local rname, kind = GetTradeSkillInfo(i)
    rname, kind = safe(rname), safe(kind)
    if rname and kind ~= "header" and kind ~= "subheader" then
      local r = {
        n = rname, diff = diffNum(kind),
        icon = GetTradeSkillIcon and safe(GetTradeSkillIcon(i)),
        spell = spellFromLink(GetTradeSkillRecipeLink and safe(GetTradeSkillRecipeLink(i))),
        item = idFromLink(GetTradeSkillItemLink and safe(GetTradeSkillItemLink(i)), "item"),
        reagents = {},
      }
      for j = 1, (GetTradeSkillNumReagents and GetTradeSkillNumReagents(i)) or 0 do
        local _, _, need = GetTradeSkillReagentInfo(i, j)
        local id = idFromLink(GetTradeSkillReagentItemLink and safe(GetTradeSkillReagentItemLink(i, j)), "item")
        if id then r.reagents[#r.reagents + 1] = { id = id, c = tonumber(safe(need)) or 1 } end
      end
      list[r.spell and ("s" .. r.spell) or rname] = r
    end
  end
  return saveRecipes(name, rank, max, list)
end

local function scanCrafts()
  if not (GetCraftDisplaySkillLine and GetNumCrafts and GetCraftInfo) then return false end
  local name, rank, max = GetCraftDisplaySkillLine()
  name, rank, max = safe(name), tonumber(safe(rank)), tonumber(safe(max))
  if not name or name == "" then return false end
  if ExpandCraftSkillLine then pcall(ExpandCraftSkillLine, 0) end
  local list = {}
  for i = 1, GetNumCrafts() or 0 do
    local rname, _, kind = GetCraftInfo(i)
    rname, kind = safe(rname), safe(kind)
    if rname and kind ~= "header" then
      local itemLink = GetCraftItemLink and safe(GetCraftItemLink(i))
      local r = {
        n = rname, diff = diffNum(kind),
        icon = GetCraftIcon and safe(GetCraftIcon(i)),
        spell = spellFromLink(GetCraftRecipeLink and safe(GetCraftRecipeLink(i))) or spellFromLink(itemLink),
        item = idFromLink(itemLink, "item"),
        reagents = {},
      }
      for j = 1, (GetCraftNumReagents and GetCraftNumReagents(i)) or 0 do
        local _, _, need = GetCraftReagentInfo(i, j)
        local id = idFromLink(GetCraftReagentItemLink and safe(GetCraftReagentItemLink(i, j)), "item")
        if id then r.reagents[#r.reagents + 1] = { id = id, c = tonumber(safe(need)) or 1 } end
      end
      list[r.spell and ("s" .. r.spell) or rname] = r
    end
  end
  return saveRecipes(name, rank, max, list)
end

-- The modern profession window (Forever uses this one)
local function scanModern()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetBaseProfessionInfo) then return false end
  local ok, info = pcall(T.GetBaseProfessionInfo)
  if not ok or type(info) ~= "table" then return false end
  local prof = safe(info.professionName)
  if not prof or prof == "" then return false end -- window still loading; TRADE_SKILL_LIST_UPDATE rescans
  local list, n = {}, 0
  for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local ok2, r = pcall(T.GetRecipeInfo, id)
    if ok2 and type(r) == "table" and safe(r.learned) then
      local rec = { n = safe(r.name), icon = safe(r.icon), spell = id, diff = diffNum(safe(r.relativeDifficulty)), reagents = {} }
      if T.GetRecipeSchematic then
        local ok3, sch = pcall(T.GetRecipeSchematic, id, false)
        if ok3 and type(sch) == "table" then
          rec.item = safe(sch.outputItemID)
          for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
            local first = slot.reagents and slot.reagents[1]
            if first and first.itemID then
              rec.reagents[#rec.reagents + 1] = { id = first.itemID, c = safe(slot.quantityRequired) or 1 }
            end
          end
        end
      end
      list["s" .. id] = rec
      n = n + 1
    end
  end
  if n == 0 then return false end -- an empty list is a window that hasn't filled in yet
  return saveRecipes(prof, safe(info.skillLevel), safe(info.maxSkillLevel), list)
end

local queued = {}
local function scanSoon(which)
  if queued[which] then return end
  queued[which] = true
  C_Timer.After(0.5, function()
    queued[which] = false
    if which == "craft" then FP:Try("craft scan", scanCrafts)
    else
      local ok, res = pcall(scanTradeSkills)
      if not ok then FP:Debug("trade scan", res) end
      if not (ok and res) then FP:Try("profession scan", scanModern) end
    end
  end)
end

---------------------------------------------------------------------------
-- Bags and bank: item counts only
---------------------------------------------------------------------------

local function numSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
  return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function slotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local i = C_Container.GetContainerItemInfo(bag, slot)
    if i then return safe(i.itemID), safe(i.stackCount) end
    return
  end
  if GetContainerItemInfo then
    local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
    return idFromLink(safe(link), "item"), safe(count)
  end
end

local function countBags(bags)
  local items = {}
  for _, bag in ipairs(bags) do
    for slot = 1, numSlots(bag) do
      local id, count = slotItem(bag, slot)
      if id then items[id] = (items[id] or 0) + (tonumber(count) or 1) end
    end
  end
  return items
end

-- Bags you carry: backpack, the four bag slots, and the reagent bag (its own
-- slot, 5, on clients that have one). Bank bags come after all of those.
local function carriedBags()
  local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  local list, seen = {}, {}
  for b = 0, last do list[#list + 1] = b; seen[b] = true end
  local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  if reagent and not seen[reagent] then list[#list + 1] = reagent end
  return list, last
end

local function scanBags()
  local c = FP:Char()
  if not c then return end
  local bags = carriedBags()
  c.bags = { t = time(), items = countBags(bags) }
  FP:Changed()
end

local function scanBank()
  local c = FP:Char()
  if not c then return end
  local bags = { BANK_CONTAINER or -1 }
  local _, last = carriedBags()
  local first = last + 1
  for b = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do bags[#bags + 1] = b end
  c.bank = { t = time(), items = countBags(bags) }
  FP:Changed()
end

local bagsQueued = false
local function bagsSoon()
  if bagsQueued then return end
  bagsQueued = true
  C_Timer.After(1.5, function() bagsQueued = false; FP:Try("bag scan", scanBags) end)
end

---------------------------------------------------------------------------
-- Profession trainers. Reads whatever the trainer lists right now and adds
-- it to what's saved, without touching the trainer's filters: Forever
-- Metrics flips those to read every recipe, and two addons doing that would
-- set each other off. Its lists are merged in at login instead.
---------------------------------------------------------------------------

local scanTip
local function serviceSpell(i)
  if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
    local ok, data = pcall(C_TooltipInfo.GetTrainerService, i)
    if ok and type(data) == "table" and type(safe(data.id)) == "number" then return safe(data.id) end
  end
  -- older clients: fill a hidden tooltip with the service and ask it for the spell
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "ForeverProfessionsScanTip", UIParent, "GameTooltipTemplate")
  end
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  if not scanTip.SetTrainerService or not pcall(scanTip.SetTrainerService, scanTip, i) then return end
  local id
  if scanTip.GetSpell then
    local ok, _, sid = pcall(scanTip.GetSpell, scanTip)
    id = ok and safe(sid) or nil
  end
  scanTip:Hide()
  return type(id) == "number" and id or nil
end

-- One trainer list entry per recipe: an entry saved by name (no spell ID
-- known then) is replaced once the ID turns up
local function putTrainer(T, entry)
  if entry.spell then
    for k, r in pairs(T.recipes) do
      if not r.spell and r.n == entry.n then T.recipes[k] = nil end
    end
    T.recipes["s" .. entry.spell] = entry
  else
    for _, r in pairs(T.recipes) do
      if r.n == entry.n and r.spell then return r end -- keep the one with the ID
    end
    T.recipes[entry.n] = entry
  end
  return entry
end

local function scanTrainer()
  if IsTradeskillTrainer and not IsTradeskillTrainer() then return end
  if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceSkillReq) then return end
  local db, n = FP:DB(), 0
  for i = 1, GetNumTrainerServices() or 0 do
    local name, rank, category = GetTrainerServiceInfo(i)
    name, rank, category = safe(name), safe(rank), safe(category)
    if name and category ~= "header" and rank ~= "header" then
      local ok, prof, skill = pcall(GetTrainerServiceSkillReq, i)
      prof, skill = ok and safe(prof) or nil, ok and tonumber(safe(skill)) or nil
      if prof and FP.PROFESSIONS[prof] then
        local id = serviceSpell(i)
        local T = db.trainers[prof] or { recipes = {} }
        db.trainers[prof] = T
        local e = putTrainer(T, {
          n = name, spell = id, skill = skill or 0,
          lv = GetTrainerServiceLevelReq and tonumber(safe(GetTrainerServiceLevelReq(i))),
          cost = (GetTrainerServiceCost and tonumber(safe(GetTrainerServiceCost(i)))) or 0,
          icon = GetTrainerServiceIcon and safe(GetTrainerServiceIcon(i)),
        })
        -- "used" = already learned: count it as known right away
        if (category == "used" or rank == "used") and e.spell then FP:MarkLearned(e.spell) end
        T.scanned = time()
        n = n + 1
      end
    end
  end
  if n > 0 then FP:Changed() end
  FP:Debug(("trainer: %d recipes read"):format(n))
end

local function mergeMetricsTrainers()
  local fm = _G.ForeverMetricsDB
  if type(fm) ~= "table" or type(fm.profTrainer) ~= "table" then return end
  local db = FP:DB()
  for prof, T in pairs(fm.profTrainer) do
    if type(T) == "table" and FP.PROFESSIONS[prof] then
      local mine = db.trainers[prof] or { recipes = {} }
      db.trainers[prof] = mine
      for k, r in pairs(T.recipes or {}) do
        if not mine.recipes[k] then
          putTrainer(mine, { n = r.n, spell = r.spell, skill = r.skill, cost = r.cost, lv = r.lv, icon = r.icon })
        end
      end
      mine.scanned = math.max(mine.scanned or 0, T.scanned or 0)
    end
  end
end

local trainerQueued = false
local function trainerSoon()
  if trainerQueued then return end
  trainerQueued = true
  C_Timer.After(0.7, function() trainerQueued = false; FP:Try("trainer scan", scanTrainer) end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local bankOpen = false
FP:On("PLAYER_LOGIN", function()
  FP:Try("merge trainers", mergeMetricsTrainers)
  C_Timer.After(2, function() FP:Try("skills", scanSkills); bagsSoon() end)
end)
FP:On("SKILL_LINES_CHANGED", function() if FP:Char() then FP:Try("skills", scanSkills) end end)
FP:On("BAG_UPDATE_DELAYED", function() if FP:Char() then bagsSoon() end end)
FP:On("TRADE_SKILL_SHOW", function() scanSoon("trade") end)
FP:On("TRADE_SKILL_UPDATE", function() scanSoon("trade") end)
FP:On("TRADE_SKILL_LIST_UPDATE", function() scanSoon("trade") end)
FP:On("CRAFT_SHOW", function() scanSoon("craft") end)
FP:On("CRAFT_UPDATE", function() scanSoon("craft") end)
FP:On("BANKFRAME_OPENED", function() bankOpen = true; C_Timer.After(0.5, function() FP:Try("bank scan", scanBank) end) end)
FP:On("BANKFRAME_CLOSED", function() bankOpen = false end)
FP:On("PLAYERBANKSLOTS_CHANGED", function() if bankOpen then FP:Try("bank scan", scanBank) end end)
FP:On("TRAINER_SHOW", trainerSoon)
FP:On("TRAINER_UPDATE", trainerSoon)
-- Forever Metrics reads the whole trainer list (it flips the filters); add
-- what it found once it's done, not just at login
local fmQueued = false
FP:On("TRAINER_UPDATE", function()
  if fmQueued then return end
  fmQueued = true
  C_Timer.After(2, function() fmQueued = false; FP:Try("merge trainers", mergeMetricsTrainers); FP:Changed() end)
end)
FP:On("TRAINER_CLOSED", function() FP:Try("merge trainers", mergeMetricsTrainers); FP:Changed() end)
FP:On("LEARNED_SPELL_IN_TAB", function(id) FP:MarkLearned(id) end)
FP:On("LEARNED_SPELL_IN_SKILL_LINE", function(id) FP:MarkLearned(id) end)
FP:On("NEW_RECIPE_LEARNED", function(id) FP:MarkLearned(id) end)
FP:On("CHAT_MSG_SKILL", function(msg)
  msg = safe(msg)
  if type(msg) ~= "string" then return end
  local name, rank = msg:match(SKILL_PAT)
  if name then setSkill(name, tonumber(rank)) end
end)
