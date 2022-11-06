﻿local MM = LibStub("AceAddon-3.0"):GetAddon("MysticMaestro")

function MM:ValidateAHIsOpen()
  local AuctionFrame = _G["AuctionFrame"]
  if not AuctionFrame or not AuctionFrame:IsShown() then
    MM:Print("Auction house window must be open to perform scan")
    return false
  end
  return true
end

local function getAuctionInfo(i)
  local itemName, icon, _, quality, _, level, _, _, buyoutPrice, _, _, seller = GetAuctionItemInfo("list", i)
  local link = GetAuctionItemLink("list", i)
  local duration = GetAuctionItemTimeLeft("list", i)
  return itemName, level, buyoutPrice, quality, seller, icon, link, duration
end

local function isEnchantItemFound(itemName, quality, level, buyoutPrice, i)
  local trinketFound = itemName and itemName:find("Insignia") and level == 15
  local mysticScroll = itemName and itemName:match("Mystic Scroll: (.+)")
  local properItem = buyoutPrice and buyoutPrice > 0 and ((quality and quality >= 3) or mysticScroll) 
  local enchantID
  if trinketFound then
    enchantID = GetAuctionItemMysticEnchant("list", i)
  elseif properItem then
    if mysticScroll then
      enchantID = MM.RE_LOOKUP[mysticScroll]
    else
      enchantID = GetAuctionItemMysticEnchant("list", i)
    end
  end
  return properItem and enchantID, enchantID, trinketFound
end

function MM:CollectSpecificREData(scanTime, expectedEnchantID)
  local listings = self.db.realm.RE_AH_LISTINGS
  listings[expectedEnchantID][scanTime] = listings[expectedEnchantID][scanTime] or {}
  listings[expectedEnchantID][scanTime]["other"] = listings[expectedEnchantID][scanTime]["other"] or {}
  local enchantFound = false
  local numBatchAuctions = GetNumAuctionItems("list")
  if numBatchAuctions > 0 then
    for i = 1, numBatchAuctions do
      local itemName, level, buyoutPrice, quality = getAuctionInfo(i)
      buyoutPrice = MM:round(buyoutPrice / 10000, 4, true)
      local itemFound, enchantID, trinketFound = isEnchantItemFound(itemName,quality,level,buyoutPrice,i)
      if itemFound and enchantID == expectedEnchantID then
        enchantFound = true
        table.insert(trinketFound and listings[enchantID][scanTime] or listings[enchantID][scanTime]["other"], buyoutPrice)
      end
    end
  end
  return enchantFound
end

function MM:CollectAllREData(scanTime)
  local listings = self.db.realm.RE_AH_LISTINGS
  local numBatchAuctions = GetNumAuctionItems("list")
  if numBatchAuctions > 0 then
    for i = 1, numBatchAuctions do
      local itemName, level, buyoutPrice, quality = getAuctionInfo(i)
      buyoutPrice = MM:round(buyoutPrice / 10000, 4, true)
      local itemFound, enchantID, trinketFound = isEnchantItemFound(itemName,quality,level,buyoutPrice,i)
      if itemFound then
        listings[enchantID][scanTime] = listings[enchantID][scanTime] or {}
        listings[enchantID][scanTime]["other"] = listings[enchantID][scanTime]["other"] or {}
        table.insert(trinketFound and listings[enchantID][scanTime] or listings[enchantID][scanTime]["other"], buyoutPrice)
      end
    end
  end
end

local displayInProgress, pendingQuery, awaitingResults, enchantToQuery, selectedScanTime

function MM:DeactivateSelectScanListener()
  awaitingResults = false
end

function MM:AsyncDisplayEnchantAuctions(enchantID)
  displayInProgress = true
  pendingQuery = true
  awaitingResults = false
  enchantToQuery = enchantID
  selectedScanTime = time()
end

