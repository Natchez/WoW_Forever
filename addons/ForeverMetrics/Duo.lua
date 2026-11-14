-- Forever Metrics: Duo mode
-- Two players running Forever Metrics find each other through hidden addon
-- messages (guild channel, party/raid, then whispers once paired). After you
-- approve a partner once, every character on their WoW account is recognized
-- automatically, so alts just work.
--
-- What gets shared: current character + level/XP/zone, account-wide stat
-- totals (for the head-to-head scoreboard), and highlights from their feed
-- (level-ups, rare finds, deaths, skill and gathering milestones).
-- Locally we also track "together" stats while you're grouped.

local ADDON, ns = ...
local FM = ns.FM

local PREFIX = "FMDUO"
local PROTO = 1
local ONLINE_WINDOW = 150   -- seconds without a message before a partner counts as offline
local TICK = 10             -- seconds between together-tracking / XP update ticks
local FULL_EVERY = 60       -- seconds between full stat snapshots
local FEED_MAX = 100        -- partner feed entries kept

local Duo = { online = {}, offered = {} }
FM.Duo = Duo

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function db()
  local d = FM:DB()
  d.duo = d.duo or {}
  local D = d.duo
  if not D.id then
    -- Random id for this WoW account, so a partner's alts all map to one person
    local t = {}
    for i = 1, 10 do t[i] = ("%x"):format(math.random(0, 15)) end
    D.id = table.concat(t)
  end
  D.partners = D.partners or {}
  return D
end

local function enabled() return FM:GetSetting("duo") end

-- Duo notices (online, offline, new partner) go to the on-screen feed instead
-- of chat. If the feed is turned off they fall back to a single chat line.
local function notify(text)
  if FM:GetSetting("feed") and FM.OnNewEntry then
    FM:OnNewEntry({ t = time(), k = "duo", x = text })
  else
    print("|cffe8c27aForever Metrics|r |cffff7eb6Duo:|r " .. text)
  end
end

local function short(name) return Ambiguate and Ambiguate(name, "none") or (name:match("^[^-]+") or name) end

local function commas(n)
  n = math.floor(n or 0)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  local s = tostring(n)
  while true do
    local k; s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then return s end
  end
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
  return ("%dg"):format(math.floor(c / 10000))
end

local function classWrap(class, text)
  local col = class and C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
  if col then return col:WrapTextInColorCode(text) end
  local rc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if rc and rc.colorStr then return "|c" .. rc.colorStr .. text .. "|r" end
  return text
end

local function hdr(t) return "|cffe8c27a" .. t .. "|r\n" end

