-- Forever Metrics: XP pill
-- A small always-on pill showing your current XP. Hover it (or press the
-- "Expand XP pill" keybind on keyboard/controller) to open a detail card.
-- Each XP gain pops a "+245 xp" next to it that grows, then fades away.
-- It joins Edit Mode for positioning, like the feed.

local ADDON, ns = ...
local FM = ns.FM
local unpack = unpack or table.unpack

local DEFAULTS = { point = { "TOP", "UIParent", "TOP", 0, -12 }, scale = 1 }
local POP_DUR, POP_GROW, POP_HOLD = 1.8, 0.25, 0.7   -- seconds
local POP_SCALE = 1.35                               -- how big a gain grows
local MERGE_WINDOW = 0.4                             -- quick gains combine into one pop

local pill, head, detail, divider, barBG, barFill, barRest, overlay
local hovering, pinned, editing = false, false, false
local lastXP, lastMax
local popups, driver = {}, nil
local editOwner = {}   -- separate owner so we don't clobber the feed's Edit Mode callbacks

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function cfg()
  local db = FM:DB()
  db.pillFrame = db.pillFrame or {}
  local c = db.pillFrame
  if c.point == nil then c.point = { unpack(DEFAULTS.point) } end
  if c.scale == nil then c.scale = DEFAULTS.scale end
  return c
end

local function num(n)
  n = math.floor((n or 0) + 0.5)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  local s = tostring(n)
  while true do
    local k
    s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then return s end
  end
end

local function short(n)
  if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
  if n >= 1e4 then return ("%.1fk"):format(n / 1e3) end
  return num(n)
end

local function dur(sec)
  sec = math.max(0, math.floor(sec or 0))
  local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
  if h > 0 then return ("%dh %dm"):format(h, m) end
  return ("%dm"):format(m)
end

local function money(c)
  c = c or 0
  if GetCoinTextureString then return GetCoinTextureString(c) end
  local fl = math.floor
  return ("%dg %ds %dc"):format(fl(c / 10000), fl(c / 100) % 100, c % 100)
end

local function maxLevel()
  local ok, lvl = pcall(function()
    return GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
  end)
  return (ok and lvl and lvl > 0) and lvl or 60
end

local function isMaxed()
  return UnitLevel("player") >= maxLevel()
end

---------------------------------------------------------------------------
-- Text + layout
---------------------------------------------------------------------------

local function xpPerHour()
  local s = FM:Session()
  if not s then return 0 end
  local elapsed = time() - s.start
  if elapsed < 60 then return 0 end
  return s.xp / (elapsed / 3600)
end

-- The hover card: a "how's tonight going" snapshot, not leveling math.
local DOT = "  |cffa8977a·|r  "
local GATHER = { "Mining", "Herbalism", "Skinning", "Fishing" }

