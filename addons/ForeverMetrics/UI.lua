-- Forever Metrics: UI
-- The top half of this file holds the page renderers (each returns a text
-- string for one or more characters). The bottom half is the window: a side
-- nav, tabs inside each section, a dashboard Home page, and options pages.

local ADDON, ns = ...
local FM = ns.FM

local ALL = "__ALL__"
local state = { view = nil, act = "feed" }   -- view = character key shown, or ALL

local KIND_ICON = {
  level = "|cffe8c27a[LVL]|r", quest = "|cffffd100[Q]|r", loot = "|cff1eff00[L]|r",
  skill = "|cff69ccf0[S]|r", death = "|cffff5555[X]|r", zone = "|cffaaaaaa[Z]|r",
  gather = "|cffc79c6e[G]|r", duo = "|cffff7eb6[D]|r",
}

---------------------------------------------------------------------------
-- Formatting helpers
---------------------------------------------------------------------------

local function money(c)
  c = c or 0
  if GetCoinTextureString then return GetCoinTextureString(c) end
  local fl = math.floor
  return ("%dg %ds %dc"):format(fl(c / 10000), fl(c / 100) % 100, c % 100)
end

local function dur(sec)
  sec = sec or 0
  local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
  if h > 0 then return ("%dh %dm"):format(h, m) end
  return ("%dm"):format(m)
end

local function colorName(c)
  local col = c.class and C_ClassColor and C_ClassColor.GetClassColor(c.class)
  local label = c.name .. " (" .. (c.level or "?") .. ")"
  return col and col:WrapTextInColorCode(label) or label
end

local function hdr(t) return "|cffe8c27a" .. t .. "|r\n" end

