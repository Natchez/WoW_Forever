-- Forever Metrics: floating gains
-- Money, loot, reputation, skill-ups (and optionally XP) float up above your
-- character. New lines come in at the bottom and push older ones up, with a
-- gap between lines ("Space between lines" option). These all come from
-- chat/system events, which addons can read even where combat data is hidden.
--
-- Position: it joins Edit Mode like the feed and XP pill ("Forever Metrics
-- Floating Text"), or use /fm fct move.
--
-- No damage text: Forever forbids addons from registering
-- COMBAT_LOG_EVENT_UNFILTERED (it triggers the "blocked from an action only
-- available to the Blizzard UI" popup, which pcall can't catch). Damage
-- numbers are left to Blizzard's own combat text, whose settings are on the
-- "Blizzard" tab of the Combat Text options.

local ADDON, ns = ...
local FM = ns.FM

local DUR = 2.6          -- seconds each text floats
local DRIFT = 40         -- pixels each text drifts up on its own
local GAP = 0.12         -- seconds between texts leaving the queue
local MAX_LINES = 8      -- more than this and the oldest fade out early
local MERGE = 0.35       -- quick money/xp gains combine into one
local DEFAULT_POINT = { "CENTER", "UIParent", "CENTER", 0, 140 }

local anchor, overlay, driver
local editing = false
local pool, queue, active = {}, {}, {}
local lastSpawn = 0
local editOwner = {}

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function say(msg) print("|cffe8c27aForever Metrics|r " .. msg) end

local function cfg()
  local db = FM:DB()
  db.fctFrame = db.fctFrame or {}
  local c = db.fctFrame
  if not c.point then c.point = { unpack(DEFAULT_POINT) } end
  return c
end

local function money(c)
  if GetCoinTextureString then return GetCoinTextureString(c) end
  return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
end

local function fmtToPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
  return "^" .. p
end

---------------------------------------------------------------------------
-- Text frames + animation
---------------------------------------------------------------------------

local function fontFor(scale)
  local path, size = GameFontNormalLarge:GetFont()
  return path, math.floor((size or 16) * 1.25 * scale + 0.5), "OUTLINE"
end

local function acquire()
  local f = table.remove(pool)
  if not f then
    f = CreateFrame("Frame", nil, anchor)
    f:SetSize(1, 1)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER")
    f.text:SetShadowOffset(1, -1)
  end
  return f
end

-- Height of one line plus the gap between lines
local function lineStep()
  local _, size = fontFor(FM:GetSetting("fctScale") or 1)
  return size + (FM:GetSetting("fctSpacing") or 8)
end

local function animate(_, elapsed)
  local now = GetTime()
  -- release the next queued text; newest goes at the bottom (index 1)
  if #queue > 0 and now - lastSpawn >= GAP then
    local item = table.remove(queue, 1)
    local f = acquire()
    f.text:SetFont(fontFor(FM:GetSetting("fctScale") or 1))
    f.text:SetText(item.text)
    f.born, f.slot = now, 0
    f:SetAlpha(0)
    f:Show()
    table.insert(active, 1, f)
    lastSpawn = now
    -- too many on screen: hurry the oldest along
    for i = MAX_LINES + 1, #active do
      local old = active[i]
      old.born = math.min(old.born, now - DUR * 0.8)
    end
  end

  local step = lineStep()
  local slide = math.min(1, (elapsed or 0.016) * 12)
  for i = #active, 1, -1 do
    local f = active[i]
    local t = (now - f.born) / DUR
    if t >= 1 then
      f:Hide()
      table.remove(active, i)
      pool[#pool + 1] = f
    else
      -- glide up to this line's slot, plus a gentle drift of its own
      f.slot = f.slot + ((i - 1) - f.slot) * slide
      local ease = 1 - (1 - t) * (1 - t)
      f:ClearAllPoints()
      f:SetPoint("CENTER", anchor, "CENTER", 0, f.slot * step + DRIFT * ease)
      local pop = t < 0.06 and (1.25 - (t / 0.06) * 0.25) or 1  -- quick pop on arrival
      f:SetScale(pop)
      local a = t < 0.05 and t / 0.05 or (t > 0.7 and (1 - (t - 0.7) / 0.3) or 1)
      f:SetAlpha(math.max(0, math.min(1, a)))
    end
  end

  if #queue == 0 and #active == 0 then driver:SetScript("OnUpdate", nil) end
end

local function push(text)
  if not anchor or not FM:GetSetting("fct") then return end
  if FM:GetSetting("fctCombatHide") and UnitAffectingCombat("player") then return end
  if #queue > 12 then table.remove(queue, 1) end -- never let it fall far behind
  queue[#queue + 1] = { text = text }
  driver:SetScript("OnUpdate", animate)
end

-- Money and XP arrive in bursts (kill xp + quest xp, several coins), so
-- add them up for a moment and show one total.
local pending = {}
local function pushMerged(kind, amount, format)
  local p = pending[kind]
  if p then p.amount = p.amount + amount; return end
  pending[kind] = { amount = amount }
  C_Timer.After(MERGE, function()
    local total = pending[kind].amount
    pending[kind] = nil
    push(format(total))
  end)
end

---------------------------------------------------------------------------
-- Gains
---------------------------------------------------------------------------

local PAT_LOOT = {}
for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF_MULTIPLE",
                     "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_CREATED_SELF" }) do
  local p = fmtToPattern(_G[g])
  if p then PAT_LOOT[#PAT_LOOT + 1] = p end
end
if #PAT_LOOT == 0 then PAT_LOOT = { "^You receive loot: (.+)x(%d+)%.", "^You receive loot: (.+)%." } end

local PAT_REP   = fmtToPattern(FACTION_STANDING_INCREASED) or "^Your reputation with (.+) has increased by (%d+)%."
local PAT_SKILL = fmtToPattern(SKILL_RANK_UP) or "^Your skill in (.+) has increased to (%d+)"

local function itemQuality(link)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not f then return nil end
  local ok, _, _, q = pcall(f, link)
  return ok and q or nil
end

local function itemIcon(link)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not f then return nil end
  local ok, _, _, _, _, icon = pcall(f, link)
  return ok and icon or nil
end

local function onLoot(msg)
  if not FM:GetSetting("fctLoot") then return end
  local link, qty
  for _, p in ipairs(PAT_LOOT) do
    link, qty = msg:match(p)
    if link then break end
  end
  if not link then return end
  local q = itemQuality(link)
  if q and q < (FM:GetSetting("fctLootQuality") or 1) then return end
  local icon = itemIcon(link)
  qty = tonumber(qty) or 1
  push(("+ %s%s%s"):format(icon and ("|T" .. icon .. ":0|t ") or "", link, qty > 1 and (" x" .. qty) or ""))
end

local function onRep(msg)
  if not FM:GetSetting("fctRep") then return end
  local a, b = msg:match(PAT_REP)
  if not a then return end
  local faction, amount = a, b
  if tonumber(a) and not tonumber(b) then faction, amount = b, a end -- some locales flip the order
  push(("|cff6fa8ff+%s %s|r"):format(amount, faction))
end

local function onSkill(msg)
  if not FM:GetSetting("fctSkill") then return end
  local skill, rank = msg:match(PAT_SKILL)
  if skill then push(("|cff69ccf0+1 %s (%s)|r"):format(skill, rank)) end
end

local lastMoney, lastXP, lastMax

---------------------------------------------------------------------------
-- Edit Mode / moving
---------------------------------------------------------------------------

local function applyPosition()
  local p = cfg().point
  anchor:ClearAllPoints()
  anchor:SetPoint(p[1], UIParent, p[3], p[4], p[5])
end

local function savePosition()
  local x, y = anchor:GetCenter()
  if not x then return end
  local ux, uy = UIParent:GetCenter()
  cfg().point = { "CENTER", "UIParent", "CENTER", math.floor(x - ux + 0.5), math.floor(y - uy + 0.5) }
  applyPosition()
end

local function enterEdit()
  if not anchor then return end
  editing = true
  overlay:Show()
  anchor:EnableMouse(true)
end

local function exitEdit()
  if not anchor or not editing then return end
  editing = false
  overlay:Hide()
  anchor:EnableMouse(false)
  anchor:StopMovingOrSizing()
end

---------------------------------------------------------------------------
-- Build + events
---------------------------------------------------------------------------

local function build()
  anchor = CreateFrame("Frame", "ForeverMetricsFloatingText", UIParent)
  anchor:SetSize(220, 40)
  anchor:SetFrameStrata("MEDIUM")
  anchor:SetClampedToScreen(true)
  anchor:SetMovable(true)
  anchor:EnableMouse(false)
  anchor:RegisterForDrag("LeftButton")
  anchor:SetScript("OnDragStart", function(self) if editing then self:StartMoving() end end)
  anchor:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)

  overlay = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
  overlay:SetAllPoints()
  overlay:SetFrameLevel(anchor:GetFrameLevel() + 5)
  if overlay.SetBackdrop then
    overlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    overlay:SetBackdropColor(0.1, 0.45, 0.85, 0.25)
    overlay:SetBackdropBorderColor(0.3, 0.65, 1, 0.9)
  end
  local lbl = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lbl:SetPoint("BOTTOM", overlay, "TOP", 0, 2)
  lbl:SetText("Forever Metrics Floating Text")
  overlay:Hide()

  driver = CreateFrame("Frame")
  applyPosition()

  if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("EditMode.Enter", enterEdit, editOwner)
    EventRegistry:RegisterCallback("EditMode.Exit", exitEdit, editOwner)
  end

  lastMoney = GetMoney()
  lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
end

local ev = CreateFrame("Frame")
local H = {}

function H.PLAYER_LOGIN() build() end

function H.PLAYER_MONEY()
  local m = GetMoney()
  local d = m - (lastMoney or m)
  lastMoney = m
  if d > 0 and FM:GetSetting("fctGold") then
    pushMerged("money", d, function(total) return "+" .. money(total) end)
  end
end

function H.PLAYER_XP_UPDATE()
  local cur, max = UnitXP("player"), UnitXPMax("player")
  local gained = 0
  if lastXP then gained = cur >= lastXP and (cur - lastXP) or ((lastMax or 0) - lastXP + cur) end
  lastXP, lastMax = cur, max
  if gained > 0 and FM:GetSetting("fctXP") then
    pushMerged("xp", gained, function(total) return ("|cffd9a6ff+%d XP|r"):format(total) end)
  end
end

function H.CHAT_MSG_LOOT(msg) msg = safe(msg); if msg then onLoot(msg) end end
function H.CHAT_MSG_COMBAT_FACTION_CHANGE(msg) msg = safe(msg); if msg then onRep(msg) end end
function H.CHAT_MSG_SKILL(msg) msg = safe(msg); if msg then onSkill(msg) end end

ev:SetScript("OnEvent", function(_, event, ...)
  if event ~= "PLAYER_LOGIN" and not anchor then return end
  local ok, err = pcall(H[event], ...)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics fct error|r", event, err) end
end)
for event in pairs(H) do pcall(ev.RegisterEvent, ev, event) end

---------------------------------------------------------------------------
-- Test + slash
---------------------------------------------------------------------------

function FM:FCTTest()
  if not anchor then return end
  if not FM:GetSetting("fct") then say("floating gains are off. Turn them on first.") return end
  push("+" .. money(12345))
  push("+ |cff1eff00[Sample Green Sword]|r")
  push("|cff6fa8ff+25 Stormwind|r")
  push("|cff69ccf0+1 Mining (76)|r")
  push("|cffd9a6ff+245 XP|r")
end

function FM:FCTCommand(rest)
  rest = rest or ""
  if rest == "test" then
    FM:FCTTest()
  elseif rest == "move" then
    if editing then exitEdit(); say("floating text locked.")
    else enterEdit(); say("drag the blue box, then /fm fct move again to lock.") end
  elseif rest == "reset" then
    cfg().point = { unpack(DEFAULT_POINT) }
    if anchor then applyPosition() end
    say("floating text position reset.")
  elseif rest == "" or rest == "toggle" then
    FM:SetSetting("fct", not FM:GetSetting("fct"))
    say("floating gains " .. (FM:GetSetting("fct") and "on" or "off"))
  else
    print("/fm fct [toggle | test | move | reset]")
  end
end