-- key=value;key=value encoding for small tables
local function clean(v) return (tostring(v == nil and "" or v):gsub("[;=~]", "")) end
local function encode(t)
  local out = {}
  for k, v in pairs(t) do out[#out + 1] = k .. "=" .. clean(v) end
  return table.concat(out, ";")
end
local function decode(s)
  local t = {}
  for k, v in (s or ""):gmatch("([^;=]+)=([^;]*)") do t[k] = tonumber(v) or v end
  return t
end

-- Stat summary for one character (also summed for account totals)
local function statsOf(c)
  local s, L = c.stats or {}, c.loot or {}
  local q = L.q or {}
  local nodes = 0
  for _, g in pairs(c.gathering or {}) do nodes = nodes + (g.nodes or 0) end
  return {
    k = s.kills or 0, d = s.deaths or 0, q = s.quests or 0, lv = s.levels or 0,
    g = q[2] or 0, b = q[3] or 0, e = (q[4] or 0) + (q[5] or 0),
    nd = nodes, gl = s.goldLooted or 0, p = c.played or 0,
  }
end

local function accountStats()
  local tot = {}
  for _, c in pairs(FM:DB().chars) do
    for k, v in pairs(statsOf(c)) do tot[k] = (tot[k] or 0) + v end
  end
  return tot
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function sendRaw(typ, payload, channel, target)
  if not enabled() then return false end
  local msg = typ .. "~" .. db().id .. "~" .. (payload or "")
  if #msg > 255 then return false end
  local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if not fn then return false end
  local ok = pcall(fn, PREFIX, msg, channel, target)
  return ok
end

local function helloPayload()
  return encode({ v = PROTO, n = UnitName("player") })
end

local function charPayload()
  local c = FM:Char()
  if not c then return "" end
  local _, class = UnitClass("player")
  local t = statsOf(c)
  t.n = UnitName("player"); t.c = class; t.l = UnitLevel("player")
  t.x = UnitXP("player"); t.m = UnitXPMax("player")
  t.r = (GetXPExhaustion and GetXPExhaustion()) or 0
  t.z = safe(GetRealZoneText and GetRealZoneText()) or ""
  return encode(t)
end

-- Send to every partner character currently online
local function toOnline(typ, payload)
  for _, o in pairs(Duo.online) do sendRaw(typ, payload, "WHISPER", o.who) end
end

local function anyOnline() return next(Duo.online) ~= nil end

function Duo:SendSnapshot(target, full)
  if target then
    sendRaw("C", charPayload(), "WHISPER", target)
    if full then sendRaw("A", encode(accountStats()), "WHISPER", target) end
  else
    toOnline("C", charPayload())
    if full then toOnline("A", encode(accountStats())) end
  end
end

function Duo:Broadcast()
  if not enabled() then return end
  local p = helloPayload()
  if IsInGuild and IsInGuild() then sendRaw("H", p, "GUILD") end
  if IsInRaid and IsInRaid() then sendRaw("H", p, "RAID")
  elseif IsInGroup and IsInGroup() then sendRaw("H", p, "PARTY") end
end

-- Share highlights from your own feed
local SHARE = { level = true, death = true, skill = true, gather = true, loot = true }
function Duo:Share(kind, text)
  if not enabled() or not anyOnline() or not SHARE[kind] then return end
  if kind == "loot" and not text:find("FIND!") then return end -- blues and better only
  local payload = kind .. "^" .. text
  if #payload > 200 then -- too long with item link markup: fall back to plain text
    payload = kind .. "^" .. text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
  end
  toOnline("E", payload)
  if kind == "level" then self:SendSnapshot(nil, true) end
end

-- Wrap Core's logger so feed highlights go out automatically
local origLog = FM.Log
function FM:Log(kind, text)
  origLog(self, kind, text)
  if kind ~= "duo" then pcall(Duo.Share, Duo, kind, text) end
end

---------------------------------------------------------------------------
-- Partners
---------------------------------------------------------------------------

local function newPartner(nick)
  return { nick = nick, added = time(), chars = {}, acct = {}, feed = {},
           together = { time = 0, kills = 0, quests = 0, levels = 0 } }
end

function Duo:MarkOnline(id, who)
  local was = self.online[id]
  self.online[id] = { who = who, t = GetTime() }
  local P = db().partners[id]
  if P then P.lastSeen = time() end
  if not was and P then
    notify(("|cffff7eb6%s|r is online (%s)"):format(P.nick, short(who)))
  end
  self:UpdateStrip()
end

function Duo:MarkOffline(id, quiet)
  if not self.online[id] then return end
  self.online[id] = nil
  local P = db().partners[id]
  if P and not quiet then notify(("|cffff7eb6%s|r logged off"):format(P.nick)) end
  self:UpdateStrip()
  if FM.OnUpdateUI then FM:OnUpdateUI() end
end

-- Which partner (if any) is playing this character name right now?
function Duo:OnlineIdFor(name)
  if not name then return end
  name = short(name):lower()
  for id, o in pairs(self.online) do
    if short(o.who):lower() == name then return id end
  end
end

-- Is this one of our partners' characters (online or not)?
function Duo:IsPartnerChar(name)
  if not name then return false end
  name = short(name):lower()
  if self:OnlineIdFor(name) then return true end
  for _, P in pairs(db().partners) do
    for n in pairs(P.chars) do if n:lower() == name then return true end end
  end
  return false
end

-- Turn "No player named '%s' is currently playing." into a Lua pattern
local function fmtToPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%%s", "(.+)")
  return "^" .. p .. "$"
end
local PAT_NOT_FOUND = fmtToPattern(ERR_CHAT_PLAYER_NOT_FOUND_S) or "^No player named '(.+)' is currently playing%.$"
local PAT_OFFLINE   = fmtToPattern(ERR_FRIEND_OFFLINE_S) or "^(.+) has gone offline%.$"

-- Partner logged out: the guild "has gone offline" line, or our whisper bouncing
function Duo:OnSystemMessage(msg)
  local name = msg:match(PAT_OFFLINE) or msg:match(PAT_NOT_FOUND)
  if not name then return end
  name = name:gsub("|H.-|h", ""):gsub("|h", ""):gsub("[%[%]]", "") -- strip player links
  local id = self:OnlineIdFor(name)
  if id then self:MarkOffline(id) end
end

-- Hide "No player named X is currently playing" for partner characters: those
-- come from our own background whispers racing their logout, not from you.
if ChatFrame_AddMessageEventFilter then
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg, ...)
    msg = safe(msg)
    if not msg or not enabled() then return false end
    local name = msg:match(PAT_NOT_FOUND)
    if name and Duo:IsPartnerChar(name) then return true end
    return false, msg, ...
  end)