local results = {}
function MM:SelectScan_AUCTION_ITEM_LIST_UPDATE()
  if awaitingResults then
    local listings = self.db.realm.RE_AH_LISTINGS
    listings[enchantToQuery][selectedScanTime] = listings[enchantToQuery][selectedScanTime] or {}
    listings[enchantToQuery][selectedScanTime]["other"] = listings[enchantToQuery][selectedScanTime]["other"] or {}
    awaitingResults = false
    wipe(results)
    for i=1, GetNumAuctionItems("list") do
      local itemName, level, buyoutPrice, quality, seller, icon, link, duration = getAuctionInfo(i)
      local other, rounded, destination
      if seller == nil then
        awaitingResults = true  -- TODO: timeout awaitingResults
      end
      local itemFound, enchantID, trinketFound = isEnchantItemFound(itemName,quality,level,buyoutPrice,i)
      if itemFound and enchantToQuery == enchantID then
        table.insert(results, {
          id = i,
          enchantID = enchantID,
          seller = seller,
          buyoutPrice = buyoutPrice,
          yours = seller == UnitName("player"),
          icon = icon,
          link = link,
          duration = duration
        })
        rounded = MM:round(buyoutPrice / 10000, 4, true)
        table.insert(trinketFound and listings[enchantToQuery][selectedScanTime] or listings[enchantToQuery][selectedScanTime]["other"], rounded)
      end
    end
    table.sort(results, function(k1, k2) return k1.buyoutPrice < k2.buyoutPrice end)
    if MysticMaestroMenuAHExtension and MysticMaestroMenuAHExtension:IsVisible() then
      self:PopulateSelectedEnchantAuctions(results)
      self:CalculateREStats(enchantToQuery)
      self:PopulateGraph(enchantToQuery)
      self:ShowStatistics(enchantToQuery)
    end
  end
end

local function getMyAuctionInfo(i)
  local _, icon, _, quality, _, _, _, _, buyoutPrice = GetAuctionItemInfo("owner", i)
  local enchantID = GetAuctionItemMysticEnchant("owner", i)
  local link = GetAuctionItemLink("owner", i)
  local duration = GetAuctionItemTimeLeft("owner", i)
  return icon, quality, buyoutPrice, enchantID, link, duration
end

local function collectMyAuctionsData(results)
  local numPlayerAuctions = GetNumAuctionItems("owner")
  for i=1, numPlayerAuctions do
    local icon, quality, buyoutPrice, enchantID, link = getMyAuctionInfo(i)
    if buyoutPrice and quality >= 3 and enchantID then
      results[enchantID] = results[enchantID] or {}
      table.insert(results[enchantID], {
        id = i, -- need to have owner ID so auction can be canceled
        buyoutPrice = buyoutPrice, -- need to have buyout price so canceled auction can be matched
        link = link
      })
    end
  end
end

local function collectFavoritesData(results)
  for enchantID in pairs(MM.db.realm.FAVORITE_ENCHANTS) do
    results[enchantID] = results[enchantID] or {}
  end
end

local function convertMyAuctionResults(results)
  local r = {}
  for enchantID, auctions in pairs(results) do
    table.insert(r, {
      enchantID = enchantID,
      auctions = auctions
    })
  end
  return r
end

local myAuctionResults
function MM:GetMyAuctionsResults()
  myAuctionsResults = {}
  collectMyAuctionsData(myAuctionsResults)
  collectFavoritesData(myAuctionsResults)
  return convertMyAuctionResults(myAuctionsResults)
end

MM.OnUpdateFrame:HookScript("OnUpdate",
  function()
    if displayInProgress then
      if pendingQuery and CanSendAuctionQuery() then
        MM:Print("performing query of " .. MM.RE_NAMES[enchantToQuery])
        QueryAuctionItems(MM.RE_NAMES[enchantToQuery], nil, nil, 0, 0, 3, false, true, nil)
        pendingQuery = false
        awaitingResults = true
      end
    end
  end
)

---------------------------------
--   Auction Stats functions   --
---------------------------------

function MM:CalculateStatsFromList(list)
  local min, max, count, tally = 0, 0, 0, 0
  for _, v in pairs(list) do
    if type(v) == "number" then
      if v > 0 and (v < min or min == 0) then
        min = v
      end
      if v > max then
        max = v
      end
      if v ~= nil then
        tally = tally + v
        count = count + 1
      end
    end
  end
  if count > 0 then
    local midKey = count > 1 and MM:round(count/2) or 1
    sort(list)
    local med = list[midKey]
    local mean = MM:round(tally/count)
    -- local dev = MM:StdDev(list,mean)
    return min, med, mean, max, count
  end
