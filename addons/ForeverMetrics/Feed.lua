-- Forever Metrics: on-screen activity feed
-- A small ticker that shows new activity as it happens ("Reached level 12",
-- "Looted [Green Sword]") and fades it out after a while.
--
-- Positioning: it joins Blizzard's Edit Mode. Open Edit Mode (Esc > Edit Mode)
-- and the feed shows a highlighted box you can drag anywhere; the spot is
-- saved for all your characters. If Edit Mode isn't available, /fm move does
-- the same thing.

local ADDON, ns = ...
local FM = ns.FM

local DEFAULTS = {
  enabled = true,
  lines = 5,       -- how many entries show at once
  hold = 60,       -- seconds the feed stays after the last new entry
  fade = 2,        -- seconds to fade out
  scale = 1,
  point = { "LEFT", "UIParent", "LEFT", 40, 120 },
}

local KIND_ICON = {
  level = "|cffe8c27a[LVL]|r", quest = "|cffffd100[Q]|r", loot = "|cff1eff00[L]|r",
  skill = "|cff69ccf0[S]|r", death = "|cffff5555[X]|r", zone = "|cffaaaaaa[Z]|r",
  gather = "|cffc79c6e[G]|r", duo = "|cffff7eb6[D]|r",
  xp = "|cffd9a6ff[XP]|r", money = "|cffffd700[$]|r", rep = "|cff6fa8ff[R]|r",
  threat = "|cffff6b5a[T]|r",
}

local LINE_H = 16
local feed, overlay, label
local lines = {}      -- FontStrings, index 1 = newest
local shown = {}      -- { entry, born } newest first
local editing = false

local function cfg()
  local db = FM:DB()
  db.feedFrame = db.feedFrame or {}
  local c = db.feedFrame
  for k, v in pairs(DEFAULTS) do if c[k] == nil then c[k] = v end end
  -- v0.8.0: hold now means "after the last entry", so move the old 20s default up
  if not c.holdV2 then
    c.holdV2 = true
    if c.hold == 20 then c.hold = DEFAULTS.hold end
  end
  return c
end

local function savePosition()
  local p, _, rp, x, y = feed:GetPoint(1)
  cfg().point = { p, "UIParent", rp, math.floor(x + 0.5), math.floor(y + 0.5) }
end

local function applyPosition()
  local p = cfg().point
  feed:ClearAllPoints()
  feed:SetPoint(p[1], UIParent, p[3], p[4], p[5])
  feed:SetScale(cfg().scale)
end

local function layout()
  local c = cfg()
  feed:SetSize(320, LINE_H * c.lines + 8)
  for i = 1, c.lines do
    if not lines[i] then
      local fs = feed:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      fs:SetJustifyH("LEFT")
      fs:SetWidth(312)
      fs:SetWordWrap(false)
      lines[i] = fs
    end
    lines[i]:ClearAllPoints()
    -- newest entry sits at the bottom, older ones stack upward
    lines[i]:SetPoint("BOTTOMLEFT", 4, 4 + (i - 1) * LINE_H)
  end
  for i = c.lines + 1, #lines do lines[i]:Hide() end
end

local function render()
  local c = cfg()
  for i = 1, c.lines do
    local fs, s = lines[i], shown[i]
    if s then
      fs:SetText(("%s %s"):format(KIND_ICON[s.entry.k] or "", s.entry.x))
      -- a reused line may still carry the faded-out alpha from its last entry
      if GetTime() - s.born < 0.3 then fs:SetAlpha(0.1) end
      fs:Show()
    else
      fs:SetText("")
      fs:Hide()
    end
  end
end

-- The feed works like a little chat log: new lines push older ones up, the
-- last `lines` entries stay on screen together, and the whole block fades out
-- once nothing new has happened for `hold` seconds. Older lines are slightly
-- dimmer so the newest one stands out.
local lastActivity = 0

local function clearShown()
  for k in pairs(shown) do shown[k] = nil end
end