end

function Duo:Add(id, who)
  local D = db()
  local name = short(who)
  if not D.partners[id] then
    D.partners[id] = newPartner(name)
    notify(("|cffff7eb6%s|r is now your duo partner!"):format(name))
    print(("|cffe8c27aForever Metrics|r |cffff7eb6Duo:|r rename %s with |cffffff00/fm duo name <nickname>|r."):format(name))
    FM:Log("duo", "Teamed up with " .. name)
  end
  self:MarkOnline(id, who)
  sendRaw("H", helloPayload(), "WHISPER", who)
  self:SendSnapshot(who, true)
end

function Duo:Offer(id, who)
  if self.offered[id] then return end
  self.offered[id] = true
  if not StaticPopupDialogs then return end
  StaticPopupDialogs.FOREVERMETRICS_DUO = StaticPopupDialogs.FOREVERMETRICS_DUO or {
    text = "%s is running Forever Metrics.\n\nAdd them as your duo partner? You'll share levels, rare finds and stats with each other.",
    button1 = "Add partner",
    button2 = "Not now",
    OnAccept = function(self, data)
      data = data or self.data
      if data then Duo:Add(data.id, data.who) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopup_Show("FOREVERMETRICS_DUO", short(who), nil, { id = id, who = who })
end

local function pushFeed(P, kind, text)
  local e = { t = time(), k = kind, x = text, who = P.current }
  P.feed[#P.feed + 1] = e
  while #P.feed > FEED_MAX do table.remove(P.feed, 1) end
  if FM:GetSetting("duoFeed") and FM.OnNewEntry then
    FM:OnNewEntry({ t = e.t, k = "duo", x = ("|cffff7eb6%s:|r %s"):format(P.nick, text) })
  end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

function Duo:OnMessage(text, channel, sender)
  if not enabled() then return end
  local typ, id, payload = text:match("^(%a)~(%w+)~(.*)$")
  if not typ or id == db().id then return end
  local P = db().partners[id]

  if typ == "H" or typ == "R" then
    if not P then return self:Offer(id, sender) end
    self:MarkOnline(id, sender)
    if typ == "H" then sendRaw("R", helloPayload(), "WHISPER", sender) end
    self:SendSnapshot(sender, true)
    return
  end

  if not P then return end -- everything below is partner-only
  self:MarkOnline(id, sender)

  if typ == "C" then
    local t = decode(payload)
    if not t.n then return end
    P.chars[t.n] = P.chars[t.n] or {}
    local ch = P.chars[t.n]
    ch.name, ch.class, ch.level, ch.xp, ch.xpMax, ch.rested, ch.zone =
      t.n, t.c, t.l, t.x, t.m, t.r, t.z
    ch.stats = { k = t.k, d = t.d, q = t.q, lv = t.lv, g = t.g, b = t.b, e = t.e, nd = t.nd, gl = t.gl, p = t.p }
    ch.lastSeen = time()
    P.current = t.n
  elseif typ == "A" then
    P.acct = decode(payload)
  elseif typ == "E" then
    local kind, msg = payload:match("^(%a+)%^(.*)$")
    if kind and msg then pushFeed(P, kind, msg) end
  elseif typ == "B" then
    self:MarkOffline(id)
  end
  self:UpdateStrip()
  if FM.OnUpdateUI then FM:OnUpdateUI() end
end

---------------------------------------------------------------------------
-- Together tracking (while grouped with an online partner)
---------------------------------------------------------------------------

local last = {}
local function groupedPartner()
  for id, o in pairs(Duo.online) do
    local n = short(o.who)
    if (UnitInParty and UnitInParty(n)) or (UnitInRaid and UnitInRaid(n)) then return id end
  end
end

local function trackTogether()
  local c = FM:Char()
  if not c then return end
  local s = c.stats
  local dk = s.kills - (last.k or s.kills)
  local dq = s.quests - (last.q or s.quests)
  local dl = s.levels - (last.l or s.levels)
  last.k, last.q, last.l = s.kills, s.quests, s.levels

  local id = groupedPartner()
  local P = id and db().partners[id]
  if not P then return end
  local T = P.together
  local before = { time = T.time, kills = T.kills }
  T.time = T.time + TICK
  T.kills = T.kills + math.max(0, dk)
  T.quests = T.quests + math.max(0, dq)
  T.levels = T.levels + math.max(0, dl)
  if math.floor(T.time / 3600) > math.floor(before.time / 3600) then
    FM:Log("duo", ("%d hours adventuring with %s"):format(math.floor(T.time / 3600), P.nick))
  end
  if math.floor(T.kills / 250) > math.floor(before.kills / 250) then
    FM:Log("duo", ("%s kills together with %s!"):format(commas(math.floor(T.kills / 250) * 250), P.nick))
  end
end

---------------------------------------------------------------------------
-- Partner XP strip (tucked under the XP pill)
---------------------------------------------------------------------------

local strip
local function buildStrip()
  local pill = _G.ForeverMetricsPill
  if strip or not pill then return end
  strip = CreateFrame("Frame", nil, pill, "BackdropTemplate")
  FM:Skin(strip, { edge = 10, alpha = 0.78 })
  strip:SetPoint("TOP", pill, "BOTTOM", 0, 1)
  strip:SetHeight(22)
  strip.text = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  strip.text:SetPoint("TOP", 0, -5)
  local T = FM.THEME
  strip.bg = strip:CreateTexture(nil, "ARTWORK")
  strip.bg:SetColorTexture(0, 0, 0, 0.6)
  strip.bg:SetPoint("BOTTOMLEFT", 9, 4); strip.bg:SetPoint("BOTTOMRIGHT", -9, 4); strip.bg:SetHeight(2)
  strip.fill = strip:CreateTexture(nil, "ARTWORK", nil, 2)
  strip.fill:SetColorTexture(1, 0.49, 0.71, 0.9)
  strip.fill:SetPoint("BOTTOMLEFT", strip.bg); strip.fill:SetHeight(2)
  strip:EnableMouse(true)
  strip:SetScript("OnMouseUp", function() if FM.OpenDuo then FM:OpenDuo() end end)
  strip:Hide()
end

function Duo:UpdateStrip()
  buildStrip()
  if not strip then return end
  local show = enabled() and FM:GetSetting("duoBar")
  local P, ch
  if show then
    local best
    for id, o in pairs(self.online) do
      if not best or o.t > best.t then best = { id = id, t = o.t } end
    end
    P = best and db().partners[best.id]
    ch = P and P.current and P.chars[P.current]
  end
  if not ch then strip:Hide(); return end
  local pct = (ch.xpMax or 0) > 0 and (ch.xp or 0) / ch.xpMax or 0
  strip.text:SetText(("|cffff7eb6%s|r  %s  |cffa8977aLv|r %s  |cffa8977a%d%%|r"):format(
    P.nick, classWrap(ch.class, ch.name or "?"), ch.level or "?", math.floor(pct * 100)))
  local w = math.max(strip.text:GetStringWidth() + 28, 130)
  strip:SetWidth(w)
  strip.fill:SetWidth(math.max(0.001, (w - 18) * math.min(1, pct)))
  strip:Show()
end

---------------------------------------------------------------------------
-- Duo tab (rendered into the main window's text area)
---------------------------------------------------------------------------

local ROWS = {
  { "p",  "Time played", dur },
  { "lv", "Levels gained" },
  { "k",  "Kills" },
  { "q",  "Quests" },
  { "d",  "Deaths", nil, true },  -- fewer is better
  { "g",  "Greens" },
  { "b",  "Blues" },
  { "e",  "Epics" },
  { "nd", "Nodes gathered" },
  { "gl", "Gold looted", money },
}

function FM:RenderDuo()
  local D = db()
  local out = {}
  if not enabled() then
    return "Duo mode is off. Turn it on in the Options tab on this page."
  end
  if not next(D.partners) then
    out[#out + 1] = hdr("No duo partner yet")
    out[#out + 1] = "  When someone in your guild or group is also running Forever Metrics,\n"
    out[#out + 1] = "  you'll get a popup asking to add them. You can also type\n"
    out[#out + 1] = "  |cffffff00/fm duo add CharacterName|r to send them a request.\n"
    return table.concat(out)
  end

  local mine = accountStats()
  for id, P in pairs(D.partners) do
    local online = self.Duo.online[id]
    local ch = P.current and P.chars[P.current]
    out[#out + 1] = hdr(("|cffff7eb6%s|r  %s"):format(P.nick, online and "|cff7fd36bonline|r" or "|cff888888offline|r"))
    if ch then
      local pct = (ch.xpMax or 0) > 0 and math.floor((ch.xp or 0) / ch.xpMax * 100) or 0
      if online then
        out[#out + 1] = ("  Playing %s, level %s (%d%%) in %s\n"):format(
          classWrap(ch.class, ch.name), ch.level or "?", pct, ch.zone ~= "" and ch.zone or "somewhere")
      else
        out[#out + 1] = ("  Last seen %s on %s, level %s\n"):format(
          P.lastSeen and date("%m/%d %H:%M", P.lastSeen) or "?", classWrap(ch.class, ch.name), ch.level or "?")
      end
    end
    local alts = {}
    for n, c in pairs(P.chars) do alts[#alts + 1] = { n = n, c = c } end
    table.sort(alts, function(a, b) return (a.c.level or 0) > (b.c.level or 0) end)
    if #alts > 1 then
      local list = {}
      for _, a in ipairs(alts) do list[#list + 1] = classWrap(a.c.class, a.n) .. " " .. (a.c.level or "?") end
      out[#out + 1] = "  |cffa8977aCharacters:|r " .. table.concat(list, ", ") .. "\n"
    end

    -- Head to head (account totals)
    out[#out + 1] = "\n" .. hdr("Head to head  |cffa8977a(all characters)|r")
    if not next(P.acct or {}) then
      out[#out + 1] = "  Waiting for their stats. They show up once you're both online.\n"
    else
      local youWins, themWins = 0, 0
      for _, r in ipairs(ROWS) do
        local key, label, fmt, lowerBetter = r[1], r[2], r[3] or commas, r[4]
        local a, b = mine[key] or 0, tonumber(P.acct[key]) or 0
        local you, them = fmt(a), fmt(b)
        local youLead = lowerBetter and a < b or (not lowerBetter and a > b)
        local themLead = lowerBetter and b < a or (not lowerBetter and b > a)
        if youLead then youWins = youWins + 1; you = "|cffe8c27a" .. you .. "|r"
        elseif themLead then themWins = themWins + 1; them = "|cffff7eb6" .. them .. "|r" end
        out[#out + 1] = ("  %s:  You %s  |cffa8977avs|r  %s %s\n"):format(label, you, P.nick, them)
      end
      local verdict
      if youWins > themWins then verdict = ("You lead %d to %d"):format(youWins, themWins)
      elseif themWins > youWins then verdict = ("%s leads %d to %d"):format(P.nick, themWins, youWins)
      else verdict = ("Dead even at %d each"):format(youWins) end
      out[#out + 1] = "  |cffe8c27a" .. verdict .. "|r\n"
    end

    -- Together
    local T = P.together
    out[#out + 1] = "\n" .. hdr("Together  |cffa8977a(while grouped)|r")
    if T.time == 0 then
      out[#out + 1] = "  Group up and this starts counting.\n"
    else
      out[#out + 1] = ("  %s adventuring  ·  %s kills  ·  %s quests  ·  %s levels\n"):format(
        dur(T.time), commas(T.kills), commas(T.quests), commas(T.levels))
    end

    -- Their recent highlights
    out[#out + 1] = "\n" .. hdr("Their highlights")
    if #P.feed == 0 then out[#out + 1] = "  Level-ups, rare finds and deaths show up here.\n" end
    for i = #P.feed, math.max(1, #P.feed - 19), -1 do
      local e = P.feed[i]
      out[#out + 1] = ("  |cff888888%s|r  %s%s\n"):format(date("%m/%d %H:%M", e.t),
        e.who and ("|cffa8977a" .. e.who .. ":|r ") or "", e.x)
    end
    out[#out + 1] = "\n"
  end
  return table.concat(out)
end

---------------------------------------------------------------------------
-- Slash: /fm duo ...
---------------------------------------------------------------------------

local function findPartner(name)
  name = (name or ""):lower()
  for id, P in pairs(db().partners) do
    if P.nick:lower() == name then return id, P end
    for n in pairs(P.chars) do if n:lower() == name then return id, P end end
  end
end

function FM:DuoCommand(rest)
  local cmd, val = (rest or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  local D = db()
  if cmd == "add" and val ~= "" then
    sendRaw("H", helloPayload(), "WHISPER", val)
    Duo.offered = {}
    print("|cffe8c27aForever Metrics|r |cffff7eb6Duo:|r sent a request to " .. val .. ". They'll get a popup if they're online and running Forever Metrics.")
  elseif cmd == "remove" and val ~= "" then
    local id, P = findPartner(val)
    if not id then return print("Forever Metrics: no duo partner named " .. val) end
    D.partners[id] = nil
    Duo.online[id] = nil
    Duo:UpdateStrip()
    print("Forever Metrics: removed duo partner " .. P.nick)
  elseif cmd == "name" and val ~= "" then
    local who, nick = val:match("^(%S+)%s+(.+)$")
    local id, P
    if who then id, P = findPartner(who) end
    if not P then
      local n = 0
      for i, p in pairs(D.partners) do n = n + 1; id, P = i, p end
      if n ~= 1 then return print("Forever Metrics: use /fm duo name <partner> <nickname>") end
      nick = val
    end
    P.nick = nick
    Duo:UpdateStrip()
    if FM.OnUpdateUI then FM:OnUpdateUI() end
    print("Forever Metrics: duo partner is now called " .. nick)
  elseif cmd == "ping" then
    Duo:Broadcast()
    print("Forever Metrics: looking for your duo partner...")
  else
    local any = false
    for id, P in pairs(D.partners) do
      any = true
      local o = Duo.online[id]
      print(("|cffff7eb6%s|r: %s"):format(P.nick, o and ("online as " .. short(o.who)) or "offline"))
    end
    if not any then print("Forever Metrics: no duo partner yet.") end
    print("/fm duo [list | add Name | remove Name | name [partner] Nickname | ping]")
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local lastRoster, sinceFull, dirty = 0, 0, false

ev:SetScript("OnEvent", function(_, event, ...)
  local ok, err = pcall(function(...)
    if event == "PLAYER_LOGIN" then
      if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
      elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
      end
      db()
      C_Timer.After(8, function() Duo:Broadcast() end)
      C_Timer.After(2, function() Duo:UpdateStrip() end)
      C_Timer.NewTicker(TICK, function()
        if not enabled() then return end
        pcall(trackTogether)
        -- drop partners we haven't heard from
        local now = GetTime()
        for id, o in pairs(Duo.online) do
          if now - o.t > ONLINE_WINDOW then Duo:MarkOffline(id) end
        end
        if not anyOnline() then return end
        sinceFull = sinceFull + TICK
        if sinceFull >= FULL_EVERY then
          sinceFull = 0; dirty = false
          Duo:SendSnapshot(nil, true)
        elseif dirty then
          dirty = false
          Duo:SendSnapshot(nil, false)
        end
      end)
      FM:OnSetting("duo", function(v)
        if v then Duo:Broadcast() else Duo.online = {} end
        Duo:UpdateStrip()
      end)
      FM:OnSetting("duoBar", function() Duo:UpdateStrip() end)
      FM:OnSetting("pill", function() Duo:UpdateStrip() end)
    elseif event == "CHAT_MSG_ADDON" then
      local prefix, text, channel, sender = ...
      prefix, text, sender = safe(prefix), safe(text), safe(sender)
      if prefix == PREFIX and text and sender then Duo:OnMessage(text, channel, sender) end
    elseif event == "CHAT_MSG_SYSTEM" then
      local msg = safe((...))
      if msg and enabled() then Duo:OnSystemMessage(msg) end
    elseif event == "GROUP_ROSTER_UPDATE" then
      if GetTime() - lastRoster > 5 then
        lastRoster = GetTime()
        C_Timer.After(2, function() Duo:Broadcast() end)
      end
    elseif event == "PLAYER_XP_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" then
      dirty = true
    elseif event == "PLAYER_LOGOUT" then
      toOnline("B", "")
    end
  end, ...)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics duo error|r", event, err) end
end)

for _, e in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_ADDON", "CHAT_MSG_SYSTEM", "GROUP_ROSTER_UPDATE",
                     "PLAYER_XP_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_LOGOUT" }) do
  pcall(ev.RegisterEvent, ev, e)
end