local function sortedPairs(tbl, n)
  local list = {}
  for k, v in pairs(tbl) do list[#list + 1] = { k = k, v = v } end
  table.sort(list, function(a, b) return a.v > b.v end)
  if n then for i = #list, n + 1, -1 do list[i] = nil end end
  return list
end

-- Characters to show for the current view (one, or all of them)
local function viewChars()
  local db = FM:DB().chars
  if state.view == ALL then
    local list = {}
    for _, c in pairs(db) do list[#list + 1] = c end
    table.sort(list, function(a, b) return (a.level or 0) > (b.level or 0) end)
    return list
  end
  return { db[state.view] }
end

local function viewOrder()
  local keys = {}
  for k in pairs(FM:DB().chars) do keys[#keys + 1] = k end
  table.sort(keys)
  table.insert(keys, 1, ALL)
  return keys
end

---------------------------------------------------------------------------
-- Tab renderers -> return a text string
---------------------------------------------------------------------------

local R = {}

function R.Overview(chars)
  local out = {}
  local tot = { played = 0, xp = 0, quests = 0, levels = 0, looted = 0, earned = 0, spent = 0 }
  for _, c in ipairs(chars) do
    local s = c.stats
    tot.played = tot.played + c.played; tot.xp = tot.xp + s.xp
    tot.quests = tot.quests + s.quests; tot.levels = tot.levels + s.levels
    tot.looted = tot.looted + s.goldLooted; tot.earned = tot.earned + s.goldEarned
    tot.spent = tot.spent + s.goldSpent
  end

  if #chars == 1 then
    local c = chars[1]
    out[#out + 1] = colorName(c) .. "  -  " .. (c.realm or "") .. "\n"
  else
    out[#out + 1] = hdr(("All Characters (%d)"):format(#chars))
    for _, c in ipairs(chars) do
      out[#out + 1] = ("  %s  %s tracked\n"):format(colorName(c), dur(c.played))
    end
  end

  out[#out + 1] = "\n" .. hdr("Totals")
  out[#out + 1] = ("  Time tracked: %s\n  XP gained: %d\n  Levels gained: %d\n  Quests completed: %d\n")
    :format(dur(tot.played), tot.xp, tot.levels, tot.quests)
  out[#out + 1] = ("  Gold looted: %s\n  Gold earned: %s\n  Gold spent: %s\n")
    :format(money(tot.looted), money(tot.earned), money(tot.spent))

  if #chars == 1 then
    local c = chars[1]
    -- Time per level, newest first
    local lv = {}
    for level, t in pairs(c.levelTimes) do lv[#lv + 1] = { level, t } end
    table.sort(lv, function(a, b) return a[1] > b[1] end)
    if #lv > 0 then
      out[#out + 1] = "\n" .. hdr("Time per level")
      for i = 1, math.min(#lv, 10) do
        out[#out + 1] = ("  Level %d: %s\n"):format(lv[i][1], dur(lv[i][2]))
      end
    end
    -- Favorite zones
    local zones = sortedPairs(c.zones, 5)
    if #zones > 0 then
      out[#out + 1] = "\n" .. hdr("Most time spent")
      for _, z in ipairs(zones) do out[#out + 1] = ("  %s: %s\n"):format(z.k, dur(z.v)) end
    end
    if state.view == FM:CharKey() then
      out[#out + 1] = "\n" .. hdr("Right now") .. "  " .. FM:SessionRecap() .. "\n"
    end
  end
  return table.concat(out)
end

function R.Feed(chars)
  local entries = {}
  local multi = #chars > 1
  for _, c in ipairs(chars) do
    for _, e in ipairs(c.feed) do entries[#entries + 1] = { e = e, c = c } end
  end
  table.sort(entries, function(a, b) return a.e.t > b.e.t end)
  if #entries == 0 then return "Nothing yet. Go do something fun!" end
  local out = {}
  for i = 1, math.min(#entries, 150) do
    local e, c = entries[i].e, entries[i].c
    local who = multi and (colorName(c) .. ": ") or ""
    out[#out + 1] = ("|cff888888%s|r %s %s%s\n"):format(date("%m/%d %H:%M", e.t),
      KIND_ICON[e.k] or "", who, e.x)
  end
  return table.concat(out)
end

---------------------------------------------------------------------------
-- Loot log + Luck (data from Core's corpse-loot tracking)
---------------------------------------------------------------------------

local QNAME = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local QHEX  = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }
local function qcolor(q, t)
  local hex = (ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] and ITEM_QUALITY_COLORS[q].hex)
  if hex then return hex .. t .. "|r" end
  return "|cff" .. (QHEX[q] or "ffffff") .. t .. "|r"
end

local function commas(n)
  n = math.floor(n or 0)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  local s = tostring(n)
  while true do
    local k; s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then return s end
  end
end

-- Merge loot data across the characters in view
local function mergeLoot(chars)
  local m = { q = {}, cloth = {}, mobs = {}, zones = {}, notable = {}, kills = 0,
              dry = {}, longest = 0, blueDry = {} }
  for _, c in ipairs(chars) do
    if FM.EnsureLoot then FM.EnsureLoot(c) end
    local L = c.loot
    m.kills = m.kills + (c.stats.kills - (L.startKills or 0))
    for q, n in pairs(L.q) do m.q[q] = (m.q[q] or 0) + n end
    for k, n in pairs(L.cloth) do m.cloth[k] = (m.cloth[k] or 0) + n end
    for _, src in ipairs({ "mobs", "zones" }) do
      for k, e in pairs(L[src]) do
        local d = m[src][k] or { kills = 0, greens = 0, blues = 0, purples = 0 }
        d.kills = d.kills + (e.kills or 0); d.greens = d.greens + (e.greens or 0)
        d.blues = d.blues + (e.blues or 0); d.purples = d.purples + (e.purples or 0)
        m[src][k] = d
      end
    end
    for _, n in ipairs(L.notable) do m.notable[#m.notable + 1] = { n = n, c = c } end
    m.dry[#m.dry + 1] = { c = c, n = c.stats.kills - L.lastGreenKill }
    m.blueDry[#m.blueDry + 1] = { c = c, n = c.stats.kills - L.lastBlueKill }
    m.longest = math.max(m.longest, L.longestDry, c.stats.kills - L.lastGreenKill)
  end
  table.sort(m.notable, function(a, b)
    if a.n.t ~= b.n.t then return a.n.t > b.n.t end
    return (a.n.kill or 0) > (b.n.kill or 0)
  end)
  return m
end

local function rate(drops, kills)
  if drops <= 0 or kills <= 0 then return "|cffa8977anone yet|r" end
  return ("1 per %s kills"):format(commas(kills / drops + 0.5))
end

function R.Loot(chars)
  local m = mergeLoot(chars)
  local multi = #chars > 1
  local out = { hdr("Drops by quality") }
  local parts = {}
  for q = 0, 5 do
    if (m.q[q] or 0) > 0 then parts[#parts + 1] = qcolor(q, ("%s %s"):format(QNAME[q], commas(m.q[q]))) end
  end
  out[#out + 1] = "  " .. (#parts > 0 and table.concat(parts, "  ·  ") or "Nothing looted yet.") .. "\n"

  local cloth = {}
  for _, name in ipairs(FM.CLOTH) do
    if (m.cloth[name] or 0) > 0 then cloth[#cloth + 1] = ("%s %s"):format(name:gsub(" Cloth", ""), commas(m.cloth[name])) end
  end
  if #cloth > 0 then
    out[#out + 1] = "\n" .. hdr("Cloth")
    out[#out + 1] = "  " .. table.concat(cloth, "  ·  ") .. "\n"
  end

  out[#out + 1] = "\n" .. hdr("Recent finds")
  if #m.notable == 0 then
    out[#out + 1] = "  Greens and better show up here as you find them.\n"
  end
  for i = 1, math.min(#m.notable, 40) do
    local n, c = m.notable[i].n, m.notable[i].c
    local who = multi and (colorName(c) .. "  ") or ""
    out[#out + 1] = ("  |cff888888%s|r  %s%s\n     |cffa8977afrom %s · %s · kill #%s|r\n"):format(
      date("%m/%d %H:%M", n.t), who, n.link, n.mob, n.zone, commas(n.kill))
  end
  return table.concat(out)
end

function R.Luck(chars)
  local m = mergeLoot(chars)
  local greens, blues, purples = m.q[2] or 0, m.q[3] or 0, (m.q[4] or 0) + (m.q[5] or 0)
  local out = { hdr("The hunt") }
  out[#out + 1] = ("  Kills tracked: %s\n"):format(commas(m.kills))
  out[#out + 1] = ("  %s: %s  |cffa8977a(%s)|r\n"):format(qcolor(2, "Greens"), commas(greens), rate(greens, m.kills))
  out[#out + 1] = ("  %s: %s  |cffa8977a(%s)|r\n"):format(qcolor(3, "Blues"), commas(blues), rate(blues, m.kills))
  if purples > 0 then
    out[#out + 1] = ("  %s: %s  |cffa8977a(%s)|r\n"):format(qcolor(4, "Epics"), commas(purples), rate(purples, m.kills))
  end

  out[#out + 1] = "\n" .. hdr("Dry streaks")
  for i, d in ipairs(m.dry) do
    local who = #chars > 1 and (colorName(d.c) .. ": ") or ""
    out[#out + 1] = ("  %s%s kills since a green  ·  %s since a blue\n"):format(
      who, commas(d.n), commas(m.blueDry[i].n))
  end
  out[#out + 1] = ("  |cffa8977aLongest green drought: %s kills|r\n"):format(commas(m.longest))

  -- Luckiest zones: greens + 5x blues + 20x epics per 100 kills, min 30 kills
  local zones = {}
  for z, e in pairs(m.zones) do
    if e.kills >= 30 then
      local score = (e.greens + e.blues * 5 + e.purples * 20) / e.kills * 100
      zones[#zones + 1] = { z = z, e = e, s = score }
    end
  end
  table.sort(zones, function(a, b) return a.s > b.s end)
  out[#out + 1] = "\n" .. hdr("Luckiest hunting grounds")
  if #zones == 0 then out[#out + 1] = "  Zones show up after 30 kills in them.\n" end
  for i = 1, math.min(#zones, 6) do
    local z = zones[i]
    out[#out + 1] = ("  %s  |cffa8977a%s kills ·|r %s%s\n"):format(z.z, commas(z.e.kills),
      qcolor(2, z.e.greens .. "g"), z.e.blues > 0 and (" " .. qcolor(3, z.e.blues .. "b")) or "")
  end

  -- Per mob
  local mobs = {}
  for name, e in pairs(m.mobs) do if name ~= "Unknown" then mobs[#mobs + 1] = { n = name, e = e } end end
  table.sort(mobs, function(a, b) return a.e.kills > b.e.kills end)
  if #mobs > 0 then
    out[#out + 1] = "\n" .. hdr("Most hunted")
    for i = 1, math.min(#mobs, 10) do
      local x = mobs[i]
      local drops = x.e.greens + x.e.blues + x.e.purples
      out[#out + 1] = ("  %s  |cffa8977a%s kills ·|r %s\n"):format(x.n, commas(x.e.kills),
        drops > 0 and qcolor(2, drops .. " green+") or "|cffa8977ano green+ yet|r")
    end
  end

  -- Blue log
  local bl = {}
  for _, x in ipairs(m.notable) do if x.n.q >= 3 then bl[#bl + 1] = x end end
  out[#out + 1] = "\n" .. hdr("Rare log")
  if #bl == 0 then out[#out + 1] = "  Your first blue will be immortalized here.\n" end
  for _, x in ipairs(bl) do
    out[#out + 1] = ("  %s  |cffa8977a%s · kill #%s · %s|r\n"):format(x.n.link, x.n.mob, commas(x.n.kill), date("%m/%d", x.n.t))
  end
  return table.concat(out)
end

function R.Activity(chars)
  if state.act == "loot" then return R.Loot(chars) end
  if state.act == "luck" then return R.Luck(chars) end
  return R.Feed(chars)
end

function R.Gathering(chars)
  local out = {}
  for _, g in ipairs(FM.GATHER_TYPES) do
    local nodes, items, per = 0, {}, {}
    for _, c in ipairs(chars) do
      local d = c.gathering[g]
      nodes = nodes + d.nodes
      if d.nodes > 0 then per[#per + 1] = ("%s %d"):format(colorName(c), d.nodes) end
      for name, n in pairs(d.items) do items[name] = (items[name] or 0) + n end
    end
    if nodes > 0 then
      local verb = g == "Fishing" and "catches" or "nodes"
      out[#out + 1] = hdr(("%s - %d %s"):format(g, nodes, verb))
      if #chars > 1 and #per > 0 then out[#out + 1] = "  " .. table.concat(per, ", ") .. "\n" end
      for _, it in ipairs(sortedPairs(items, 8)) do
        out[#out + 1] = ("  %s x%d\n"):format(it.k, it.v)
      end
      out[#out + 1] = "\n"
    end
  end

  -- Profession / skill ranks
  out[#out + 1] = hdr("Skill levels")
  local any = false
  for _, c in ipairs(chars) do
    local list = {}
    for name, s in pairs(c.skills) do list[#list + 1] = ("%s %d"):format(name, s.rank) end
    table.sort(list)
    if #list > 0 then
      any = true
      out[#out + 1] = ("  %s: %s\n"):format(colorName(c), table.concat(list, ", "))
    end
  end
  if not any then out[#out + 1] = "  Skills show up here once one levels up.\n" end
  if #out == 2 and not any then table.insert(out, 1, "No gathering yet.\n\n") end
  return table.concat(out)
end

function R.Combat(chars)
  local kills, deaths, mobs = 0, 0, {}
  for _, c in ipairs(chars) do
    kills = kills + c.stats.kills; deaths = deaths + c.stats.deaths
    for m, n in pairs(c.kills) do mobs[m] = (mobs[m] or 0) + n end
  end
  local out = { hdr("Combat") }
  out[#out + 1] = ("  Kills: %d\n  Deaths: %d\n"):format(kills, deaths)
  if deaths > 0 then out[#out + 1] = ("  Kills per death: %.1f\n"):format(kills / deaths) end
  local top = sortedPairs(mobs, 15)
  if #top > 0 then
    out[#out + 1] = "\n" .. hdr("Most defeated")
    for _, m in ipairs(top) do out[#out + 1] = ("  %s x%d\n"):format(m.k, m.v) end
  end
  return table.concat(out)
end

---------------------------------------------------------------------------
-- Window (v0.9.0): side navigation on the left, optional tabs along the top
-- of the content area, and a dashboard Home page.
--
-- To add a page: add a section (or a tab inside one) to buildSections().
-- A tab's `kind` is "dash", "text" (render returns a string) or "options"
-- (lists the toggles in FM.SETTINGS with that group). Any settings group
-- that isn't placed anywhere gets its own Options page automatically.
---------------------------------------------------------------------------

local W, H = 800, 540
local NAV_W = 170
local CONTENT_W = W - (12 + NAV_W + 12) - 14   -- 592
local ROW_H = 28

local win, nav, content, navButtons, tabButtons = nil, nil, nil, {}, {}
local titleText, charPrev, charNext, charLabel, hint
local textScroll, textChild, text
local dash, cards = nil, {}
local opts, optsChild, optsNote, rows = nil, nil, nil, {}

local ui = { sec = 1, tabs = {}, sel = 1, focus = "nav" }
local SECTIONS

-- A line of help under each options page
local NOTES = {
  pill    = "Hover the pill for tonight's stats. Move it in Edit Mode (Esc > Edit Mode).",
  feed    = "Move the feed in Edit Mode. Tune it with /fm feed lines 5, /fm feed hold 60, /fm feed scale 1.2.",
  levelup = "Visit your class trainer once so level-ups can list your new skills. /fm levelup test previews it.",
  duo     = "Pairing is automatic when you share a guild or group. /fm duo lists partners and commands.",
  fct     = "Gains rise above your character. Move them in Edit Mode, or /fm fct move. /fm fct test shows samples (target one first to see the spell lines above it). Spells show above your target only while enemy nameplates are on (V by default); otherwise they float with your gains. Spell hits are a best guess: the game hides which spell did the damage, so the first hit on your target after you cast is shown with that spell, and a partner's hit can sometimes be counted.",
  fctBlizz = "These are WoW's own combat text settings, saved by the game. Options this client doesn't have are hidden. They can't be changed in combat.",
  tooltip = "Uses base ratios before talents and buffs. Conditional AP (vs Undead, feral forms) is skipped.",
  chat    = "The background option uses WoW's own chat opacity setting, so turning it off restores what you had. Hidden buttons stay hidden even when chat fades in on hover; the tabs always stay.",
  qol     = "All off by default. Faster auto loot follows your Auto Loot game setting.",
}

local function buildSections()
  SECTIONS = {
    { key = "home", label = "Home", tabs = {
        { label = "Dashboard", kind = "dash" },
        { label = "Details", kind = "text", char = true, render = R.Overview } } },
    { key = "activity", label = "Activity", tabs = {
        { label = "Feed", kind = "text", char = true, render = R.Feed },
        { label = "Loot log", kind = "text", char = true, render = R.Loot },
        { label = "Luck", kind = "text", char = true, render = R.Luck } } },
    { key = "gathering", label = "Gathering", tabs = {
        { kind = "text", char = true, render = R.Gathering } } },
    { key = "combat", label = "Combat", tabs = {
        { kind = "text", char = true, render = R.Combat } } },
    { key = "duo", label = "Duo", tabs = {
        { label = "Partner", kind = "text", render = function() return FM.RenderDuo and FM:RenderDuo() or "" end },
        { label = "Options", kind = "options", group = "duo" } } },
    { divider = "Options" },
    { key = "interface", label = "Interface", tabs = {
        { label = "XP Pill", kind = "options", group = "pill" },
        { label = "Feed", kind = "options", group = "feed" },
        { label = "Level Up", kind = "options", group = "levelup" } } },
    { key = "combattext", label = "Combat Text", tabs = {
        { label = "Floating gains", kind = "options", group = "fct" },
        { label = "Blizzard", kind = "options", group = "fctBlizz" } } },
    { key = "tooltips", label = "Tooltips", tabs = { { kind = "options", group = "tooltip" } } },
    { key = "chat", label = "Chat", tabs = { { kind = "options", group = "chat" } } },
    { key = "qol", label = "Quality of Life", tabs = { { kind = "options", group = "qol" } } },
  }
  -- Any settings group not placed above gets its own page
  local used = {}
  for _, s in ipairs(SECTIONS) do
    for _, t in ipairs(s.tabs or {}) do if t.group then used[t.group] = true end end
  end
  for _, g in ipairs(FM.SETTING_GROUPS or {}) do
    if not used[g.key] then
      SECTIONS[#SECTIONS + 1] = { key = "grp_" .. g.key, label = g.label, tabs = { { kind = "options", group = g.key } } }
    end
  end
end

local function curSection() return SECTIONS[ui.sec] end
local function curTabIndex()
  local s = curSection()
  return math.min(ui.tabs[s.key] or 1, #s.tabs)
end
local function curTab() return curSection().tabs[curTabIndex()] end
local function sectionIndex(key)
  for i, s in ipairs(SECTIONS) do if s.key == key then return i end end
end

local function setColor(tex, c, a) tex:SetColorTexture(c[1], c[2], c[3], a or c[4]) end

---------------------------------------------------------------------------
-- Options pages
---------------------------------------------------------------------------

local activateOption -- defined below

local function optionDefs(group)
  local list = {}
  for _, d in ipairs(FM.SETTINGS) do
    -- game-setting rows only appear if this client actually has that CVar
    if d.group == group and (not d.cvar or FM:CVarExists(d.cvar)) then list[#list + 1] = d end
  end
  return list
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local row = CreateFrame("Button", nil, optsChild)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row:SetPoint("RIGHT", optsChild, "RIGHT")
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints(); setColor(row.hl, FM.THEME.hl)
  row.hl:Hide()
  local mouseHl = row:CreateTexture(nil, "HIGHLIGHT")
  mouseHl:SetAllPoints(); setColor(mouseHl, FM.THEME.hl, 0.08)
  row.cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.cb:SetSize(24, 24)
  row.cb:SetPoint("LEFT", 8, 0)
  row.cb:SetScript("OnClick", function(self)
    ui.sel, ui.focus = i, "content"
    if row.def then FM:SetSetting(row.def.key, self:GetChecked() and true or false) end
  end)
  row.btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.btn:SetSize(76, 22)
  row.btn:SetPoint("LEFT", 8, 0)
  row.btn:SetScript("OnClick", function() ui.sel, ui.focus = i, "content"; activateOption(i) end)
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.label:SetJustifyH("LEFT")
  row:SetScript("OnClick", function() ui.sel, ui.focus = i, "content"; activateOption(i) end)
  rows[i] = row
  return row
end

local function renderOptions(group)
  local defs = optionDefs(group)
  ui.rows = defs
  ui.sel = math.max(1, math.min(ui.sel, #defs))
  for i, d in ipairs(defs) do
    local r = getRow(i)
    r.def = d
    r.label:ClearAllPoints()
    if d.action or d.choices then
      r.cb:Hide()
      r.btn:SetText(d.choices and FM:ChoiceLabel(d.key) or (d.button or "Go"))
      r.btn:SetWidth(d.choices and 130 or 76)
      r.btn:Show()
      r.label:SetPoint("LEFT", r.btn, "RIGHT", 10, 0)
    else
      r.btn:Hide()
      r.cb:SetChecked(FM:GetSetting(d.key) and true or false); r.cb:Show()
      r.label:SetPoint("LEFT", r.cb, "RIGHT", 6, 0)
    end
    r.label:SetText(d.label)
    if ui.focus == "content" and i == ui.sel then r.hl:Show() else r.hl:Hide() end
    r:Show()
  end
  for i = #defs + 1, #rows do rows[i]:Hide() end
  optsNote:ClearAllPoints()
  optsNote:SetPoint("TOPLEFT", 10, -(#defs * ROW_H) - 14)
  optsNote:SetPoint("RIGHT", -10, 0)
  optsNote:SetText(NOTES[group] and ("|cffa8977a" .. NOTES[group] .. "|r") or "")
  optsChild:SetHeight(#defs * ROW_H + 80)
end

activateOption = function(i)
  local d = ui.rows and ui.rows[i]
  if not d then return end
  if d.choices then
    FM:CycleChoice(d.key)
  elseif d.action then
    local fn = FM[d.action]
    if not fn then
      -- The file that provides this didn't load (usually a Lua error in it)
      print(("|cffff5555Forever Metrics|r \"%s\" isn't available: part of the addon failed to load. Type |cffffff00/console scriptErrors 1|r then |cffffff00/reload|r to see the error."):format(d.label))
      return
    end
    local ok, err = pcall(fn, FM)
    if not ok then print("|cffff5555ForeverMetrics error|r", d.label, err) end
  else
    FM:SetSetting(d.key, not FM:GetSetting(d.key))
  end
end

---------------------------------------------------------------------------
-- Dashboard
---------------------------------------------------------------------------

local CARD_W = math.floor((CONTENT_W - 10) / 2)

local function makeCard(col, row, title, h)
  local card = CreateFrame("Frame", nil, dash, "BackdropTemplate")
  FM:Skin(card, { edge = 10, alpha = 0.55 })
  card:SetSize(CARD_W, h)
  card:SetPoint("TOPLEFT", (col - 1) * (CARD_W + 10), -((row - 1) * (h + 8)))
  card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  card.title:SetPoint("TOPLEFT", 12, -10)
  card.title:SetText(title)
  card.body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  card.body:SetPoint("TOPLEFT", 12, -30)
  card.body:SetWidth(CARD_W - 24)
  card.body:SetJustifyH("LEFT")
  card.body:SetJustifyV("TOP")
  card.body:SetSpacing(3)
  -- Item links in a card show their tooltip on hover
  if card.SetHyperlinksEnabled then
    card:SetHyperlinksEnabled(true)
    card:SetScript("OnHyperlinkEnter", function(self, link)
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      pcall(GameTooltip.SetHyperlink, GameTooltip, link)
      GameTooltip:Show()
    end)
    card:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  end
  return card
end

local function cardButton(card, label, onClick)
  local b = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
  b:SetSize(84, 20)
  b:SetPoint("BOTTOMRIGHT", -10, 10)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local selectSection -- defined below

local function buildDash()
  dash = CreateFrame("Frame", nil, content)
  local h = 134
  cards.session  = makeCard(1, 1, "This session", h)
  cards.level    = makeCard(2, 1, "Next level", h)
  cards.duo      = makeCard(1, 2, "|cffff7eb6Duo|r", h)
  cards.lastLvl  = makeCard(2, 2, "Last level-up", h)
  cards.finds    = makeCard(1, 3, "Recent finds", h)
  cards.lifetime = makeCard(2, 3, "This character", h)

  -- XP bar on the Next level card
  local L, T = cards.level, FM.THEME
  L.barBG = L:CreateTexture(nil, "ARTWORK")
  L.barBG:SetColorTexture(0, 0, 0, 0.6)
  L.barBG:SetPoint("BOTTOMLEFT", 12, 14); L.barBG:SetPoint("BOTTOMRIGHT", -12, 14); L.barBG:SetHeight(6)
  L.barRest = L:CreateTexture(nil, "ARTWORK", nil, 1)
  setColor(L.barRest, T.rested)
  L.barRest:SetPoint("BOTTOMLEFT", L.barBG); L.barRest:SetHeight(6)
  L.barFill = L:CreateTexture(nil, "ARTWORK", nil, 2)
  setColor(L.barFill, T.bar)
  L.barFill:SetPoint("BOTTOMLEFT", L.barBG); L.barFill:SetHeight(6)

  cardButton(cards.lastLvl, "Replay", function()
    if FM.ReplayLevelUp then FM:ReplayLevelUp() end
  end)
  cardButton(cards.duo, "Open", function()
    local i = sectionIndex("duo")
    if i then ui.tabs.duo = 1; selectSection(i) end
  end)
end

local function fillDash()
  local c = FM:Char()
  if not c then return end
  local s = FM:Session() or { start = time(), xp = 0, kills = 0, quests = 0, nodes = 0, startMoney = GetMoney() }

  -- This session
  local el = time() - s.start
  local xph = el >= 60 and s.xp / (el / 3600) or 0
  local net = GetMoney() - (s.startMoney or GetMoney())
  local lines = {
    ("%s played"):format(dur(el)),
    ("%s XP  |cffa8977a(%s/hr)|r"):format(commas(s.xp), commas(xph)),
    ("%d kills  ·  %d quests  ·  %d nodes"):format(s.kills or 0, s.quests or 0, s.nodes or 0),
    ("Gold %s%s"):format(net >= 0 and "|cff7fd36b+|r" or "|cffff6b6b-|r", money(math.abs(net))),
  }
  if s.bestLoot then lines[#lines + 1] = "Best loot: " .. s.bestLoot end
  cards.session.body:SetText(table.concat(lines, "\n"))

  -- Next level
  local L = cards.level
  local lvl, cur, max = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
  local inner = CARD_W - 24
  if not max or max <= 0 then
    L.body:SetText(("Level %d\nMax level. Nice work!"):format(lvl))
    L.barFill:SetWidth(0.001); L.barRest:SetWidth(0.001)
  else
    local rested = (GetXPExhaustion and GetXPExhaustion()) or 0
    local pct = cur / max
    local eta = xph > 0 and dur((max - cur) / xph * 3600) or "keep going to estimate"
    L.body:SetText(("Level %d  ·  |cffe8c27a%d%%|r\n%s / %s XP  ·  %s to go\nRested: %s\nTime to level: %s"):format(
      lvl, math.floor(pct * 100), commas(cur), commas(max), commas(max - cur),
      rested > 0 and commas(rested) or "none", eta))
    L.barFill:SetWidth(math.max(0.001, inner * math.min(1, pct)))
    L.barRest:SetWidth(math.max(0.001, inner * math.min(1, (cur + rested) / max)))
  end

  -- Duo
  local D = FM:DB().duo
  local partners = D and D.partners
  if not partners or not next(partners) then
    cards.duo.body:SetText("No duo partner yet.\nGroup up with someone running Forever Metrics, or type |cffffff00/fm duo add Name|r.")
  else
    local out = {}
    for id, P in pairs(partners) do
      local online = FM.Duo and FM.Duo.online and FM.Duo.online[id]
      local ch = P.current and P.chars and P.chars[P.current]
      out[#out + 1] = ("|cffff7eb6%s|r  %s"):format(P.nick, online and "|cff7fd36bonline|r" or "|cff888888offline|r")
      if ch then
        local pct = (ch.xpMax or 0) > 0 and math.floor((ch.xp or 0) / ch.xpMax * 100) or 0
        out[#out + 1] = ("%s  ·  %d%%"):format(colorName(ch), pct)
        if online and ch.zone and ch.zone ~= "" then out[#out + 1] = "in " .. ch.zone end
      end
      if P.together and P.together.time > 0 then
        out[#out + 1] = ("|cffa8977aTogether: %s, %s kills|r"):format(dur(P.together.time), commas(P.together.kills))
      end
      break -- the card has room for one partner
    end
    cards.duo.body:SetText(table.concat(out, "\n"))
  end

  -- Last level-up
  local LU = c.lastLevelUp
  if LU then
    local n = #(LU.skills or {})
    cards.lastLvl.body:SetText(("|cffe8c27aLevel %d|r  ·  %s\n%s\n%s"):format(
      LU.level, date("%m/%d %H:%M", LU.t or time()),
      LU.took and ("Level %d took %s"):format(LU.level - 1, dur(LU.took)) or "",
      n > 0 and ("%d new %s to train"):format(n, n == 1 and "skill" or "skills") or "No new trainer skills"))
  else
    cards.lastLvl.body:SetText("No level-up saved yet.\nYour next ding shows up here.")
  end

  -- Recent finds
  if FM.EnsureLoot then FM.EnsureLoot(c) end
  local notable = c.loot and c.loot.notable or {}
  if #notable == 0 then
    cards.finds.body:SetText("Greens and better show up here as you find them.")
  else
    local out = {}
    for i = #notable, math.max(1, #notable - 3), -1 do
      local n = notable[i]
      out[#out + 1] = ("%s  |cffa8977a%s|r"):format(n.link, n.mob or "")
    end
    cards.finds.body:SetText(table.concat(out, "\n"))
  end

  -- This character
  local st = c.stats
  cards.lifetime.body:SetText(("%s tracked\n%s kills  ·  %s deaths\n%s quests  ·  %d levels gained\nGold looted %s"):format(
    dur(c.played), commas(st.kills), commas(st.deaths), commas(st.quests), st.levels, money(st.goldLooted)))
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function layoutTabs(s)
  local n = #s.tabs
  for _, b in ipairs(tabButtons) do b:Hide() end
  if n <= 1 then return end
  local x, idx = 0, curTabIndex()
  for i, t in ipairs(s.tabs) do
    local b = tabButtons[i]
    b.label:SetText(t.label or s.label)
    local w = b.label:GetStringWidth() + 28
    b:SetWidth(w)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", content, "TOPLEFT", x, 0)
    x = x + w + 4
    if i == idx then
      b.under:Show(); b.bg:Show()
      b.label:SetTextColor(1, 0.82, 0.35)
    else
      b.under:Hide(); b.bg:Hide()
      b.label:SetTextColor(0.8, 0.78, 0.72)
    end
    b:Show()
  end
end

local function placeBodies(top)
  for _, f in ipairs({ textScroll, opts }) do
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, top)
    f:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -26, 0)
  end
  dash:ClearAllPoints()
  dash:SetPoint("TOPLEFT", content, "TOPLEFT", 0, top)
  dash:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
end

local function updateHint(tab)
  local pad = win.usesPad
  if not pad then hint:SetText("Drag to move  ·  Esc to close"); return end
  local parts = { "LB/RB: tab" }
  if tab.char then parts[#parts + 1] = "D-pad L/R: character" end
  if ui.focus == "nav" then
    parts[#parts + 1] = "D-pad U/D: section"
    if tab.kind ~= "dash" then parts[#parts + 1] = "A: enter page" end
    parts[#parts + 1] = "B: close"
  else
    parts[#parts + 1] = tab.kind == "options" and "D-pad U/D: pick  ·  A: toggle" or "D-pad U/D: scroll"
    parts[#parts + 1] = "B: back"
  end
  hint:SetText(table.concat(parts, "   "))
end

local function refresh()
  if not win or not win:IsShown() then return end
  local s, tab = curSection(), curTab()

  -- Side nav
  for i, b in pairs(navButtons) do
    if i == ui.sec then
      b.sel:Show(); b.bar:Show()
      b.label:SetTextColor(1, 0.82, 0.35)
    else
      b.sel:Hide(); b.bar:Hide()
      b.label:SetTextColor(0.85, 0.83, 0.78)
    end
  end
  if ui.focus == "nav" and win.usesPad then nav.focusEdge:Show() else nav.focusEdge:Hide() end

  titleText:SetText("|cffe8c27aForever Metrics|r  |cffa8977a·  " .. s.label .. "|r")
  layoutTabs(s)
  placeBodies(#s.tabs > 1 and -32 or 0)

  -- Character switcher only on pages that show one character's data
  if tab.char then
    if not state.view or (state.view ~= ALL and not FM:DB().chars[state.view]) then
      state.view = FM:CharKey()
    end
    charLabel:SetText(state.view == ALL and "All Characters" or colorName(FM:DB().chars[state.view]))
    charPrev:Show(); charNext:Show(); charLabel:Show()
  else
    charPrev:Hide(); charNext:Hide(); charLabel:Hide()
  end

  textScroll:Hide(); opts:Hide(); dash:Hide()
  if tab.kind == "dash" then
    dash:Show()
    fillDash()
  elseif tab.kind == "options" then
    opts:Show()
    renderOptions(tab.group)
  else
    textScroll:Show()
    text:SetText(tab.render(tab.char and viewChars() or nil) or "")
    textChild:SetHeight(text:GetStringHeight() + 20)
  end
  updateHint(tab)
end
FM.OnUpdateUI = function() refresh() end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------

local function resetScroll()
  if textScroll then textScroll:SetVerticalScroll(0) end
  if opts then opts:SetVerticalScroll(0) end
end

selectSection = function(i)
  if not SECTIONS[i] or SECTIONS[i].divider then return end
  ui.sec, ui.sel = i, 1
  resetScroll()
  refresh()
end

local function selectTab(i)
  local s = curSection()
  ui.tabs[s.key] = i
  ui.sel = 1
  resetScroll()
  refresh()
end

local function moveSection(dir)
  local i = ui.sec
  for _ = 1, #SECTIONS do
    i = ((i - 1 + dir) % #SECTIONS) + 1
    if not SECTIONS[i].divider then break end
  end
  selectSection(i)
end

local function cycleTab(dir)
  local s = curSection()
  if #s.tabs <= 1 then return end
  selectTab(((curTabIndex() - 1 + dir) % #s.tabs) + 1)
end

local function cycle(dir) -- character
  local keys = viewOrder()
  local idx = 1
  for i, k in ipairs(keys) do if k == state.view then idx = i end end
  idx = ((idx - 1 + dir) % #keys) + 1
  state.view = keys[idx]
  refresh()
end

local function scrollBy(px)
  local f = (curTab().kind == "options") and opts or textScroll
  local maxS = f:GetVerticalScrollRange()
  f:SetVerticalScroll(math.max(0, math.min(maxS, f:GetVerticalScroll() + px)))
end

local function moveSel(d)
  local n = math.max(1, #(ui.rows or {}))
  ui.sel = ((ui.sel - 1 + d) % n) + 1
  refresh()
  -- keep the selected row in view
  local top = (ui.sel - 1) * ROW_H
  local view, cur = opts:GetHeight(), opts:GetVerticalScroll()
  if top < cur then opts:SetVerticalScroll(top)
  elseif top + ROW_H > cur + view then opts:SetVerticalScroll(top + ROW_H - view) end
end

---------------------------------------------------------------------------
-- Controller support
-- While the window is open it takes the controller buttons below; anything
-- else passes through to the game. Closing it gives full control back.
-- Focus is either the side nav or the page: A enters a page, B backs out.
---------------------------------------------------------------------------

local PAD = {
  PADLSHOULDER = function() cycleTab(-1) end,
  PADRSHOULDER = function() cycleTab(1) end,
  PADDLEFT  = function() if curTab().char then cycle(-1) end end,
  PADDRIGHT = function() if curTab().char then cycle(1) end end,
  PADDUP = function()
    if ui.focus == "nav" then moveSection(-1)
    elseif curTab().kind == "options" then moveSel(-1)
    else scrollBy(-40) end
  end,
  PADDDOWN = function()
    if ui.focus == "nav" then moveSection(1)
    elseif curTab().kind == "options" then moveSel(1)
    else scrollBy(40) end
  end,
  PAD1 = function() -- A / Cross
    if ui.focus == "nav" then
      if curTab().kind ~= "dash" then ui.focus = "content"; ui.sel = 1; refresh() end
    elseif curTab().kind == "options" then
      activateOption(ui.sel)
    end
  end,
  PAD2 = function() -- B / Circle
    if ui.focus == "content" then ui.focus = "nav"; refresh() else win:Hide() end
  end,
  PAD4 = function() cycleTab(1) end, -- Y / Triangle
}

local function setPropagate(on)
  -- Changing input propagation is blocked in combat; skip it then.
  if InCombatLockdown() then return end
  if win.SetPropagateGamePadInput then pcall(win.SetPropagateGamePadInput, win, on) end
end

local function setupGamepad()
  if not win.EnableGamePadButton then return false end -- client has no gamepad API
  win:EnableGamePadButton(true)
  win:SetScript("OnGamePadButtonDown", function(_, button)
    local fn = PAD[button]
    if fn then
      setPropagate(false)
      fn()
    else
      setPropagate(true) -- not ours, let the game have it
    end
  end)
  win:SetScript("OnGamePadStick", function(_, stick, _, y)
    if stick == "Right" and math.abs(y) > 0.3 then scrollBy(-y * 12) end
  end)
  return true
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local function scrollArea()
  local sf = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(CONTENT_W - 32, 10)
  sf:SetScrollChild(child)
  return sf, child
end

local function build()
  buildSections()

  win = CreateFrame("Frame", "ForeverMetricsFrame", UIParent, "BackdropTemplate")
  FM:Skin(win, { edge = 16 })
  win:SetSize(W, H)
  win:SetPoint("CENTER")
  win:SetClampedToScreen(true)
  win:SetMovable(true); win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetFrameStrata("HIGH")
  tinsert(UISpecialFrames, "ForeverMetricsFrame") -- Esc closes it

  -- Header
  titleText = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleText:SetPoint("TOPLEFT", 20, -15)
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -3, -3)
  close:SetScript("OnClick", function() win:Hide() end)
  charNext = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  charNext:SetSize(26, 22); charNext:SetPoint("TOPRIGHT", -38, -10); charNext:SetText(">")
  charNext:SetScript("OnClick", function() cycle(1) end)
  charLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  charLabel:SetPoint("RIGHT", charNext, "LEFT", -10, 0)
  charPrev = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  charPrev:SetSize(26, 22); charPrev:SetPoint("RIGHT", charLabel, "LEFT", -10, 0); charPrev:SetText("<")
  charPrev:SetScript("OnClick", function() cycle(-1) end)
  local rule = win:CreateTexture(nil, "ARTWORK")
  setColor(rule, FM.THEME.border, 0.35)
  rule:SetPoint("TOPLEFT", 16, -40); rule:SetPoint("TOPRIGHT", -16, -40); rule:SetHeight(1)

  -- Side nav
  nav = CreateFrame("Frame", nil, win, "BackdropTemplate")
  FM:Skin(nav, { edge = 10, alpha = 0.45 })
  nav:SetPoint("TOPLEFT", 12, -48)
  nav:SetPoint("BOTTOMLEFT", 12, 34)
  nav:SetWidth(NAV_W)
  nav.focusEdge = nav:CreateTexture(nil, "OVERLAY")
  setColor(nav.focusEdge, FM.THEME.bar, 0.5)
  nav.focusEdge:SetPoint("TOPRIGHT", -2, -6); nav.focusEdge:SetPoint("BOTTOMRIGHT", -2, 6); nav.focusEdge:SetWidth(2)
  nav.focusEdge:Hide()

  local y = -8
  for i, s in ipairs(SECTIONS) do
    if s.divider then
      y = y - 6
      local d = nav:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      d:SetPoint("TOPLEFT", 14, y - 4)
      d:SetText(s.divider:upper())
      local line = nav:CreateTexture(nil, "ARTWORK")
      setColor(line, FM.THEME.border, 0.25)
      line:SetPoint("LEFT", d, "RIGHT", 6, 0); line:SetPoint("RIGHT", nav, "RIGHT", -10, 0); line:SetHeight(1)
      y = y - 22
    else
      local b = CreateFrame("Button", nil, nav)
      b:SetSize(NAV_W - 12, 26)
      b:SetPoint("TOPLEFT", 6, y)
      b.sel = b:CreateTexture(nil, "BACKGROUND")
      b.sel:SetAllPoints(); setColor(b.sel, FM.THEME.hl)
      b.bar = b:CreateTexture(nil, "ARTWORK")
      setColor(b.bar, FM.THEME.bar)
      b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
      local mh = b:CreateTexture(nil, "HIGHLIGHT")
      mh:SetAllPoints(); setColor(mh, FM.THEME.hl, 0.1)
      b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      b.label:SetPoint("LEFT", 14, 0)
      b.label:SetText(s.label)
      b:SetScript("OnClick", function() ui.focus = "nav"; selectSection(i) end)
      navButtons[i] = b
      y = y - 28
    end
  end

  -- Content area
  content = CreateFrame("Frame", nil, win)
  content:SetPoint("TOPLEFT", 12 + NAV_W + 12, -48)
  content:SetPoint("BOTTOMRIGHT", -14, 34)

  -- Tabs (a small pool, reused by every section)
  for i = 1, 5 do
    local b = CreateFrame("Button", nil, content)
    b:SetHeight(26)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(); setColor(b.bg, FM.THEME.hl, 0.12)
    b.under = b:CreateTexture(nil, "ARTWORK")
    setColor(b.under, FM.THEME.bar)
    b.under:SetPoint("BOTTOMLEFT"); b.under:SetPoint("BOTTOMRIGHT"); b.under:SetHeight(2)
    local mh = b:CreateTexture(nil, "HIGHLIGHT")
    mh:SetAllPoints(); setColor(mh, FM.THEME.hl, 0.1)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("CENTER", 0, 1)
    b:SetScript("OnClick", function() selectTab(i) end)
    b:Hide()
    tabButtons[i] = b
  end

  -- Page bodies
  textScroll, textChild = scrollArea()
  text = textChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", 6, -4)
  text:SetWidth(CONTENT_W - 44)
  text:SetJustifyH("LEFT")
  text:SetSpacing(4)

  opts, optsChild = scrollArea()
  optsNote = optsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  optsNote:SetJustifyH("LEFT")
  optsNote:SetSpacing(3)

  buildDash()

  hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOM", 0, 13)

  win:SetScript("OnShow", function() ui.focus = "nav"; refresh() end)
  win:SetScript("OnHide", function() setPropagate(true) end)
  win.usesPad = setupGamepad()

  -- Keep the dashboard's timers ticking while it's open
  C_Timer.NewTicker(5, function()
    if win:IsShown() and curTab().kind == "dash" then pcall(fillDash) end
  end)

  ui.sec = sectionIndex("home") or 1
  win:Hide()
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

local function openAt(key, tab)
  if not FM.char then return end
  if not win then build() end
  local i = sectionIndex(key)
  if i then
    ui.sec = i
    if tab then ui.tabs[key] = tab end
  end
  ui.focus = "nav"
  if win:IsShown() then refresh() else win:Show() end
end

function FM:OpenSettings() openAt("interface") end
function FM:OpenDuo() openAt("duo", 1) end

function FM:ToggleUI()
  if not self.char then return end
  if not win then build() end
  if win:IsShown() then win:Hide() else win:Show() end
end
