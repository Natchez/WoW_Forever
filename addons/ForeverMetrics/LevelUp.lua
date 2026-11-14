-- Forever Metrics: level-up celebration
-- A little pop-up when you ding: the new level, how long the last level took,
-- stat gains, a new talent point, and the class skills you can now train.
--
-- New skills come from your class trainer. The first time you open your
-- trainer, Forever Metrics remembers its whole skill list (including the
-- ones you're too low for), so later level-ups can say what just unlocked.
-- Reading it from the trainer means it matches Forever exactly, with no
-- hard-coded spell tables.
--
-- If you level up in combat, the pop-up waits until the fight ends.

local ADDON, ns = ...
local FM = ns.FM

local STAT_NAMES = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
local AUTO_CLOSE = 30   -- seconds

local modal, pending
local showSkillTooltip -- defined below
local baseStats = {}

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function say(msg) print("|cffe8c27aForever Metrics|r " .. msg) end

local function money(c)
  c = c or 0
  if GetCoinTextureString then return GetCoinTextureString(c) end
  return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
end

local function dur(sec)
  sec = math.max(0, math.floor(sec or 0))
  local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
  if h > 0 then return ("%dh %dm"):format(h, m) end
  return ("%dm"):format(m)
end

local function classKey()
  local _, class = UnitClass("player")
  return class or "UNKNOWN"
end

-- Base (naked, unbuffed) stats. Gear and buffs aren't included in the first
-- value UnitStat returns, so the difference across a ding is the level gain.
local function snapshotStats()
  for i = 1, 5 do
    -- hidden in combat sometimes; then this level's stat gains are skipped
    baseStats[i] = tonumber(safe(UnitStat("player", i)))
  end
end

---------------------------------------------------------------------------
-- Trainer cache
---------------------------------------------------------------------------

-- Words the trainer uses for a skill's status (not ranks)
local SERVICE_TYPES = { available = true, unavailable = true, used = true, header = true }

local function trainerDB()
  local db = FM:DB()
  db.trainer = db.trainer or {}
  db.trainer[classKey()] = db.trainer[classKey()] or { spells = {} }
  local T = db.trainer[classKey()]
  -- v0.14.1: skills used to be saved under "name|rank", but Forever's
  -- trainer gives the status where Classic gives the rank, so every rank of
  -- a spell overwrote the last. Re-key what was saved by spell ID.
  if not T.byId then
    local fixed = {}
    for key, sp in pairs(T.spells) do
      if SERVICE_TYPES[sp.r] then sp.r = nil end
      fixed[sp.id and ("id" .. sp.id) or key] = sp
    end
    T.spells, T.byId = fixed, true
  end
  return T
end

local FILTERS = { "available", "unavailable", "used" }

-- "Requires Level %d" -> a pattern that finds the number anywhere in a line
local REQ_PAT = (type(ITEM_MIN_LEVEL) == "string" and
  ITEM_MIN_LEVEL:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%d", "(%%d+)")) or "Requires Level (%d+)"

local function levelFromLines(lines)
  for _, t in ipairs(lines) do
    local n = t:match(REQ_PAT)
    if n then return tonumber(n) end
  end
end

-- The trainer's tooltip for a service names the spell (so we can show its
-- real tooltip later, when the trainer is closed) and says "Requires Level N"
-- (a fallback if the level API comes back empty).
local scanTip
local function serviceDetails(i)
  -- Modern clients: tooltip data without drawing a tooltip
  if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
    local ok, data = pcall(C_TooltipInfo.GetTrainerService, i)
    if ok and type(data) == "table" then
      local lines = {}
      for _, l in ipairs(data.lines or {}) do
        local t = safe(l.leftText)
        if type(t) == "string" then lines[#lines + 1] = t end
      end
      local id = safe(data.id)
      return type(id) == "number" and id or nil, levelFromLines(lines)
    end
  end
  -- Older clients: fill a hidden tooltip and read it back
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "ForeverMetricsScanTip", UIParent, "GameTooltipTemplate")
  end
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  if not scanTip.SetTrainerService or not pcall(scanTip.SetTrainerService, scanTip, i) then return end
  local id
  if scanTip.GetSpell then
    local _, sid = scanTip:GetSpell()
    id = safe(sid)
  end
  local lines = {}
  for l = 2, scanTip:NumLines() do
    local fs = _G["ForeverMetricsScanTipTextLeft" .. l]
    local t = fs and safe(fs:GetText())
    if type(t) == "string" then lines[#lines + 1] = t end
  end
  scanTip:Hide()
  return type(id) == "number" and id or nil, levelFromLines(lines)
end

-- "Rank 3" and the like, from the spell itself
local function spellRank(id)
  if not id then return nil end
  local f = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
  if not f then return nil end
  local ok, sub = pcall(f, id)
  sub = ok and safe(sub) or nil
  if type(sub) == "string" and sub ~= "" then return sub end
end

local function spellIcon(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  if GetSpellTexture then return GetSpellTexture(id) end
end

local scanning = false
local scanProblemShown = false

-- Profession trainers: every recipe they teach, with the skill rank it
-- needs, saved account-wide by profession for the stats page (missing and
-- upcoming recipes).
local function scanProfTrainer()
  local saved = {}
  if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
    for _, f in ipairs(FILTERS) do
      saved[f] = GetTrainerServiceTypeFilter(f)
      pcall(SetTrainerServiceTypeFilter, f, 1)
    end
  end
  if ExpandTrainerSkillLine then pcall(ExpandTrainerSkillLine, 0) end

  local db = FM:DB()
  db.profTrainer = db.profTrainer or {}
  local found = 0
  for i = 1, GetNumTrainerServices() or 0 do
    local name, rank, category = GetTrainerServiceInfo(i)
    name, rank, category = safe(name), safe(rank), safe(category)
    if SERVICE_TYPES[rank] and not SERVICE_TYPES[category] then category, rank = rank, nil end
    if name and category ~= "header" then
      local prof, skill = nil, nil
      if GetTrainerServiceSkillReq then
        local ok, sn, sr = pcall(GetTrainerServiceSkillReq, i)
        if ok then prof, skill = safe(sn), tonumber(safe(sr)) end
      end
      if prof then
        local id = serviceDetails(i)
        local lv = GetTrainerServiceLevelReq and tonumber(safe(GetTrainerServiceLevelReq(i)))
        local T = db.profTrainer[prof] or { recipes = {} }
        db.profTrainer[prof] = T
        T.recipes[id and ("s" .. id) or name] = {
          n = name, r = (rank and rank ~= "") and rank or nil, spell = id, skill = skill or 0, lv = lv,
          icon = (GetTrainerServiceIcon and safe(GetTrainerServiceIcon(i))) or spellIcon(id),
          cost = (GetTrainerServiceCost and safe(GetTrainerServiceCost(i))) or 0,
        }
        T.scanned = time()
        found = found + 1
      end
    end
  end

  if SetTrainerServiceTypeFilter then
    for _, f in ipairs(FILTERS) do
      if saved[f] ~= nil then pcall(SetTrainerServiceTypeFilter, f, (saved[f] and saved[f] ~= 0) and 1 or 0) end
    end
  end
  if FM.debug then say(("profession trainer scan: %d recipes saved."):format(found)) end
end

local function scanTrainer()
  if scanning then return end
  if IsTradeskillTrainer and IsTradeskillTrainer() then
    scanning = true
    scanProfTrainer() -- safeScan resets the flag, even on an error
    scanning = false
    return
  end
  if not GetNumTrainerServices then
    if FM.debug then say("trainer scan: this client has no trainer API.") end
    return
  end
  scanning = true

  -- Show every service while we read, then put the player's filters back
  local saved = {}
  if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
    for _, f in ipairs(FILTERS) do
      saved[f] = GetTrainerServiceTypeFilter(f)
      pcall(SetTrainerServiceTypeFilter, f, 1)
    end
  end
  -- Collapsed sections hide their skills from the list, so open them all
  if ExpandTrainerSkillLine then pcall(ExpandTrainerSkillLine, 0) end

  local T = trainerDB()
  local total, found, noLevel = GetNumTrainerServices() or 0, 0, 0
  for i = 1, total do
    local name, rank, category = GetTrainerServiceInfo(i)
    name, rank, category = safe(name), safe(rank), safe(category)
    -- Forever returns (name, status) where Classic returns (name, rank, status)
    if SERVICE_TYPES[rank] and not SERVICE_TYPES[category] then category, rank = rank, nil end
    if name and category ~= "header" then
      local id, tipLevel = serviceDetails(i)
      local req = GetTrainerServiceLevelReq and safe(GetTrainerServiceLevelReq(i))
      if not req or req <= 0 then req = tipLevel end
      if req and req > 0 then
        if (not rank or rank == "") and id then rank = spellRank(id) end
        -- one entry per rank: the spell ID is unique per rank
        local key = id and ("id" .. id) or (name .. "|" .. (rank or "") .. "|" .. req)
        T.spells[key] = {
          n = name, r = (rank and rank ~= "") and rank or nil, lv = req, id = id,
          icon = (GetTrainerServiceIcon and safe(GetTrainerServiceIcon(i))) or spellIcon(id),
          cost = (GetTrainerServiceCost and safe(GetTrainerServiceCost(i))) or 0,
        }
        found = found + 1
      else
        noLevel = noLevel + 1
      end
    end
  end

  if SetTrainerServiceTypeFilter then
    for _, f in ipairs(FILTERS) do
      if saved[f] ~= nil then pcall(SetTrainerServiceTypeFilter, f, (saved[f] and saved[f] ~= 0) and 1 or 0) end
    end
  end
  scanning = false

  if FM.debug then
    say(("trainer scan: %d entries, %d skills saved, %d with no level found."):format(total, found, noLevel))
  end
  if found == 0 and total > 0 and not scanProblemShown then
    scanProblemShown = true
    say(("couldn't read the skill levels from this trainer (%d entries). Type |cffffff00/fm levelup check|r and send Claude what it prints."):format(total))
  end
  if found > 0 then
    local first = not T.scanned
    T.scanned = time()
    if first then say("remembered your trainer's skill list. Level-ups will now show what you can train.") end
  end
end

-- The list can still be filling in when the trainer opens, and changing the
-- filters refreshes it, so scan again shortly after any update.
local function safeScan()
  local ok, err = pcall(scanTrainer)
  scanning = false -- an error mid-scan must not block every later scan
  if not ok then
    FM.lastTrainerError = tostring(err)
    if FM.debug or not scanProblemShown then
      scanProblemShown = true
      print("|cffff5555ForeverMetrics|r couldn't read your trainer:", err, " (/fm levelup check for details)")
    end
  end
end

local rescanQueued = false
local function queueScan()
  if rescanQueued then return end
  rescanQueued = true
  C_Timer.After(0.5, function()
    rescanQueued = false
    if not scanning then safeScan() end
  end)
end

---------------------------------------------------------------------------
-- Spellbook: spells you know, plus "future" spells where the client lists
-- them, each with the level it's learned at. Saved per class so the list
-- builds up over time. Catches skills the trainer scan misses, and games
-- that teach skills automatically.
---------------------------------------------------------------------------

local function learnLevel(id)
  local f = (C_Spell and C_Spell.GetSpellLevelLearned) or GetSpellLevelLearned
  if not f then return nil end
  local ok, lv = pcall(f, id)
  lv = ok and tonumber(safe(lv)) or nil
  if lv and lv > 0 then return lv end
end

local function isKnown(id)
  if not id then return false end
  if IsPlayerSpell then
    local ok, v = pcall(IsPlayerSpell, id)
    if ok and safe(v) then return true end
  end
  if IsSpellKnown then
    local ok, v = pcall(IsSpellKnown, id)
    if ok and safe(v) then return true end
  end
  return false
end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(info) == "table" then return safe(info.name), safe(info.iconID) end
  end
  if GetSpellInfo then
    local name, _, icon = GetSpellInfo(id)
    return safe(name), safe(icon)
  end
end

local function bookDB()
  local T = trainerDB()
  T.book = T.book or {}
  return T.book
end

-- Calls fn(spellID, name, rank, icon, isFuture) for every spellbook spell
local function eachBookSpell(fn)
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo
     and Enum and Enum.SpellBookSpellBank then
    local FUTURE = Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
    local SPELL = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
      local L = C_SpellBook.GetSpellBookSkillLineInfo(line)
      if L and not L.shouldHide and L.itemIndexOffset and L.numSpellBookItems then
        for i = L.itemIndexOffset + 1, L.itemIndexOffset + L.numSpellBookItems do
          local it = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
          if it and (it.itemType == SPELL or it.itemType == FUTURE) then
            local id = safe(it.spellID) or safe(it.actionID)
            if id then fn(id, safe(it.name), safe(it.subName), safe(it.iconID), it.itemType == FUTURE) end
          end
        end
      end
    end
    return "modern"
  end
  if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
    local BOOK = BOOKTYPE_SPELL or "spell"
    for tab = 1, GetNumSpellTabs() do
      local _, _, offset, num = GetSpellTabInfo(tab)
      for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
        local kind, id = GetSpellBookItemInfo(i, BOOK)
        id = safe(id)
        if id and (kind == "SPELL" or kind == "FUTURESPELL") then
          local name, rank = GetSpellBookItemName(i, BOOK)
          local icon = GetSpellBookItemTexture and GetSpellBookItemTexture(i, BOOK)
          fn(id, safe(name), safe(rank), safe(icon), kind == "FUTURESPELL")
        end
      end
    end
    return "classic"
  end
  return "none"
end

local bookStats = { api = "?", seen = 0, withLevel = 0, future = 0 }

local function scanBook()
  local B = bookDB()
  local seen, withLevel, future = 0, 0, 0
  bookStats.api = eachBookSpell(function(id, name, rank, icon, isFuture)
    seen = seen + 1
    if isFuture then future = future + 1 end
    local lv = learnLevel(id)
    if lv and name then
      withLevel = withLevel + 1
      B[id] = { n = name, r = (rank and rank ~= "") and rank or nil, lv = lv, id = id, icon = icon }
    end
  end)
  bookStats.seen, bookStats.withLevel, bookStats.future = seen, withLevel, future
end

local bookQueued = false
local function queueBookScan()
  if bookQueued then return end
  bookQueued = true
  C_Timer.After(1, function()
    bookQueued = false
    local ok, err = pcall(scanBook)
    if not ok and FM.debug then print("|cffff5555ForeverMetrics spellbook scan error|r", err) end
  end)
end

-- Spells learned in the last little while (auto-learned at a ding, or trained)
local recentLearned = {}

-- Everything known about skills for one level, from all sources, without
-- duplicates. Each entry: n, r, id, icon, lv, cost (trainer only), known.
local function skillsAt(level, extra)
  local list, cost, byKey = {}, 0, {}
  local function keyOf(sk) return sk.id and ("id" .. sk.id) or (sk.n .. "|" .. (sk.r or "")) end
  local function add(sk, fromTrainer)
    local k, k2 = keyOf(sk), sk.n .. "|" .. (sk.r or "")
    local cur = byKey[k] or byKey[k2]
    if cur then
      -- fill in whatever the other source knew
      cur.id = cur.id or sk.id
      cur.icon = cur.icon or sk.icon
      if fromTrainer then cur.cost = sk.cost end
      return
    end
    local e = { n = sk.n, r = sk.r, id = sk.id, icon = sk.icon, lv = sk.lv,
                cost = fromTrainer and sk.cost or nil, fromTrainer = fromTrainer }
    list[#list + 1] = e
    byKey[k], byKey[k2] = e, e
  end
  for _, sk in pairs(trainerDB().spells) do if sk.lv == level then add(sk, true) end end
  for _, sk in pairs(bookDB()) do if sk.lv == level then add(sk, false) end end
  for _, sk in ipairs(extra or {}) do add(sk, false) end
  for _, e in ipairs(list) do
    e.known = isKnown(e.id)
    if not e.r then e.r = spellRank(e.id) end
    if not e.known and e.cost then cost = cost + e.cost end
  end
  table.sort(list, function(a, b) return a.n < b.n end)
  return list, cost
end

-- Whether any source has data yet (otherwise the pop-up shows a hint)
local function haveSkillData()
  return trainerDB().scanned or next(bookDB()) ~= nil
end

-- Tooltip for a skill row. With a spell ID it's the game's own spell
-- tooltip; skills saved before v0.11.0 have no ID until the trainer is
-- visited again, so they get a short summary instead.
showSkillTooltip = function(owner, s)
  if not s then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local shown = false
  if s.id and GameTooltip.SetSpellByID then
    shown = pcall(GameTooltip.SetSpellByID, GameTooltip, s.id)
  end
  if not shown then
    GameTooltip:ClearLines()
    GameTooltip:AddLine(s.n, 1, 1, 1)
    if s.r then GameTooltip:AddLine(s.r, 0.66, 0.59, 0.48) end
    GameTooltip:AddLine(("Learn at level %d"):format(s.lv or 0), 0.91, 0.76, 0.48)
    GameTooltip:AddLine("Visit your trainer again to see the full description here.", 0.6, 0.6, 0.6, true)
  end
  if (s.cost or 0) > 0 then GameTooltip:AddLine("Training cost: " .. money(s.cost), 1, 1, 1) end
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- The modal
---------------------------------------------------------------------------

-- Layout: two columns. Left: the level, how long it took, stat gains and
-- talent points. Right: a scrolling list of skills (new this level, then
-- the next level that brings new ones), with the training cost below.
local W, H = 600, 300
local LEFT_W = 230                 -- left column width
local RIGHT_X = LEFT_W + 22        -- where the right column starts
local ROW_H = 22

local function getRow(i)
  local child = modal.listChild
  local r = modal.rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, child)
  r:SetHeight(ROW_H)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 2, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.name:SetPoint("RIGHT", r, "RIGHT", -70, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.cost = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.cost:SetPoint("RIGHT", -4, 0)
  r.hdr = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  r.hdr:SetPoint("LEFT", 2, 0)
  r.hdr:SetTextColor(0.91, 0.76, 0.48)
  -- Hover a skill to see its full tooltip
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(FM.THEME.hl[1], FM.THEME.hl[2], FM.THEME.hl[3], FM.THEME.hl[4])
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self) if self.skill then showSkillTooltip(self, self.skill) end end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  modal.rows[i] = r
  return r
end

local function build()
  modal = CreateFrame("Frame", "ForeverMetricsLevelUp", UIParent, "BackdropTemplate")
  FM:Skin(modal, { edge = 16, alpha = 0.96 })
  modal:SetSize(W, H)
  modal:SetPoint("TOP", UIParent, "TOP", 0, -140)
  modal:SetFrameStrata("DIALOG")
  modal:SetClampedToScreen(true)
  modal:EnableMouse(true)
  modal:SetMovable(true)
  modal:RegisterForDrag("LeftButton")
  modal:SetScript("OnDragStart", modal.StartMoving)
  modal:SetScript("OnDragStop", modal.StopMovingOrSizing)
  tinsert(UISpecialFrames, "ForeverMetricsLevelUp") -- Esc closes it

  local cx = 12 + LEFT_W / 2 -- centre of the left column

  -- Spinning star burst behind the title
  modal.burst = modal:CreateTexture(nil, "BACKGROUND", nil, 1)
  modal.burst:SetTexture("Interface\\Cooldown\\star4")
  modal.burst:SetBlendMode("ADD")
  modal.burst:SetVertexColor(1, 0.8, 0.35)
  modal.burst:SetSize(200, 200)
  modal.burst:SetPoint("CENTER", modal, "TOPLEFT", cx, -40)

  modal.title = modal:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  modal.title:SetPoint("TOP", modal, "TOPLEFT", cx, -24)
  modal.title:SetTextColor(1, 0.82, 0.35)

  modal.sub = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  modal.sub:SetPoint("TOP", modal.title, "BOTTOM", 0, -4)
  modal.sub:SetTextColor(0.66, 0.59, 0.48)

  local rule = modal:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(FM.THEME.border[1], FM.THEME.border[2], FM.THEME.border[3], 0.35)
  rule:SetPoint("TOPLEFT", 24, -74); rule:SetWidth(LEFT_W - 24); rule:SetHeight(1)

  modal.gains = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  modal.gains:SetPoint("TOP", modal, "TOPLEFT", cx, -86)
  modal.gains:SetWidth(LEFT_W - 20)
  modal.gains:SetSpacing(5)

  -- divider between the columns
  local div = modal:CreateTexture(nil, "ARTWORK")
  div:SetColorTexture(FM.THEME.border[1], FM.THEME.border[2], FM.THEME.border[3], 0.3)
  div:SetPoint("TOPLEFT", RIGHT_X - 10, -18); div:SetPoint("BOTTOMLEFT", RIGHT_X - 10, 50); div:SetWidth(1)

  -- skills list (scrolls when long)
  local sf = CreateFrame("ScrollFrame", nil, modal, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", RIGHT_X, -18)
  sf:SetPoint("BOTTOMRIGHT", -32, 70)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(W - RIGHT_X - 32, 10)
  sf:SetScrollChild(child)
  modal.list, modal.listChild, modal.rows = sf, child, {}

  modal.empty = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  modal.empty:SetPoint("TOPLEFT", 4, -4)
  modal.empty:SetWidth(W - RIGHT_X - 40)
  modal.empty:SetJustifyH("LEFT")
  modal.empty:SetSpacing(3)

  modal.foot = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  modal.foot:SetPoint("BOTTOMLEFT", RIGHT_X + 2, 52)
  modal.foot:SetPoint("RIGHT", modal, "RIGHT", -20, 0)
  modal.foot:SetJustifyH("LEFT")

  modal.ok = CreateFrame("Button", nil, modal, "UIPanelButtonTemplate")
  modal.ok:SetSize(110, 24)
  modal.ok:SetPoint("BOTTOM", 0, 14)
  modal.ok:SetText("Nice!")
  modal.ok:SetScript("OnClick", function() modal:Hide() end)

  -- Controller: A or B closes it, D-pad up/down scrolls the skills, every
  -- other button passes through
  if modal.EnableGamePadButton then
    modal:EnableGamePadButton(true)
    modal:SetScript("OnGamePadButtonDown", function(self, button)
      local mine = (button == "PAD1" or button == "PAD2" or button == "PADDUP" or button == "PADDDOWN")
      if not InCombatLockdown() and self.SetPropagateGamePadInput then
        pcall(self.SetPropagateGamePadInput, self, not mine)
      end
      if button == "PADDUP" or button == "PADDDOWN" then
        local sfr = self.list
        local v = sfr:GetVerticalScroll() + (button == "PADDUP" and -ROW_H * 2 or ROW_H * 2)
        sfr:SetVerticalScroll(math.max(0, math.min(sfr:GetVerticalScrollRange(), v)))
      elseif mine then
        self:Hide()
      end
    end)
  end

  modal:SetScript("OnHide", function(self)
    self:SetScript("OnUpdate", nil)
    if not InCombatLockdown() and self.SetPropagateGamePadInput then
      pcall(self.SetPropagateGamePadInput, self, true)
    end
  end)
  modal:Hide()
end

-- Pop in (grow + fade), spin the burst, then fade out after a while
local function animate(self, elapsed)
  self.age = self.age + elapsed
  local t = self.age
  local g = math.min(t / 0.3, 1)
  local ease = 1 - (1 - g) * (1 - g)
  local scale = 0.75 + 0.25 * ease + (g < 1 and 0.08 * math.sin(g * math.pi) or 0)
  self:SetScale(scale)
  local a = math.max(0.05, ease)
  -- Stay open while the mouse is over it (e.g. reading a skill tooltip)
  if t > AUTO_CLOSE and self:IsMouseOver() then
    self.age = AUTO_CLOSE
    t = AUTO_CLOSE
  end
  if t > AUTO_CLOSE then
    a = 1 - (t - AUTO_CLOSE) / 1.5
    if a <= 0 then self:Hide(); return end
  end
  self:SetAlpha(a)
  self.burst:SetRotation(t * 0.6)
  self.burst:SetAlpha(math.max(0.15, 0.85 - t * 0.25))
end

-- Fill the skills list: section headers and skill rows
local function fillSkills(data)
  for _, r in ipairs(modal.rows) do r:Hide() end
  modal.empty:Hide(); modal.foot:SetText("")
  modal.list:SetVerticalScroll(0)

  if not FM:GetSetting("levelSkills") then
    modal.empty:SetText("|cffa8977aSkill lists are turned off (Options > Interface > Level Up).|r")
    modal.empty:Show()
    modal.listChild:SetHeight(40)
    return
  end
  if #data.skills == 0 and not haveSkillData() then
    modal.empty:SetText("|cffe8c27aNew skills|r\n\n|cffa8977aVisit your class trainer once, and level-ups will list the skills you unlock, plus what's coming next.|r")
    modal.empty:Show()
    modal.listChild:SetHeight(80)
    return
  end

  -- what's next: the first later level that brings anything
  local nextList, nextCost, nextLevel = {}, 0, nil
  for L = data.level + 1, data.level + 10 do
    local l2, c2 = skillsAt(L)
    if #l2 > 0 then nextList, nextCost, nextLevel = l2, c2, L; break end
  end

  local i, y = 0, 0
  local function header(text)
    i = i + 1
    local r = getRow(i)
    r.skill = nil
    r.icon:Hide(); r.name:Hide(); r.cost:Hide(); r.hl:Hide()
    r.hdr:SetText(text); r.hdr:Show()
    r:SetAlpha(1)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", modal.listChild, "TOPLEFT", 0, -y)
    r:SetPoint("TOPRIGHT", modal.listChild, "TOPRIGHT", 0, -y)
    r:Show()
    y = y + ROW_H + 2
  end
  local function row(sk, dim)
    i = i + 1
    local r = getRow(i)
    r.skill = sk
    r.hdr:Hide(); r.icon:Show(); r.name:Show(); r.cost:Show(); r.hl:Show()
    r.icon:SetTexture(sk.icon or spellIcon(sk.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.name:SetText(sk.r and ("%s |cffa8977a%s|r"):format(sk.n, sk.r) or sk.n)
    if sk.known then
      r.cost:SetText("|cff7fd36blearned|r")
    elseif sk.cost then
      r.cost:SetText(sk.cost > 0 and money(sk.cost) or "|cff7fd36bfree|r")
    else
      r.cost:SetText("|cffa8977aat trainer|r")
    end
    r:SetAlpha(dim and 0.8 or 1)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", modal.listChild, "TOPLEFT", 0, -y)
    r:SetPoint("TOPRIGHT", modal.listChild, "TOPRIGHT", 0, -y)
    r:Show()
    y = y + ROW_H
  end

  if #data.skills > 0 then
    header(("New this level (%d)"):format(#data.skills))
    for _, sk in ipairs(data.skills) do row(sk, false) end
    y = y + 8
  end
  if nextLevel then
    header(("Next up: level %d (%d)"):format(nextLevel, #nextList))
    for _, sk in ipairs(nextList) do row(sk, true) end
  end
  if i == 0 then
    modal.empty:SetText("|cffe8c27aNew skills|r\n\n|cffa8977aNothing new this level, and your upcoming skills aren't known yet. Open your class trainer, then type /fm levelup check.|r")
    modal.empty:Show()
    y = 80
  end
  modal.listChild:SetHeight(math.max(y, 10))

  -- cost line under the list
  local have = GetMoney()
  if (data.cost or 0) > 0 then
    local t = ("Train now: %s  ·  you have %s"):format(money(data.cost), money(have))
    if have < data.cost then t = t .. "  |cffff6b6b(short)|r" end
    modal.foot:SetText(t)
  elseif nextLevel and nextCost > 0 then
    modal.foot:SetText(("Level %d training: %s  ·  you have %s"):format(nextLevel, money(nextCost), money(have)))
  end
end

local function show(data, keepAnim)
  if not modal then build() end
  modal.data = data
  modal.title:SetText(("Level %d!"):format(data.level))
  modal.sub:SetText(data.took and ("Level %d took %s"):format(data.level - 1, dur(data.took)) or "Ding!")

  -- Stat gains, one kind per line
  local lines = {}
  if (data.hp or 0) > 0 then lines[#lines + 1] = ("|cff7fd36b+%d|r Health"):format(data.hp) end
  if (data.mp or 0) > 0 then lines[#lines + 1] = ("|cff69ccf0+%d|r %s"):format(data.mp, data.powerName or "Mana") end
  local stats = {}
  for i, name in ipairs(STAT_NAMES) do
    local d = data.stats and data.stats[i]
    -- a ding gives 0-3 per stat; anything bigger is a gear swap, so skip it
    if d and d > 0 and d <= 5 then stats[#stats + 1] = ("|cffe8c27a+%d|r %s"):format(d, name) end
  end
  for _, st in ipairs(stats) do lines[#lines + 1] = st end
  if (data.talents or 0) > 0 then
    lines[#lines + 1] = ("\n|cffffd100+%d talent %s to spend|r"):format(data.talents, data.talents == 1 and "point" or "points")
  end
  modal.gains:SetText(#lines > 0 and table.concat(lines, "\n") or "Onward!")

  fillSkills(data)

  if keepAnim and modal:IsShown() then return end -- just refreshed the content
  modal.age = 0
  modal:SetScale(0.75); modal:SetAlpha(0)
  modal:Show()
  modal:SetScript("OnUpdate", animate)
end

-- Remember the last ding per character so it can be replayed later
local function remember(data)
  local c = FM:Char()
  if not c then return end
  local copy = {}
  for k, v in pairs(data) do copy[k] = v end
  copy.skills = {}
  for i, s in ipairs(data.skills or {}) do
    copy.skills[i] = { n = s.n, r = s.r, lv = s.lv, icon = s.icon, cost = s.cost, id = s.id, known = s.known }
  end
  copy.t = time()
  c.lastLevelUp = copy
end

function FM:ReplayLevelUp()
  local c = self:Char()
  local data = c and c.lastLevelUp
  if not data then
    -- Nothing saved yet (saving started in v0.7.1): rebuild what we can for
    -- your current level. Stat gains aren't known, so those are left out.
    local level = UnitLevel("player")
    local skills, cost = skillsAt(level)
    data = {
      level = level, skills = skills, cost = cost,
      took = c and c.levelTimes and c.levelTimes[level],
    }
    say("no level-up saved on this character yet, so this is rebuilt for your current level. Your next ding is saved in full.")
  end
  show(data)
end

---------------------------------------------------------------------------
-- Blizzard's own level-up banner ("You've Reached Level N"). Ours either
-- waits for it to finish, or (option) it's closed so ours shows right away.
---------------------------------------------------------------------------

local BLIZZ_BANNERS = { "LevelUpDisplay", "EventToastManagerFrame" }
local dingAt = 0

local function blizzBannerShowing()
  for _, name in ipairs(BLIZZ_BANNERS) do
    local f = _G[name]
    if f and f.IsShown and f:IsShown() then return true end
  end
  return false
end

local function closeBlizzBanner(f)
  if f.CloseActiveToasts then pcall(f.CloseActiveToasts, f) end -- modern toast manager
  pcall(f.Hide, f)
end

-- Only touch Blizzard's banner right after a ding, so its other toasts still work
local bannerHooked = false
local function hookBlizzBanner()
  if bannerHooked then return end
  bannerHooked = true
  for _, name in ipairs(BLIZZ_BANNERS) do
    local f = _G[name]
    if f and f.HookScript then
      f:HookScript("OnShow", function(self)
        if FM:GetSetting("hideBlizzLevelUp") and GetTime() - dingAt < 8 then closeBlizzBanner(self) end
      end)
    end
  end
end

-- Show ours once Blizzard's banner is gone (gives up waiting after 8 seconds)
local function showAfterBanner(data)
  local waited = 0
  local function try()
    if FM:GetSetting("hideBlizzLevelUp") then
      for _, name in ipairs(BLIZZ_BANNERS) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then closeBlizzBanner(f) end
      end
    end
    if blizzBannerShowing() and waited < 8 then
      waited = waited + 0.5
      C_Timer.After(0.5, try)
      return
    end
    show(data)
  end
  try()
end

local function celebrate(data)
  remember(data)
  if not FM:GetSetting("levelModal") then return end
  if InCombatLockdown() or UnitAffectingCombat("player") then
    pending = data -- wait until the fight is over
    return
  end
  showAfterBanner(data)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local H = {}

local lastDing -- { level, t }

function H.PLAYER_LOGIN()
  snapshotStats()
  queueBookScan()
  pcall(hookBlizzBanner)
end

function H.SPELLS_CHANGED() queueBookScan() end

-- A spell was learned. Shortly after a ding, add it to the pop-up.
local function onLearned(id)
  id = tonumber(safe(id))
  if not id then return end
  local name, icon = spellName(id)
  if not name then return end
  local lv = learnLevel(id)
  local sk = { n = name, id = id, icon = icon, lv = lv or UnitLevel("player") }
  recentLearned[#recentLearned + 1] = { sk = sk, t = GetTime() }
  while #recentLearned > 20 do table.remove(recentLearned, 1) end
  if lv then bookDB()[id] = { n = name, lv = lv, id = id, icon = icon } end

  if lastDing and GetTime() - lastDing.t < 20 and modal and modal.data and modal.data.level == lastDing.level then
    local data = modal.data
    data.skills, data.cost = skillsAt(data.level, { sk })
    remember(data)
    if modal:IsShown() then show(data, true) end
  end
end

function H.LEARNED_SPELL_IN_SKILL_LINE(id) onLearned(id) end -- modern clients
function H.LEARNED_SPELL_IN_TAB(id) onLearned(id) end        -- classic clients

-- Core calls this once for every level gained (see FM:CheckLevel), with
-- live = false for levels caught up at login, which get no pop-up.
function FM:OnLevelGained(level, live, info)
  if not live then return end
  info = info or {}
  lastDing = { level = level, t = GetTime() }
  dingAt = GetTime()
  pcall(hookBlizzBanner)
  local c = FM:Char()
  C_Timer.After(0.5, function()
    local ok, err = pcall(function()
      local stats = {}
      for i = 1, 5 do
        local now = tonumber(safe(UnitStat("player", i)))
        stats[i] = (now and baseStats[i]) and (now - baseStats[i]) or 0
      end
      snapshotStats()
      pcall(scanBook)
      -- include anything learned in the moments around the ding
      local extra = {}
      for _, r in ipairs(recentLearned) do
        if GetTime() - r.t < 5 then extra[#extra + 1] = r.sk end
      end
      local skills, cost = skillsAt(level, extra)
      local _, powerToken = UnitPowerType("player")
      local powerName = powerToken and safe(_G[powerToken]) or nil
      if type(powerName) ~= "string" then powerName = nil end
      celebrate({
        level = level, hp = info.hp, mp = info.mp, talents = info.talents,
        stats = stats, skills = skills, cost = cost, powerName = powerName,
        took = c and c.levelTimes and c.levelTimes[level],
      })
    end)
    if not ok then print("|cffff5555ForeverMetrics level-up error|r", err) end
  end)
end

function H.PLAYER_REGEN_ENABLED()
  if pending then
    local data = pending
    pending = nil
    C_Timer.After(1, function() showAfterBanner(data) end)
  end
end

function H.TRAINER_SHOW()
  FM.trainerSeen = (FM.trainerSeen or 0) + 1
  safeScan(); queueScan()
end
function H.TRAINER_UPDATE() queueScan() end

ev:SetScript("OnEvent", function(_, event, ...)
  local ok, err = pcall(H[event], ...)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics level-up error|r", event, err) end
end)
for event in pairs(H) do pcall(ev.RegisterEvent, ev, event) end

---------------------------------------------------------------------------
-- /fm levelup [test]
---------------------------------------------------------------------------

function FM:LevelUpCommand(rest)
  if rest == "last" or rest == "replay" then
    FM:ReplayLevelUp()
  elseif rest == "check" or rest == "trainer" then
    -- What each skill source can see. Send this to Claude if skills don't show.
    pcall(scanBook)
    local T = trainerDB()
    local n, withId = 0, 0
    for _, sp in pairs(T.spells) do
      n = n + 1
      if sp.id then withId = withId + 1 end
    end
    local bookN = 0
    for _ in pairs(bookDB()) do bookN = bookN + 1 end
    local yes = function(v) return v and "yes" or "no" end
    say("level-up skills check (v" .. ((C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "?") .. ")")
    print(("  Trainer: API %s, opened this session %d time(s), %d skills saved (%d with tooltip)%s"):format(
      yes(GetNumTrainerServices), FM.trainerSeen or 0, n, withId,
      T.scanned and (", last read " .. date("%m/%d %H:%M", T.scanned)) or ", never read"))
    print(("    level API %s, tooltip API %s, filters %s, expand %s"):format(
      yes(GetTrainerServiceLevelReq), yes(C_TooltipInfo and C_TooltipInfo.GetTrainerService),
      yes(SetTrainerServiceTypeFilter), yes(ExpandTrainerSkillLine)))
    if FM.lastTrainerError then print("    last error: " .. FM.lastTrainerError) end
    print(("  Spellbook: %s API, %d spells, %d future, %d with a learn level; %d saved"):format(
      bookStats.api, bookStats.seen, bookStats.future, bookStats.withLevel, bookN))
    print(("    learn-level API %s"):format(yes((C_Spell and C_Spell.GetSpellLevelLearned) or GetSpellLevelLearned)))
    local lvl = UnitLevel("player")
    for _, L in ipairs({ lvl, lvl + 1, lvl + 2 }) do
      local list = skillsAt(L)
      local names = {}
      for _, sp in ipairs(list) do
        names[#names + 1] = (sp.r and (sp.n .. " (" .. sp.r .. ")") or sp.n) .. (sp.known and "*" or "")
      end
      print(("  Level %d: %s"):format(L, #names > 0 and table.concat(names, ", ") or "nothing found"))
    end
    print("  (* = already learned)")
    -- With the trainer window open: what its first few entries look like
    local total = GetNumTrainerServices and tonumber(safe(GetNumTrainerServices())) or 0
    if total > 0 then
      print(("  Open trainer: %d entries. First few (name | rank | type | level | tooltip level | spell ID):"):format(total))
      local shown = 0
      for i = 1, total do
        if shown >= 5 then break end
        local ok, name, rank, category = pcall(GetTrainerServiceInfo, i)
        if ok and category ~= "header" then
          shown = shown + 1
          local req = GetTrainerServiceLevelReq and select(2, pcall(GetTrainerServiceLevelReq, i))
          local ok2, id, tipLevel = pcall(serviceDetails, i)
          print(("    %s | %s | %s | %s | %s | %s"):format(tostring(safe(name)), tostring(safe(rank)), tostring(category),
            tostring(safe(req)), ok2 and tostring(tipLevel) or ("error: " .. tostring(id)), ok2 and tostring(id) or "-"))
        end
      end
    else
      print("  Open your class trainer and run this again to see what it reports.")
    end
  elseif rest == "test" then
    local level = UnitLevel("player")
    local skills, cost = skillsAt(level)
    show({
      level = level, hp = 18, mp = 15, talents = level >= 10 and 1 or 0,
      stats = { 1, 0, 1, 1, 0 }, skills = skills, cost = cost,
      took = FM:Char() and FM:Char().levelTimes[level],
    })
  else
    FM:SetSetting("levelModal", not FM:GetSetting("levelModal"))
    say("level-up pop-up " .. (FM:GetSetting("levelModal") and "on" or "off") .. "  (/fm levelup last replays your last one, /fm levelup test previews, /fm levelup check shows what skill data it can see)")
  end
end
