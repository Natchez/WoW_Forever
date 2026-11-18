-- Forever Professions: the questions the tooltip and window ask
--   FP:Recipe(spell)       name, profession, skill, item made, materials
--   FP:Uses(itemID)        every recipe that uses an item, across characters,
--                          sorted skill-ups first
--   FP:Summary(key, prof)  one character's profession at a glance
--   FP:Have(key, itemID)   bags + bank on one character
-- Results are cached until something saved changes.

local ADDON, ns = ...
local FP = ns.FP
local safe = FP.safe

local cache = { uses = {}, recipe = {} }
FP:OnChanged(function() cache.uses, cache.index = {}, nil end)

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

function FP:ItemName(id)
  if not id then return "?" end
  local n = (C_Item and C_Item.GetItemNameByID and safe(C_Item.GetItemNameByID(id)))
  if not n and GetItemInfo then n = safe((GetItemInfo(id))) end
  if not n then
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return (ForeverProfessions_Items and ForeverProfessions_Items[id]) or ("item " .. id)
  end
  return n
end

-- Item names arrive from the server a moment after they're asked for:
-- redraw once a burst of them has landed
local namesQueued = false
FP:On("GET_ITEM_INFO_RECEIVED", function()
  if namesQueued then return end
  namesQueued = true
  C_Timer.After(1, function() namesQueued = false; FP:Changed() end)
end)

function FP:ItemIcon(id)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not (id and f) then return 134400 end -- question mark
  local ok, _, _, _, _, icon = pcall(f, id)
  return ok and safe(icon) or 134400
end