end

local function calculateLimitor(tMed,oMed,tMax)
  local val
  if tMed and oMed then
    val = tMed + oMed
  elseif tMed then
    val = tMed * 2
  elseif oMed then
    val = oMed * 2
  end
  if val and tMax and val > tMax then
    val = tMax
  end
  return val
end

function MM:CalculateMarketValues(list,dev)
  local tMin, tMed, tMean, tMax, tCount = MM:CalculateStatsFromList(list)
  local oMin, oMed, oMean, oMax, oCount
  if list.other ~= nil then
    oMin, oMed, oMean, oMax, oCount = MM:CalculateStatsFromList(list.other)
  end
  if tCount and tCount > 0 or oCount and oCount > 0 then
    local limitor = calculateLimitor(tMed,oMed,tMax)
    local adjustedList = MM:CombineListsLimited(list,list.other,limitor)
    local aMin, aMed, aMean, aMax, aCount = MM:CalculateStatsFromList(adjustedList)
    local aDev = dev and MM:StdDev(adjustedList,aMean) or 0
    local total = ( tCount or 0 ) + ( oCount or 0 )
    return {Min=aMin, Med=aMed, Mean=aMean, Max=aMax, Dev=aDev, Count=aCount, Trinkets=(tCount or 0), Total=total}
  end
end

function MM:CalculateStatsFromTime(reID,sTime)
  local listing = self.db.realm.RE_AH_LISTINGS[reID][sTime]
  local stats = self.db.realm.RE_AH_STATISTICS[reID]
  local r = MM:CalculateMarketValues(listing,true)
  if r then
    stats["daily"], stats["current"] = stats["daily"] or {}, stats["current"] or {}
    local d = stats["daily"]
    local t = {}
    local c = stats["current"]
    local dCode = MM:TimeToDate(sTime)
    t.Min,t.Med,t.Mean,t.Max,t.Count,t.Dev,t.Total,t.Trinkets = r.Min,r.Med,r.Mean,r.Max,r.Count,r.Dev,r.Total,r.Trinkets
    d[dCode] = d[dCode] or {}
    table.insert(d[dCode],t)
    if c.Last == nil or c.Last <= sTime then
      c.Min,c.Med,c.Mean,c.Max,c.Count,c.Last,c.Dev,c.Total,c.Trinkets = r.Min,r.Med,r.Mean,r.Max,r.Count,sTime,r.Dev,r.Total,r.Trinkets
    end
  end
end

local valueList = { "Min", "Med", "Mean", "Max", "Count", "Dev", "Total", "Trinkets" }

function MM:CalculateDailyAverages(reID)
  local stats = self.db.realm.RE_AH_STATISTICS[reID]
  if stats then
    local daily = stats["daily"]
    if daily then
      local rAvg, rCount = {}, 0
      -- setup rolling average obj
      for _, val in pairs(valueList) do rAvg[val] = 0 end
      for dCode, scans in pairs(daily) do
        local avg, count, remove = {}, 0, {}
        rCount = rCount + 1
        for _, val in pairs(valueList) do avg[val] = 0 end
        for k, scan in ipairs(scans) do
          -- setup daily average
          for _, val in pairs(valueList) do avg[val] = avg[val] + scan[val] end
          count = count + 1
          table.insert(remove,k)
        end
        for _, val in pairs(valueList) do
          -- set each day average value
          avg[val] = avg[val] / count
          rAvg[val] = rAvg[val] + avg[val]
        end
      end
      for _, val in pairs(valueList) do
        -- set total average of each data point
        rAvg[val] = rAvg[val] / rCount
        stats["current"]["10d_"..val] = MM:round( rAvg[val] , 1 , true  )
      end
      -- We have finished with the Daily data and can remove it
      stats.daily = nil
    end
  end
end

function MM:CalculateAllStats()
  local listDB = self.db.realm.RE_AH_LISTINGS
  local removeList = {}
  local reID, listing, timekey, values, k
  for reID, listing in pairs(listDB) do
    for timekey, values in pairs(listing) do
      if not MM:BeyondDays(timekey) then 
        MM:CalculateStatsFromTime(reID,timekey)
      else
        table.insert(removeList,timekey)
      end
    end
    for k, timekey in pairs(removeList) do 
      listing[timekey] = nil
    end
    MM:CalculateDailyAverages(reID)
  end
