-- Forever Professions: auction house prices
-- Prices are read at the auction house, never guessed:
--   passively   whatever you browse or search records each item's lowest
--               buyout per item (Classic list pages, or the modern AH's
--               browse and search results)
--   "Price materials" button beside the AH window: looks up, one at a
--               time, every material your characters' recipes use and every
--               item they make
-- Saved per realm and faction (each has its own AH), shared by all your
-- characters: ForeverProfessionsDB.prices["<realm>-<faction>"][itemID] =
-- { p = copper per item, t = when }.
-- Read with FP:Price(itemID) -> copper, seconds old (or nil).

local ADDON, ns = ...
local FP = ns.FP
local safe = FP.safe

local FRESH = 15 * 60 -- within this, a scan keeps the lowest price it sees

local function bucket()
  local db = FP:DB()
  db.prices = db.prices or {}
  local key = (safe(GetRealmName()) or "?") .. "-" .. (safe(UnitFactionGroup("player")) or "?")
  db.prices[key] = db.prices[key] or {}
  return db.prices[key]
end

function FP:Price(id)
  if not id or not self:DB() then return nil end
  local e = bucket()[id]
  if not e or not e.p or e.p <= 0 then return nil end
  return e.p, time() - (e.t or 0)
end

-- "2h ago"
function FP:Age(sec)
  if not sec then return "" end
  if sec < 3600 then return math.max(1, math.floor(sec / 60)) .. "m ago" end
  if sec < 86400 then return math.floor(sec / 3600) .. "h ago" end
  return math.floor(sec / 86400) .. "d ago"
end

-- What making a recipe once costs at AH prices: total, and how many of its
-- materials have no price yet
function FP:MaterialsCost(reagents)
  local total, unpriced = 0, 0
  for _, g in ipairs(reagents or {}) do
    local p = self:Price(g.id)
    if p then total = total + p * (g.c or 1) else unpriced = unpriced + 1 end
  end
  return total, unpriced
end

local changedQueued = false
local recorded = 0
local function record(id, unit)
  id, unit = tonumber(safe(id)), tonumber(safe(unit))
  if not id or not unit or unit <= 0 then return end
  unit = math.floor(unit + 0.5)
  local P, now = bucket(), time()
  local e = P[id]
  if not e or now - (e.t or 0) > FRESH or unit < e.p then
    P[id] = { p = unit, t = now }
  else
    e.t = now
  end
  recorded = recorded + 1
  if not changedQueued then
    changedQueued = true
    C_Timer.After(1, function() changedQueued = false; FP:Changed() end)
  end
end

---------------------------------------------------------------------------
-- Passive: read results as the AH shows them
---------------------------------------------------------------------------

local modern = C_AuctionHouse and C_AuctionHouse.GetBrowseResults and true or false

-- Classic: each list page; buyout is for the whole stack
FP:On("AUCTION_ITEM_LIST_UPDATE", function()
  if not (GetNumAuctionItems and GetAuctionItemInfo) then return end
  local n = GetNumAuctionItems("list") or 0
  for i = 1, n do
    local info = { GetAuctionItemInfo("list", i) }
    local count, buyout, itemID = safe(info[3]), safe(info[10]), safe(info[17])
    if not itemID and GetAuctionItemLink then
      local link = safe(GetAuctionItemLink("list", i))
      itemID = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
    end
    count, buyout = tonumber(count) or 1, tonumber(buyout) or 0
    if itemID and buyout > 0 and count > 0 then record(itemID, buyout / count) end
  end
  if n > 0 then FP:Debug(("AH (classic): read %d listings"):format(n)) end
end)

-- Modern: browse results carry each item's lowest price
local function readBrowse()
  local ok, list = pcall(C_AuctionHouse.GetBrowseResults)
  if not ok or type(list) ~= "table" then return end
  for _, r in ipairs(list) do
    if type(r) == "table" and type(r.itemKey) == "table" then record(r.itemKey.itemID, r.minPrice) end
  end
  FP:Debug(("AH (modern): read %d browse results"):format(#list))
end
FP:On("BROWSE_RESULTS_UPDATED", function() if modern then readBrowse() end end)
FP:On("BROWSE_RESULTS_ADDED", function() if modern then readBrowse() end end)

-- Modern: a stackable item's search, cheapest first
FP:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
  if not (C_AuctionHouse and C_AuctionHouse.GetCommoditySearchResultInfo) then return end
  local ok, r = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, 1)
  if ok and type(r) == "table" then record(itemID, r.unitPrice) end
end)

