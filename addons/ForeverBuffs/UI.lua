-- Forever Buffs: the icon row
-- One secure button per missing buff, so a click casts it. Secure buttons can
-- only be shown, hidden, moved, resized or re-pointed out of combat, so every
-- change here is skipped in combat and redone on PLAYER_REGEN_ENABLED.
--
-- Positioning: joins Blizzard's Edit Mode (Esc > Edit Mode), with /fb move as
-- a fallback. The spot is saved account-wide in ForeverBuffsDB.

local ADDON, ns = ...
local FB = ns.FB
local safe = FB.safe

local UI = {}
FB.UI = UI

local SIZE, GAP, PAD = 34, 5, 6
local MAX = 8
local THEME = {
  bg     = { 0.12, 0.085, 0.055, 0.75 },  -- same leather and gold as ForeverMetrics
  border = { 0.66, 0.51, 0.31, 0.95 },
}

local holder, overlay
local buttons = {}
local editing, testing = false, false
local testTimer

---------------------------------------------------------------------------
-- Position and scale
---------------------------------------------------------------------------

-- Saved in UIParent units, so changing the scale doesn't move the row
local function relScale()
  local a, b = holder:GetEffectiveScale(), UIParent:GetEffectiveScale()
  if not a or not b or b == 0 then return 1 end
  return a / b
end

function UI:ApplyPosition()
  if not holder then return end
  if InCombatLockdown() then FB.pending = true; UI.positionPending = true; return end
  UI.positionPending = false
  local db = FB:DB()
  holder:SetScale(db.scale or 1)
  local p = db.point
  local rel = relScale()
  holder:ClearAllPoints()
  if p[3] == "BOTTOMLEFT" then
    holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[4] / rel, p[5] / rel)
  else
    holder:SetPoint(p[1], UIParent, p[3], p[4] / rel, p[5] / rel)
  end
end

local function savePosition()
  local cx, cy = holder:GetCenter()
  if not cx or not cy then return end
  local rel = relScale()
  FB:DB().point = { "CENTER", "UIParent", "BOTTOMLEFT", math.floor(cx * rel + 0.5), math.floor(cy * rel + 0.5) }
  UI:ApplyPosition()
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

