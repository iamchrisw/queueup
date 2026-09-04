local addonName, addon = ...

local priv = addon._priv
local util = priv.util

local Print = util.Print

priv.debug = priv.debug or {}
local debugMod = priv.debug

debugMod.enabled = debugMod.enabled or false
debugMod.nextApplicantID = debugMod.nextApplicantID or 900000
debugMod.fakeRows = debugMod.fakeRows or {}
debugMod.simulatedListingKind = debugMod.simulatedListingKind or nil
debugMod.running = debugMod.running or false
debugMod.targetCount = 50

local NAME_POOL = {
  "Alpha", "Bravo", "Comet", "Delta", "Echo", "Frost", "Gale", "Halo",
  "Ion", "Jade", "Kilo", "Luna", "Mango", "Nova", "Onyx", "Pico",
  "Quill", "Rift", "Solar", "Titan", "Umbra", "Vex", "Wisp", "Xeno",
}

local CLASS_POOL = {
  { file = "WARRIOR", label = "Warrior", role = "TANK", spec = "Protection" },
  { file = "PALADIN", label = "Paladin", role = "HEALER", spec = "Holy" },
  { file = "DEMONHUNTER", label = "Demon Hunter", role = "DAMAGER", spec = "Havoc" },
  { file = "PRIEST", label = "Priest", role = "HEALER", spec = "Discipline" },
  { file = "MAGE", label = "Mage", role = "DAMAGER", spec = "Frost" },
  { file = "DRUID", label = "Druid", role = "TANK", spec = "Guardian" },
  { file = "HUNTER", label = "Hunter", role = "DAMAGER", spec = "Marksmanship" },
  { file = "MONK", label = "Monk", role = "HEALER", spec = "Mistweaver" },
}

local function Pick(list, idx)
  if #list == 0 then
    return nil
  end
  local pos = ((idx - 1) % #list) + 1
  return list[pos]
end

local function BuildRoleMask(role)
  return {
    TANK = role == "TANK",
    HEALER = role == "HEALER",
    DAMAGER = role == "DAMAGER",
  }
end

local function MakeFakeRow(seedIndex)
  local classInfo = Pick(CLASS_POOL, seedIndex) or CLASS_POOL[1]
  local base = Pick(NAME_POOL, seedIndex) or "Test"
  local applicantID = debugMod.nextApplicantID
  debugMod.nextApplicantID = debugMod.nextApplicantID + 1

  local name = string.format("%s-%s", base, "Debug")
  -- Keep the synthetic population plausible: higher item level should usually
  -- correlate with higher rating, while still leaving room for outliers.
  local ilvl = 250 + ((seedIndex * 37) % 71) -- 250-320 inclusive
  local ilvlNorm = (ilvl - 250) / 70
  local ratingNoise = ((seedIndex * 173) % 361) - 180
  -- Bias the sample toward the upper end (roughly 2,500 average), while
  -- retaining a few believable low-rated outliers.
  local rating = math.floor(2200 + (ilvlNorm * 800) + ratingNoise + 0.5)
  if seedIndex % 11 == 0 then
    rating = (seedIndex * 97) % 1001
  end
  rating = math.max(0, math.min(3000, rating))
  local best = 2 + (seedIndex % 13)
  local raidProgress = string.format("%d/8 Normal  %d/8 HC  %d/8 Mythic", math.min(8, seedIndex % 9), math.min(8, (seedIndex + 3) % 9), math.min(8, (seedIndex + 6) % 9))

  return {
    applicantID = applicantID,
    memberIndex = 1,
    name = name,
    playerKey = name,
    classLocalized = classInfo.label,
    classFile = classInfo.file,
    spec = classInfo.spec,
    role = classInfo.role,
    roles = BuildRoleMask(classInfo.role),
    ilvl = ilvl,
    rating = rating,
    numMembers = 1,
    applicantStatus = "applied",
    pendingStatus = "",
    isInvited = false,
    note = "",
    applicationNote = "QueueUp debug applicant",
    highestCompletion = best,
    groupRootID = tostring(applicantID),
    hasDeserter = (seedIndex % 9 == 0),
    isGroupLeader = false,
    isGroupMember = false,
    isFake = true,
    raidProgressText = raidProgress,
  }
end

function debugMod.SetEnabled(enabled)
  debugMod.enabled = enabled and true or false
  Print("debug fake applicants " .. (debugMod.enabled and "enabled" or "disabled"))
end

function debugMod.Stop()
  if debugMod.ticker and debugMod.ticker.Cancel then
    debugMod.ticker:Cancel()
  end
  debugMod.ticker = nil
  debugMod.running = false
  debugMod.enabled = false
  debugMod.simulatedListingKind = nil
  debugMod.fakeRows = {}
  if addon.UI and addon.UI.RefreshApplicants then addon.UI.RefreshApplicants() end
  Print("debug simulation stopped")
end

function debugMod.Start(kind)
  debugMod.Stop()
  debugMod.enabled = true
  debugMod.running = true
  debugMod.simulatedListingKind = kind == "raid" and "raid" or "dungeon"
  local added = 0
  local function tick()
    if added >= debugMod.targetCount then
      if debugMod.ticker and debugMod.ticker.Cancel then debugMod.ticker:Cancel() end
      debugMod.ticker = nil
      debugMod.running = false
      Print("debug simulation complete: 50 applicants")
      return
    end
    debugMod.Add(1)
    added = added + 1
    if addon.UI and addon.UI.RefreshApplicants then addon.UI.RefreshApplicants() end
  end
  if C_Timer and C_Timer.NewTicker then
    debugMod.ticker = C_Timer.NewTicker(0.25, tick)
  else
    for i = 1, debugMod.targetCount do tick() end
  end
  Print("debug simulation started: " .. debugMod.simulatedListingKind)
end

function debugMod.IsRunning()
  return debugMod.running == true
end

function debugMod.Clear()
  debugMod.fakeRows = {}
  Print("debug fake applicants cleared")
end

function debugMod.Add(count)
  count = math.max(1, math.min(50, tonumber(count) or 1))
  local startIndex = #debugMod.fakeRows + 1
  for i = 1, count do
    debugMod.fakeRows[#debugMod.fakeRows + 1] = MakeFakeRow(startIndex + i - 1)
  end
  Print("added " .. tostring(count) .. " fake applicant(s)")
end

function debugMod.ListCount()
  return #debugMod.fakeRows
end

function debugMod.GetRows()
  return debugMod.fakeRows
end

function debugMod.SetListingKind(kind)
  local v = tostring(kind or ""):lower()
  if v == "" or v == "off" or v == "none" or v == "reset" then
    debugMod.simulatedListingKind = nil
    Print("debug listing simulation disabled")
    return
  end
  if v ~= "dungeon" and v ~= "raid" then
    Print("debug listing kind must be dungeon, raid, or none")
    return
  end
  debugMod.simulatedListingKind = v
  Print("debug listing simulation set to " .. v)
end

function debugMod.GetListingKind()
  return debugMod.simulatedListingKind
end

do
  local originalGetApplicants = addon.ApplicantData.GetApplicants
  addon.ApplicantData.GetApplicants = function(...)
    local rows = originalGetApplicants(...)
    if not debugMod.enabled then
      return rows
    end

    rows = rows or {}
    for _, fake in ipairs(debugMod.fakeRows) do
      rows[#rows + 1] = fake
    end
    return rows
  end
end
