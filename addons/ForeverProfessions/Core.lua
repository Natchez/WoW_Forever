-- Forever Professions: Core
-- One account-wide SavedVariable, ForeverProfessionsDB:
--   chars[<name-realm>]  name, realm, class, lastSeen,
--                        skills[<profession>] = { rank, max }
--                        prof[<profession>]   = { rank, max, scanned, recipes = { ["s"..spell] = recipe } }
--                        bags / bank          = { t, items = { [itemID] = count } }
--   trainers[<profession>] = { scanned, recipes = { ["s"..spell] = { n, spell, skill, cost, lv, icon } } }
--   recipes[spell]       = { n, p, i, r = { {id, c}, ... } }  materials of every recipe any
--                          character has seen, so alts can use them (adds to Data.lua)
--   settings             = { key = value }
-- Never rename or reset these keys; migrate them.

local ADDON, ns = ...
local FP = {}
ns.FP = FP
_G.ForeverProfessions = FP

do
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  FP.VERSION = getMeta and getMeta(ADDON, "Version") or "?"
end

FP.PROFESSIONS = {
  Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Leatherworking = true,
  Tailoring = true, Cooking = true, ["First Aid"] = true,
  Mining = true, Herbalism = true, Skinning = true, Fishing = true,
}
FP.GATHERING = { Mining = true, Herbalism = true, Skinning = true, Fishing = true }

-- Forever's "secret values" can't be read or compared: treat them as missing.
function FP.safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

function FP:Say(msg) print("|cffe8c27aForever Professions|r " .. msg) end
function FP:Debug(...) if self.debug then print("|cffff5555ForeverProfessions|r", ...) end end

-- Runs fn in pcall; errors print only with /fp debug on.
function FP:Try(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then self:Debug(label, err) end
  return ok, err
end

function FP:DB() return ForeverProfessionsDB end
function FP:Char() return self.char end
function FP:CharKey() return self.key end

-- Theme, same leather and gold as Forever Metrics
FP.THEME = {
  bg     = { 0.12, 0.085, 0.055, 0.92 },
  border = { 0.66, 0.51, 0.31, 0.95 },
  bar    = { 0.88, 0.67, 0.30, 1 },
  hl     = { 0.88, 0.67, 0.30, 0.18 },
}
-- Recipe difficulty, 0 = orange (always a skill-up) .. 3 = grey (never)
FP.DIFF_COLOR = { [0] = "ff8040", [1] = "ffff00", [2] = "40bf40", [3] = "9d9d9d" }
FP.DIFF_LABEL = { [0] = "Orange: always a skill-up", [1] = "Yellow: usually a skill-up",
                  [2] = "Green: sometimes a skill-up", [3] = "Grey: no more skill-ups" }
FP.CLASS_COLOR = {
  WARRIOR = "c69b6d", MAGE = "3fc7eb", ROGUE = "fff468", SHAMAN = "0070dd", DRUID = "ff7c0a",
  PRIEST = "ffffff", PALADIN = "f48cba", HUNTER = "aad372", WARLOCK = "8788ee",
}

function FP:Skin(f, opts)
  if not f or not f.SetBackdrop then return end
  opts = opts or {}
  local edge = opts.edge or 12
  local inset = math.floor(edge / 4 + 0.5)
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = edge,
    insets = { left = inset, right = inset, top = inset, bottom = inset },
  })
  local bg, br = self.THEME.bg, self.THEME.border
  f:SetBackdropColor(bg[1], bg[2], bg[3], opts.alpha or bg[4])
  f:SetBackdropBorderColor(br[1], br[2], br[3], br[4])
end

-- "Genebelcher" in class colour; short = first 4 letters for tight spots
function FP:CharName(key, short)
  local c = self:DB().chars[key]
  local n = c and c.name or (key or "?"):match("^[^-]+") or "?"
  if short and #n > 6 then n = n:sub(1, 4) end
  local col = c and self.CLASS_COLOR[c.class or ""] or "ffffff"
  return "|cff" .. col .. n .. "|r"
end

function FP:Money(c)
  c = c or 0
  if GetCoinTextureString then return GetCoinTextureString(c) end
  return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
end

---------------------------------------------------------------------------
-- Settings: add a row here; UI.lua builds the Options page from it.
---------------------------------------------------------------------------

FP.SETTINGS = {
  { group = "tooltip", key = "tipLine",   label = "Add a Crafting line to item tooltips", default = true },
  { group = "tooltip", key = "tipShift",  label = "Hold Shift for the top recipes",       default = true },
  { group = "tooltip", key = "tipHint",   label = "Show the \"Shift: details\" hint",     default = true },
  { group = "tooltip", key = "altClick",  label = "Alt-click an item to list every recipe that uses it", default = true },
  { group = "tooltip", key = "tipAlts",   label = "Include your other characters",        default = true },
  { group = "tooltip", key = "tipGrey",   label = "Count grey recipes",                   default = true },
}
local defs, hooks = {}, {}
for _, d in ipairs(FP.SETTINGS) do defs[d.key] = d end

function FP:GetSetting(key)
  local s = ForeverProfessionsDB and ForeverProfessionsDB.settings
  if s and s[key] ~= nil then return s[key] end
  return defs[key] and defs[key].default