function FP:ItemLink(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if f then
    local ok, _, link = pcall(f, id)
    if ok and safe(link) then return link end
  end
  return "[" .. self:ItemName(id) .. "]"
end

function FP:Have(key, id)
  local c = self:DB().chars[key]
  if not c or not id then return 0 end
  local n = 0
  if c.bags and c.bags.items then n = n + (c.bags.items[id] or 0) end
  if c.bank and c.bank.items then n = n + (c.bank.items[id] or 0) end
  return n
end

---------------------------------------------------------------------------
-- Recipes: what any character has seen, then the shipped table
---------------------------------------------------------------------------

function FP:Recipe(spell)
  if not spell then return nil end
  local seen = self:DB().recipes[spell]
  if seen and seen.r and #seen.r > 0 then return seen end
  if cache.recipe[spell] then return cache.recipe[spell] end
  local d = ForeverProfessions_Data and ForeverProfessions_Data[spell]
  if not d then return seen end
  local regs = {}
  for i = 1, #(d[5] or {}), 2 do regs[#regs + 1] = { id = d[5][i], c = d[5][i + 1] } end
  local r = { n = d[1], p = d[2], s = d[3], i = (d[4] ~= 0) and d[4] or nil, r = regs }
  cache.recipe[spell] = r
  return r
end

-- How many times key can make something from what's in their bags and bank
function FP:CanMake(key, reagents)
  if not reagents or #reagents == 0 then return 0 end
  local n
  for _, g in ipairs(reagents) do
    local times = math.floor(self:Have(key, g.id) / math.max(1, g.c or 1))
    n = n and math.min(n, times) or times
  end
  return n or 0
end

-- Materials key is short of, for making it once: { {id, short}, ... }
function FP:Missing(key, reagents)
  local out = {}
  for _, g in ipairs(reagents or {}) do
    local short = (g.c or 1) - self:Have(key, g.id)
    if short > 0 then out[#out + 1] = { id = g.id, short = short } end
  end
  return out
end

-- Every character holding an item: { {key, bags, bank, total}, ... },
-- this character first, then most first
function FP:Holders(id)
  local out, me = {}, self:CharKey()
  for key, c in pairs(self:DB().chars) do
    local bags = c.bags and c.bags.items and c.bags.items[id] or 0
    local bank = c.bank and c.bank.items and c.bank.items[id] or 0
    if bags + bank > 0 then out[#out + 1] = { key = key, bags = bags, bank = bank, total = bags + bank } end
  end
  table.sort(out, function(a, b)
    if (a.key == me) ~= (b.key == me) then return a.key == me end
    if a.total ~= b.total then return a.total > b.total end
    return a.key < b.key
  end)
  return out
end

-- Another character holding at least `need` of an item (or nil)
function FP:WhoHas(id, need, notKey)
  local best, bestN
  for key in pairs(self:DB().chars) do
    if key ~= notKey then
      local n = self:Have(key, id)
      if n >= (need or 1) and (not bestN or n > bestN) then best, bestN = key, n end
    end
  end
  return best, bestN
end

function FP:Rank(key, prof)
  local c = self:DB().chars[key]
  if not c then return nil end
  local s = c.skills and c.skills[prof]
  local p = c.prof and c.prof[prof]
  return (s and s.rank) or (p and p.rank), (s and s.max) or (p and p.max)
end

local function chars()
  local keys = {}
  local me = FP:CharKey()
  for key in pairs(FP:DB().chars) do
    if key == me or FP:GetSetting("tipAlts") then keys[#keys + 1] = key end
  end
  return keys
end

local RANK_CAP = { Apprentice = 75, Journeyman = 150, Expert = 225, Artisan = 300 }

local function knows(c, prof, spell, name)
  -- "Journeyman Blacksmithing": trained once your cap has reached it
  local title = type(name) == "string" and name:match("^(%a+) ")
  if title and RANK_CAP[title] then
    local s, P = c.skills and c.skills[prof], c.prof and c.prof[prof]
    local max = (s and s.max) or (P and P.max) or 0
    return max >= RANK_CAP[title]
  end
  local P = c.prof and c.prof[prof]
  if not P or not P.recipes then return false end
  if spell and P.recipes["s" .. spell] then return true end
  for _, r in pairs(P.recipes) do if r.n == name then return true end end
  return false
end

---------------------------------------------------------------------------
-- Which recipes use an item
---------------------------------------------------------------------------

-- Tooltip and Alt-click order: skill-ups you can make now, skill-ups you're
-- short for, anything else you can make, the rest, then learnable
local function useRank(e)
  if e.kind == "learn" then return 9 end
  local skill, can = e.diff and e.diff <= 1, (e.canMake or 0) > 0
  if skill and can then return 0 elseif skill then return 1 elseif can then return 2 end
  return 3
end
local function sortUses(a, b)
  local ra, rb = useRank(a), useRank(b)
  if ra ~= rb then return ra < rb end
  local da, db = a.diff or 4, b.diff or 4
  if da ~= db then return da < db end
  local me = FP:CharKey()
  if (a.key == me) ~= (b.key == me) then return a.key == me end
  if (a.canMake or 0) ~= (b.canMake or 0) then return (a.canMake or 0) > (b.canMake or 0) end
  return (a.n or "") < (b.n or "")
end

-- Recipes page order: by colour (the list is grouped by it), then makeable
local function sortEntries(a, b)
  if (a.kind == "learn") ~= (b.kind == "learn") then return b.kind == "learn" end
  local da, db = a.diff or 4, b.diff or 4
  if da ~= db then return da < db end
  local ma, mb = (a.canMake or 0) > 0, (b.canMake or 0) > 0
  if ma ~= mb then return ma end
  local me = FP:CharKey()
  if (a.key == me) ~= (b.key == me) then return a.key == me end
  return (a.n or "") < (b.n or "")
end

function FP:Uses(item)
  if not item then return nil end
  if cache.uses[item] then return cache.uses[item] end
  local db = self:DB()
  local out = { item = item, list = {}, skillups = 0, known = 0, learn = 0, recipes = 0 }
  local distinct = {}

  for _, key in ipairs(chars()) do
    local c = db.chars[key]
    -- recipes this character knows
    for prof, P in pairs(c.prof or {}) do
      for _, r in pairs(P.recipes or {}) do
        local regs = r.reagents
        if (not regs or #regs == 0) and r.spell then
          local R = self:Recipe(r.spell); regs = R and R.r
        end
        for _, g in ipairs(regs or {}) do
          if g.id == item then
            local e = {
              kind = "known", key = key, prof = prof, spell = r.spell, n = r.n, icon = r.icon,
              made = r.item, need = g.c or 1, diff = r.diff, reagents = regs,
              canMake = self:CanMake(key, regs), missing = self:Missing(key, regs),
            }
            if self:Have(key, item) < e.need then e.altHas = self:WhoHas(item, e.need, key) end
            out.list[#out.list + 1] = e
            distinct[r.spell or r.n] = true
            break
          end
        end
      end
    end
    -- recipes a trainer would teach this character now
    for prof, T in pairs(db.trainers) do
      local rank = self:Rank(key, prof)
      local P = c.prof and c.prof[prof]
      if rank and P and P.recipes then -- unknown recipe lists would suggest ones you already have
        for _, t in pairs(T.recipes or {}) do
          if t.spell and (t.skill or 0) <= rank and not knows(c, prof, t.spell, t.n) then
            local R = self:Recipe(t.spell)
            for _, g in ipairs(R and R.r or {}) do
              if g.id == item then
                out.list[#out.list + 1] = {
                  kind = "learn", key = key, prof = prof, spell = t.spell, n = t.n or R.n, icon = t.icon,
                  made = R.i, need = g.c or 1, cost = t.cost or 0, skill = t.skill, reagents = R.r,
                }
                break
              end
            end
          end
        end
      end
    end
  end

  local grey = self:GetSetting("tipGrey")
  for _, e in ipairs(out.list) do
    if e.kind == "learn" then out.learn = out.learn + 1
    elseif grey or e.diff ~= 3 then
      out.known = out.known + 1
      if e.diff and e.diff <= 1 then out.skillups = out.skillups + 1 end
    end
  end
  for _ in pairs(distinct) do out.recipes = out.recipes + 1 end
  table.sort(out.list, sortUses)
  cache.uses[item] = out
  return out
end

---------------------------------------------------------------------------
-- One character's profession, for the Overview cards
---------------------------------------------------------------------------

function FP:Summary(key, prof)
  local c = self:DB().chars[key]
  local P = c and c.prof and c.prof[prof]
  local rank, max = self:Rank(key, prof)
  local s = { key = key, prof = prof, rank = rank or 0, max = max, seen = P and P.recipes and next(P.recipes) ~= nil,
              craft = 0, learn = 0, learnCost = 0, upcoming = 0, nextSkill = nil }
  local best
  for _, r in pairs(P and P.recipes or {}) do
    local regs = (r.reagents and #r.reagents > 0) and r.reagents or (self:Recipe(r.spell) or {}).r
    local can = self:CanMake(key, regs)
    if can > 0 then s.craft = s.craft + 1 end
    if r.diff and r.diff <= 1 then
      local score = r.diff * 10 + (can > 0 and 0 or 5)
      if not best or score < best.score or (score == best.score and (r.n or "") < (best.r.n or "")) then
        best = { score = score, r = r, can = can, missing = self:Missing(key, regs) }
      end
    end
  end
  s.best = best
  local T = self:DB().trainers[prof]
  for _, t in pairs(T and T.recipes or {}) do
    if not knows(c, prof, t.spell, t.n) then
      if (t.skill or 0) <= s.rank then
        if s.seen then s.learn = s.learn + 1; s.learnCost = s.learnCost + (t.cost or 0) end
      else
        s.upcoming = s.upcoming + 1
        if not s.nextSkill or t.skill < s.nextSkill then s.nextSkill = t.skill end
      end
    end
  end
  s.trainerSeen = T ~= nil
  return s
end

-- Every (character, profession) pair, current character first
function FP:Pairs()
  local db, out, me = self:DB(), {}, self:CharKey()
  for key, c in pairs(db.chars) do
    local seen = {}
    for prof in pairs(c.prof or {}) do if self.PROFESSIONS[prof] then seen[prof] = true end end
    for prof in pairs(c.skills or {}) do if self.PROFESSIONS[prof] then seen[prof] = true end end
    for prof in pairs(seen) do
      if prof ~= "Fishing" or (self:Rank(key, prof) or 0) > 1 then out[#out + 1] = { key = key, prof = prof } end
    end
  end
  table.sort(out, function(a, b)
    if (a.key == me) ~= (b.key == me) then return a.key == me end
    if a.key ~= b.key then return a.key < b.key end
    local ga, gb = FP.GATHERING[a.prof] and 1 or 0, FP.GATHERING[b.prof] and 1 or 0
    if ga ~= gb then return ga < gb end
    return (self:Rank(a.key, a.prof) or 0) > (self:Rank(b.key, b.prof) or 0)
  end)
  return out
end

-- Recipes for the Recipes page: known (with colours) plus learnable now
function FP:RecipeList(key, prof)
  local c = self:DB().chars[key]
  local P = c and c.prof and c.prof[prof]
  local rank = self:Rank(key, prof) or 0
  local list = {}
  for _, r in pairs(P and P.recipes or {}) do
    local regs = (r.reagents and #r.reagents > 0) and r.reagents or (self:Recipe(r.spell) or {}).r or {}
    list[#list + 1] = { kind = "known", key = key, prof = prof, spell = r.spell, n = r.n, icon = r.icon, made = r.item,
                        diff = r.diff, reagents = regs, canMake = self:CanMake(key, regs), missing = self:Missing(key, regs) }
  end
  local T = self:DB().trainers[prof]
  if P and P.recipes then
    for _, t in pairs(T and T.recipes or {}) do
      if not knows(c, prof, t.spell, t.n) and (t.skill or 0) <= rank then
        local R = self:Recipe(t.spell) or {}
        list[#list + 1] = { kind = "learn", key = key, prof = prof, spell = t.spell, n = t.n or R.n, icon = t.icon,
                            made = R.i, reagents = R.r or {}, cost = t.cost or 0, skill = t.skill }
      end
    end
  end
  table.sort(list, sortEntries)
  return list
end
