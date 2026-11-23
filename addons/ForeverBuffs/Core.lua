-- Forever Buffs: core
-- Works out which of your class buffs (Data.lua) are missing or about to run
-- out, and hands that list to UI.lua. Checks only happen out of combat; in
-- combat the last result stays on screen.
--
-- Forever notes (see ForeverMetrics for the history):
--   * Some API returns are "secret values" that can't be compared or used.
--     Everything read from the game goes through safe() first.
--   * Never register COMBAT_LOG_EVENT_UNFILTERED (blocked-action popup).
--   * Events are registered with pcall and handlers run inside pcall; errors
--     print only with /fb debug on.

local ADDON, ns = ...
local FB = ns.FB

FB.PREFIX = "|cffe8c27aForever Buffs|r"
FB.debug = false

FB.DEFAULTS = {
  enabled = true,
  point = { "CENTER", "UIParent", "CENTER", 0, -160 },
  scale = 1,
  glow = true,
  restHide = false,   -- "Only remind outside cities (resting)"
  threshold = 60,     -- seconds left that count as "about to run out"
}

local THROTTLE = 0.25

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end
FB.safe = safe

function FB:Print(...)
  print(FB.PREFIX, ...)
end

function FB:Debug(...)
  if FB.debug then print("|cff888888Forever Buffs:|r", ...) end
end

-- pcall that reports in debug mode
function FB:Try(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and FB.debug then print("|cffff5555Forever Buffs error|r", label, err) end
  return ok
end

function FB:DB()
  ForeverBuffsDB = ForeverBuffsDB or {}
  local db = ForeverBuffsDB
  for k, v in pairs(FB.DEFAULTS) do
    if db[k] == nil then
      if type(v) == "table" then
        local copy = {}
        for i, x in ipairs(v) do copy[i] = x end
        db[k] = copy
      else
        db[k] = v
      end
    end
  end
  db.chars = db.chars or {}
  return db
end

function FB:Char()
  local db = FB:DB()
  local name = safe(UnitName("player")) or "?"
  -- Forever's GetRealmName() can return "": fall back to the last realm seen
  local realm = safe(GetRealmName and GetRealmName())
  if type(realm) == "string" and realm ~= "" then db.realm = realm
  else realm = db.realm or (ForeverMetricsDB and ForeverMetricsDB.realm) or "?" end
  local key = name .. "-" .. realm
  local blank = name .. "-"
  if realm ~= "?" and db.chars[blank] then
    db.chars[key] = db.chars[key] or db.chars[blank]
    db.chars[blank] = nil
  end
  db.chars[key] = db.chars[key] or {}
  local c = db.chars[key]
  c.last = c.last or {}
  return c
end

local function spellNameByID(id)
  if not id then return nil end
  local ok, n = pcall(function()
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
  end)
  n = ok and safe(n) or nil
  if type(n) == "string" and n ~= "" then return n end
end

-- Look a spell up by name. On most clients this only finds spells you know.
local function spellInfoByName(name)
  local ok, id, icon = pcall(function()
    if C_Spell and C_Spell.GetSpellInfo then
      local info = C_Spell.GetSpellInfo(name)
      if info then return info.spellID, info.iconID end
      return nil
    end
    if GetSpellInfo then
      local _, _, ic, _, _, _, sid = GetSpellInfo(name)
      return sid, ic
    end
  end)
  if not ok then return nil end
  return safe(id), safe(icon)
end

function FB:SpellIcon(id, name)
  local ok, tex = pcall(function()
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id or name) end
    if GetSpellTexture then return GetSpellTexture(id or name) end
  end)
  tex = ok and safe(tex) or nil
  if not tex and name then
    local _, icon = spellInfoByName(name)
    tex = icon
  end
  return tex or 134400 -- question mark
end

---------------------------------------------------------------------------
-- Spellbook: which spells do you know?
---------------------------------------------------------------------------

FB.known = {}
FB.knownCount = 0

