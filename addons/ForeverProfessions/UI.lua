-- Forever Professions: the /fp window and the Alt-click panel
-- Window: side nav (Overview, Recipes, Options > Tooltips), styled like
-- Forever Metrics. Overview has a card per character and profession;
-- Recipes lists one profession's recipes by colour with filters, search and
-- a detail pane. Controller: LB/RB tab or profession, D-pad U/D section or
-- recipe, A open, B back/close.

local ADDON, ns = ...
local FP = ns.FP

local W, H, NAV_W = 900, 590, 168
local CONTENT_W = W - 12 - NAV_W - 12 - 14
local ROW_H = 20
local GOLD, MUTED, FAINT, GREEN, RED = "|cffe8c27a", "|cffa8977a", "|cff7a6a55", "|cff7fd36b", "|cffff6b6b"
local DIFF_GROUP = { [0] = "Orange  ·  always a skill-up", [1] = "Yellow  ·  usually a skill-up",
                     [2] = "Green  ·  sometimes", [3] = "Grey  ·  no skill-ups" }

local win, nav, content, titleText, hint
local navButtons, tabButtons = {}, {}
local pages = {}
local ui = { sec = 1, focus = "nav", view = "ALL", pair = 1, filter = "skill", search = "", sel = 1 }

local SECTIONS = {
  { key = "overview", label = "Overview" },
  { key = "recipes",  label = "Recipes" },
  { divider = "Options" },
  { key = "tooltips", label = "Tooltips" },
}

local function an(word) return (word:match("^[AEIOUaeiou]") and "an " or "a ") .. word end
local function setColor(tex, c, a) tex:SetColorTexture(c[1], c[2], c[3], a or c[4]) end
local function secKey() return SECTIONS[ui.sec] and SECTIONS[ui.sec].key end
local function sectionIndex(key) for i, s in ipairs(SECTIONS) do if s.key == key then return i end end end

local function colored(e)
  if e.kind == "learn" then return GOLD .. (e.n or "?") .. "|r" end
  return "|cff" .. (e.diff and FP.DIFF_COLOR[e.diff] or "ffffff") .. (e.n or "?") .. "|r"
end

local function newButton(parent, label, w, h)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 80, h or 22)
  b:SetText(label)
  return b
end