local function fmtTime(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  if sec >= 60 then return ("%dm"):format(math.floor(sec / 60)) end
  return ("%ds"):format(sec)
end

local function showTooltip(b)
  local d = b.data
  if not d or editing then return end
  GameTooltip:SetOwner(b, "ANCHOR_TOP")
  local ok = false
  if d.spellID and GameTooltip.SetSpellByID then
    ok = pcall(GameTooltip.SetSpellByID, GameTooltip, d.spellID)
  elseif d.itemID and GameTooltip.SetItemByID then
    ok = pcall(GameTooltip.SetItemByID, GameTooltip, d.itemID)
  end
  if not ok then GameTooltip:SetText(d.spellName or d.itemName or d.label or "?", 1, 1, 1) end
  GameTooltip:AddLine(" ")
  if d.sample then
    GameTooltip:AddLine("Sample icon. /fb test hides it.", 0.66, 0.6, 0.48)
  else
    if d.expires then
      GameTooltip:AddLine(("%s runs out in %s"):format(d.label, fmtTime(d.expires - GetTime())), 1, 0.82, 0)
    else
      GameTooltip:AddLine(("%s is missing"):format(d.label), 1, 0.42, 0.42)
    end
    if d.action and d.action.type == "macro" then
      GameTooltip:AddLine(("Click to apply %s"):format(d.itemName or "poison"), 0.5, 0.83, 0.42)
    elseif d.action then
      GameTooltip:AddLine("Click to cast", 0.5, 0.83, 0.42)
    elseif d.hint then
      GameTooltip:AddLine(d.hint, 0.66, 0.6, 0.48)
    end
  end
  GameTooltip:Show()
end

local function makeButton(i)
  local b = CreateFrame("Button", "ForeverBuffsButton" .. i, holder, "SecureActionButtonTemplate")
  b:SetSize(SIZE, SIZE)
  -- AnyDown too, so it works whichever way the "cast on key down" option is set
  b:RegisterForClicks("AnyUp", "AnyDown")

  b.edge = b:CreateTexture(nil, "BACKGROUND")
  b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  b.edge:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 0.9)

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

  b.shade = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.shade:SetPoint("BOTTOMLEFT"); b.shade:SetPoint("BOTTOMRIGHT"); b.shade:SetHeight(13)
  b.shade:SetColorTexture(0, 0, 0, 0.55)

  b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.time:SetPoint("BOTTOM", 0, 1)
  b.time:SetTextColor(1, 0.82, 0)

  -- Gentle pulse around icons that need attention
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.glow:SetBlendMode("ADD")
  b.glow:SetVertexColor(1, 0.82, 0.45)
  b.glow:SetSize(SIZE * 1.9, SIZE * 1.9)
  b.glow:SetPoint("CENTER")
  b.glow:SetAlpha(0)
  local ag = b.glow:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(0.1); a:SetToAlpha(0.75); a:SetDuration(1.1)
  if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
  b.pulse = ag

  b:SetScript("OnEnter", showTooltip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

local ATTRS = { "type", "spell", "unit", "item", "macrotext" }

local function setAction(b, action)
  for _, k in ipairs(ATTRS) do b:SetAttribute(k, nil) end
  if not action then return end
  b:SetAttribute("type", action.type)
  if action.spell then b:SetAttribute("spell", action.spell) end
  if action.unit then b:SetAttribute("unit", action.unit) end
  if action.item then b:SetAttribute("item", action.item) end
  if action.macrotext then b:SetAttribute("macrotext", action.macrotext) end
end

local function setTimeText(b)
  local d = b.data
  if d and d.expires then
    b.time:SetText(fmtTime(d.expires - GetTime()))
    b.time:Show(); b.shade:Show()
  elseif d and d.sampleTime then
    b.time:SetText(fmtTime(d.sampleTime))
    b.time:Show(); b.shade:Show()
  else
    b.time:Hide(); b.shade:Hide()
  end
end

---------------------------------------------------------------------------
-- Apply a list (out of combat only)
---------------------------------------------------------------------------

local function samples()
  local out = {}
  for _, s in ipairs(FB.SAMPLES) do
    out[#out + 1] = { sample = true, label = s[2], spellName = s[2], spellID = s[1],
      icon = FB:SpellIcon(s[1], s[2]), sampleTime = s[3] }
  end
  return out
end

function UI:Apply()
  if not holder then return end
  if InCombatLockdown() then FB.pending = true; return end
  if UI.positionPending then UI:ApplyPosition() end

  local db = FB:DB()
  local list = (editing or testing) and samples() or (FB.list or {})
  local visible = editing or testing or (#list > 0 and not FB:ShouldHide())
  local n = math.min(#list, MAX)

  for i = 1, MAX do
    local b = buttons[i]
    local d = list[i]
    if d and i <= n then
      b.data = d
      setAction(b, (not d.sample) and d.action or nil)
      b.icon:SetTexture(d.icon or 134400)
      b.icon:SetDesaturated(d.hint ~= nil)
      setTimeText(b)
      b:ClearAllPoints()
      b:SetPoint("LEFT", holder, "LEFT", PAD + (i - 1) * (SIZE + GAP), 0)
      if db.glow and not editing and not d.expires and not d.sampleTime then
        b.pulse:Play()
      else
        b.pulse:Stop(); b.glow:SetAlpha(0)
      end
      b:Show()
    else
      b.data = nil
      setAction(b, nil)
      b.pulse:Stop()
      b:Hide()
    end
  end

  local count = math.max(n, 1)
  holder:SetSize(PAD * 2 + count * SIZE + (count - 1) * GAP, SIZE + PAD * 2)
  if visible then holder:Show() else holder:Hide() end
end

-- Countdown text; safe in combat (only font strings change)
function UI:Tick()
  for i = 1, MAX do
    local b = buttons[i]
    if b and b:IsShown() and b.data and b.data.expires then setTimeText(b) end
  end
end

function UI:AfterCombat()
  if UI.positionPending then UI:ApplyPosition() end
end

---------------------------------------------------------------------------
-- Edit Mode, /fb move and /fb test
---------------------------------------------------------------------------

local function enterEdit()
  if not holder or InCombatLockdown() then return end
  editing = true
  overlay:Show()
  UI:Apply()
end

local function exitEdit()
  if not holder or not editing then return end
  editing = false
  overlay:Hide()
  holder:StopMovingOrSizing()
  if not InCombatLockdown() then savePosition() end
  UI:Apply()
end

function UI:ToggleMove()
  if not holder then return end
  if InCombatLockdown() then FB:Print("can't move the icons in combat."); return end
  if editing then
    exitEdit(); FB:Print("icons locked.")
  else
    enterEdit(); FB:Print("drag the box, then /fb move again to lock.")
  end
end

function UI:ToggleTest()
  if not holder then return end
  if InCombatLockdown() then FB:Print("try again out of combat."); return end
  if testTimer then testTimer:Cancel(); testTimer = nil end
  testing = not testing
  if testing then
    FB:Print("showing sample icons for 15 seconds.")
    testTimer = C_Timer.NewTimer(15, function()
      testTimer = nil
      if testing then
        testing = false
        if InCombatLockdown() then FB.pending = true else UI:Apply() end
      end
    end)
  end
  UI:Apply()
end

---------------------------------------------------------------------------
-- Options panel (Esc > Options > AddOns > Forever Buffs). Best effort: if the
-- client's Settings API differs, the slash commands still do everything.
---------------------------------------------------------------------------

local function buildOptions()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
      and Settings.CreateCheckbox and Settings.RegisterAddOnCategory) then return end
  local db = FB:DB()
  local cat = Settings.RegisterVerticalLayoutCategory("Forever Buffs")

  local function onChange(setting, fn)
    if setting and setting.SetValueChangedCallback then
      setting:SetValueChangedCallback(function() FB:Try("option", fn) end)
    end
  end

  local function checkbox(key, name, tip, after)
    local s = Settings.RegisterAddOnSetting(cat, "ForeverBuffs_" .. key, key, db, type(false), name, FB.DEFAULTS[key])
    Settings.CreateCheckbox(cat, s, tip)
    onChange(s, after or function() FB:Refresh() end)
  end

  checkbox("enabled", "Show reminders", "Show icons for buffs you're missing. Same as /fb.")
  checkbox("restHide", "Only remind outside cities",
    "Hide the icons while you're resting (in a city or inn).")
  checkbox("glow", "Glow", "A gentle pulse around missing buffs.")

  if Settings.CreateSlider and Settings.CreateSliderOptions then
    pcall(function()
      local s = Settings.RegisterAddOnSetting(cat, "ForeverBuffs_scale", "scale", db, type(1), "Scale", FB.DEFAULTS.scale)
      local opts = Settings.CreateSliderOptions(0.5, 2, 0.05)
      if opts.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return ("%.2f"):format(v) end)
      end
      Settings.CreateSlider(cat, s, opts, "Size of the icons. Same as /fb scale N.")
      onChange(s, function() UI:ApplyPosition() end)
    end)
  end

  Settings.RegisterAddOnCategory(cat)
  UI.category = cat
end

function UI:OpenOptions()
  local cat = UI.category
  if cat and Settings and Settings.OpenToCategory then
    local ok = pcall(Settings.OpenToCategory, cat.GetID and cat:GetID() or cat.ID)
    if ok then return end
  end
  FB:Print("options panel not available here. Use the /fb commands instead.")
end

---------------------------------------------------------------------------
-- Build (called from Core on PLAYER_LOGIN)
---------------------------------------------------------------------------

function UI:Build()
  holder = CreateFrame("Frame", "ForeverBuffsFrame", UIParent, "BackdropTemplate")
  holder:SetFrameStrata("MEDIUM")
  holder:SetClampedToScreen(true)
  holder:SetMovable(true)
  holder:SetSize(PAD * 2 + SIZE, SIZE + PAD * 2)
  if holder.SetBackdrop then
    holder:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    holder:SetBackdropColor(THEME.bg[1], THEME.bg[2], THEME.bg[3], THEME.bg[4])
    holder:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4])
  end

  for i = 1, MAX do buttons[i] = makeButton(i) end

  -- Edit Mode box: sits above the buttons and takes the drag
  overlay = CreateFrame("Frame", nil, holder, "BackdropTemplate")
  overlay:SetPoint("TOPLEFT", -3, 3); overlay:SetPoint("BOTTOMRIGHT", 3, -3)
  overlay:SetFrameLevel(holder:GetFrameLevel() + 20)
  if overlay.SetBackdrop then
    overlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    overlay:SetBackdropColor(0.1, 0.45, 0.85, 0.25)
    overlay:SetBackdropBorderColor(0.3, 0.65, 1, 0.9)
  end
  overlay:EnableMouse(true)
  overlay:RegisterForDrag("LeftButton")
  overlay:SetScript("OnDragStart", function() if not InCombatLockdown() then holder:StartMoving() end end)
  overlay:SetScript("OnDragStop", function()
    holder:StopMovingOrSizing()
    if not InCombatLockdown() then savePosition() end
  end)
  local lbl = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lbl:SetPoint("BOTTOM", overlay, "TOP", 0, 2)
  lbl:SetText("Forever Buffs")
  overlay:Hide()

  holder:Hide()
  UI:ApplyPosition()

  if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("EditMode.Enter", enterEdit, UI)
    EventRegistry:RegisterCallback("EditMode.Exit", exitEdit, UI)
  end

  FB:Try("options", buildOptions)
  UI:Apply()
end