-- Modern: an item's search (gear and the like), one row per listing
FP:On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
  if not (C_AuctionHouse and C_AuctionHouse.GetItemSearchResultInfo and type(itemKey) == "table") then return end
  local best
  local n = C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetNumItemSearchResults(itemKey) or 1
  for i = 1, math.min(n or 1, 20) do
    local ok, r = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
    local p = ok and type(r) == "table" and tonumber(safe(r.buyoutAmount))
    local q = ok and type(r) == "table" and tonumber(safe(r.quantity)) or 1
    if p and p > 0 then
      p = p / math.max(1, q)
      if not best or p < best then best = p end
    end
  end
  if best then record(itemKey.itemID, best) end
end)

---------------------------------------------------------------------------
-- Active: "Price materials" looks up everything your recipes use or make
---------------------------------------------------------------------------

local function targets()
  local db, set, list = FP:DB(), {}, {}
  local function add(id) if id and not set[id] then set[id] = true; list[#list + 1] = id end end
  for key, c in pairs(db.chars) do
    for prof, P in pairs(c.prof or {}) do
      for _, r in pairs(P.recipes or {}) do
        local regs = (r.reagents and #r.reagents > 0) and r.reagents or (FP:Recipe(r.spell) or {}).r
        for _, g in ipairs(regs or {}) do add(g.id) end
        add(r.item)
      end
    end
  end
  for prof, T in pairs(db.trainers) do
    for _, t in pairs(T.recipes or {}) do
      local R = t.spell and FP:Recipe(t.spell)
      for _, g in ipairs(R and R.r or {}) do add(g.id) end
    end
  end
  return list
end

local scan = { queue = nil, i = 0, button = nil }

local function ahOpen()
  return (_G.AuctionHouseFrame and _G.AuctionHouseFrame:IsShown()) or (_G.AuctionFrame and _G.AuctionFrame:IsShown())
end

local function setLabel()
  local b = scan.button
  if not b then return end
  if scan.queue then b:SetText(("Pricing %d / %d"):format(scan.i, #scan.queue))
  else b:SetText("Price materials") end
end

local function stop(msg)
  scan.queue = nil
  setLabel()
  if msg then FP:Say(msg) end
end

local function queryOne(id)
  if modern and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey then
    local key = C_AuctionHouse.MakeItemKey(id)
    local sorts = { { sortOrder = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
    return pcall(C_AuctionHouse.SendSearchQuery, key, sorts, false)
  end
  if QueryAuctionItems then
    local name = FP:ItemName(id)
    if name:match("^item %d+$") then return true end -- name not loaded: skip it
    return pcall(QueryAuctionItems, name, nil, nil, 0, false, nil, false, true)
  end
  return false, "no auction house API found"
end

local function ready()
  if modern then
    if C_AuctionHouse.IsThrottledMessageSystemReady then return C_AuctionHouse.IsThrottledMessageSystemReady() end
    return true
  end
  return not CanSendAuctionQuery or CanSendAuctionQuery()
end

local function step()
  if not scan.queue then return end
  if not ahOpen() then return stop("stopped pricing: the auction house closed.") end
  if not ready() then C_Timer.After(0.3, step); return end
  scan.i = scan.i + 1
  local id = scan.queue[scan.i]
  if not id then
    local n = #scan.queue
    stop(("priced %d materials and crafted items."):format(n))
    FP:Changed()
    return
  end
  local ok, err = queryOne(id)
  if not ok then return stop("couldn't search the auction house: " .. tostring(err)) end
  setLabel()
  C_Timer.After(modern and 0.8 or 0.5, step)
end

function FP:PriceMaterials()
  if scan.queue then return stop("stopped pricing.") end
  if not ahOpen() then return FP:Say("open the auction house first.") end
  scan.queue, scan.i = targets(), 0
  if #scan.queue == 0 then return stop("no recipes yet: open a profession window first.") end
  FP:Debug(("pricing %d items with the %s auction house"):format(#scan.queue, modern and "modern" or "classic"))
  step()
end

local function attach()
  local frame = _G.AuctionHouseFrame or _G.AuctionFrame
  if not frame or scan.button then return end
  local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  b:SetSize(130, 24)
  b:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, -30)
  b:SetScript("OnClick", function() FP:Try("price materials", FP.PriceMaterials, FP) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Forever Professions")
    GameTooltip:AddLine("Looks up the lowest price of every material your characters' recipes use, and every item they make. Click again to stop.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  scan.button = b
  setLabel()
end

FP:On("AUCTION_HOUSE_SHOW", function() FP:Try("AH button", attach) end)
FP:On("AUCTION_HOUSE_CLOSED", function() if scan.queue then stop("stopped pricing: the auction house closed.") end end)