local function onUpdate()
  if editing then return end
  local c, now = cfg(), GetTime()
  local idle = now - lastActivity
  local group = 1
  if idle >= c.hold then group = 1 - (idle - c.hold) / c.fade end
  if group <= 0 then
    clearShown()
    render()
    feed:SetScript("OnUpdate", nil)
    return
  end
  for i = 1, c.lines do
    local s = shown[i]
    if s then
      local age = now - s.born
      local a = age < 0.3 and (0.1 + 0.9 * age / 0.3) or 1   -- newest line fades in
      a = a * (1 - (i - 1) * 0.1) * group                     -- older lines a touch dimmer
      lines[i]:SetAlpha(math.max(0, math.min(1, a)))
    end
  end
end

function FM:OnNewEntry(entry)
  if FM.debug then print("|cff888888FM feed:|r", feed and "built" or "NOT BUILT", cfg and feed and (cfg().enabled and "on" or "off") or "", entry and entry.x) end
  if not feed or not cfg().enabled then return end
  table.insert(shown, 1, { entry = entry, born = GetTime() })
  for i = cfg().lines + 1, #shown do shown[i] = nil end
  lastActivity = GetTime()
  render()
  feed:SetScript("OnUpdate", onUpdate)
end

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------

local function enterEdit()
  if not feed then return end
  editing = true
  feed:Show()
  overlay:Show()
  feed:EnableMouse(true)
  feed:SetMovable(true)
  -- Show sample lines so there's something to line up against
  local samples = {
    { k = "level", x = "Reached level 12" },
    { k = "loot", x = "Looted |cff1eff00[Sample Green]|r" },
    { k = "skill", x = "Reached 100 Mining" },
    { k = "quest", x = "Completed a quest" },
    { k = "zone", x = "Entered a new zone" },
  }
  for i = 1, cfg().lines do
    local s = samples[((i - 1) % #samples) + 1]
    lines[i]:SetText(("%s %s"):format(KIND_ICON[s.k], s.x))
    lines[i]:SetAlpha(1)
    lines[i]:Show()
  end
end

local function exitEdit()
  if not feed or not editing then return end
  editing = false
  overlay:Hide()
  feed:EnableMouse(false)
  feed:StopMovingOrSizing()
  render()
  for i = 1, cfg().lines do if shown[i] then lines[i]:SetAlpha(1) end end
  if #shown > 0 then
    lastActivity = GetTime()
    feed:SetScript("OnUpdate", onUpdate)
  end
  if not cfg().enabled then feed:Hide() end
end

local function build()
  feed = CreateFrame("Frame", "ForeverMetricsFeed", UIParent)
  feed:SetFrameStrata("MEDIUM")
  feed:SetClampedToScreen(true)
  feed:EnableMouse(false) -- clicks pass through except while editing
  feed:RegisterForDrag("LeftButton")
  feed:SetScript("OnDragStart", function(self) if editing then self:StartMoving() end end)
  feed:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)

  -- Highlight box, styled to sit alongside Blizzard's Edit Mode boxes
  overlay = CreateFrame("Frame", nil, feed, "BackdropTemplate")
  overlay:SetAllPoints()
  overlay:SetFrameLevel(feed:GetFrameLevel() + 5)
  if overlay.SetBackdrop then
    overlay:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2,
    })
    overlay:SetBackdropColor(0.1, 0.45, 0.85, 0.25)
    overlay:SetBackdropBorderColor(0.3, 0.65, 1, 0.9)
  end
  overlay:EnableMouse(false)
  label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("BOTTOM", overlay, "TOP", 0, 2)
  label:SetText("Forever Metrics Feed")
  overlay:Hide()

  layout()
  applyPosition()
  cfg().enabled = FM:GetSetting("feed")
  if cfg().enabled then feed:Show() else feed:Hide() end
  FM:OnSetting("feed", function(v)
    cfg().enabled = v
    if v or editing then feed:Show() else feed:Hide() end
  end)

  -- Hook into Blizzard's Edit Mode when the client has it
  if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("EditMode.Enter", enterEdit, FM)
    EventRegistry:RegisterCallback("EditMode.Exit", exitEdit, FM)
    FM.feedUsesEditMode = true
  end

  -- After each update, say hello once so you can see where the feed lives
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local version = getMeta and getMeta(ADDON, "Version") or "?"
  if cfg().enabled and cfg().hello ~= version then
    cfg().hello = version
    C_Timer.After(4, function()
      FM:OnNewEntry({ t = time(), k = "level", x = ("Forever Metrics %s: your activity feed shows up here"):format(version) })
    end)
  end
