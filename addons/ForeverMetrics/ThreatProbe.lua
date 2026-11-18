-- Forever Metrics: threat probe (temporary)
-- Finds out what Forever's threat functions give an addon before a threat
-- meter is built on them, since the combat log is blocked here.
--   /fm threat test    one snapshot for your target, printed in chat
--   /fm threat watch   while you fight, one compact line in the on-screen feed
--                      whenever threat changes ("Kil'hala 100% tank · You
--                      72%"), and a count of threat events after each fight
-- For each of you, your pet, and your party (and their pets): the result of
-- UnitThreatSituation and UnitDetailedThreatSituation against your target,
-- and whether each value is a "secret" the addon can't read.

local ADDON, ns = ...
local FM = ns.FM

local function say(msg) print("|cffe8c27aForever Metrics threat|r " .. msg) end

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end

-- A value as text, or "SECRET"
local function show(v)
  if isSecret(v) then return "|cffff6b6bSECRET|r" end
  if v == nil then return "nil" end
  if type(v) == "number" then return (v % 1 == 0) and tostring(v) or ("%.1f"):format(v) end
  return tostring(v)
end

local function units()
  local list = { "player", "pet" }
  for i = 1, 4 do list[#list + 1] = "party" .. i; list[#list + 1] = "partypet" .. i end
  return list
end

local function snapshot()
  local mob = "target"
  if not UnitExists(mob) then say("no target. Target a mob you're fighting, then try again."); return end
  local mobName = UnitName(mob)
  say(("target: %s  ·  hostile %s  ·  in combat %s"):format(show(mobName), show(UnitCanAttack("player", mob)), show(UnitAffectingCombat(mob))))
  say(("functions: UnitThreatSituation %s · UnitDetailedThreatSituation %s · GetThreatStatusColor %s"):format(
    type(UnitThreatSituation), type(UnitDetailedThreatSituation), type(GetThreatStatusColor)))
  for _, u in ipairs(units()) do
    if UnitExists(u) then
      local name = UnitName(u)
      local ok1, status = pcall(UnitThreatSituation or function() end, u, mob)
      local ok2, tanking, dstatus, scaled, raw, value = pcall(UnitDetailedThreatSituation or function() end, u, mob)
      local line = ("%s (%s): situation %s  ·  tanking %s  status %s  scaled %s%%  raw %s%%  value %s"):format(
        show(name), u, ok1 and show(status) or "|cffff6b6berror|r",
        ok2 and show(tanking) or "|cffff6b6berror|r", show(dstatus), show(scaled), show(raw), show(value))
      say(line)
      if not ok2 then say("  error: " .. tostring(tanking)) end
    end
  end
end

-- One line for the feed: "Kolkar Wrangler: Kil'hala 100% tank · You 72%"
local function compact()
  local mob = "target"
  if not UnitExists(mob) then return nil end
  local parts = {}
  for _, u in ipairs(units()) do
    if UnitExists(u) and pcall(UnitDetailedThreatSituation or error, u, mob) then
      local _, tanking, _, scaled = pcall(UnitDetailedThreatSituation, u, mob)
      local name = u == "player" and "You" or UnitName(u)
      name = isSecret(name) and u or (name or u)
      local pct
      if isSecret(scaled) then pct = "|cffff6b6bsecret|r"
      elseif scaled then pct = ("%d%%"):format(math.floor(scaled + 0.5))
      else pct = "-" end
      local tank = (not isSecret(tanking) and tanking) and " |cffe8c27atank|r" or ""
      parts[#parts + 1] = name .. " " .. pct .. tank
    end
  end
  if #parts == 0 then return nil end
  local mobName = UnitName(mob)
  return (isSecret(mobName) and "target" or (mobName or "target")) .. ": " .. table.concat(parts, "  ·  ")
end

-- Feed, or chat if the feed is turned off
local function post(text)
  if FM.OnNewEntry and FM:GetSetting("feed") then
    FM:OnNewEntry({ t = time(), k = "threat", x = text }) -- shown only, not saved to the history
  else
    say(text)
  end
end

-- Watching: compact lines during combat and a count of each threat event
local watch = { on = false, counts = {} }
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit)
  if not watch.on then return end
  if event == "PLAYER_REGEN_ENABLED" then
    local parts = {}
    for e, n in pairs(watch.counts) do parts[#parts + 1] = e .. " " .. n end
    post("fight over. Threat events: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
    watch.counts, watch.last = {}, nil
    return
  end
  watch.counts[event] = (watch.counts[event] or 0) + 1
end)
for _, e in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_ENABLED" }) do
  pcall(ev.RegisterEvent, ev, e)
end

local ticker
function FM:ThreatCommand(rest)
  rest = (rest or ""):lower()
  if rest == "move" then
    if FM.ThreatMove then FM:ThreatMove() end
  elseif rest == "watch" then
    watch.on = not watch.on
    if ticker then ticker:Cancel(); ticker = nil end
    if watch.on then
      watch.counts = {}
      ticker = C_Timer.NewTicker(1, function()
        if InCombatLockdown() and UnitExists("target") then
          local ok, line = pcall(compact)
          if not ok then say("error: " .. tostring(line)); return end
          if line and line ~= watch.last then watch.last = line; post(line) end -- only when it changes
        end
      end)
      say("watching: threat shows in the on-screen feed while you fight, when it changes. /fm threat watch again to stop. /fm threat test prints the full detail in chat.")
    else
      say("stopped watching.")
    end
  else
    local ok, err = pcall(snapshot)
    if not ok then say("error: " .. tostring(err)) end
  end
end
