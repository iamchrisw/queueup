local addonName, addon = ...

local priv = addon._priv
local util = priv.util
local const = priv.const
local state = priv.state

local SafeCall = util.SafeCall
local ROLE_ORDER = const.ROLE_ORDER
local ROLE_LABELS = const.ROLE_LABELS
local FIT_LABEL_BY_STEPS = const.FIT_LABEL_BY_STEPS

local RulesEngine = addon.RulesEngine
local Actions = addon.Actions

local function GetGroupRoleNeeds()
  local target = {
    TANK = 1,
    HEALER = 1,
    DAMAGER = 3,
  }

  local counts = {
    TANK = 0,
    HEALER = 0,
    DAMAGER = 0,
  }

  local members = GetNumGroupMembers() or 0
  if members <= 0 then
    members = 1
  end

  local isRaid = IsInRaid()
  for i = 1, members do
    local unit
    if i == members and not isRaid then
      unit = "player"
    elseif isRaid then
      unit = "raid" .. i
    else
      unit = "party" .. i
    end

    if UnitExists(unit) then
      local r = UnitGroupRolesAssigned(unit)
      if counts[r] ~= nil then
        counts[r] = counts[r] + 1
      end
    end
  end

  local needs = {
    TANK = math.max(0, target.TANK - counts.TANK),
    HEALER = math.max(0, target.HEALER - counts.HEALER),
    DAMAGER = math.max(0, target.DAMAGER - counts.DAMAGER),
  }

  return needs
end

