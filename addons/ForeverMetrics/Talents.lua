-- Forever Metrics: talent planner
-- Try talent builds without spending points. Your class's three trees with
-- the real talents (read with the game's talent functions); left-click adds
-- a point, right-click takes one away, with the game's rules: 5 points per
-- tier in a tree before the next tier, and talents that need another one
-- maxed first. Two budgets: your level's points (level - 9), or a level 60
-- build (51). Plans are saved per character in ForeverMetricsDB.talentPlans
-- and never touch your real talents.
--   Open: the Plan / Plan 60 buttons beside Blizzard's talent window,
--   or /fm talents (your level) and /fm talents 60.

local ADDON, ns = ...
local FM = ns.FM

local ICON, GAP_X, GAP_Y = 34, 46, 44
local TREE_W, TREE_H = 4 * GAP_X + 16, 7 * GAP_Y + 40
local win
local trees = {}     -- [tab] = { name, icon, talents = { [i] = { name, icon, tier, column, max, real, pre = { tier, column } } } }
local plan           -- { level60 = bool, ranks = { [tab] = { [i] = rank } } }

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end
local function say(msg) print("|cffe8c27aForever Metrics talents|r " .. msg) end

---------------------------------------------------------------------------
-- Reading the trees
---------------------------------------------------------------------------

local function tabName(tab)
  if not GetTalentTabInfo then return "Tree " .. tab end
  local r = { GetTalentTabInfo(tab) }
  -- clients differ: (name, icon, spent, ...) or (id, name, description, icon, spent, ...)
  if type(r[1]) == "string" then return r[1] end
  if type(r[2]) == "string" then return r[2] end
  return "Tree " .. tab
end

-- GetTalentInfo's results: most clients start with the name; some start
-- with a talent ID. Returns name, icon, tier, column, rank, max.
local function talentInfo(tab, i)
  local r = { GetTalentInfo(tab, i) }
  if type(safe(r[1])) == "number" and type(safe(r[2])) == "string" then table.remove(r, 1) end
  return safe(r[1]), safe(r[2]), tonumber(safe(r[3])), tonumber(safe(r[4])), tonumber(safe(r[5])), tonumber(safe(r[6]))
end

local function numTabs()
  if not GetNumTalentTabs then return 0 end
  local n = tonumber(safe(GetNumTalentTabs())) or 0
  if n == 0 then n = tonumber(safe(GetNumTalentTabs(false, false))) or 0 end
  return n
end

local function readTrees()
  trees = {}
  if not (GetNumTalents and GetTalentInfo) then return false end
  local found = 0
  for tab = 1, math.min(3, numTabs()) do
    local T = { name = tabName(tab), talents = {} }
    for i = 1, tonumber(safe(GetNumTalents(tab))) or 0 do
      local ok, name, icon, tier, column, rank, max = pcall(talentInfo, tab, i)
      if ok and name and tier and column and max then
        local t = { name = name, icon = icon, tier = tier, column = column, max = max, real = rank or 0 }
        if GetTalentPrereqs then
          local pt, pc = GetTalentPrereqs(tab, i)
          pt, pc = tonumber(safe(pt)), tonumber(safe(pc))
          if pt and pc then t.pre = { tier = pt, column = pc } end
        end
        T.talents[i] = t
        found = found + 1
      end
    end
    trees[tab] = T
  end
  return found > 0
end

-- /fm talents test: what this client's talent functions give back
local function describe(...)
  local out = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if issecretvalue and issecretvalue(v) then out[#out + 1] = "SECRET"
    elseif type(v) == "table" then
      local keys = {}
      for k, x in pairs(v) do if #keys < 8 then keys[#keys + 1] = tostring(k) .. "=" .. tostring(x) end end
      out[#out + 1] = "{" .. table.concat(keys, ", ") .. "}"
    else out[#out + 1] = tostring(v) end
  end
  return #out > 0 and table.concat(out, ", ") or "(nothing)"
end

local function probe()
  local function try(label, f, ...)
    if type(f) ~= "function" then say(label .. ": |cffff6b6bno such function|r"); return end
    local res = { pcall(f, ...) }
    if res[1] then say(label .. ": " .. describe(select(2, unpack(res))))
    else say(label .. ": |cffff6b6berror|r " .. tostring(res[2])) end
  end
  try("GetNumTalentTabs()", GetNumTalentTabs)
  try("GetNumTalentTabs(false, false)", GetNumTalentTabs, false, false)
  try("GetTalentTabInfo(1)", GetTalentTabInfo, 1)
  try("GetNumTalents(1)", GetNumTalents, 1)
  try("GetTalentInfo(1, 1)", GetTalentInfo, 1, 1)
  try("GetTalentPrereqs(1, 1)", GetTalentPrereqs, 1, 1)
  try("UnitCharacterPoints", UnitCharacterPoints, "player")
  say(("other talent systems: C_SpecializationInfo %s · C_ClassTalents %s · C_Traits %s · GetSpecialization %s"):format(
    type(C_SpecializationInfo), type(C_ClassTalents), type(C_Traits), type(GetSpecialization)))
  if C_SpecializationInfo and C_SpecializationInfo.GetTalentInfo then
    try("C_SpecializationInfo.GetTalentInfo({ tier = 1, column = 1 })", C_SpecializationInfo.GetTalentInfo, { tier = 1, column = 1 })
  end
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  local ui = {}
  for _, n in ipairs({ "Blizzard_TalentUI", "Blizzard_PlayerSpells", "Blizzard_ClassTalentUI" }) do
    ui[#ui + 1] = n .. " " .. (isLoaded and tostring(isLoaded(n)) or "?")
  end
  say("talent windows: " .. table.concat(ui, " · ") .. " · PlayerTalentFrame " .. type(_G.PlayerTalentFrame) ..
    " · TalentFrame " .. type(_G.TalentFrame) .. " · PlayerSpellsFrame " .. type(_G.PlayerSpellsFrame))
end

---------------------------------------------------------------------------
-- The plan and its rules
---------------------------------------------------------------------------

local function plans()
  local db = FM:DB()
  db.talentPlans = db.talentPlans or {}
  return db.talentPlans
end

local function loadPlan()
  local key = FM:CharKey() or "?"
  plans()[key] = plans()[key] or { level60 = false, ranks = {} }
  plan = plans()[key]
  for tab = 1, 3 do plan.ranks[tab] = plan.ranks[tab] or {} end
end

local function rank(tab, i) return plan.ranks[tab][i] or 0 end

local function budget()
  if plan.level60 then return 51 end
  return math.max(0, (UnitLevel("player") or 1) - 9)
end

local function spentIn(tab, belowTier)
  local n = 0
  for i, t in pairs(trees[tab].talents) do
    if not belowTier or t.tier < belowTier then n = n + rank(tab, i) end
  end
  return n
end

local function spentTotal()
  local n = 0
  for tab in pairs(trees) do n = n + spentIn(tab) end
  return n
end

local function findAt(tab, tier, column)
  for i, t in pairs(trees[tab].talents) do
    if t.tier == tier and t.column == column then return i, t end
  end
end

local function preMet(tab, t)
  if not t.pre then return true end
  local i, p = findAt(tab, t.pre.tier, t.pre.column)
  return not p or rank(tab, i) >= p.max
end

local function canAdd(tab, i)
  local t = trees[tab].talents[i]
  if rank(tab, i) >= t.max or spentTotal() >= budget() then return false end
  if spentIn(tab, t.tier) < (t.tier - 1) * 5 then return false end
  return preMet(tab, t)
end

-- Taking a point back must leave every other planned talent still allowed
local function canRemove(tab, i)
  if rank(tab, i) <= 0 then return false end
  plan.ranks[tab][i] = rank(tab, i) - 1
  local ok = true
  for j, t in pairs(trees[tab].talents) do
    if rank(tab, j) > 0 then
      if spentIn(tab, t.tier) < (t.tier - 1) * 5 or not preMet(tab, t) then ok = false; break end
    end
  end
  plan.ranks[tab][i] = rank(tab, i) + 1
  return ok
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local buttons = {}

local function refresh()
  if not win or not win:IsShown() then return end
  local total, cap = spentTotal(), budget()
  local split = {}
  for tab = 1, #trees do
    split[#split + 1] = spentIn(tab)
    win.treeTitle[tab]:SetText(("%s  |cffe8c27a%d|r"):format(trees[tab].name, spentIn(tab)))
  end
  local _, class = UnitClass("player")
  win.title:SetText(("|cffe8c27aTalent Planner|r  |cffa8977a·  %s  ·  %s|r"):format(
    (class and (class:sub(1, 1) .. class:sub(2):lower())) or "", plan.level60 and "level 60 build" or ("level " .. (UnitLevel("player") or "?"))))
  win.points:SetText(("%d / %d points   |cffa8977a(%s)|r"):format(total, cap, table.concat(split, " / ")))
  win.levelBtn:SetText(plan.level60 and "Use my level" or "Level 60 build")
  for _, b in ipairs(buttons) do
    local r, t = rank(b.tab, b.i), trees[b.tab].talents[b.i]
    b.rank:SetText(r .. "/" .. t.max)
    local open = r > 0 or canAdd(b.tab, b.i)
    b.icon:SetDesaturated(not open)
    b.icon:SetAlpha(open and 1 or 0.45)
    if r >= t.max then b.rank:SetTextColor(1, 0.82, 0.2)
    elseif r > 0 then b.rank:SetTextColor(0.5, 1, 0.5)
    else b.rank:SetTextColor(0.7, 0.7, 0.7) end
  end
end

local function talentTooltip(b)
  local t = trees[b.tab].talents[b.i]
  GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
  local shown = GameTooltip.SetTalent and pcall(GameTooltip.SetTalent, GameTooltip, b.tab, b.i)
  if not shown then GameTooltip:SetText(t.name) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(("Planned: %d/%d   (you have %d)"):format(rank(b.tab, b.i), t.max, t.real), 1, 0.82, 0.35)
  if t.pre and not preMet(b.tab, t) then
    local _, p = findAt(b.tab, t.pre.tier, t.pre.column)
    if p then GameTooltip:AddLine("Needs " .. p.name .. " maxed first", 1, 0.4, 0.4) end
  end
  if spentIn(b.tab, t.tier) < (t.tier - 1) * 5 then
    GameTooltip:AddLine(("Needs %d points in %s first"):format((t.tier - 1) * 5, trees[b.tab].name), 1, 0.4, 0.4)
  end
  GameTooltip:AddLine("Left-click: add  ·  Right-click: remove", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function build()
  win = CreateFrame("Frame", "ForeverMetricsTalentPlanner", UIParent, "BackdropTemplate")
  FM:Skin(win, { edge = 16 })
  win:SetSize(3 * TREE_W + 40, TREE_H + 110)
  win:SetPoint("CENTER")
  win:SetFrameStrata("HIGH")
  win:SetClampedToScreen(true); win:SetMovable(true); win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  tinsert(UISpecialFrames, "ForeverMetricsTalentPlanner")
  win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  win.title:SetPoint("TOPLEFT", 18, -14)
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -3, -3)
  win.points = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  win.points:SetPoint("TOPLEFT", 18, -40)

  local function button(label, w, x, fn)
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", x, 14); b:SetText(label)
    b:SetScript("OnClick", fn)
    return b
  end
  button("Start from my talents", 150, 18, function()
    for tab, T in pairs(trees) do
      plan.ranks[tab] = {}
      for i, t in pairs(T.talents) do if t.real > 0 then plan.ranks[tab][i] = t.real end end
    end
    refresh()
  end)
  button("Clear", 70, 174, function() for tab = 1, 3 do plan.ranks[tab] = {} end; refresh() end)
  win.levelBtn = button("Level 60 build", 120, 250, function()
    plan.level60 = not plan.level60
    -- dropping to your level's budget clears a plan that no longer fits
    if spentTotal() > budget() then for tab = 1, 3 do plan.ranks[tab] = {} end end
    refresh()
  end)
  local note = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("BOTTOMRIGHT", -18, 19)
  note:SetText("A plan only: your real talents aren't changed")

  win.treeTitle = {}
  for tab, T in ipairs(trees) do
    local x = 20 + (tab - 1) * TREE_W
    local bg = CreateFrame("Frame", nil, win, "BackdropTemplate")
    FM:Skin(bg, { edge = 10, alpha = 0.4 })
    bg:SetPoint("TOPLEFT", x, -64); bg:SetSize(TREE_W - 8, TREE_H)
    win.treeTitle[tab] = bg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.treeTitle[tab]:SetPoint("TOP", 0, -8)
    for i, t in pairs(T.talents) do
      local b = CreateFrame("Button", nil, bg)
      b:SetSize(ICON, ICON)
      b:SetPoint("TOPLEFT", 12 + (t.column - 1) * GAP_X, -30 - (t.tier - 1) * GAP_Y)
      b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      b.icon = b:CreateTexture(nil, "ARTWORK")
      b.icon:SetAllPoints(); b.icon:SetTexture(t.icon or 134400)
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
      b.rank = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      b.rank:SetPoint("BOTTOMRIGHT", 4, -4)
      b.tab, b.i = tab, i
      b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
          if canRemove(self.tab, self.i) then plan.ranks[self.tab][self.i] = rank(self.tab, self.i) - 1 end
        elseif canAdd(self.tab, self.i) then
          plan.ranks[self.tab][self.i] = rank(self.tab, self.i) + 1
        end
        if plan.ranks[self.tab][self.i] == 0 then plan.ranks[self.tab][self.i] = nil end
        refresh()
        if GameTooltip:IsOwned(self) then talentTooltip(self) end
      end)
      b:SetScript("OnEnter", talentTooltip)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      buttons[#buttons + 1] = b
    end
  end
  win:SetScript("OnShow", refresh)
  win:Hide()
end

function FM:OpenTalentPlanner(level60)
  if not FM:Char() then return end
  if not win then
    if not readTrees() then
      say("couldn't read your talent trees on this client. Type |cffffff00/fm talents test|r and send Claude a screenshot of what it prints.")
      return
    end
    loadPlan()
    build()
  end
  if level60 ~= nil then
    plan.level60 = level60 and true or false
    if spentTotal() > budget() then for tab = 1, 3 do plan.ranks[tab] = {} end end
  end
  win:Show()
  refresh()
end

function FM:TalentsCommand(rest)
  rest = (rest or ""):lower()
  if rest == "test" then
    local ok, err = pcall(probe)
    if not ok then say("probe error: " .. tostring(err)) end
    return
  end
  self:OpenTalentPlanner(rest == "60" and true or (rest == "" and nil or false))
end

---------------------------------------------------------------------------
-- Buttons beside Blizzard's talent window
---------------------------------------------------------------------------

local attached = false
local function attach()
  local frame = _G.PlayerTalentFrame or _G.TalentFrame
  if not frame or attached then return end
  attached = true
  local plan1 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  plan1:SetSize(86, 22)
  plan1:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, -30)
  plan1:SetText("Plan")
  plan1:SetScript("OnClick", function() FM:OpenTalentPlanner(false) end)
  local plan60 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  plan60:SetSize(86, 22)
  plan60:SetPoint("TOPLEFT", plan1, "BOTTOMLEFT", 0, -4)
  plan60:SetText("Plan lv 60")
  plan60:SetScript("OnClick", function() FM:OpenTalentPlanner(true) end)
  for _, b in ipairs({ plan1, plan60 }) do
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Talent Planner")
      GameTooltip:AddLine(self == plan60 and "Try a full level 60 build (51 points)." or "Try builds with your level's points.", 1, 1, 1, true)
      GameTooltip:AddLine("Nothing is spent; it's a plan only.", 0.7, 0.7, 0.7, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name ~= "Blizzard_TalentUI" then return end
  local ok, err = pcall(attach)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics talents error|r", err) end
end)
pcall(ev.RegisterEvent, ev, "ADDON_LOADED")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
