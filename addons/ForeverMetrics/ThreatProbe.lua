-- Forever Metrics: threat probe (temporary)
-- Finds out what Forever's threat functions give an addon before a threat
-- meter is built on them, since the combat log is blocked here.
--   /fm threat test    one snapshot for your target, printed in chat
--   /fm threat watch   a snapshot every 2 seconds while you're in combat,
--                      plus a count of threat events, until the fight ends
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

-- Watching: snapshots during combat and a count of each threat event
local watch = { on = false, counts = {} }
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit)
  if not watch.on then return end
  if event == "PLAYER_REGEN_ENABLED" then
    local parts = {}
    for e, n in pairs(watch.counts) do parts[#parts + 1] = e .. " " .. n end
    say("fight over. Events seen: " .. (#parts > 0 and table.concat(parts, ", ") or "none") .. ". Still watching; /fm threat watch to stop.")
    watch.counts = {}
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
  if rest == "watch" then
    watch.on = not watch.on
    if ticker then ticker:Cancel(); ticker = nil end
    if watch.on then
      watch.counts = {}
      ticker = C_Timer.NewTicker(2, function()
        if InCombatLockdown() and UnitExists("target") then
          local ok, err = pcall(snapshot)
          if not ok then say("error: " .. tostring(err)) end
        end
      end)
      say("watching: snapshots every 2 seconds while you fight. /fm threat watch again to stop.")
    else
      say("stopped watching.")
    end
  else
    local ok, err = pcall(snapshot)
    if not ok then say("error: " .. tostring(err)) end
  end
end