end

function MM:CalculateREStats(reID)
  local listing = self.db.realm.RE_AH_LISTINGS[reID]
  local removeList = {}
  local timekey, values, k
  for timekey, values in pairs(listing) do
    if not MM:BeyondDays(timekey) then 
      MM:CalculateStatsFromTime(reID,timekey)
    else
      table.insert(removeList,timekey)
    end
  end
  for k, timekey in pairs(removeList) do 
    listing[timekey] = nil
  end
  MM:CalculateDailyAverages(reID)
end

function MM:LowestListed(reID,keytype)
  local current = self.db.realm.RE_AH_STATISTICS[reID].current
  if not current then return nil end
  local price = current[keytype or "Min"]
  return price
end

function MM:OrbValue(reID, keytype)
  local cost = MM:OrbCost(reID)
  local value = MM:LowestListed(reID,keytype)
  return value and MM:round(value / cost,2,true) or nil
end

---------------------------------------
--   Auction Interaction functions   --
---------------------------------------

StaticPopupDialogs["MM_BUYOUT_AUCTION"] = {
  text = BUYOUT_AUCTION_CONFIRMATION,
  button1 = ACCEPT,
  button2 = CANCEL,
  OnAccept = function(self)
    local data = MM:GetSelectedSelectedEnchantAuctionData()
      PlaceAuctionBid("list", data.id, data.buyoutPrice)
      MM:RefreshSelectedEnchantAuctions()
  end,
  OnShow = function(self)
    local data = MM:GetSelectedSelectedEnchantAuctionData()
    MoneyFrame_Update(self.moneyFrame, data.buyoutPrice)
  end,
  hasMoneyFrame = 1,
  showAlert = 1,
  timeout = 0,
  exclusive = 1,
  hideOnEscape = 1,
  --enterClicksFirstButton = 1  -- causes taint for some reason
}

function MM:BuyoutAuction(id)
  SetSelectedAuctionItem("list", id)
  StaticPopup_Show("MM_BUYOUT_AUCTION")
end

StaticPopupDialogs["MM_CANCEL_AUCTION"] = {
	text = CANCEL_AUCTION_CONFIRMATION,
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function()
		CancelAuction(GetSelectedAuctionItem("owner"))
    MM:RefreshSelectedEnchantAuctions()
	end,
	OnShow = function(self)
    self.text:SetText(CANCEL_AUCTION_CONFIRMATION)
	end,
	showAlert = 1,
	timeout = 0,
	exclusive = 1,
	hideOnEscape = 1,
  --enterClicksFirstButton = 1  -- causes taint for some reason
}

-- returns the first id that matches enchantID and buyoutPrice
local function findOwnerAuctionID(enchantID, buyoutPrice)
  local results = MM:GetMyAuctionsResults()
  for _, result in ipairs(results) do
    if result.enchantID == enchantID then
      for _, auction in ipairs(result.auctions) do
        if auction.buyoutPrice == buyoutPrice then
          print(auction.id)
          return auction.id
        end
      end
    end
  end
  print("this shouldn't print")
  return nil
end

function MM:CancelAuction(enchantID, buyoutPrice)
  local auctionID = findOwnerAuctionID(enchantID, buyoutPrice)
  SetSelectedAuctionItem("owner", auctionID)
  StaticPopup_Show("MM_CANCEL_AUCTION")
end

local listingPrice
StaticPopupDialogs["MM_LIST_AUCTION"] = {
	text = "List auction for the following amount?",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function()
		StartAuction(listingPrice, listingPrice, 1, 1, 1)
    MM:RefreshSelectedEnchantAuctions()
	end,
	OnShow = function(self)
    MoneyFrame_Update(self.moneyFrame, listingPrice)
	end,
  OnCancel = function(self)
    ClickAuctionSellItemButton()
    ClearCursor()
  end,
  hasMoneyFrame = 1,
	showAlert = 1,
	timeout = 0,
	exclusive = 1,
	hideOnEscape = 1,
  enterClicksFirstButton = 1  -- doesn't cause taint for some reason
}