end
function FP:SetSetting(key, value)
  ForeverProfessionsDB.settings = ForeverProfessionsDB.settings or {}
  ForeverProfessionsDB.settings[key] = value
  for _, fn in ipairs(hooks[key] or {}) do pcall(fn, value) end
  self:Changed()
end
function FP:OnSetting(key, fn) hooks[key] = hooks[key] or {}; table.insert(hooks[key], fn) end

-- Anything saved changed: drop cached lookups and redraw open windows
local listeners = {}
function FP:OnChanged(fn) listeners[#listeners + 1] = fn end
function FP:Changed()
  self.dirty = true
  for _, fn in ipairs(listeners) do pcall(fn) end
end

---------------------------------------------------------------------------
-- First run: borrow what Forever Metrics already saw (recipes, bags, bank,
-- trainers), so every character shows up without logging each one in.
-- Read-only: ForeverMetricsDB is never changed.
---------------------------------------------------------------------------

local function importFromMetrics(db)
  local fm = _G.ForeverMetricsDB
  if type(fm) ~= "table" or db.importedFM then return end
  local n = 0
  for key, c in pairs(fm.chars or {}) do
    if type(c) == "table" and not db.chars[key] then
      local mine = { name = c.name, realm = c.realm, class = c.class, lastSeen = c.lastSeen, skills = {}, prof = {} }
      for skill, s in pairs(c.skills or {}) do
        if FP.PROFESSIONS[skill] and type(s) == "table" then mine.skills[skill] = { rank = s.rank } end
      end
      for prof, P in pairs(c.prof or {}) do
        if prof ~= "" and type(P) == "table" then
          local recipes = {}
          for k, r in pairs(P.recipes or {}) do
            local regs = {}
            for _, g in ipairs(r.reagents or {}) do
              if g.id then regs[#regs + 1] = { id = g.id, c = g.c or 1 } end
            end
            recipes[k] = { n = r.n, spell = r.spell, item = r.item, icon = r.icon, diff = r.diff, reagents = regs }
          end
          mine.prof[prof] = { rank = P.rank, max = P.max, scanned = P.scanned, recipes = recipes }
        end
      end
      for _, where in ipairs({ "bags", "bank" }) do
        local src = c[where]
        if type(src) == "table" and type(src.items) == "table" then
          local items = {}
          for id, e in pairs(src.items) do items[id] = type(e) == "table" and (e.c or 0) or e end
          mine[where] = { t = src.t, items = items }
        end
      end
      db.chars[key] = mine
      n = n + 1
    end
  end
  for prof, T in pairs(fm.profTrainer or {}) do
    if not db.trainers[prof] and type(T) == "table" then
      local recipes = {}
      for k, r in pairs(T.recipes or {}) do
        recipes[k] = { n = r.n, spell = r.spell, skill = r.skill, cost = r.cost, lv = r.lv, icon = r.icon }
      end
      db.trainers[prof] = { scanned = T.scanned, recipes = recipes }
    end
  end
  db.importedFM = time()
  if n > 0 then FP:Say(("brought in %d characters from Forever Metrics."):format(n)) end
end

---------------------------------------------------------------------------
-- Events: a tiny registry other files add handlers to
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}
function FP:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    pcall(frame.RegisterEvent, frame, event) -- an event this client lacks just isn't registered
  end
  table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then FP:Debug(event, err) end
  end
end)

FP:On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  ForeverProfessionsDB = ForeverProfessionsDB or {}
  local db = ForeverProfessionsDB
  db.version = 1
  db.chars = db.chars or {}
  db.trainers = db.trainers or {}
  db.recipes = db.recipes or {}
  db.settings = db.settings or {}
end)

FP:On("PLAYER_LOGIN", function()
  local db = ForeverProfessionsDB
  FP:Try("import", importFromMetrics, db)
  local name, realm = FP.safe(UnitName("player")), FP.safe(GetRealmName())
  if not name then return end
  FP.key = name .. "-" .. (realm or "?")
  local c = db.chars[FP.key] or { name = name, realm = realm, skills = {}, prof = {} }
  db.chars[FP.key] = c
  c.skills, c.prof = c.skills or {}, c.prof or {}
  local _, classFile = UnitClass("player")
  c.class = FP.safe(classFile) or c.class
  c.lastSeen = time()
  FP.char = c
  FP:Changed()
end)

---------------------------------------------------------------------------
-- Slash commands and key binding
---------------------------------------------------------------------------

BINDING_HEADER_FOREVERPROFESSIONS = "Forever Professions"
BINDING_NAME_FOREVERPROFESSIONS_TOGGLE = "Open / close Forever Professions"

SLASH_FOREVERPROFESSIONS1 = "/fp"
SLASH_FOREVERPROFESSIONS2 = "/fprof"
SlashCmdList.FOREVERPROFESSIONS = function(arg)
  arg = (arg or ""):lower():match("^%s*(.-)%s*$")
  if arg == "debug" then
    FP.debug = not FP.debug
    FP:Say("debug " .. (FP.debug and "on: errors print in chat." or "off."))
  elseif arg == "options" or arg == "settings" then
    if FP.OpenAt then FP:OpenAt("tooltips") end
  elseif arg ~= "" and FP.OpenRecipes then
    FP:OpenRecipes(arg) -- /fp copper bar: search recipes for it
  elseif FP.Toggle then
    FP:Toggle()
  end
end