function RulesEngine.Score(row)
  local rules = state.DB.rules
  local flags = rules.enableFlags
  local neededRoles = rules.neededRoles or {}
  local hardFailRole = false
  local hardFailRating = false
  local hardFailIlvl = false

  local function Clamp01(v)
    if v < 0 then
      return 0
    end
    if v > 1 then
      return 1
    end
    return v
  end

  local function Normalize(value, floorValue, ceilValue)
    value = tonumber(value) or 0
    floorValue = tonumber(floorValue) or 0
    ceilValue = tonumber(ceilValue) or 1
    if ceilValue <= floorValue then
      return 0
    end
    return Clamp01((value - floorValue) / (ceilValue - floorValue))
  end

  local function Pow(value, exponent)
    value = tonumber(value) or 0
    exponent = tonumber(exponent) or 1
    if value <= 0 then
      return 0
    end
    return value ^ exponent
  end

  local matchedRoles = {}
  local roleGateEnabled = flags.useRole == true
  local ratingGateEnabled = flags.useRating == true and (tonumber(rules.minRating) or 0) > 0
  local ilvlGateEnabled = flags.useIlvl == true and (tonumber(rules.minIlvl) or 0) > 0
  local minRating = tonumber(rules.minRating) or 0
  local minIlvl = tonumber(rules.minIlvl) or 0

  local anyNeededRoleSelected = false
  for _, roleKey in ipairs(ROLE_ORDER) do
    if neededRoles[roleKey] then
      anyNeededRoleSelected = true
      if row.roles and row.roles[roleKey] then
        matchedRoles[#matchedRoles + 1] = ROLE_LABELS[roleKey] or roleKey
      end
    end
  end

  local rolePass = true
  if roleGateEnabled and anyNeededRoleSelected and #matchedRoles == 0 then
    rolePass = false
    hardFailRole = true
  end

  local ratingPass = true
  if ratingGateEnabled and (tonumber(row.rating) or 0) < minRating then
    ratingPass = false
    hardFailRating = true
  end

  local ilvlPass = true
  if ilvlGateEnabled and (tonumber(row.ilvl) or 0) < minIlvl then
    ilvlPass = false
    hardFailIlvl = true
  end

  local ratingNorm = 0.5
  if flags.useRating then
    local ratingTarget = math.max(minRating + 500, 3000)
    ratingNorm = 0.5 + (Normalize(row.rating or 0, minRating, ratingTarget) * 0.5)
    if (tonumber(row.rating) or 0) < minRating then
      ratingNorm = Normalize(row.rating or 0, 0, minRating) * 0.5
    end
  end
  local ilvlFloor = 220
  local ilvlCeil = 275
  if minIlvl > 0 then
    ilvlFloor = math.max(0, minIlvl - 20)
    ilvlCeil = minIlvl + 35
  end
  local ilvlNorm = 0.5
  if flags.useIlvl then
    local ilvlValue = tonumber(row.ilvl) or 0
    if ilvlValue >= minIlvl then
      ilvlNorm = 0.5 + (Normalize(ilvlValue, minIlvl, ilvlCeil) * 0.5)
    else
      ilvlNorm = Normalize(ilvlValue, 0, minIlvl) * 0.5
    end
  end
  local bestNorm = Normalize(row.highestCompletion or 0, 2, 15)
  local qualityNorm = (ratingNorm * 0.45) + (ilvlNorm * 0.40) + (bestNorm * 0.15)

  local failedGates = 0
  if roleGateEnabled and not rolePass then
    failedGates = failedGates + 1
  end
  if ratingGateEnabled and not ratingPass then
    failedGates = failedGates + 1
  end
  if ilvlGateEnabled and not ilvlPass then
    failedGates = failedGates + 1
  end

  local gateMultiplier = 1.0
  if failedGates == 1 then
    gateMultiplier = 0.70
  elseif failedGates == 2 then
    gateMultiplier = 0.45
  elseif failedGates >= 3 then
    gateMultiplier = 0.25
  end

  -- A role mismatch is materially more important than being slightly under a
  -- numeric threshold: it can make the group composition fail outright.
  if hardFailRole then
    if failedGates == 1 then
      gateMultiplier = 0.40
    elseif failedGates == 2 then
      gateMultiplier = 0.22
    else
      gateMultiplier = 0.12
    end
  end

  local finalNorm = Clamp01(qualityNorm * gateMultiplier)
  local score = math.floor((finalNorm * 100) + 0.5)

  local fitSteps
  -- Use a slightly compressed internal range so strong applicants can reach
  -- the final square without requiring impossible theoretical maximums.
  -- The full ten-square track remains dynamic: just-meeting applicants sit in
  -- the middle while clear contenders reach 9-10.
  fitSteps = math.max(1, math.min(10, math.ceil(finalNorm * 12)))
  local badge = FIT_LABEL_BY_STEPS[fitSteps] or "Awful Fit"

  row.fitSteps = fitSteps
  row.hardFailRole = hardFailRole
  row.hardFailRating = hardFailRating
  row.hardFailIlvl = hardFailIlvl
  row.fitBreakdown = string.format(
    "Gates: role %s, rating %s (%d/%d), ilvl %s (%d/%d) | Q: R %.2f I %.2f B %.2f | Final: %.0f%% (x%.2f) | Tier %d/10",
    rolePass and "pass" or "fail",
    ratingPass and "pass" or "fail",
    tonumber(row.rating) or 0,
    minRating,
    ilvlPass and "pass" or "fail",
    tonumber(row.ilvl) or 0,
    minIlvl,
    ratingNorm,
    ilvlNorm,
    bestNorm,
    finalNorm * 100,
    gateMultiplier,
    fitSteps
  )

  local reasons = {}
  if #matchedRoles > 0 then
    reasons[#reasons + 1] = "Needed role: " .. table.concat(matchedRoles, "+")
  end
  if ratingGateEnabled then
    reasons[#reasons + 1] = string.format("Rating %s (%d/%d)", ratingPass and "pass" or "fail", tonumber(row.rating) or 0, minRating)
  end
  if ilvlGateEnabled then
    reasons[#reasons + 1] = string.format("iLvl %s (%d/%d)", ilvlPass and "pass" or "fail", tonumber(row.ilvl) or 0, minIlvl)
  end
  reasons[#reasons + 1] = "Quality " .. string.format("%.0f%%", qualityNorm * 100)
  return score, badge, table.concat(reasons, ", ")
end

local function CompareRows(a, b)
  local mode = state.DB.sort.mode
  local dir = state.DB.sort.direction

  local function cmp(x, y)
    if dir == "asc" then
      return x < y
    end
    return x > y
  end

  local function nameTieBreak()
    return cmp(string.lower(a.name or ""), string.lower(b.name or ""))
  end

  if mode == "name" then
    return nameTieBreak()
  elseif mode == "rating" then
    if a.rating == b.rating then
      if a.ilvl == b.ilvl then
        return nameTieBreak()
      end
      return cmp(a.ilvl, b.ilvl)
    end
    return cmp(a.rating, b.rating)
  elseif mode == "ilvl" then
    if a.ilvl == b.ilvl then
      if a.rating == b.rating then
        return nameTieBreak()
      end
      return cmp(a.rating, b.rating)
    end
    return cmp(a.ilvl, b.ilvl)
  end

  if a.score == b.score then
    if a.rating == b.rating then
      if a.ilvl == b.ilvl then
        return nameTieBreak()
      end
      return cmp(a.ilvl, b.ilvl)
    end
    return cmp(a.rating, b.rating)
  end
  return cmp(a.score, b.score)
end

local function SortRows(rows)
  table.sort(rows, CompareRows)
end

local CLASS_ID_BY_FILE = {
  WARRIOR = 1,
  PALADIN = 2,
  HUNTER = 3,
  ROGUE = 4,
  PRIEST = 5,
  DEATHKNIGHT = 6,
  SHAMAN = 7,
  MAGE = 8,
  WARLOCK = 9,
  MONK = 10,
  DRUID = 11,
  DEMONHUNTER = 12,
  EVOKER = 13,
}

local function GetSpecIconForRow(row)
  local specName = tostring(row.spec or "")
  local classFile = string.upper(tostring(row.classFile or ""))
  local classID = CLASS_ID_BY_FILE[classFile]
  if specName ~= "" and classID and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
    local numSpecs = GetNumSpecializationsForClassID(classID) or 0
    local wanted = string.lower(specName)
    for i = 1, numSpecs do
      local _, name, _, icon = GetSpecializationInfoForClassID(classID, i)
      if name and string.lower(tostring(name)) == wanted and icon then
        return icon
      end
    end
  end
  return nil
end

local function GetRoleTexCoords(roleKey)
  if roleKey == "TANK" then
    return 0, 19 / 64, 22 / 64, 41 / 64
  elseif roleKey == "HEALER" then
    return 20 / 64, 39 / 64, 1 / 64, 20 / 64
  end
  return 20 / 64, 39 / 64, 22 / 64, 41 / 64
end

function Actions.Invite(applicantID)
  if not C_LFGList or type(applicantID) ~= "number" then
    return false
  end

  local ok = SafeCall(C_LFGList.InviteApplicant, applicantID)
  if ok == nil then
    ok = SafeCall(C_LFGList.InviteApplicant, applicantID, 1)
  end
  return ok ~= nil
end

function Actions.Decline(applicantID)
  if not C_LFGList or type(applicantID) ~= "number" then
    return false
  end

  local ok = SafeCall(C_LFGList.DeclineApplicant, applicantID)
  return ok ~= nil
end

priv.rules.SortRows = SortRows
priv.rules.GetSpecIconForRow = GetSpecIconForRow
priv.rules.GetRoleTexCoords = GetRoleTexCoords
