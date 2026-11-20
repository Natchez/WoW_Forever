-- Forever Metrics: shops on the minimap
-- Forever has Blizzard's town-service minimap tracking (Repair, Food & Drink,
-- Innkeeper, Flight Master, trainers...); Blizzard draws the icons. This
-- switches the ones you pick on, from Options > Minimap, and can keep them
-- to towns only: on while you're resting (a city or an inn), off outside.
-- Each type is a setting row with `track = "<tracking name>"`; rows for
-- types this client doesn't have are hidden (FM:HasTracking).

local ADDON, ns = ...
local FM = ns.FM

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

-- name -> index and whether it's on, for every tracking type the game offers
local function trackingList()
  local out = {}
  if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
    for i = 1, C_Minimap.GetNumTrackingTypes() or 0 do
      local ok, a, b = pcall(C_Minimap.GetTrackingInfo, i)
      if ok then
        local name, active
        if type(a) == "table" then name, active = a.name, a.active else name, active = a, b end
        name = safe(name)
        if name then out[name] = { index = i, active = safe(active) and true or false } end
      end
    end
  elseif GetNumTrackingTypes and GetTrackingInfo then
    for i = 1, GetNumTrackingTypes() or 0 do
      local name, _, active = GetTrackingInfo(i)
      name = safe(name)
      if name then out[name] = { index = i, active = safe(active) and true or false } end
    end
  end
  return out
end

function FM:HasTracking(name) return trackingList()[name] ~= nil end

local function setTracking(index, on)
  if C_Minimap and C_Minimap.SetTracking then return pcall(C_Minimap.SetTracking, index, on) end
  if SetTracking then return pcall(SetTracking, index, on) end
end

local function shopRows()
  local rows = {}
  for _, d in ipairs(FM.SETTINGS) do if d.track then rows[#rows + 1] = d end end
  return rows
end

-- Switch each shop type on or off to match the settings (only the types this
-- page lists; herbs, minerals and the like are left alone)
local function apply()
  local list = trackingList()
  local master = FM:GetSetting("mmShops")
  local here = not FM:GetSetting("mmTowns") or (IsResting and safe(IsResting()))
  local changed = 0
  for _, d in ipairs(shopRows()) do
    local t = list[d.track]
    if t then
      local want = master and here and FM:GetSetting(d.key) and true or false
      if t.active ~= want then
        setTracking(t.index, want)
        changed = changed + 1
      end
    end
  end
  if FM.debug and changed > 0 then print("|cff888888FM minimap:|r switched", changed, "shop types") end
end

local function safeApply()
  local ok, err = pcall(apply)
  if not ok and FM.debug then print("|cffff5555ForeverMetrics minimap error|r", err) end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    FM:OnSetting("mmShops", safeApply)
    FM:OnSetting("mmTowns", safeApply)
    for _, d in ipairs(shopRows()) do FM:OnSetting(d.key, safeApply) end
    return
  end
  -- the tracking list fills in a moment after login and zoning
  C_Timer.After(2, safeApply)
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_UPDATE_RESTING" }) do
  pcall(ev.RegisterEvent, ev, e)
end
