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
local MAX_SKILLS = 8
local AUTO_CLOSE = 30   -- seconds

local modal, pending
local showSkillTooltip -- defined below
local baseStats = {}

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
    local base = UnitStat("player", i)
    baseStats[i] = base
  end
end

---------------------------------------------------------------------------
-- Trainer cache
---------------------------------------------------------------------------

local function trainerDB()
  local db = FM:DB()
  db.trainer = db.trainer or {}
  db.trainer[classKey()] = db.trainer[classKey()] or { spells = {} }
  return db.trainer[classKey()]
end

local FILTERS = { "available", "unavailable", "used" }

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

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

local function spellIcon(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  if GetSpellTexture then return GetSpellTexture(id) end
end

local scanning = false

local function scanTrainer()
  if scanning then return end
  if IsTradeskillTrainer and IsTradeskillTrainer() then return end -- professions aren't class skills
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
    name, rank = safe(name), safe(rank)
    if name and category ~= "header" then
      local id, tipLevel = serviceDetails(i)
      local req = GetTrainerServiceLevelReq and safe(GetTrainerServiceLevelReq(i))
      if not req or req <= 0 then req = tipLevel end
      if req and req > 0 then
        local key = name .. "|" .. (rank or "")
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
  if found > 0 then
    local first = not T.scanned
    T.scanned = time()
    if first then say("remembered your trainer's skill list. Level-ups will now show what you can train.") end
  end
end

-- The list can still be filling in when the trainer opens, and changing the
-- filters refreshes it, so scan again shortly after any update.
local rescanQueued = false
local function queueScan()
  if scanning or rescanQueued then return end
  rescanQueued = true
  C_Timer.After(0.5, function()
    rescanQueued = false
    local ok, err = pcall(scanTrainer)
    scanning = false
    if not ok and FM.debug then print("|cffff5555ForeverMetrics trainer scan error|r", err) end
  end)
end

local function skillsAt(level)
  local list, cost = {}, 0
  for _, s in pairs(trainerDB().spells) do
    if s.lv == level then
      list[#list + 1] = s
      cost = cost + (s.cost or 0)
    end
  end
  table.sort(list, function(a, b) return a.n < b.n end)
  return list, cost
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

local function build()
  modal = CreateFrame("Frame", "ForeverMetricsLevelUp", UIParent, "BackdropTemplate")
  FM:Skin(modal, { edge = 16, alpha = 0.96 })
  modal:SetSize(360, 200)
  modal:SetPoint("TOP", UIParent, "TOP", 0, -140)
  modal:SetFrameStrata("DIALOG")
  modal:SetClampedToScreen(true)
  modal:EnableMouse(true)
  modal:SetMovable(true)
  modal:RegisterForDrag("LeftButton")
  modal:SetScript("OnDragStart", modal.StartMoving)
  modal:SetScript("OnDragStop", modal.StopMovingOrSizing)
  tinsert(UISpecialFrames, "ForeverMetricsLevelUp") -- Esc closes it

  -- Spinning star burst behind the title
  modal.burst = modal:CreateTexture(nil, "BACKGROUND", nil, 1)
  modal.burst:SetTexture("Interface\\Cooldown\\star4")
  modal.burst:SetBlendMode("ADD")
  modal.burst:SetVertexColor(1, 0.8, 0.35)
  modal.burst:SetSize(220, 220)
  modal.burst:SetPoint("CENTER", modal, "TOP", 0, -34)

  modal.title = modal:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  modal.title:SetPoint("TOP", 0, -18)
  modal.title:SetTextColor(1, 0.82, 0.35)

  modal.sub = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  modal.sub:SetPoint("TOP", modal.title, "BOTTOM", 0, -4)
  modal.sub:SetTextColor(0.66, 0.59, 0.48)

  local rule = modal:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(FM.THEME.border[1], FM.THEME.border[2], FM.THEME.border[3], 0.35)
  rule:SetPoint("TOPLEFT", 18, -66); rule:SetPoint("TOPRIGHT", -18, -66); rule:SetHeight(1)

  modal.gains = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  modal.gains:SetPoint("TOP", 0, -76)
  modal.gains:SetWidth(320)
  modal.gains:SetSpacing(3)

  modal.skillsHdr = modal:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  modal.skillsHdr:SetPoint("TOPLEFT", 22, -110)
  modal.skillsHdr:SetTextColor(0.91, 0.76, 0.48)

  modal.rows = {}
  for i = 1, MAX_SKILLS do
    local r = CreateFrame("Frame", nil, modal)
    r:SetSize(316, 20)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT")
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetJustifyH("LEFT")
    r.cost = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.cost:SetPoint("RIGHT")
    -- Hover a skill to see its full tooltip
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(FM.THEME.hl[1], FM.THEME.hl[2], FM.THEME.hl[3], FM.THEME.hl[4])
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self) showSkillTooltip(self, self.skill) end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    modal.rows[i] = r
  end

  modal.foot = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  modal.foot:SetWidth(316)
  modal.foot:SetJustifyH("LEFT")

  modal.ok = CreateFrame("Button", nil, modal, "UIPanelButtonTemplate")
  modal.ok:SetSize(110, 24)
  modal.ok:SetPoint("BOTTOM", 0, 14)
  modal.ok:SetText("Nice!")
  modal.ok:SetScript("OnClick", function() modal:Hide() end)

  -- Controller: A or B closes it, every other button passes through
  if modal.EnableGamePadButton then
    modal:EnableGamePadButton(true)
    modal:SetScript("OnGamePadButtonDown", function(self, button)
      local mine = (button == "PAD1" or button == "PAD2")
      if not InCombatLockdown() and self.SetPropagateGamePadInput then
        pcall(self.SetPropagateGamePadInput, self, not mine)
      end
      if mine then self:Hide() end
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

local function show(data)
  if not modal then build() end
  modal.title:SetText(("Level %d!"):format(data.level))
  modal.sub:SetText(data.took and ("Level %d took %s"):format(data.level - 1, dur(data.took)) or "Ding!")

  -- Stat gains line(s)
  local parts = {}
  if (data.hp or 0) > 0 then parts[#parts + 1] = ("|cff7fd36b+%d|r Health"):format(data.hp) end
  if (data.mp or 0) > 0 then parts[#parts + 1] = ("|cff69ccf0+%d|r %s"):format(data.mp, data.powerName or "Mana") end
  for i, name in ipairs(STAT_NAMES) do
    local d = data.stats and data.stats[i]
    -- a ding gives 0-3 per stat; anything bigger is a gear swap, so skip it
    if d and d > 0 and d <= 5 then
      parts[#parts + 1] = ("|cffe8c27a+%d|r %s"):format(d, name)
    end
  end
  local gains = table.concat(parts, "  ·  ")
  if (data.talents or 0) > 0 then
    gains = gains .. ("\n|cffffd100+%d talent %s to spend|r"):format(data.talents, data.talents == 1 and "point" or "points")
  end
  modal.gains:SetText(gains ~= "" and gains or "Onward!")

  -- Skills
  local y = -76 - modal.gains:GetStringHeight() - 14
  for _, r in ipairs(modal.rows) do r:Hide() end
  modal.skillsHdr:Hide(); modal.foot:Hide()

  if FM:GetSetting("levelSkills") then
    modal.skillsHdr:ClearAllPoints()
    modal.skillsHdr:SetPoint("TOPLEFT", 22, y)
    modal.skillsHdr:Show()
    y = y - 20
    if not trainerDB().scanned then
      modal.skillsHdr:SetText("New skills")
      modal.foot:SetText("|cffa8977aVisit your class trainer once, and future level-ups will list the skills you just unlocked.|r")
      modal.foot:ClearAllPoints(); modal.foot:SetPoint("TOPLEFT", 22, y); modal.foot:Show()
      y = y - modal.foot:GetStringHeight() - 6
    elseif #data.skills == 0 then
      modal.skillsHdr:SetText("New skills")
      modal.foot:SetText("|cffa8977aNothing new at the trainer this level.|r")
      modal.foot:ClearAllPoints(); modal.foot:SetPoint("TOPLEFT", 22, y); modal.foot:Show()
      y = y - modal.foot:GetStringHeight() - 6
    else
      modal.skillsHdr:SetText(("New at your trainer (%d)"):format(#data.skills))
      for i, s in ipairs(data.skills) do
        local r = modal.rows[i]
        if not r then break end
        r.skill = s
        r.icon:SetTexture(s.icon or spellIcon(s.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.name:SetText(s.r and ("%s |cffa8977a(%s)|r"):format(s.n, s.r) or s.n)
        r.cost:SetText((s.cost or 0) > 0 and money(s.cost) or "|cff7fd36bfree|r")
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 22, y); r:Show()
        y = y - 22
      end
      local extra = #data.skills - MAX_SKILLS
      local afford = GetMoney() >= data.cost
      local foot = ("Total %s  ·  you have %s"):format(money(data.cost), money(GetMoney()))
      if not afford then foot = foot .. "  |cffff6b6b(short)|r" end
      if extra > 0 then foot = ("|cffa8977a+%d more|r   "):format(extra) .. foot end
      modal.foot:SetText(foot)
      modal.foot:ClearAllPoints(); modal.foot:SetPoint("TOPLEFT", 22, y - 4); modal.foot:Show()
      y = y - 4 - modal.foot:GetStringHeight() - 6
    end
  end

  modal:SetHeight(-y + 50)
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
    copy.skills[i] = { n = s.n, r = s.r, lv = s.lv, icon = s.icon, cost = s.cost, id = s.id }
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

local function celebrate(data)
  remember(data)
  if not FM:GetSetting("levelModal") then return end
  if InCombatLockdown() or UnitAffectingCombat("player") then
    pending = data -- wait until the fight is over
    return
  end
  show(data)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local H = {}

function H.PLAYER_LOGIN()
  snapshotStats()
end

function H.PLAYER_LEVEL_UP(level, hp, mp, talents)
  level = tonumber(level) or UnitLevel("player")
  local c = FM:Char()
  -- Core records how long the previous level took (it runs on the same event)
  C_Timer.After(0.5, function()
    local stats = {}
    for i = 1, 5 do
      local now = UnitStat("player", i)
      stats[i] = (now and baseStats[i]) and (now - baseStats[i]) or 0
    end
    snapshotStats()
    local skills, cost = skillsAt(level)
    local _, powerToken = UnitPowerType("player")
    local powerName = powerToken and _G[powerToken] or nil
    if type(powerName) ~= "string" then powerName = nil end
    celebrate({
      level = level, hp = tonumber(hp), mp = tonumber(mp), talents = tonumber(talents),
      stats = stats, skills = skills, cost = cost, powerName = powerName,
      took = c and c.levelTimes and c.levelTimes[level],
    })
  end)
end

function H.PLAYER_REGEN_ENABLED()
  if pending then
    local data = pending
    pending = nil
    C_Timer.After(1, function() show(data) end)
  end
end

function H.TRAINER_SHOW() scanTrainer(); queueScan() end
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
  elseif rest == "trainer" then
    -- What the trainer cache holds, to check the skill list is working
    local T = trainerDB()
    local n, withId = 0, 0
    for _, sp in pairs(T.spells) do
      n = n + 1
      if sp.id then withId = withId + 1 end
    end
    if not T.scanned then
      say("no trainer skills saved for this class yet. Open your class trainer once.")
    else
      say(("%d trainer skills saved (%d can show a tooltip), last read %s."):format(n, withId, date("%m/%d %H:%M", T.scanned)))
      local lvl = UnitLevel("player")
      for _, L in ipairs({ lvl, lvl + 1, lvl + 2 }) do
        local list = skillsAt(L)
        local names = {}
        for _, sp in ipairs(list) do names[#names + 1] = sp.r and (sp.n .. " (" .. sp.r .. ")") or sp.n end
        print(("  Level %d: %s"):format(L, #names > 0 and table.concat(names, ", ") or "nothing new"))
      end
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
    say("level-up pop-up " .. (FM:GetSetting("levelModal") and "on" or "off") .. "  (/fm levelup last replays your last one, /fm levelup test previews, /fm levelup trainer lists saved skills)")
  end
end