-- A flat button with a gold highlight when selected (tabs, chips)
local function flatButton(parent, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(h or 24)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints(); setColor(b.bg, FP.THEME.hl, 0.14)
  b.under = b:CreateTexture(nil, "ARTWORK")
  setColor(b.under, FP.THEME.bar)
  b.under:SetPoint("BOTTOMLEFT"); b.under:SetPoint("BOTTOMRIGHT"); b.under:SetHeight(2)
  local mh = b:CreateTexture(nil, "HIGHLIGHT")
  mh:SetAllPoints(); setColor(mh, FP.THEME.hl, 0.1)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.label:SetPoint("CENTER", 0, 1)
  function b:SetOn(on)
    if on then self.bg:Show(); self.under:Show(); self.label:SetTextColor(1, 0.82, 0.35)
    else self.bg:Hide(); self.under:Hide(); self.label:SetTextColor(0.8, 0.78, 0.72) end
  end
  function b:SetLabel(t) self.label:SetText(t); self:SetWidth(self.label:GetStringWidth() + 26) end
  return b
end

local function scrollArea(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(10, 10)
  sf:SetScrollChild(child)
  return sf, child
end

local function itemTooltip(owner, e)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if e.made then pcall(GameTooltip.SetItemByID, GameTooltip, e.made)
  elseif e.spell and GameTooltip.SetSpellByID then pcall(GameTooltip.SetSpellByID, GameTooltip, e.spell)
  else GameTooltip:SetText(e.n or "?") end
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------

local OV = {}
local CARD_W = math.floor((CONTENT_W - 26 - 10) / 2)
local CARD_H = 108

local function makeTile(parent, i)
  local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  FP:Skin(t, { edge = 10, alpha = 0.5 })
  local w = math.floor((CONTENT_W - 30) / 4)
  t:SetSize(w, 46)
  t:SetPoint("TOPLEFT", (i - 1) * (w + 10), 0)
  t.big = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  t.big:SetPoint("TOPLEFT", 10, -7)
  t.small = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  t.small:SetPoint("TOPLEFT", 10, -28)
  return t
end

local function makeCard(i)
  local card = CreateFrame("Frame", nil, OV.child, "BackdropTemplate")
  FP:Skin(card, { edge = 10, alpha = 0.55 })
  card:SetSize(CARD_W, CARD_H)
  card.icon = card:CreateTexture(nil, "ARTWORK")
  card.icon:SetSize(28, 28); card.icon:SetPoint("TOPLEFT", 10, -9)
  card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  card.title:SetPoint("LEFT", card.icon, "RIGHT", 8, 0)
  card.title:SetPoint("RIGHT", card, "RIGHT", -92, 0)
  card.title:SetJustifyH("LEFT"); card.title:SetWordWrap(false)
  card.btn = newButton(card, "Recipes", 78, 20)
  card.btn:SetPoint("TOPRIGHT", -8, -12)
  card.barBG = card:CreateTexture(nil, "ARTWORK")
  card.barBG:SetColorTexture(0, 0, 0, 0.6)
  card.barBG:SetPoint("TOPLEFT", 10, -44); card.barBG:SetPoint("TOPRIGHT", -70, -44); card.barBG:SetHeight(6)
  card.fill = card:CreateTexture(nil, "ARTWORK", nil, 1)
  setColor(card.fill, FP.THEME.bar)
  card.fill:SetPoint("TOPLEFT", card.barBG); card.fill:SetHeight(6)
  card.rank = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  card.rank:SetPoint("LEFT", card.barBG, "RIGHT", 8, 0)
  card.body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  card.body:SetPoint("TOPLEFT", 10, -56); card.body:SetPoint("RIGHT", -10, 0)
  card.body:SetJustifyH("LEFT"); card.body:SetJustifyV("TOP"); card.body:SetSpacing(3)
  card.body:SetWordWrap(false)
  OV.cards[i] = card
  return card
end

local PROF_ICON = {
  Alchemy = 136240, Blacksmithing = 136241, Enchanting = 136244, Engineering = 136243, Leatherworking = 133611,
  Tailoring = 136249, Cooking = 133971, ["First Aid"] = 135966, Mining = 136248, Herbalism = 136246,
  Skinning = 134366, Fishing = 136245,
}

local function cardLines(s)
  local L = {}
  local function row(label, text) L[#L + 1] = MUTED .. label .. "|r  " .. text end
  if FP.GATHERING[s.prof] and not s.seen then
    row("Gathering ", "skill " .. s.rank .. (s.max and (" of " .. s.max) or ""))
    if s.nextSkill then row("Trainer   ", "next at skill " .. s.nextSkill)
    elseif not s.trainerSeen then row("Trainer   ", FAINT .. "visit one once to see what's next|r") end
    return table.concat(L, "\n")
  end
  if not s.seen then
    row("Recipes   ", FAINT .. "open your " .. s.prof .. " window once on this character|r")
  else
    row("Craft now ", s.craft > 0 and (s.craft .. (s.craft == 1 and " recipe" or " recipes")) or (FAINT .. "nothing with what's in your bags|r"))
  end
  if not s.trainerSeen then row("Learn now ", FAINT .. "visit " .. an(s.prof) .. " trainer once|r")
  elseif s.seen then
    row("Learn now ", s.learn > 0 and (s.learn .. "  ·  " .. FP:Money(s.learnCost)) or (FAINT .. "nothing new at your skill|r"))
  end
  if s.best then
    local r, note = s.best.r, ""
    if s.best.can > 0 then note = MUTED .. "  make " .. s.best.can .. "|r"
    elseif s.best.missing[1] then note = MUTED .. "  needs " .. FP:ItemName(s.best.missing[1].id) .. "|r" end
    row("Skill-up  ", "|cff" .. FP.DIFF_COLOR[r.diff] .. (r.n or "?") .. "|r" .. note)
  elseif s.seen and s.nextSkill then
    row("Skill-up  ", FAINT .. "all grey or green: next trainer recipe at " .. s.nextSkill .. "|r")
  end
  return table.concat(L, "\n")
end

local function viewKeys()
  local keys, me = {}, FP:CharKey()
  for key in pairs(FP:DB().chars) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    if (a == me) ~= (b == me) then return a == me end
    return a < b
  end)
  return keys
end

local function buildOverview()
  local p = CreateFrame("Frame", nil, content)
  p:SetAllPoints()
  OV.frame, OV.cards = p, {}
  OV.strip = CreateFrame("Frame", nil, p)
  OV.strip:SetPoint("TOPLEFT", 0, -34); OV.strip:SetSize(CONTENT_W, 46)
  OV.tiles = {}
  for i = 1, 4 do OV.tiles[i] = makeTile(OV.strip, i) end
  OV.scroll, OV.child = scrollArea(p)
  OV.scroll:SetPoint("TOPLEFT", 0, -88); OV.scroll:SetPoint("BOTTOMRIGHT", -26, 0)
  OV.child:SetWidth(CONTENT_W - 26)
  OV.empty = OV.child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  OV.empty:SetPoint("TOPLEFT", 6, -6); OV.empty:SetWidth(CONTENT_W - 40); OV.empty:SetJustifyH("LEFT")
  pages.overview = p
end

local function fillOverview()
  -- tabs: All characters + each character
  local keys = viewKeys()
  local views = { "ALL" }
  for _, k in ipairs(keys) do views[#views + 1] = k end
  OV.views = views
  local found = false
  for _, v in ipairs(views) do if v == ui.view then found = true end end
  if not found then ui.view = "ALL" end
  local x = 0
  for i, b in ipairs(tabButtons) do
    local v = views[i]
    if v then
      b:SetLabel(v == "ALL" and "All characters" or FP:CharName(v))
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", content, "TOPLEFT", x, 0)
      x = x + b:GetWidth() + 4
      b:SetOn(v == ui.view)
      b.onClick = function() ui.view = v; FP:Refresh() end
      b:Show()
    else b:Hide() end
  end

  local pairsList = {}
  for _, pr in ipairs(FP:Pairs()) do
    if ui.view == "ALL" or pr.key == ui.view then pairsList[#pairsList + 1] = pr end
  end
  local craft, learn, cost, chars = 0, 0, 0, {}
  for i, pr in ipairs(pairsList) do
    local s = FP:Summary(pr.key, pr.prof)
    craft, learn, cost = craft + s.craft, learn + s.learn, cost + s.learnCost
    chars[pr.key] = true
    local card = OV.cards[i] or makeCard(i)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", ((i - 1) % 2) * (CARD_W + 10), -math.floor((i - 1) / 2) * (CARD_H + 8))
    card.icon:SetTexture(PROF_ICON[pr.prof] or 134400)
    card.title:SetText(pr.prof .. "  " .. MUTED .. "·|r " .. FP:CharName(pr.key))
    local max = s.max or ((s.rank <= 75 and 75) or (s.rank <= 150 and 150) or (s.rank <= 225 and 225) or 300)
    card.rank:SetText(s.rank .. " / " .. max)
    card.fill:SetWidth(math.max(0.001, (CARD_W - 80) * math.min(1, s.rank / max)))
    card.body:SetText(cardLines(s))
    local hasRecipes = s.seen or (s.trainerSeen and not FP.GATHERING[pr.prof])
    if hasRecipes then
      card.btn:Show()
      card.btn:SetScript("OnClick", function() FP:OpenPair(pr.key, pr.prof) end)
    else card.btn:Hide() end
    card:Show()
  end
  for i = #pairsList + 1, #OV.cards do OV.cards[i]:Hide() end
  local n = 0
  for _ in pairs(chars) do n = n + 1 end
  local T = OV.tiles
  T[1].big:SetText(#pairsList); T[1].small:SetText((#pairsList == 1 and "profession" or "professions") .. "  ·  " .. n .. (n == 1 and " character" or " characters"))
  T[2].big:SetText(craft); T[2].small:SetText("recipes you can craft now")
  T[3].big:SetText(learn); T[3].small:SetText("to learn at trainers")
  T[4].big:SetText(FP:Money(cost)); T[4].small:SetText("to train them all")
  OV.child:SetHeight(math.ceil(#pairsList / 2) * (CARD_H + 8) + 10)
  if #pairsList == 0 then
    OV.empty:SetText(MUTED .. "No professions yet. Open a profession window, or visit a trainer, and they'll show up here.|r")
    OV.empty:Show()
  else OV.empty:Hide() end
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

local RC = { rows = {}, mats = {} }
local LIST_W = 300
local FILTERS = { { "skill", "Skill-ups" }, { "make", "Can make" }, { "learn", "Learnable" }, { "all", "All" } }

local function matchesSearch(e, q)
  if q == "" then return true end
  if (e.n or ""):lower():find(q, 1, true) then return true end
  for _, g in ipairs(e.reagents or {}) do
    if FP:ItemName(g.id):lower():find(q, 1, true) then return true end
  end
  return false
end

local function passes(e, f)
  if f == "skill" then return e.kind == "known" and e.diff and e.diff <= 1 end
  if f == "make" then return e.kind == "known" and (e.canMake or 0) > 0 end
  if f == "learn" then return e.kind == "learn" end
  return true
end

-- The list for the current profession, as rows: headers and recipes
local function recipeRows()
  local pairsList = FP:Pairs()
  RC.pairs = pairsList
  if #pairsList == 0 then return {} end
  ui.pair = math.max(1, math.min(ui.pair, #pairsList))
  local pr = pairsList[ui.pair]
  local q = ui.search:lower()
  local rows, lastGroup = {}, nil
  for _, e in ipairs(FP:RecipeList(pr.key, pr.prof)) do
    if passes(e, ui.filter) and matchesSearch(e, q) then
      local g = e.kind == "learn" and "Learn at trainer" or (e.diff and DIFF_GROUP[e.diff]) or "Just learned  ·  open the window for colours"
      if g ~= lastGroup then rows[#rows + 1] = { header = g }; lastGroup = g end
      rows[#rows + 1] = e
    end
  end
  return rows
end

local function getRow(i)
  if RC.rows[i] then return RC.rows[i] end
  local r = CreateFrame("Button", nil, RC.child)
  r:SetSize(LIST_W - 30, ROW_H)
  r:SetPoint("TOPLEFT", 4, -(i - 1) * ROW_H - 4)
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints(); setColor(r.sel, FP.THEME.hl, 0.35)
  local mh = r:CreateTexture(nil, "HIGHLIGHT")
  mh:SetAllPoints(); setColor(mh, FP.THEME.hl, 0.12)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 2, 0)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r, "RIGHT", -70, 0)
  r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  r.note = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.note:SetPoint("RIGHT", -4, 0)
  r.hdr = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.hdr:SetPoint("LEFT", 2, -2)
  r:SetScript("OnClick", function(self) if self.entry then ui.sel = self.index; FP:Refresh() end end)
  r:SetScript("OnEnter", function(self) if self.entry then itemTooltip(self, self.entry) end end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  RC.rows[i] = r
  return r
end

local function getMat(i)
  if RC.mats[i] then return RC.mats[i] end
  local m = CreateFrame("Frame", nil, RC.detail)
  m:SetSize(10, 24)
  m:SetPoint("TOPLEFT", 14, -104 - (i - 1) * 26); m:SetPoint("RIGHT", RC.detail, "RIGHT", -14, 0)
  m.icon = m:CreateTexture(nil, "ARTWORK")
  m.icon:SetSize(20, 20); m.icon:SetPoint("LEFT")
  m.name = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  m.name:SetPoint("LEFT", m.icon, "RIGHT", 8, 0)
  m.have = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  m.have:SetPoint("RIGHT")
  RC.mats[i] = m
  return m
end

local function buildRecipes()
  local p = CreateFrame("Frame", nil, content)
  p:SetAllPoints()
  RC.frame = p
  RC.prev = newButton(p, "<", 26, 22); RC.prev:SetPoint("TOPLEFT", 0, -2)
  RC.prev:SetScript("OnClick", function() FP:CyclePair(-1) end)
  RC.label = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  RC.label:SetPoint("LEFT", RC.prev, "RIGHT", 10, 0)
  RC.next = newButton(p, ">", 26, 22)
  RC.next:SetScript("OnClick", function() FP:CyclePair(1) end)

  RC.search = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  RC.search:SetSize(190, 20); RC.search:SetPoint("TOPRIGHT", -4, -3)
  RC.search:SetAutoFocus(false)
  RC.search:SetScript("OnTextChanged", function(self, user)
    if user then ui.search = self:GetText() or ""; ui.sel = 1; FP:Refresh() end
  end)
  RC.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  RC.searchHint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  RC.searchHint:SetPoint("LEFT", RC.search, "LEFT", 2, 0)
  RC.searchHint:SetText("Search recipes or materials")

  RC.chips = {}
  local x = 0
  for i, f in ipairs(FILTERS) do
    local b = flatButton(p, 22)
    b:SetLabel(f[2]); b:SetPoint("TOPLEFT", x, -32)
    x = x + b:GetWidth() + 4
    b:SetScript("OnClick", function() ui.filter = f[1]; ui.sel = 1; FP:Refresh() end)
    RC.chips[i] = b
  end

  RC.listBox = CreateFrame("Frame", nil, p, "BackdropTemplate")
  FP:Skin(RC.listBox, { edge = 10, alpha = 0.5 })
  RC.listBox:SetPoint("TOPLEFT", 0, -60); RC.listBox:SetPoint("BOTTOMLEFT", 0, 0); RC.listBox:SetWidth(LIST_W)
  RC.scroll, RC.child = scrollArea(RC.listBox)
  RC.scroll:SetPoint("TOPLEFT", 4, -4); RC.scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  RC.child:SetWidth(LIST_W - 30)
  RC.empty = RC.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  RC.empty:SetPoint("TOPLEFT", 8, -8); RC.empty:SetWidth(LIST_W - 50); RC.empty:SetJustifyH("LEFT")

  local d = CreateFrame("Frame", nil, p, "BackdropTemplate")
  FP:Skin(d, { edge = 10, alpha = 0.5 })
  d:SetPoint("TOPLEFT", LIST_W + 10, -60); d:SetPoint("BOTTOMRIGHT", 0, 0)
  RC.detail = d
  d.icon = d:CreateTexture(nil, "ARTWORK")
  d.icon:SetSize(40, 40); d.icon:SetPoint("TOPLEFT", 14, -14)
  d.name = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -2); d.name:SetPoint("RIGHT", -14, 0)
  d.name:SetJustifyH("LEFT"); d.name:SetWordWrap(false)
  d.sub = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -5); d.sub:SetPoint("RIGHT", -14, 0); d.sub:SetJustifyH("LEFT")
  d.mh = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.mh:SetPoint("TOPLEFT", 14, -78); d.mh:SetText("Materials")
  d.summary = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  d.summary:SetPoint("LEFT", 14, 0); d.summary:SetPoint("RIGHT", -14, 0); d.summary:SetJustifyH("LEFT")
  d.link = newButton(d, "Link in chat", 110, 22)
  d.link:SetPoint("BOTTOMLEFT", 14, 14)
  d.link:SetScript("OnClick", function()
    local e = RC.current
    if not e then return end
    local link = e.made and FP:ItemLink(e.made)
    if not link and e.spell then
      local f = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
      link = f and FP.safe(f(e.spell))
    end
    link = link or e.n
    if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
    if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
  end)
  d.empty = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  d.empty:SetPoint("TOPLEFT", 14, -14); d.empty:SetPoint("RIGHT", -14, 0); d.empty:SetJustifyH("LEFT")
  pages.recipes = p
end

local function fillDetail(e, pr)
  local d = RC.detail
  RC.current = e
  for _, m in ipairs(RC.mats) do m:Hide() end
  if not e then
    d.icon:Hide(); d.name:SetText(""); d.sub:SetText(""); d.mh:Hide(); d.summary:SetText(""); d.link:Hide()
    d.empty:SetText(MUTED .. "Pick a recipe on the left.|r"); d.empty:Show()
    return
  end
  d.empty:Hide(); d.icon:Show(); d.mh:Show(); d.link:Show()
  d.icon:SetTexture(e.icon or (e.made and FP:ItemIcon(e.made)) or 134400)
  d.name:SetText(colored(e))
  if e.kind == "learn" then
    d.sub:SetText(pr.prof .. MUTED .. "  ·  learn at a trainer: " .. FP:Money(e.cost or 0) .. ", needs skill " .. (e.skill or "?") .. "|r")
  else
    d.sub:SetText(pr.prof .. MUTED .. "  ·  |r" .. (e.diff and ("|cff" .. FP.DIFF_COLOR[e.diff] .. FP.DIFF_LABEL[e.diff] .. "|r")
      or (MUTED .. "just learned: open your " .. pr.prof .. " window to see its colour|r")))
  end
  local regs = e.reagents or {}
  for i, g in ipairs(regs) do
    local m = getMat(i)
    m.icon:SetTexture(FP:ItemIcon(g.id))
    local p = FP:Price(g.id)
    m.name:SetText(FP:ItemName(g.id) .. MUTED .. "  ×" .. g.c .. (p and ("  ·  " .. FP:Money(p * g.c)) or "") .. "|r")
    local have = FP:Have(pr.key, g.id)
    if have >= g.c then
      m.have:SetText(GREEN .. "have " .. have .. "|r")
    else
      local alt, n = FP:WhoHas(g.id, g.c - have, pr.key)
      m.have:SetText(RED .. have .. " / " .. g.c .. "|r" .. (alt and (MUTED .. "  ·  |r" .. FP:CharName(alt, true) .. MUTED .. " has " .. n .. "|r") or ""))
    end
    m:Show()
  end
  d.summary:ClearAllPoints()
  d.summary:SetPoint("TOPLEFT", 14, -110 - #regs * 26); d.summary:SetPoint("RIGHT", -14, 0)
  -- AH: what the materials cost, what the item sells for, and the difference
  local money = ""
  if #regs > 0 then
    local cost, unpriced = FP:MaterialsCost(regs)
    local sells = e.made and FP:Price(e.made)
    local parts = {}
    if unpriced < #regs then
      parts[#parts + 1] = "Materials " .. FP:Money(cost) .. (unpriced > 0 and (MUTED .. " (" .. unpriced .. " not priced)|r") or "")
    end
    if sells then parts[#parts + 1] = "Sells for " .. FP:Money(sells) end
    if sells and unpriced == 0 then
      local diff = sells - cost
      parts[#parts + 1] = (diff >= 0 and (GREEN .. "Profit |r") or (RED .. "Loss |r")) .. FP:Money(math.abs(diff))
    end
    if #parts > 0 then money = "\n\n" .. table.concat(parts, MUTED .. "   ·   |r") end
    if #parts == 0 and FP:GetSetting("tipPrice") then
      money = "\n\n" .. FAINT .. "No AH prices yet: click Price materials beside the auction house window.|r"
    end
  end
  if #regs == 0 then
    d.summary:SetText(MUTED .. "Materials not known yet. They fill in once any of your characters learns this recipe.|r")
  elseif e.kind == "learn" then
    d.summary:SetText(MUTED .. "Learn it, then you could make " .. FP:CanMake(pr.key, regs) .. " with what you have.|r")
  else
    local can = FP:CanMake(pr.key, regs)
    d.summary:SetText(can > 0 and ("You can make " .. GREEN .. can .. "|r.") or (MUTED .. "You can't make this yet.|r"))
  end
  if money ~= "" then d.summary:SetText(d.summary:GetText() .. money) end
end

local function fillRecipes()
  for _, b in ipairs(tabButtons) do b:Hide() end
  local rows = recipeRows()
  local pr = RC.pairs[ui.pair]
  if not pr then
    RC.label:SetText(MUTED .. "No professions yet|r"); RC.next:Hide()
    for _, r in ipairs(RC.rows) do r:Hide() end
    RC.empty:SetText(MUTED .. "Open a profession window on any character and its recipes show up here.|r"); RC.empty:Show()
    fillDetail(nil)
    return
  end
  RC.label:SetText(pr.prof .. MUTED .. "  ·  |r" .. FP:CharName(pr.key) .. FAINT .. "   " .. ui.pair .. " of " .. #RC.pairs .. "|r")
  RC.next:ClearAllPoints(); RC.next:SetPoint("LEFT", RC.label, "RIGHT", 10, 0); RC.next:Show()
  for i, f in ipairs(FILTERS) do RC.chips[i]:SetOn(ui.filter == f[1]) end
  if (RC.search:GetText() or "") ~= ui.search then RC.search:SetText(ui.search) end
  if ui.search == "" and not RC.search:HasFocus() then RC.searchHint:Show() else RC.searchHint:Hide() end

  -- recipe rows only (headers can't be selected)
  local recipeIdx = {}
  for i, r in ipairs(rows) do if not r.header then recipeIdx[#recipeIdx + 1] = i end end
  RC.recipeIdx = recipeIdx
  if not rows[ui.sel] or rows[ui.sel].header then ui.sel = recipeIdx[1] or 1 end

  for i, e in ipairs(rows) do
    local r = getRow(i)
    r.index = i
    if e.header then
      r.entry = nil
      r.icon:Hide(); r.name:Hide(); r.note:Hide(); r.sel:Hide()
      r.hdr:SetText(e.header:upper()); r.hdr:Show()
    else
      r.entry = e
      r.hdr:Hide(); r.icon:Show(); r.name:Show(); r.note:Show()
      r.icon:SetTexture(e.icon or (e.made and FP:ItemIcon(e.made)) or 134400)
      r.name:SetText(colored(e))
      if e.kind == "learn" then r.note:SetText(FP:Money(e.cost or 0))
      elseif (e.canMake or 0) > 0 then r.note:SetText(GREEN .. "make " .. e.canMake .. "|r")
      elseif #(e.missing or {}) > 0 then r.note:SetText(MUTED .. #e.missing .. " missing|r")
      else r.note:SetText("") end
      if i == ui.sel then r.sel:Show() else r.sel:Hide() end
    end
    r:Show()
  end
  for i = #rows + 1, #RC.rows do RC.rows[i]:Hide() end
  RC.child:SetHeight(#rows * ROW_H + 10)
  if #rows == 0 then
    local why = ui.search ~= "" and "Nothing matches your search." or
      ({ skill = "No skill-ups here right now. Try All.", make = "Nothing you can make with what's in your bags.",
         learn = "Nothing to learn at your skill. Visit the trainer again after skilling up." })[ui.filter] or "No recipes yet."
    RC.empty:SetText(MUTED .. why .. "|r"); RC.empty:Show()
  else RC.empty:Hide() end
  fillDetail(rows[ui.sel] and not rows[ui.sel].header and rows[ui.sel] or nil, pr)
end

---------------------------------------------------------------------------
-- Options (Tooltips)
---------------------------------------------------------------------------

local OP = { rows = {} }
local function buildOptions()
  local p = CreateFrame("Frame", nil, content)
  p:SetAllPoints()
  local y = -4
  for _, d in ipairs(FP.SETTINGS) do
    if d.group == "tooltip" then
      local row = CreateFrame("Button", nil, p)
      row:SetSize(CONTENT_W - 20, 28); row:SetPoint("TOPLEFT", 0, y)
      row.sel = row:CreateTexture(nil, "BACKGROUND")
      row.sel:SetAllPoints(); setColor(row.sel, FP.THEME.hl)
      row.cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
      row.cb:SetSize(24, 24); row.cb:SetPoint("LEFT", 8, 0)
      row.cb:SetScript("OnClick", function(self) FP:SetSetting(d.key, self:GetChecked() and true or false) end)
      row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.label:SetPoint("LEFT", row.cb, "RIGHT", 6, 0); row.label:SetText(d.label)
      row:SetScript("OnClick", function() FP:SetSetting(d.key, not FP:GetSetting(d.key)) end)
      row.def = d
      OP.rows[#OP.rows + 1] = row
      y = y - 30
    end
  end
  local note = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 10, y - 12); note:SetWidth(CONTENT_W - 30); note:SetJustifyH("LEFT"); note:SetSpacing(3)
  note:SetText(MUTED .. "Hover an item for one line. Hold Shift for its top three recipes. Alt-click it (in your bags, the bank or a chat link) for every recipe that uses it.\n\n" ..
    "Other characters' recipes and bags update when you log in on them. The bank updates when you open it.|r")
  pages.tooltips = p
end

local function fillOptions()
  for _, b in ipairs(tabButtons) do b:Hide() end
  for i, row in ipairs(OP.rows) do
    row.cb:SetChecked(FP:GetSetting(row.def.key) and true or false)
    if ui.focus == "content" and i == ui.sel and win.usesPad then row.sel:Show() else row.sel:Hide() end
  end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function updateHint()
  if not win.usesPad then hint:SetText("Drag to move  ·  Esc to close  ·  Alt-click an item to see every recipe using it"); return end
  local k, parts = secKey(), {}
  if k == "overview" then parts[#parts + 1] = "LB/RB: character" elseif k == "recipes" then parts[#parts + 1] = "LB/RB: profession" end
  if ui.focus == "nav" then
    parts[#parts + 1] = "D-pad U/D: section"
    if k ~= "overview" then parts[#parts + 1] = "A: enter" end
    parts[#parts + 1] = "B: close"
  else
    parts[#parts + 1] = k == "recipes" and "D-pad U/D: recipe  ·  X: filter" or "D-pad U/D: pick  ·  A: toggle"
    parts[#parts + 1] = "B: back"
  end
  hint:SetText(table.concat(parts, "     "))
end

local refreshQueued = false
function FP:Refresh()
  if not win or not win:IsShown() then return end
  for i, b in pairs(navButtons) do
    if i == ui.sec then b.sel:Show(); b.bar:Show(); b.label:SetTextColor(1, 0.82, 0.35)
    else b.sel:Hide(); b.bar:Hide(); b.label:SetTextColor(0.85, 0.83, 0.78) end
  end
  local k = secKey()
  titleText:SetText(GOLD .. "Forever Professions|r |cff8a7a64v" .. FP.VERSION .. "|r  " .. MUTED .. "·  " .. SECTIONS[ui.sec].label .. "|r")
  for key, p in pairs(pages) do if key == k then p:Show() else p:Hide() end end
  if k == "overview" then fillOverview() elseif k == "recipes" then fillRecipes() else fillOptions() end
  updateHint()
end

-- Redraw what's open shortly after saved data changes (scans come in bursts)
FP:OnChanged(function()
  if refreshQueued then return end
  local mainOpen = win and win:IsShown()
  local usesOpen = FP.uses and FP.uses:IsShown() and FP.uses.item
  if not mainOpen and not usesOpen then return end
  refreshQueued = true
  C_Timer.After(0.3, function()
    refreshQueued = false
    if win and win:IsShown() then FP:Try("refresh", FP.Refresh, FP) end
    if FP.uses and FP.uses:IsShown() and FP.uses.item then FP:Try("uses", FP.ShowUses, FP, FP.uses.item, true) end
  end)
end)

local function selectSection(i)
  if not SECTIONS[i] or SECTIONS[i].divider then return end
  ui.sec, ui.sel = i, 1
  FP:Refresh()
end

function FP:CyclePair(dir)
  local n = #(RC.pairs or FP:Pairs())
  if n == 0 then return end
  ui.pair = ((ui.pair - 1 + dir) % n) + 1
  ui.sel = 1
  if RC.scroll then RC.scroll:SetVerticalScroll(0) end
  FP:Refresh()
end

local function cycleView(dir)
  local v = OV.views or { "ALL" }
  local idx = 1
  for i, k in ipairs(v) do if k == ui.view then idx = i end end
  ui.view = v[((idx - 1 + dir) % #v) + 1]
  FP:Refresh()
end

local function moveRecipe(dir)
  local idx = RC.recipeIdx or {}
  if #idx == 0 then return end
  local pos = 1
  for i, v in ipairs(idx) do if v == ui.sel then pos = i end end
  pos = math.max(1, math.min(#idx, pos + dir))
  ui.sel = idx[pos]
  FP:Refresh()
  local top = (ui.sel - 1) * ROW_H
  local view, cur = RC.scroll:GetHeight(), RC.scroll:GetVerticalScroll()
  if top < cur then RC.scroll:SetVerticalScroll(top)
  elseif top + ROW_H > cur + view then RC.scroll:SetVerticalScroll(top + ROW_H - view + 8) end
end

local function moveSection(dir)
  local i = ui.sec
  for _ = 1, #SECTIONS do
    i = ((i - 1 + dir) % #SECTIONS) + 1
    if not SECTIONS[i].divider then break end
  end
  selectSection(i)
end

local PAD = {
  PADLSHOULDER = function() if secKey() == "recipes" then FP:CyclePair(-1) elseif secKey() == "overview" then cycleView(-1) end end,
  PADRSHOULDER = function() if secKey() == "recipes" then FP:CyclePair(1) elseif secKey() == "overview" then cycleView(1) end end,
  PADDUP = function()
    if ui.focus == "nav" then moveSection(-1)
    elseif secKey() == "recipes" then moveRecipe(-1)
    elseif secKey() == "tooltips" then ui.sel = math.max(1, ui.sel - 1); FP:Refresh()
    else OV.scroll:SetVerticalScroll(math.max(0, OV.scroll:GetVerticalScroll() - 60)) end
  end,
  PADDDOWN = function()
    if ui.focus == "nav" then moveSection(1)
    elseif secKey() == "recipes" then moveRecipe(1)
    elseif secKey() == "tooltips" then ui.sel = math.min(#OP.rows, ui.sel + 1); FP:Refresh()
    else OV.scroll:SetVerticalScroll(math.min(OV.scroll:GetVerticalScrollRange(), OV.scroll:GetVerticalScroll() + 60)) end
  end,
  PAD1 = function()
    if ui.focus == "nav" then
      if secKey() ~= "overview" then ui.focus = "content"; ui.sel = 1; FP:Refresh() end
    elseif secKey() == "tooltips" then
      local row = OP.rows[ui.sel]
      if row then FP:SetSetting(row.def.key, not FP:GetSetting(row.def.key)) end
    end
  end,
  PAD2 = function() if ui.focus == "content" then ui.focus = "nav"; FP:Refresh() else win:Hide() end end,
  PAD3 = function() -- X: next filter
    if secKey() ~= "recipes" then return end
    for i, f in ipairs(FILTERS) do
      if f[1] == ui.filter then ui.filter = FILTERS[(i % #FILTERS) + 1][1]; break end
    end
    ui.sel = 1; FP:Refresh()
  end,
}

local function setPropagate(frame, on)
  if InCombatLockdown() then return end
  if frame.SetPropagateGamePadInput then pcall(frame.SetPropagateGamePadInput, frame, on) end
end

local function setupGamepad()
  if not win.EnableGamePadButton then return false end
  win:EnableGamePadButton(true)
  win:SetScript("OnGamePadButtonDown", function(self, button)
    local fn = PAD[button]
    setPropagate(self, not fn)
    if fn then FP:Try("pad", fn) end
  end)
  return true
end

local function build()
  win = CreateFrame("Frame", "ForeverProfessionsFrame", UIParent, "BackdropTemplate")
  FP:Skin(win, { edge = 16 })
  win:SetSize(W, H); win:SetPoint("CENTER")
  win:SetClampedToScreen(true); win:SetMovable(true); win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetFrameStrata("HIGH")
  tinsert(UISpecialFrames, "ForeverProfessionsFrame")

  titleText = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleText:SetPoint("TOPLEFT", 20, -15)
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -3, -3)
  close:SetScript("OnClick", function() win:Hide() end)
  local rule = win:CreateTexture(nil, "ARTWORK")
  setColor(rule, FP.THEME.border, 0.35)
  rule:SetPoint("TOPLEFT", 16, -40); rule:SetPoint("TOPRIGHT", -16, -40); rule:SetHeight(1)

  nav = CreateFrame("Frame", nil, win, "BackdropTemplate")
  FP:Skin(nav, { edge = 10, alpha = 0.45 })
  nav:SetPoint("TOPLEFT", 12, -48); nav:SetPoint("BOTTOMLEFT", 12, 34); nav:SetWidth(NAV_W)
  local y = -8
  for i, s in ipairs(SECTIONS) do
    if s.divider then
      y = y - 6
      local d = nav:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      d:SetPoint("TOPLEFT", 14, y - 4); d:SetText(s.divider:upper())
      local line = nav:CreateTexture(nil, "ARTWORK")
      setColor(line, FP.THEME.border, 0.25)
      line:SetPoint("LEFT", d, "RIGHT", 6, 0); line:SetPoint("RIGHT", nav, "RIGHT", -10, 0); line:SetHeight(1)
      y = y - 22
    else
      local b = CreateFrame("Button", nil, nav)
      b:SetSize(NAV_W - 12, 26); b:SetPoint("TOPLEFT", 6, y)
      b.sel = b:CreateTexture(nil, "BACKGROUND"); b.sel:SetAllPoints(); setColor(b.sel, FP.THEME.hl)
      b.bar = b:CreateTexture(nil, "ARTWORK"); setColor(b.bar, FP.THEME.bar)
      b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
      local mh = b:CreateTexture(nil, "HIGHLIGHT"); mh:SetAllPoints(); setColor(mh, FP.THEME.hl, 0.1)
      b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      b.label:SetPoint("LEFT", 14, 0); b.label:SetText(s.label)
      b:SetScript("OnClick", function() ui.focus = "nav"; selectSection(i) end)
      navButtons[i] = b
      y = y - 28
    end
  end

  content = CreateFrame("Frame", nil, win)
  content:SetPoint("TOPLEFT", 12 + NAV_W + 12, -48)
  content:SetPoint("BOTTOMRIGHT", -14, 34)
  for i = 1, 8 do
    local b = flatButton(content, 26)
    b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    b:Hide()
    tabButtons[i] = b
  end

  buildOverview(); buildRecipes(); buildOptions()

  hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOM", 0, 13)
  win:SetScript("OnShow", function() ui.focus = "nav"; FP:Try("refresh", FP.Refresh, FP) end)
  win:SetScript("OnHide", function(self) setPropagate(self, true) end)
  win.usesPad = setupGamepad()
  win:Hide()
end

function FP:OpenAt(key)
  if not self:Char() then return end
  if not win then build() end
  ui.sec = sectionIndex(key) or 1
  ui.focus = "nav"
  if win:IsShown() then self:Refresh() else win:Show() end
end

function FP:Toggle()
  if not self:Char() then return end
  if not win then build() end
  if win:IsShown() then win:Hide() else win:Show() end
end

-- Recipes page on one character's profession
function FP:OpenPair(key, prof)
  for i, pr in ipairs(self:Pairs()) do
    if pr.key == key and pr.prof == prof then ui.pair = i end
  end
  ui.sel, ui.filter = 1, "all"
  self:OpenAt("recipes")
end

-- Recipes page searching for text (a recipe or material name); jumps to the
-- first profession with a match
function FP:OpenRecipes(text)
  ui.search, ui.filter, ui.sel = text or "", "all", 1
  local q = ui.search:lower()
  if q ~= "" then
    local found
    for i, pr in ipairs(self:Pairs()) do
      for _, e in ipairs(self:RecipeList(pr.key, pr.prof)) do
        if matchesSearch(e, q) then found = i; break end
      end
      if found then break end
    end
    if found then ui.pair = found end
  end
  self:OpenAt("recipes")
end

---------------------------------------------------------------------------
-- Alt-click panel: every recipe that uses one item
---------------------------------------------------------------------------

local UP = { rows = {} }

local function buildUses()
  local f = CreateFrame("Frame", "ForeverProfessionsUses", UIParent, "BackdropTemplate")
  FP:Skin(f, { edge = 14 })
  f:SetSize(380, 420); f:SetPoint("CENTER", 260, 40)
  f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("DIALOG")
  tinsert(UISpecialFrames, "ForeverProfessionsUses")
  f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(26, 26); f.icon:SetPoint("TOPLEFT", 14, -12)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("LEFT", f.icon, "RIGHT", 8, 0); f.title:SetPoint("RIGHT", f, "RIGHT", -36, 0)
  f.title:SetJustifyH("LEFT"); f.title:SetWordWrap(false)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  local rule = f:CreateTexture(nil, "ARTWORK"); setColor(rule, FP.THEME.border, 0.35)
  rule:SetPoint("TOPLEFT", 12, -46); rule:SetPoint("TOPRIGHT", -12, -46); rule:SetHeight(1)
  f.scroll, f.child = scrollArea(f)
  f.scroll:SetPoint("TOPLEFT", 10, -52); f.scroll:SetPoint("BOTTOMRIGHT", -30, 44)
  f.child:SetWidth(340)
  f.open = newButton(f, "Open in Recipes", 130, 22)
  f.open:SetPoint("BOTTOMLEFT", 14, 12)
  f.open:SetScript("OnClick", function() FP:OpenRecipes(FP:ItemName(f.item)); f:Hide() end)
  FP.uses = f
  return f
end

local function usesRow(i)
  if UP.rows[i] then return UP.rows[i] end
  local f = FP.uses
  local r = CreateFrame("Button", nil, f.child)
  r:SetSize(338, ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  local mh = r:CreateTexture(nil, "HIGHLIGHT"); mh:SetAllPoints(); setColor(mh, FP.THEME.hl, 0.12)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 4, 0)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r, "RIGHT", -130, 0)
  r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  r.note = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.note:SetPoint("RIGHT", -4, 0); r.note:SetJustifyH("RIGHT"); r.note:SetWidth(126); r.note:SetWordWrap(false)
  r.hdr = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.hdr:SetPoint("LEFT", 4, -2)
  r:SetScript("OnEnter", function(self) if self.entry then itemTooltip(self, self.entry) end end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self)
    if self.entry then FP:OpenPair(self.entry.key, self.entry.prof); FP.uses:Hide() end
  end)
  UP.rows[i] = r
  return r
end

function FP:ShowUses(item, keepPos)
  local f = self.uses or buildUses()
  local u = self:Uses(item)
  if not u then return end
  f.item = item
  f.icon:SetTexture(self:ItemIcon(item))
  local total = #u.list
  f.title:SetText(GOLD .. self:ItemName(item) .. "|r  " .. MUTED .. "·  " .. total .. (total == 1 and " recipe" or " recipes") .. "|r")
  local groups = { { "Skill-ups", {} }, { "Can make", {} }, { "Other recipes", {} }, { "Learn at trainer", {} } }
  for _, e in ipairs(u.list) do
    local g = e.kind == "learn" and 4 or ((e.diff and e.diff <= 1) and 1 or ((e.canMake or 0) > 0 and 2 or 3))
    table.insert(groups[g][2], e)
  end
  local i = 0
  for _, g in ipairs(groups) do
    if #g[2] > 0 then
      i = i + 1
      local h = usesRow(i)
      h.entry = nil; h.icon:Hide(); h.name:Hide(); h.note:Hide()
      h.hdr:SetText(g[1]:upper()); h.hdr:Show(); h:Show()
      for _, e in ipairs(g[2]) do
        i = i + 1
        local r = usesRow(i)
        r.entry = e
        r.hdr:Hide(); r.icon:Show(); r.name:Show(); r.note:Show()
        r.icon:SetTexture(e.icon or (e.made and self:ItemIcon(e.made)) or 134400)
        r.name:SetText(colored(e) .. MUTED .. "  ×" .. (e.need or 1) .. "|r")
        r.note:SetText(self:EntryNote(e, item))
        r:Show()
      end
    end
  end
  for j = i + 1, #UP.rows do UP.rows[j]:Hide() end
  f.child:SetHeight(i * ROW_H + 8)
  if not keepPos then f.scroll:SetVerticalScroll(0) end
  f:Show()
end

---------------------------------------------------------------------------
-- A "/fp" button just outside the right edge of the profession window
-- (modern Professions window, or Classic's trade skill and craft windows),
-- opening the Recipes page on the profession that's open.
---------------------------------------------------------------------------

local function openProfession()
  local prof = FP.lastProf
  local T = C_TradeSkillUI
  if T and T.GetBaseProfessionInfo then
    local ok, info = pcall(T.GetBaseProfessionInfo)
    local n = ok and type(info) == "table" and FP.safe(info.professionName)
    if n and n ~= "" then prof = n end
  end
  if GetTradeSkillLine and _G.TradeSkillFrame and _G.TradeSkillFrame:IsShown() then
    local n = FP.safe((GetTradeSkillLine()))
    if n and n ~= "" and n ~= "UNKNOWN" then prof = n end
  end
  if GetCraftDisplaySkillLine and _G.CraftFrame and _G.CraftFrame:IsShown() then
    local n = FP.safe((GetCraftDisplaySkillLine()))
    if n and n ~= "" then prof = n end
  end
  if prof then FP:OpenPair(FP:CharKey(), prof) else FP:OpenAt("recipes") end
end

local function attachButton(frame)
  if not frame or frame.__fpButton then return end
  local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  b:SetSize(46, 24)
  b:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, -30)
  b:SetText("/fp")
  b:SetScript("OnClick", function() FP:Try("profession button", openProfession) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Forever Professions")
    GameTooltip:AddLine("Open this profession's recipes: skill-ups, what you can make, and what to learn.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.__fpButton = b
  if not FP:GetSetting("profButton") then b:Hide() end
end

local function attachAll()
  for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
    if _G[name] then FP:Try("profession button", attachButton, _G[name]) end
  end
end

FP:On("TRADE_SKILL_SHOW", attachAll)
FP:On("CRAFT_SHOW", attachAll)
FP:On("ADDON_LOADED", function(name)
  if name == "Blizzard_Professions" or name == "Blizzard_TradeSkillUI" or name == "Blizzard_CraftUI" then attachAll() end
end)
FP:OnSetting("profButton", function(on)
  for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
    local f = _G[name]
    if f and f.__fpButton then if on then f.__fpButton:Show() else f.__fpButton:Hide() end end
  end
end)