end

-- /fm feed test: show a sample line and report where the feed is
local function feedStatus()
  local c = cfg()
  local x, y = feed:GetCenter()
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  local onScreen = x and y and x > 0 and y > 0 and x < sw and y < sh
  print(("|cffe8c27aForever Metrics|r feed: %s, %s, %d lines, scale %.1f, at %s"):format(
    c.enabled and "|cff7fd36bon|r" or "|cffff6b6boff|r (turn it on with /fm feed)",
    feed:IsVisible() and "visible" or "|cffff6b6bhidden|r",
    c.lines, c.scale,
    x and ("%d, %d of %dx%d%s"):format(x, y, sw, sh, onScreen and "" or " |cffff6b6b(off screen! /fm feed reset)|r") or "unknown"))
  local fs = lines[1]
  local function alphaOf(r)
    if not r then return 0 end
    if r.GetEffectiveAlpha then return r:GetEffectiveAlpha() end
    return r:GetAlpha()
  end
  print(("  frame alpha %.2f, scale %.2f, size %dx%d, line 1: %s, alpha %.2f, font %s, text %q"):format(
    alphaOf(feed), feed:GetEffectiveScale(), feed:GetWidth(), feed:GetHeight(),
    fs and (fs:IsVisible() and "visible" or "hidden") or "missing",
    alphaOf(fs), fs and fs.GetFont and tostring((fs:GetFont())) or "?",
    fs and (fs:GetText() or "") or ""))
end

-- Build after login, once SavedVariables are loaded
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function() build() end)

---------------------------------------------------------------------------
-- Slash helpers (called from Core's /fm handler)
---------------------------------------------------------------------------

function FM:FeedCommand(rest)
  if not feed then return end
  local c = cfg()
  local cmd, val = (rest or ""):match("^(%S*)%s*(.-)$")
  if cmd == "" or cmd == "toggle" then
    FM:SetSetting("feed", not FM:GetSetting("feed"))
    print("Forever Metrics feed:", c.enabled and "on" or "off")
  elseif cmd == "lines" and tonumber(val) then
    c.lines = math.max(1, math.min(15, tonumber(val)))
    layout(); render()
    print("Forever Metrics feed lines:", c.lines)
  elseif cmd == "hold" and tonumber(val) then
    c.hold = math.max(3, tonumber(val))
    print("Forever Metrics feed hold:", c.hold .. "s")
  elseif cmd == "scale" and tonumber(val) then
    c.scale = math.max(0.5, math.min(2, tonumber(val)))
    feed:SetScale(c.scale)
    print("Forever Metrics feed scale:", c.scale)
  elseif cmd == "reset" then
    c.point = { (unpack or table.unpack)(DEFAULTS.point) }
    c.scale = 1
    applyPosition()
    print("Forever Metrics feed position reset.")
  elseif cmd == "test" then
    if not c.enabled then
      print("Forever Metrics: the feed is turned off. Turning it on for you.")
      FM:SetSetting("feed", true)
    end
    FM:OnNewEntry({ t = time(), k = "level", x = "This is what a feed entry looks like" })
    -- Outline the feed for a few seconds so it's obvious where it is
    if not editing then
      overlay:Show()
      C_Timer.After(8, function() if not editing then overlay:Hide() end end)
    end
    local ok, err = pcall(feedStatus)
    if not ok then print("Forever Metrics feed status error:", err) end
  else
    print("/fm feed [toggle | lines N | hold SECONDS | scale N | reset | test]")
  end
end

function FM:MoveCommand()
  if not feed then return end
  if editing then exitEdit(); print("Forever Metrics: feed locked.")
  else enterEdit(); print("Forever Metrics: drag the feed, then /fm move again to lock.") end
end