local function sessionCard()
  local s = FM:Session() or { start = time(), kills = 0, quests = 0, deaths = 0, nodes = 0, skillUps = 0, goldLooted = 0, mobs = {} }
  local c = FM:Char() or { skills = {} }
  local out = {}

  -- Where + how long
  local zone = (GetRealZoneText and GetRealZoneText()) or ""
  out[#out + 1] = ("|cffe8c27aSession %s|r%s%s"):format(dur(time() - s.start), DOT, zone)

  -- What you did
  local did = { ("%d kills"):format(s.kills), ("%d quests"):format(s.quests) }
  if s.levels and s.levels > 0 then table.insert(did, 1, ("|cffe8c27a+%d lvl|r"):format(s.levels)) end
  if s.deaths > 0 then did[#did + 1] = ("|cffff6b6b%d %s|r"):format(s.deaths, s.deaths == 1 and "death" or "deaths") end
  out[#out + 1] = table.concat(did, DOT)

  -- Favorite victim
  local topMob, topN = nil, 0
  for mob, n in pairs(s.mobs or {}) do if n > topN then topMob, topN = mob, n end end
  if topMob then out[#out + 1] = ("Most hunted: %s |cffa8977ax%d|r"):format(topMob, topN) end

  -- Gathering: nodes + current gathering skill levels
  local skills = {}
  for _, g in ipairs(GATHER) do
    local sk = c.skills and c.skills[g]
    if sk then skills[#skills + 1] = ("%s %d"):format(g, sk.rank) end
  end
  if s.nodes > 0 or #skills > 0 then
    local line = ("%d nodes"):format(s.nodes)
    if #skills > 0 then line = line .. DOT .. table.concat(skills, ", ") end
    if s.skillUps > 0 then line = line .. (" |cff69ccf0(+%d)|r"):format(s.skillUps) end
    out[#out + 1] = line
  end

  -- Money: what changed in your wallet, and what dropped off mobs
  local net = GetMoney() - (s.startMoney or GetMoney())
  local netStr = net >= 0 and ("|cff7fd36b+|r" .. money(net)) or ("|cffff6b6b-|r" .. money(-net))
  out[#out + 1] = ("Gold %s%slooted %s"):format(netStr, DOT, money(s.goldLooted))

  -- Best drop
  if s.bestLoot then out[#out + 1] = "Best loot: " .. s.bestLoot end

  out[#out + 1] = "|cffa8977aClick: open Forever Metrics  ·  Right-click: pin|r"
  return table.concat(out, "\n")
end

local barPct, restPct = 0, 0

local function update()
  if not pill then return end
  local lvl = UnitLevel("player")
  local expanded = hovering or pinned or editing

  if isMaxed() then
    head:SetText(("|cffe8c27aLv %d|r  max level"):format(lvl))
    barPct, restPct = 0, 0
  else
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local pct = max > 0 and cur / max or 0
    head:SetText(("|cffe8c27aLv %d|r  %s / %s  |cffa8977a%d%%|r"):format(lvl, num(cur), num(max), math.floor(pct * 100)))
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    barPct = math.min(1, math.max(0, pct))
    restPct = math.min(1, (cur + rested) / math.max(max, 1))
  end

  if expanded then
    detail:SetText(sessionCard())
    detail:Show()
  else
    detail:Hide()
  end

  -- Resize to fit
  local w = head:GetStringWidth() + 36
  local h = 30
  if expanded then
    w = math.max(w, detail:GetStringWidth() + 40)
    h = h + detail:GetStringHeight() + 18
  end
  local pw = math.max(w, 150)
  pill:SetSize(pw, h)
  -- Size the bar from the NEW width so it never pokes out after collapsing
  local inner = pw - 20
  barFill:SetWidth(math.max(0.001, inner * barPct))
  barRest:SetWidth(math.max(0.001, inner * restPct))
  if divider then if expanded then divider:Show() else divider:Hide() end end
end

---------------------------------------------------------------------------
-- Gain pop-ups: grow, drift up, fade
---------------------------------------------------------------------------

local function animate()
  local now, any = GetTime(), false
  local base = cfg().scale
  for _, p in ipairs(popups) do
    if p.active then
      local t = now - p.born
      if t >= POP_DUR then
        p.active = false
        p:Hide()
      else
        any = true
        local g = math.min(t / POP_GROW, 1)
        local s = 1 + (POP_SCALE - 1) * (1 - (1 - g) * (1 - g)) -- ease-out growth
        local a = t < POP_HOLD and 1 or math.max(0, 1 - (t - POP_HOLD) / (POP_DUR - POP_HOLD))
        p:SetScale(base * s)
        p:SetAlpha(a)
        p:ClearAllPoints()
        p:SetPoint("LEFT", pill, "RIGHT", 12 / s, (t * 12) / s)
      end
    end
  end
  if not any then driver:SetScript("OnUpdate", nil) end
end

local function popGain(amount)
  if not pill or not pill:IsShown() or not FM:GetSetting("xpPopups") then return end
  local now = GetTime()
  -- Merge quick back-to-back gains (e.g. kill xp + quest xp) into one pop
  for _, p in ipairs(popups) do
    if p.active and now - p.born < MERGE_WINDOW then
      p.amount = p.amount + amount
      p.text:SetText(("|cffe8c27a+%s xp|r"):format(num(p.amount)))
      p.born = now
      return
    end
  end
  local p
  for _, f in ipairs(popups) do if not f.active then p = f; break end end
  if not p then
    p = CreateFrame("Frame", nil, UIParent)
    p:SetSize(1, 1)
    p:SetFrameStrata("MEDIUM")
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.text:SetPoint("LEFT")
    popups[#popups + 1] = p
  end
  p.active, p.born, p.amount = true, now, amount
  p.text:SetText(("|cffe8c27a+%s xp|r"):format(num(amount)))
  p:Show()
  driver:SetScript("OnUpdate", animate)
end

---------------------------------------------------------------------------
-- Visibility: setting, combat dimming
---------------------------------------------------------------------------

local function applyVisibility()
  if not pill then return end
  if FM:GetSetting("pill") or editing then pill:Show() else pill:Hide() end
  local dim = FM:GetSetting("pillCombatFade") and UnitAffectingCombat("player") and not (hovering or pinned or editing)
  pill:SetAlpha(dim and 0.35 or 1)
end

---------------------------------------------------------------------------
-- Hide Blizzard's XP bar (setting)
-- Uses alpha + mouse only, never Hide(), so we don't taint Blizzard's
-- protected UI or Edit Mode. Covers both modern and Classic frame names.
---------------------------------------------------------------------------

local XPBAR_FRAMES = { "MainStatusTrackingBarContainer", "MainMenuExpBar", "MainMenuBarExpBar", "ExhaustionTick" }
local hooked = {}

local function setMouseDeep(f, on)
  pcall(f.EnableMouse, f, on)
  for _, child in ipairs({ f:GetChildren() }) do
    pcall(child.EnableMouse, child, on)
    for _, gc in ipairs({ child:GetChildren() }) do pcall(gc.EnableMouse, gc, on) end
  end
end

function FM:ApplyXPBar()
  local hide = FM:GetSetting("hideXPBar")
  local found = 0
  for _, name in ipairs(XPBAR_FRAMES) do
    local f = _G[name]
    if f and f.SetAlpha then
      found = found + 1
      if not hooked[f] then
        hooked[f] = true
        f:HookScript("OnShow", function(self)
          if FM:GetSetting("hideXPBar") then self:SetAlpha(0) end
        end)
      end
      f:SetAlpha(hide and 0 or 1)
      if not InCombatLockdown() then setMouseDeep(f, not hide) end
    end
  end
  if FM.debug then print("Forever Metrics: XP bar frames found:", found) end
  if found == 0 and hide then
    print("|cffe8c27aForever Metrics|r couldn't find the XP bar frame on this client. Tell Claude!")
  end
end

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------

local function savePosition()
  local cx, top = pill:GetCenter(), pill:GetTop()
  if not cx or not top then return end
  cfg().point = { "TOP", "UIParent", "BOTTOMLEFT", math.floor(cx + 0.5), math.floor(top + 0.5) }
  pill:ClearAllPoints()
  pill:SetPoint("TOP", UIParent, "BOTTOMLEFT", cfg().point[4], cfg().point[5])
end

local function applyPosition()
  local p = cfg().point
  pill:ClearAllPoints()
  pill:SetPoint(p[1], UIParent, p[3], p[4], p[5])
  pill:SetScale(cfg().scale)
end

local function enterEdit()
  if not pill then return end
  editing = true
  overlay:Show()
  pill:SetMovable(true)
  applyVisibility(); update()
end

local function exitEdit()
  if not pill or not editing then return end
  editing = false
  overlay:Hide()
  pill:StopMovingOrSizing()
  applyVisibility(); update()
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local function build()
  pill = CreateFrame("Frame", "ForeverMetricsPill", UIParent, "BackdropTemplate")
  pill:SetFrameStrata("MEDIUM")
  pill:SetClampedToScreen(true)
  pill:EnableMouse(true)
  pill:RegisterForDrag("LeftButton")
  FM:Skin(pill, { edge = 12, alpha = 0.82 })

  head = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  head:SetPoint("TOP", 0, -9)

  detail = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  detail:SetPoint("TOPLEFT", 20, -36)
  detail:SetJustifyH("LEFT")
  detail:SetSpacing(4)
  detail:Hide()

  -- Faint gold rule between the XP line and the card
  divider = pill:CreateTexture(nil, "ARTWORK")
  divider:SetColorTexture(FM.THEME.border[1], FM.THEME.border[2], FM.THEME.border[3], 0.35)
  divider:SetPoint("TOPLEFT", 14, -27); divider:SetPoint("TOPRIGHT", -14, -27); divider:SetHeight(1)
  divider:Hide()

  -- Thin progress bar along the bottom edge (stands in for the XP bar)
  barBG = pill:CreateTexture(nil, "ARTWORK")
  barBG:SetColorTexture(0, 0, 0, 0.6)
  barBG:SetPoint("BOTTOMLEFT", 10, 6); barBG:SetPoint("BOTTOMRIGHT", -10, 6)  -- tucked inside the rounded edge
  barBG:SetHeight(2)
  local T = FM.THEME
  barRest = pill:CreateTexture(nil, "ARTWORK", nil, 1)
  barRest:SetColorTexture(T.rested[1], T.rested[2], T.rested[3], T.rested[4])
  barRest:SetPoint("BOTTOMLEFT", barBG); barRest:SetHeight(2)
  barFill = pill:CreateTexture(nil, "ARTWORK", nil, 2)
  barFill:SetColorTexture(T.bar[1], T.bar[2], T.bar[3], T.bar[4])
  barFill:SetPoint("BOTTOMLEFT", barBG); barFill:SetHeight(2)

  -- Edit Mode highlight
  overlay = CreateFrame("Frame", nil, pill, "BackdropTemplate")
  overlay:SetPoint("TOPLEFT", -3, 3); overlay:SetPoint("BOTTOMRIGHT", 3, -3)
  overlay:SetFrameLevel(pill:GetFrameLevel() + 5)
  if overlay.SetBackdrop then
    overlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    overlay:SetBackdropColor(0.1, 0.45, 0.85, 0.2)
    overlay:SetBackdropBorderColor(0.3, 0.65, 1, 0.9)
  end
  local lbl = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lbl:SetPoint("BOTTOM", overlay, "TOP", 0, 2)
  lbl:SetText("Forever Metrics XP")
  overlay:Hide()

  pill:SetScript("OnEnter", function() hovering = true; applyVisibility(); update() end)
  pill:SetScript("OnLeave", function() hovering = false; applyVisibility(); update() end)
  pill:SetScript("OnMouseUp", function(_, button)
    if editing then return end
    if button == "RightButton" then FM:TogglePillExpanded()   -- right-click pins the card open
    elseif FM.ToggleUI then FM:ToggleUI() end                  -- left-click opens /fm
  end)
  pill:SetScript("OnDragStart", function(self) if editing then self:StartMoving() end end)
  pill:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)

  driver = CreateFrame("Frame")

  applyPosition()
  lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
  applyVisibility()
  update()
  FM:ApplyXPBar()

  -- Refresh session/time numbers while expanded
  C_Timer.NewTicker(1, function() if hovering or pinned or editing then update() end end)

  if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("EditMode.Enter", enterEdit, editOwner)
    EventRegistry:RegisterCallback("EditMode.Exit", exitEdit, editOwner)
  end

  FM:OnSetting("pill", applyVisibility)
  FM:OnSetting("pillCombatFade", applyVisibility)
  FM:OnSetting("hideXPBar", function() FM:ApplyXPBar() end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local H = {}

function H.PLAYER_LOGIN() build() end

function H.PLAYER_XP_UPDATE()
  local cur, max = UnitXP("player"), UnitXPMax("player")
  if lastXP then
    local gained = cur >= lastXP and (cur - lastXP) or ((lastMax or 0) - lastXP + cur)
    if gained > 0 then popGain(gained) end
  end
  lastXP, lastMax = cur, max
  update()
end

function H.PLAYER_LEVEL_UP() update() end
function H.UPDATE_EXHAUSTION() update() end
function H.PLAYER_REGEN_DISABLED() applyVisibility() end
function H.PLAYER_REGEN_ENABLED()
  applyVisibility()
  if FM:GetSetting("hideXPBar") then FM:ApplyXPBar() end -- finish mouse changes skipped in combat
end
function H.PLAYER_ENTERING_WORLD()
  if pill then FM:ApplyXPBar(); update() end
end

ev:SetScript("OnEvent", function(_, event, ...)
  if event ~= "PLAYER_LOGIN" and not pill then return end
  local ok, err = pcall(H[event], ...)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics pill error|r", event, err) end
end)
for event in pairs(H) do pcall(ev.RegisterEvent, ev, event) end

---------------------------------------------------------------------------
-- Public: keybind + slash
---------------------------------------------------------------------------

function FM:TogglePillExpanded()
  if not pill then return end
  pinned = not pinned
  applyVisibility(); update()
end

function FM:PillCommand(rest)
  if not pill then return end
  local cmd, val = (rest or ""):match("^(%S*)%s*(.-)$")
  if cmd == "" or cmd == "toggle" then
    FM:SetSetting("pill", not FM:GetSetting("pill"))
    print("Forever Metrics XP pill:", FM:GetSetting("pill") and "on" or "off")
  elseif cmd == "scale" and tonumber(val) then
    cfg().scale = math.max(0.5, math.min(2, tonumber(val)))
    pill:SetScale(cfg().scale)
    print("Forever Metrics XP pill scale:", cfg().scale)
  elseif cmd == "reset" then
    cfg().point = { unpack(DEFAULTS.point) }
    cfg().scale = 1
    applyPosition()
    print("Forever Metrics XP pill position reset.")
  elseif cmd == "test" then
    popGain(math.random(80, 400))
  else
    print("/fm pill [toggle | scale N | reset | test]")
  end
end
