-- Forever Metrics: mail contacts
-- A small list beside the Send Mail tab: people you've mailed recently, your
-- friends (offline ones too, which the game's own name suggestions skip),
-- and your other characters on this realm. Click a name to fill in "To:".
-- Right-click a recent name to forget it.
--
-- Saved account-wide in ForeverMetricsDB.mail[<realm>] = { {n, t, c}, ... }
-- (name, last sent, times sent), newest first.

local ADDON, ns = ...
local FM = ns.FM

local MAX_RECENT = 15
local ROW_H = 18

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function realm() return safe(GetRealmName()) or "?" end

local function recentList()
  local db = FM:DB()
  db.mail = db.mail or {}
  db.mail[realm()] = db.mail[realm()] or {}
  return db.mail[realm()]
end

-- "bobbelcher " -> "Bobbelcher" (names are case-insensitive in game)
local function tidy(name)
  if type(name) ~= "string" then return nil end
  name = name:match("^%s*(.-)%s*$")
  if name == "" then return nil end
  return name:sub(1, 1):upper() .. name:sub(2)
end

local function remember(name)
  name = tidy(name)
  if not name then return end
  local list = recentList()
  local entry
  for i = #list, 1, -1 do
    if list[i].n:lower() == name:lower() then entry = table.remove(list, i) end
  end
  entry = entry or { n = name, c = 0 }
  entry.t, entry.c = time(), (entry.c or 0) + 1
  table.insert(list, 1, entry)
  while #list > MAX_RECENT do table.remove(list) end
end

local function forget(name)
  local list = recentList()
  for i = #list, 1, -1 do
    if list[i].n:lower() == name:lower() then table.remove(list, i) end
  end
end

-- Everyone on your friends list, online or not
local function friends()
  local out = {}
  if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
    for i = 1, C_FriendList.GetNumFriends() or 0 do
      local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
      local n = ok and type(info) == "table" and safe(info.name)
      if n then out[#out + 1] = { n = n, online = safe(info.connected) } end
    end
  elseif GetNumFriends and GetFriendInfo then
    for i = 1, GetNumFriends() or 0 do
      local n, _, _, _, connected = GetFriendInfo(i)
      n = safe(n)
      if n then out[#out + 1] = { n = n, online = safe(connected) } end
    end
  end
  table.sort(out, function(a, b) return a.n < b.n end)
  return out
end

-- Your other characters on this realm (from Forever Metrics' saved data)
local function alts()
  local out, here = {}, realm()
  for key, c in pairs(FM:DB().chars or {}) do
    if key ~= FM:CharKey() and c.realm == here and c.name then out[#out + 1] = { n = c.name, class = c.class } end
  end
  table.sort(out, function(a, b) return a.n < b.n end)
  return out
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local panel, rows = nil, {}

local function fill(name)
  local box = _G.SendMailNameEditBox
  if not box then return end
  box:SetText(name)
  if box.SetCursorPosition then box:SetCursorPosition(#name) end
  local subject = _G.SendMailSubjectEditBox
  if subject and subject.SetFocus then subject:SetFocus() end
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, panel)
  r:SetSize(150, ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(); hl:SetColorTexture(FM.THEME.hl[1], FM.THEME.hl[2], FM.THEME.hl[3], 0.25)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", 6, 0); r.text:SetPoint("RIGHT", -4, 0)
  r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
  r:SetScript("OnClick", function(self, button)
    if not self.name then return end
    if button == "RightButton" and self.recent then
      forget(self.name)
      FM:RefreshMailContacts()
    else
      fill(self.name)
    end
  end)
  r:SetScript("OnEnter", function(self)
    if not self.name then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.name)
    if self.tip then GameTooltip:AddLine(self.tip, 0.8, 0.75, 0.65) end
    GameTooltip:AddLine("Click: send to " .. self.name, 0.5, 0.9, 0.5)
    if self.recent then GameTooltip:AddLine("Right-click: forget", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

local function build()
  local parent = _G.MailFrame or UIParent
  panel = CreateFrame("Frame", "ForeverMetricsMailContacts", parent, "BackdropTemplate")
  FM:Skin(panel, { edge = 12 })
  panel:SetWidth(166)
  panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, -28)
  panel:SetFrameStrata(parent:GetFrameStrata() or "MEDIUM")
  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.title:SetPoint("TOPLEFT", 10, -9)
  panel.title:SetText("Send to")
  panel:Hide()
end

local function age(t)
  local d = time() - (t or 0)
  if d < 3600 then return "today" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

function FM:RefreshMailContacts()
  if not panel then return end
  local sendTab = _G.SendMailFrame and _G.SendMailFrame:IsShown()
  if not FM:GetSetting("mailContacts") or not sendTab then panel:Hide(); return end

  local seen, i, y = {}, 0, -28
  local function header(text)
    i = i + 1
    local r = getRow(i)
    r.name, r.recent, r.tip = nil, nil, nil
    r.text:SetText("|cffa8977a" .. text:upper() .. "|r")
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 8, y)
    r:Show()
    y = y - ROW_H
  end
  local function add(name, label, tip, recent)
    if not name or seen[name:lower()] then return end
    seen[name:lower()] = true
    i = i + 1
    local r = getRow(i)
    r.name, r.recent, r.tip = name, recent, tip
    r.text:SetText(label or name)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 8, y)
    r:Show()
    y = y - ROW_H
  end

  local me = (safe(UnitName("player")) or ""):lower()
  seen[me] = true

  local recent = recentList()
  if #recent > 0 then
    header("Recent")
    for _, e in ipairs(recent) do
      add(e.n, e.n, ("Mailed %d time%s, last %s"):format(e.c or 1, (e.c or 1) == 1 and "" or "s", age(e.t)), true)
    end
  end
  local f = friends()
  local firstFriend = true
  for _, e in ipairs(f) do
    if not seen[e.n:lower()] then
      if firstFriend then header("Friends"); firstFriend = false end
      add(e.n, e.online and e.n or ("|cff9d9d9d" .. e.n .. "|r"), e.online and "Online" or "Offline")
    end
  end
  local a = alts()
  local firstAlt = true
  for _, e in ipairs(a) do
    if not seen[e.n:lower()] then
      if firstAlt then header("Your characters"); firstAlt = false end
      local col = RAID_CLASS_COLORS and e.class and RAID_CLASS_COLORS[e.class]
      add(e.n, col and ("|c" .. (col.colorStr or "ffffffff") .. e.n .. "|r") or e.n, "Your character")
    end
  end
  for j = i + 1, #rows do rows[j]:Hide() end

  if i == 0 then
    panel.title:SetText("Send to\n|cffa8977aPeople you mail show up here.|r")
    panel:SetHeight(56)
  else
    panel.title:SetText("Send to")
    panel:SetHeight(-y + 10)
  end
  panel:Show()
end

---------------------------------------------------------------------------
-- Remember who mail goes to: SendMail is hooked for the name, and it's saved
-- once the game confirms the mail went.
---------------------------------------------------------------------------

local pending
if type(SendMail) == "function" then
  hooksecurefunc("SendMail", function(recipient) pending = safe(recipient) end)
end

local hooked = false
local function hookFrames()
  if hooked or not _G.SendMailFrame then return end
  hooked = true
  build()
  _G.SendMailFrame:HookScript("OnShow", function() FM:RefreshMailContacts() end)
  _G.SendMailFrame:HookScript("OnHide", function() if panel then panel:Hide() end end)
end

local ev = CreateFrame("Frame")
local H = {}
function H.MAIL_SHOW()
  hookFrames()
  if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end -- refresh the list
  FM:RefreshMailContacts()
end
function H.MAIL_SEND_SUCCESS()
  local name = pending
  if not name and _G.SendMailNameEditBox then name = safe(_G.SendMailNameEditBox:GetText()) end
  pending = nil
  if FM:GetSetting("mailContacts") then remember(name) end
  FM:RefreshMailContacts()
end
function H.MAIL_FAILED() pending = nil end
function H.FRIENDLIST_UPDATE() if panel and panel:IsShown() then FM:RefreshMailContacts() end end

ev:SetScript("OnEvent", function(_, event, ...)
  if not FM:Char() then return end
  local ok, err = pcall(H[event], ...)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics mail error|r", event, err) end
end)
for event in pairs(H) do pcall(ev.RegisterEvent, ev, event) end

FM:OnSetting("mailContacts", function() FM:RefreshMailContacts() end)
