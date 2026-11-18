-- Forever Metrics: threat meter
-- A small list of your party's threat on your target, built on the game's
-- own threat functions (UnitDetailedThreatSituation), since Forever blocks
-- the combat log. Shows in combat with a hostile target; hides after.
--   rows      you, your pet and your party, highest threat first, in class
--             colours; a role marker when the group has roles set; a gold
--             edge on whoever has aggro; your row gets a gold outline and
--             turns yellow/orange/red as you near the warning point
--   warning   when you're not the one with aggro and reach the set % (90 by
--             default): a banner mid-screen and a [T] line in the feed,
--             optional sound; once per climb
-- Settings live under Options > Threat Meter. Move it in Edit Mode or with
-- /fm threat move. Position: ForeverMetricsDB.threatFrame.

local ADDON, ns = ...
local FM = ns.FM

local ROW_H, WIDTH = 18, 220
local MAX_ROWS = 6
local DEFAULT_POINT = { "TOP", "UIParent", "CENTER", 0, -120 }

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end
local function isSecret(v) return issecretvalue and issecretvalue(v) or false end

local function cfg()
  local db = FM:DB()
  db.threatFrame = db.threatFrame or {}
  local c = db.threatFrame
  if not c.point then c.point = { unpack(DEFAULT_POINT) } end
  return c
end

local meter, rows, banner = nil, {}, nil
local editing, unlocked = false, false
local warned = false

---------------------------------------------------------------------------
-- Who to show
---------------------------------------------------------------------------