-- only do trinkets for now, and return nil if trinket with enchantID not found
local function findSellableItemWithEnchantID(enchantID)
  local items = {trinket = {},other = {}}
  for bagID=0, 4 do
    for slotIndex=1, GetContainerNumSlots(bagID) do
      local _,_,_,quality,_,_,item = GetContainerItemInfo(bagID, slotIndex)
      -- we have an item, with at least 3 quality and is not soulbound
      if item and quality >= 3 and not MM:IsSoulbound(bagID, slotIndex) then
        local re = GetREInSlot(bagID, slotIndex)
        -- the item matches our specified RE, and is sorted into trinket or not
        if re == enchantID then
          local _,_,_,_,reqLevel,_,_,_,_,_,vendorPrice = GetItemInfo(item)
          local istrinket = reqLevel == 15 and item:find("Insignia of the")
          table.insert(istrinket and items.trinket or items.other, istrinket and {bagID, slotIndex} or {bagID, slotIndex, vendorPrice})
        end
      end
    end
  end
  if #items.trinket > 0 then
    return unpack(items.trinket[1])
  elseif #items.other then
    return -- Remove this when we are ready for non trinket
    -- table.sort(items.other,function(k1, k2) return MM:Compare(items.other[k1].vendorPrice, items.other[k2].vendorPrice, ">") end)
    -- return unpack(items.other[1])
  else
    return
  end
end


function MM:ListAuction(enchantID, price)
  local bagID, slotIndex = findSellableItemWithEnchantID(enchantID)
  if bagID then
    PickupContainerItem(bagID, slotIndex)
    ClickAuctionSellItemButton()
    listingPrice = price
    StaticPopup_Show("MM_LIST_AUCTION")
  else
    print("No item found")
  end
end

function MM:ClosePopups()
  StaticPopup_Hide("MM_BUYOUT_AUCTION")
  StaticPopup_Hide("MM_CANCEL_AUCTION")
  StaticPopup_Hide("MM_LIST_AUCTION")
  if GetAuctionSellItemInfo() then
    ClickAuctionSellItemButton()
    ClearCursor()
  end
end

local refreshInProgress, restoreInProgress, refreshList, restoreList
local enchantToRestore
function MM:RefreshSelectedEnchantAuctions()
  refreshInProgress = true
  enchantToRestore = MM:GetSelectedSelectedEnchantAuctionData().enchantID  -- will need to be updated if refreshed and no item selected
end

-- entry point for refresh after buying or cancelling an auction
function MM:BuyCancel_AUCTION_ITEM_LIST_UPDATE()
  if refreshInProgress then
    refreshInProgress = false
    refreshList = true
  end
  if restoreInProgress then
    restoreInProgress = false
    restoreList = true
  end
end

-- entry point for refresh after listing an auction
function MM:List_AUCTION_OWNED_LIST_UPDATE()
  if refreshInProgress then
    refreshInProgress = false
    refreshList = true
  end
end

local function enchantToRestoreIsStillSelected()
  local selectedMyAuctionData = MM:GetSelectedMyAuctionData()
  local selectedSelectedEnchantAuctionData = MM:GetSelectedSelectedEnchantAuctionData()
  return selectedMyAuctionData and selectedMyAuctionData.enchantID == enchantToRestore
  or selectedSelectedEnchantAuctionData and selectedSelectedEnchantAuctionData.enchantID == enchantToRestore
end

MM.OnUpdateFrame:HookScript("OnUpdate",
  function()
    if refreshList and CanSendAuctionQuery() then
      if enchantToRestoreIsStillSelected() then
        QueryAuctionItems("zzxxzzy")
        restoreInProgress = true
      end
      refreshList = false
    end
    if restoreList and CanSendAuctionQuery() then
      if enchantToRestoreIsStillSelected() then
        MM:AsyncDisplayEnchantAuctions(enchantToRestore)
        QueryAuctionItems(MM.RE_NAMES[enchantToRestore], nil, nil, 0, 0, 3, false, true, nil)
        local results = MM:GetMyAuctionsResults()
        for _, result in ipairs(results) do
          if enchantToRestore == result.enchantID then
            MM:SetSelectedMyAuctionData(result)
          end
        end
      end
      restoreList = false
    end
  end
)