local function addKnown(name)
  name = safe(name)
  if type(name) == "string" and name ~= "" and not FB.known[name] then
    FB.known[name] = true
    FB.knownCount = FB.knownCount + 1
  end
end

local function scanModern()
  local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
  local future = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
  for t = 1, C_SpellBook.GetNumSpellBookSkillLines() do
    local line = C_SpellBook.GetSpellBookSkillLineInfo(t)
    local offset = line and safe(line.itemIndexOffset)
    local n = line and safe(line.numSpellBookItems)
    if offset and n then
      for i = offset + 1, offset + n do
        local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
        if item and (future == nil or safe(item.itemType) ~= future) then addKnown(item.name) end
      end
    end
  end
end

local function scanClassic()
  local book = BOOKTYPE_SPELL or "spell"
  for t = 1, GetNumSpellTabs() do
    local _, _, offset, n = GetSpellTabInfo(t)
    offset, n = safe(offset), safe(n)
    if offset and n then
      for i = offset + 1, offset + n do
        local kind = GetSpellBookItemInfo and safe((GetSpellBookItemInfo(i, book)))
        if kind ~= "FUTURESPELL" then addKnown((GetSpellBookItemName(i, book))) end
      end
    end
  end
end

function FB:ScanSpellbook()
  FB.known, FB.knownCount = {}, 0
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
    FB:Try("spellbook (modern)", scanModern)
  end
  if FB.knownCount == 0 and GetNumSpellTabs and GetSpellBookItemName then
    FB:Try("spellbook (classic)", scanClassic)
  end
  FB:Debug("spellbook scan found", FB.knownCount, "spells")
end

-- s = a prepared spell { id, name, en }
local function knows(s)
  if FB.known[s.name] or FB.known[s.en] then return true end
  if s.id then
    if IsPlayerSpell then
      local ok, r = pcall(IsPlayerSpell, s.id)
      if ok and safe(r) then return true end
    end
    if IsSpellKnown then
      local ok, r = pcall(IsSpellKnown, s.id)
      if ok and safe(r) then return true end
    end
  end
  -- Spellbook scan didn't work on this client: ask the game by name instead
  if FB.knownCount == 0 and spellInfoByName(s.name) then return true end
  return false
end

---------------------------------------------------------------------------
-- Prepare the class table: resolve names in the game's language
---------------------------------------------------------------------------

local function prepSpell(pair)
  local id, en = pair[1], pair[2]
  return { id = id, en = en, name = spellNameByID(id) or en }
end