local function groupUnits()
  local list = { "player" }
  if UnitExists("pet") then list[#list + 1] = "pet" end
  if not (IsInRaid and IsInRaid()) then
    for i = 1, 4 do
      if UnitExists("party" .. i) then list[#list + 1] = "party" .. i end
    end
  end
  return list
end

local function classColor(unit)
  if unit == "pet" then return 0.55, 0.75, 0.45 end
  local _, class = UnitClass(unit)
  class = safe(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 0.7, 0.7, 0.7
end

local function role(unit)
  if not UnitGroupRolesAssigned then return nil end
  local ok, r = pcall(UnitGroupRolesAssigned, unit)
  r = ok and safe(r) or nil
  if r == "TANK" or r == "HEALER" then return r end
end

-- { unit, name, pct (nil if hidden), raw (secret-safe value for the bar), tanking }
local function readThreat(mob)
  local out = {}
  local justMe = FM:GetSetting("threatRows") == "me"
  for _, u in ipairs(groupUnits()) do
    if not justMe or u == "player" then
      local ok, tanking, _, scaled = pcall(UnitDetailedThreatSituation, u, mob)
      if ok and (scaled ~= nil or tanking ~= nil) then
        local name = u == "player" and "You" or UnitName(u)
        out[#out + 1] = {
          unit = u, name = isSecret(name) and u or (name or u),
          pct = safe(scaled), raw = scaled, tanking = safe(tanking),
        }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.pct and b.pct then
      if a.pct ~= b.pct then return a.pct > b.pct end
    elseif a.pct or b.pct then
      return a.pct ~= nil -- hidden values sort last
    end
    return a.unit == "player"
  end)
  return out
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local function savePosition()
  local cx, top = meter:GetCenter(), meter:GetTop()
  if not cx or not top then return end
  cfg().point = { "TOP", "UIParent", "BOTTOMLEFT", math.floor(cx + 0.5), math.floor(top + 0.5) }
  meter:ClearAllPoints()
  meter:SetPoint("TOP", UIParent, "BOTTOMLEFT", cfg().point[4], cfg().point[5])
end

local function applyPosition()
  local p = cfg().point
  meter:ClearAllPoints()
  meter:SetPoint(p[1], UIParent, p[3], p[4], p[5])
  meter:SetScale(FM:GetSetting("threatScale") or 1)
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("StatusBar", nil, meter)
  r:SetSize(WIDTH - 16, ROW_H - 2)
  r:SetPoint("TOPLEFT", 8, -22 - (i - 1) * ROW_H)
  r:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  r:SetMinMaxValues(0, 100)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints(); r.bg:SetColorTexture(0, 0, 0, 0.5)
  r.edge = r:CreateTexture(nil, "OVERLAY")
  r.edge:SetPoint("TOPLEFT"); r.edge:SetPoint("BOTTOMLEFT"); r.edge:SetWidth(3)
  r.edge:SetColorTexture(1, 0.82, 0.35, 1)
  r.outline = CreateFrame("Frame", nil, r, "BackdropTemplate")
  r.outline:SetPoint("TOPLEFT", -1, 1); r.outline:SetPoint("BOTTOMRIGHT", 1, -1)
  if r.outline.SetBackdrop then
    r.outline:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  end
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", 6, 0); r.name:SetPoint("RIGHT", r, "RIGHT", -44, 0)
  r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  r.pct = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.pct:SetPoint("RIGHT", -5, 0)
  rows[i] = r
  return r
end

local ROLE_TAG = { TANK = "|cffe8c27a[T]|r ", HEALER = "|cff7fd36b[H]|r " }

-- Your row's colour as you near the warning point
local function myColor(pct)
  local at = FM:GetSetting("threatWarnAt") or 90
  if not pct then return 0.25, 0.78, 0.92 end
  if pct >= at then return 1, 0.29, 0.24 end
  if pct >= at - 10 then return 1, 0.55, 0.15 end
  if pct >= at - 20 then return 1, 0.83, 0.2 end
  return 0.25, 0.78, 0.92
end

local function draw(list, title)
  meter.title:SetText(title or "")
  for i = 1, MAX_ROWS do
    local r = rows[i]
    local e = list[i]
    if e then
      r = getRow(i)
      local me = e.unit == "player"
      local cr, cg, cb = classColor(e.unit)
      if me then cr, cg, cb = myColor(e.pct) end
      r:SetStatusBarColor(cr, cg, cb, 0.75)
      if e.pct then r:SetValue(math.min(100, e.pct))
      else pcall(r.SetValue, r, e.raw) end -- a hidden value can still fill a bar
      r.name:SetText((ROLE_TAG[role(e.unit) or ""] or "") .. e.name)
      r.pct:SetText(e.pct and ("%d%%"):format(math.floor(e.pct + 0.5)) or "")
      if e.tanking then r.edge:Show() else r.edge:Hide() end
      if r.outline.SetBackdropBorderColor then
        if me then r.outline:SetBackdropBorderColor(1, 0.82, 0.35, 0.9); r.outline:Show() else r.outline:Hide() end
      end
      r:Show()
    elseif r then
      r:Hide()
    end
  end
  meter:SetHeight(28 + math.max(1, math.min(#list, MAX_ROWS)) * ROW_H)
end

local SAMPLE = {
  { unit = "party1", name = "Kil'hala", pct = 100, tanking = true },
  { unit = "player", name = "You", pct = 72 },
  { unit = "party2", name = "Lindabelcher", pct = 41 },
}

---------------------------------------------------------------------------
-- Warning
---------------------------------------------------------------------------

local function showBanner(text, sub)
  if not banner then
    banner = CreateFrame("Frame", nil, UIParent)
    banner:SetSize(600, 60)
    banner:SetPoint("CENTER", 0, 180)
    banner:SetFrameStrata("HIGH")
    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    banner.text:SetPoint("TOP")
    banner.text:SetTextColor(1, 0.35, 0.24)
    banner.sub = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    banner.sub:SetPoint("TOP", banner.text, "BOTTOM", 0, -4)
    banner.sub:SetTextColor(1, 0.82, 0.66)
  end
  banner.text:SetText(text); banner.sub:SetText(sub or "")
  banner:SetAlpha(1); banner:Show()
  banner.until_ = GetTime() + 2.5
  banner:SetScript("OnUpdate", function(self)
    local left = self.until_ - GetTime()
    if left <= 0 then self:Hide(); self:SetScript("OnUpdate", nil)
    elseif left < 0.6 then self:SetAlpha(left / 0.6) end
  end)
end

local function checkWarning(list, mobName)
  if not FM:GetSetting("threatWarn") then return end
  local me
  for _, e in ipairs(list) do if e.unit == "player" then me = e end end
  if not me or not me.pct then return end
  local at = FM:GetSetting("threatWarnAt") or 90
  if me.tanking then warned = false; return end -- you already have it
  if me.pct < at - 15 then warned = false end    -- climbed back down: arm again
  if warned or me.pct < at then return end
  warned = true
  local holder
  for _, e in ipairs(list) do if e.tanking then holder = e.name end end
  local pct = math.floor(me.pct + 0.5)
  showBanner(("PULLING AGGRO  ·  %d%%"):format(pct), holder and ("ease off until " .. holder .. " gets it back") or "ease off")
  if FM.OnNewEntry then
    FM:OnNewEntry({ t = time(), k = "threat", x = ("|cffff6b5aPulling aggro|r on %s: %d%%"):format(mobName or "your target", pct) })
  end
  if FM:GetSetting("threatSound") and PlaySound then
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
  end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

local function wanted()
  if editing or unlocked then return true end
  if not FM:GetSetting("threatMeter") then return false end
  if not (UnitAffectingCombat("player") or InCombatLockdown()) then return false end
  if not UnitExists("target") or not safe(UnitCanAttack("player", "target")) or safe(UnitIsDead("target")) then return false end
  if FM:GetSetting("threatHideSolo") and not UnitExists("pet") and (GetNumGroupMembers and GetNumGroupMembers() or 0) == 0 then
    return false
  end
  return true
end

local function update()
  if not meter then return end
  if editing or unlocked then
    draw(SAMPLE, "Threat (drag to move)")
    meter:Show()
    return
  end
  if not wanted() then meter:Hide(); return end
  local list = readThreat("target")
  if #list == 0 then meter:Hide(); return end
  local mobName = safe(UnitName("target"))
  draw(list, mobName)
  meter:Show()
  checkWarning(list, mobName)
end

local function build()
  meter = CreateFrame("Frame", "ForeverMetricsThreat", UIParent, "BackdropTemplate")
  meter:SetSize(WIDTH, 28 + ROW_H)
  meter:SetFrameStrata("MEDIUM")
  meter:SetClampedToScreen(true)
  meter:RegisterForDrag("LeftButton")
  FM:Skin(meter, { edge = 12, alpha = 0.8 })
  meter.title = meter:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  meter.title:SetPoint("TOPLEFT", 9, -7); meter.title:SetPoint("RIGHT", meter, "RIGHT", -40, 0)
  meter.title:SetJustifyH("LEFT"); meter.title:SetWordWrap(false)
  local tag = meter:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  tag:SetPoint("TOPRIGHT", -9, -7); tag:SetText("threat")
  meter:SetScript("OnDragStart", function(self) if editing or unlocked then self:StartMoving() end end)
  meter:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)
  applyPosition()
  meter:Hide()

  if EventRegistry and EventRegistry.RegisterCallback then
    local owner = {}
    EventRegistry:RegisterCallback("EditMode.Enter", function()
      editing = true; meter:SetMovable(true); meter:EnableMouse(true); update()
    end, owner)
    EventRegistry:RegisterCallback("EditMode.Exit", function()
      editing = false; meter:StopMovingOrSizing()
      if not unlocked then meter:EnableMouse(false) end
      update()
    end, owner)
  end
  for _, k in ipairs({ "threatMeter", "threatRows", "threatHideSolo", "threatWarnAt" }) do FM:OnSetting(k, update) end
  FM:OnSetting("threatScale", function() applyPosition(); update() end)

  -- Steady refresh while fighting, on top of the threat events
  C_Timer.NewTicker(0.5, function()
    if meter:IsShown() or UnitAffectingCombat("player") then
      local ok, err = pcall(update)
      if not ok and FM.debug then print("|cffff5555ForeverMetrics threat error|r", err) end
    end
  end)
end

-- /fm threat move: unlock for dragging without Edit Mode
function FM:ThreatMove()
  if not meter then return end
  unlocked = not unlocked
  meter:SetMovable(unlocked); meter:EnableMouse(unlocked)
  if not unlocked then meter:StopMovingOrSizing() end
  print("|cffe8c27aForever Metrics|r threat meter " .. (unlocked and "unlocked: drag it, then /fm threat move again to lock." or "locked."))
  update()
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local ok, err = pcall(build)
    if not ok and FM.debug then print("|cffff5555ForeverMetrics threat error|r", err) end
    return
  end
  if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_TARGET_CHANGED" then warned = false end
  local ok, err = pcall(update)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics threat error|r", event, err) end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED",
                     "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "UNIT_PET" }) do
  pcall(ev.RegisterEvent, ev, e)
end