function FB:Prepare()
  local _, class = UnitClass("player")
  FB.class = safe(class)
  FB.entries = {}
  for _, e in ipairs(FB.BUFFS[FB.class] or {}) do
    local p = { def = e, key = e.key, label = e.label, spells = {}, match = {} }
    for _, pair in ipairs(e.spells or {}) do
      local s = prepSpell(pair)
      p.spells[#p.spells + 1] = s
      p.match[s.name], p.match[s.en] = s, s
    end
    for _, pair in ipairs(e.counts or {}) do
      local s = prepSpell(pair)
      p.match[s.name], p.match[s.en] = p.match[s.name] or true, p.match[s.en] or true
    end
    FB.entries[#FB.entries + 1] = p
  end
  local ps = prepSpell(FB.POISONS_SPELL)
  FB.poisonsSpell = ps
end

---------------------------------------------------------------------------
-- Reading your buffs and weapon enchants
---------------------------------------------------------------------------

-- name -> expirationTime (0 = never runs out)
local function scanAuras()
  local out = {}
  local function put(name, exp)
    name, exp = safe(name), safe(exp)
    if type(name) ~= "string" then return end
    exp = type(exp) == "number" and exp or 0
    local old = out[name]
    if old == nil or (old ~= 0 and (exp == 0 or exp > old)) then out[name] = exp end
  end
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 40 do
      local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if not ok then break end
      if not (issecretvalue and issecretvalue(a)) then
        if a == nil then break end
        pcall(function() put(a.name, a.expirationTime) end)
      end
    end
  elseif UnitBuff then
    for i = 1, 40 do
      local ok, name, _, _, _, _, exp = pcall(UnitBuff, "player", i)
      if not ok then break end
      local hidden = issecretvalue and issecretvalue(name)
      if not hidden and name == nil then break end
      if not hidden then put(name, exp) end
    end
  end
  return out
end

local SLOT = { main = 16, off = 17 }

local function weaponEnchants()
  if not GetWeaponEnchantInfo then return nil end
  local ok, mh, mhExp, _, _, oh, ohExp = pcall(GetWeaponEnchantInfo)
  if not ok then return nil end
  return {
    main = { has = safe(mh), ms = safe(mhExp) },
    off  = { has = safe(oh), ms = safe(ohExp) },
  }
end

local function itemInfoInstant(id)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not f or not id then return end
  local ok, _, _, _, _, icon, classID = pcall(f, id)
  if ok then return safe(icon), safe(classID) end
end

-- Is there a weapon in that hand? (A shield or off-hand frill doesn't count.)
local function weaponInSlot(hand)
  local id = safe(GetInventoryItemID("player", SLOT[hand]))
  if not id then return false end
  if hand == "main" then return true, id end
  local _, classID = itemInfoInstant(id)
  local WEAPON = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
  return classID == WEAPON, id
end

---------------------------------------------------------------------------
-- Rogue poisons in your bags
---------------------------------------------------------------------------

local function itemName(id)
  local ok, n = pcall(function()
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    if GetItemInfo then return (GetItemInfo(id)) end
  end)
  return ok and safe(n) or nil
end

local function itemLevel(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not f then return 0 end
  local ok, _, _, _, lvl = pcall(f, id)
  return (ok and safe(lvl)) or 0
end

local function bagPoisons()
  local found = {} -- list of { name, id }
  local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local itemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
  if not numSlots or not itemID then return found end
  local seen = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local ok, n = pcall(numSlots, bag)
    n = ok and safe(n) or 0
    for slot = 1, n do
      local ok2, id = pcall(itemID, bag, slot)
      id = ok2 and safe(id) or nil
      if id and not seen[id] then
        seen[id] = true
        local name = itemName(id)
        if name and name:find("Poison") then found[#found + 1] = { name = name, id = id } end
      end
    end
  end
  return found
end

local function pickPoison(hand, poisons)
  for _, prefix in ipairs(FB.POISONS[hand] or {}) do
    local best, bestLvl
    for _, p in ipairs(poisons) do
      if p.name:sub(1, #prefix) == prefix then
        local lvl = itemLevel(p.id)
        if not best or lvl > bestLvl then best, bestLvl = p, lvl end
      end
    end
    if best then return best end
  end
  return poisons[1]
end

---------------------------------------------------------------------------
-- Gates
---------------------------------------------------------------------------

FB.GATES = {
  -- Rogues get poisons from the Poisons skill at level 20
  poisons = function()
    if FB.poisonsSpell and knows(FB.poisonsSpell) then return true end
    return (safe(UnitLevel("player")) or 0) >= 20
  end,
}

---------------------------------------------------------------------------
-- Evaluate: what should be on screen?
---------------------------------------------------------------------------
-- Each result: { key, label, icon, spellID, itemID, expires (GetTime-based,
-- nil when missing), action = { type = "spell", spell = name } or
-- { type = "macro", macrotext = ... } or nil, hint }

local function pickSpell(p, known)
  local last = FB:Char().last[p.key]
  if last then
    for _, s in ipairs(known) do
      if s.name == last or s.en == last then return s end
    end
  end
  return known[1]
end

local function rememberSpell(p, s)
  if type(s) == "table" then FB:Char().last[p.key] = s.name end
end

function FB:Evaluate()
  local list, nextCheck = {}, nil
  local now, threshold = GetTime(), FB:DB().threshold or 60
  local auras = scanAuras()
  local weapons, poisons

  local function due(at)
    if at > now and (nextCheck == nil or at < nextCheck) then nextCheck = at end
  end

  for _, p in ipairs(FB.entries or {}) do
    local d = p.def
    local pass = true
    if d.gate and FB.GATES[d.gate] then
      local ok, r = pcall(FB.GATES[d.gate])
      pass = ok and r
    end
    if pass and d.minRage then
      local rage = safe(UnitPower("player", (Enum and Enum.PowerType and Enum.PowerType.Rage) or 1)) or 0
      pass = rage >= d.minRage
    end

    local known = {}
    if pass and not d.poison then
      for _, s in ipairs(p.spells) do if knows(s) then known[#known + 1] = s end end
      pass = #known > 0
    end

    if pass and d.weapon then
      local hasWeapon, weaponID = weaponInSlot(d.weapon)
      weapons = weapons or weaponEnchants()
      if hasWeapon and weapons then
        local w = weapons[d.weapon]
        local r = { key = p.key, label = p.label }
        local show = false
        if not w.has then
          show = true
        elseif type(w.ms) == "number" and w.ms > 0 then
          local expires = now + w.ms / 1000
          if w.ms / 1000 < threshold then show, r.expires = true, expires
          else due(expires - threshold) end
        end
        if show then
          if d.poison then
            poisons = poisons or bagPoisons()
            local pz = pickPoison(d.weapon, poisons)
            if pz then
              r.itemID, r.itemName = pz.id, pz.name
              r.icon = itemInfoInstant(pz.id)
              r.action = { type = "macro", macrotext = ("/use %s\n/use %d"):format(pz.name, SLOT[d.weapon]) }
            else
              r.icon = safe(GetInventoryItemTexture("player", SLOT[d.weapon]))
              r.hint = "No poison in your bags"
            end
          else
            local s = pickSpell(p, known)
            r.spellName, r.spellID = s.name, (spellInfoByName(s.name)) or s.id
            r.icon = FB:SpellIcon(s.id, s.name)
            r.action = { type = "spell", spell = s.name }
          end
          r.icon = r.icon or 134400
          list[#list + 1] = r
        end
      end
    elseif pass then
      -- A buff on you
      local activeName, exp
      for name, e in pairs(auras) do
        if p.match[name] then
          if activeName == nil or e == 0 or (exp ~= 0 and e > exp) then activeName, exp = name, e end
        end
      end
      local r, show = { key = p.key, label = p.label }, false
      if not activeName then
        show = true
      else
        local m = p.match[activeName]
        if type(m) == "table" then rememberSpell(p, m) end
        if exp > 0 then
          if exp - now < threshold then show, r.expires = true, exp
          else due(exp - threshold) end
        end
      end
      if show then
        local s = pickSpell(p, known)
        r.spellName, r.spellID = s.name, (spellInfoByName(s.name)) or s.id
        r.icon = FB:SpellIcon(s.id, s.name)
        r.action = { type = "spell", spell = s.name, unit = "player" }
        list[#list + 1] = r
      end
    end
  end
  return list, nextCheck
end

---------------------------------------------------------------------------
-- Refresh: evaluate (out of combat only) and hand the result to the UI
---------------------------------------------------------------------------

FB.list = {}
FB.pending = false

function FB:ShouldHide()
  local db = FB:DB()
  if not db.enabled then return true end
  if safe(UnitIsDeadOrGhost("player")) then return true end
  if UnitInVehicle and safe(UnitInVehicle("player")) then return true end
  if UnitHasVehicleUI and safe(UnitHasVehicleUI("player")) then return true end
  if UnitOnTaxi and safe(UnitOnTaxi("player")) then return true end
  if db.restHide and IsResting and safe(IsResting()) then return true end
  return false
end

function FB:Refresh()
  if not FB.ready then return end
  if InCombatLockdown() then FB.pending = true; return end
  FB.pending = false
  local ok, list, nextCheck = pcall(FB.Evaluate, FB)
  if not ok then
    if FB.debug then print("|cffff5555Forever Buffs error|r evaluate", list) end
    return
  end
  FB.list, FB.nextCheck = list, nextCheck
  if FB.UI then FB:Try("apply", FB.UI.Apply, FB.UI) end
end

local queued = false
function FB:Request()
  if queued then return end
  queued = true
  C_Timer.After(THROTTLE, function()
    queued = false
    FB:Refresh()
  end)
end

-- Remember which version of a buff you cast (armor, aspect, imbue...)
local function onCast(spellID)
  spellID = safe(spellID)
  if not spellID then return end
  local name = spellNameByID(spellID)
  if not name then return end
  for _, p in ipairs(FB.entries or {}) do
    local s = p.match[name]
    if type(s) == "table" then rememberSpell(p, s) end
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local H = {}

function H.PLAYER_LOGIN()
  FB:DB()
  FB:Prepare()
  FB:ScanSpellbook()
  FB.ready = true
  if FB.UI then FB:Try("build", FB.UI.Build, FB.UI) end
  -- Warriors: shout reminder depends on rage
  if FB.class == "WARRIOR" then
    if ev.RegisterUnitEvent then pcall(ev.RegisterUnitEvent, ev, "UNIT_POWER_UPDATE", "player")
    else pcall(ev.RegisterEvent, ev, "UNIT_POWER_UPDATE") end
  end
  -- Re-check when a buff crosses the "running out" line, and keep countdowns ticking
  C_Timer.NewTicker(1, function()
    if FB.nextCheck and GetTime() >= FB.nextCheck and not InCombatLockdown() then
      FB.nextCheck = nil
      FB:Request()
    end
    if FB.UI then FB:Try("tick", FB.UI.Tick, FB.UI) end
  end)
  FB:Request()
end

function H.PLAYER_ENTERING_WORLD() FB:Request() end
function H.SPELLS_CHANGED()
  if not FB.ready then return end
  FB:Prepare()
  FB:ScanSpellbook()
  FB:Request()
end
function H.PLAYER_REGEN_ENABLED()
  FB:Refresh() -- also applies anything held back during combat
  if FB.UI and FB.UI.AfterCombat then FB.UI:AfterCombat() end
end
function H.UNIT_AURA(unit) if safe(unit) == "player" then FB:Request() end end
function H.UNIT_INVENTORY_CHANGED(unit) if safe(unit) == "player" then FB:Request() end end
function H.UNIT_POWER_UPDATE(unit) if safe(unit) == "player" and not InCombatLockdown() then FB:Request() end end
function H.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID) if safe(unit) == "player" then onCast(spellID) end end
function H.UNIT_ENTERED_VEHICLE(unit) if safe(unit) == "player" then FB:Request() end end
function H.UNIT_EXITED_VEHICLE(unit) if safe(unit) == "player" then FB:Request() end end
H.PLAYER_EQUIPMENT_CHANGED = function() FB:Request() end
H.BAG_UPDATE_DELAYED = H.PLAYER_EQUIPMENT_CHANGED
H.PLAYER_LEVEL_UP = H.PLAYER_EQUIPMENT_CHANGED
H.PLAYER_DEAD = H.PLAYER_EQUIPMENT_CHANGED
H.PLAYER_ALIVE = H.PLAYER_EQUIPMENT_CHANGED
H.PLAYER_UNGHOST = H.PLAYER_EQUIPMENT_CHANGED
H.PLAYER_UPDATE_RESTING = H.PLAYER_EQUIPMENT_CHANGED
H.PLAYER_CONTROL_LOST = H.PLAYER_EQUIPMENT_CHANGED
H.PLAYER_CONTROL_GAINED = H.PLAYER_EQUIPMENT_CHANGED

local UNIT_EVENTS = {
  UNIT_AURA = true, UNIT_INVENTORY_CHANGED = true, UNIT_SPELLCAST_SUCCEEDED = true,
  UNIT_ENTERED_VEHICLE = true, UNIT_EXITED_VEHICLE = true,
}

ev:SetScript("OnEvent", function(_, event, ...)
  if event ~= "PLAYER_LOGIN" and not FB.ready then return end
  local fn = H[event]
  if not fn then return end
  local ok, err = pcall(fn, ...)
  if not ok and FB.debug then print("|cffff5555Forever Buffs error|r", event, err) end
end)

for event in pairs(H) do
  if event ~= "UNIT_POWER_UPDATE" then
    local ok = false
    if UNIT_EVENTS[event] and ev.RegisterUnitEvent then
      ok = pcall(ev.RegisterUnitEvent, ev, event, "player")
    end
    if not ok then pcall(ev.RegisterEvent, ev, event) end
  end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function printList()
  FB:Print(("class %s, %d spells in spellbook"):format(tostring(FB.class), FB.knownCount))
  if not FB.entries or #FB.entries == 0 then
    print("  Nothing to track for this class.")
    return
  end
  local missing = {}
  for _, r in ipairs(FB.list or {}) do missing[r.key] = r end
  for _, p in ipairs(FB.entries) do
    local names = {}
    for _, s in ipairs(p.spells) do
      names[#names + 1] = (knows(s) and "|cff7fd36b" or "|cff888888") .. s.name .. "|r"
    end
    local r = missing[p.key]
    local state = r and (r.expires and "|cffffd100running out|r" or "|cffff6b6bmissing|r") or "ok / not shown"
    print(("  %s: %s  (%s)"):format(p.label, state, #names > 0 and table.concat(names, ", ") or "weapon enchant"))
  end
end

local HELP = {
  "/fb  turn reminders on or off",
  "/fb move  drag the icons (or use Edit Mode); /fb move again to lock",
  "/fb reset  put the icons back in the default spot",
  "/fb scale N  size, 0.5 to 2",
  "/fb city  toggle: only remind outside cities (while not resting)",
  "/fb glow  toggle the pulsing glow",
  "/fb test  show sample icons",
  "/fb list  what is tracked for this character",
  "/fb options  open the options panel",
  "/fb debug  print errors in chat",
}

SLASH_FOREVERBUFFS1 = "/fb"
SLASH_FOREVERBUFFS2 = "/foreverbuffs"
SlashCmdList.FOREVERBUFFS = function(arg)
  arg = (arg or ""):lower()
  local cmd, val = arg:match("^(%S*)%s*(.-)$")
  local db = FB:DB()
  local UI = FB.UI
  if cmd == "" or cmd == "toggle" then
    db.enabled = not db.enabled
    FB:Print(db.enabled and "on" or "off")
    FB:Refresh()
  elseif cmd == "on" or cmd == "off" then
    db.enabled = (cmd == "on")
    FB:Print(cmd)
    FB:Refresh()
  elseif cmd == "move" then
    if UI then UI:ToggleMove() end
  elseif cmd == "reset" then
    db.point = { unpack(FB.DEFAULTS.point) }
    db.scale = FB.DEFAULTS.scale
    if UI then UI:ApplyPosition() end
    FB:Print("position and scale reset.")
  elseif cmd == "scale" and tonumber(val) then
    db.scale = math.max(0.5, math.min(2, tonumber(val)))
    if UI then UI:ApplyPosition() end
    FB:Print("scale", db.scale)
  elseif cmd == "city" or cmd == "resting" then
    db.restHide = not db.restHide
    FB:Print("only remind outside cities:", db.restHide and "on" or "off")
    FB:Refresh()
  elseif cmd == "glow" then
    db.glow = not db.glow
    FB:Print("glow:", db.glow and "on" or "off")
    FB:Refresh()
  elseif cmd == "test" then
    if UI then UI:ToggleTest() end
  elseif cmd == "list" then
    printList()
  elseif cmd == "options" or cmd == "config" or cmd == "settings" then
    if UI then UI:OpenOptions() end
  elseif cmd == "debug" then
    FB.debug = not FB.debug
    FB:Print("debug:", FB.debug and "on" or "off")
  else
    FB:Print("commands:")
    for _, line in ipairs(HELP) do print("  " .. line) end
  end
end
