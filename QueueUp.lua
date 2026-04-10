local addonName, addon = ...

local DEFAULTS = {
  firstRun = true,
  rules = {
    roleWeights = {
      TANK = 3,
      HEALER = 3,
      DAMAGER = 2,
    },
    neededRoles = {
      TANK = true,
      HEALER = true,
      DAMAGER = true,
    },
    minRating = 1800,
    minIlvl = 610,
    classSpecPrefs = {},
    enableFlags = {
      useRole = true,
      useClassSpec = false,
      useRating = true,
      useIlvl = true,
    },
  },
  sort = {
    mode = "score",
    direction = "desc",
  },
  playerNotes = {},
}

local function CopyTable(tbl)
  if type(tbl) ~= "table" then
    return tbl
  end

  local out = {}
  for k, v in pairs(tbl) do
    out[k] = CopyTable(v)
  end
  return out
end

local function MergeDefaults(target, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(target[k]) ~= "table" then
        target[k] = CopyTable(v)
      else
        MergeDefaults(target[k], v)
      end
    elseif target[k] == nil then
      target[k] = v
    end
  end
end

local function EnsureDB()
  QueueUpDB = QueueUpDB or {}

  local oldFirstRun = QueueUpDB.firstRun
  MergeDefaults(QueueUpDB, DEFAULTS)
  QueueUpDB.autoDecline = nil
  if oldFirstRun ~= nil then
    QueueUpDB.firstRun = oldFirstRun
  end

  return QueueUpDB
end

local DB = EnsureDB()

local frame = CreateFrame("Frame")
local reanchorTicker = nil
local hookedFrames = {}
local applicantTicker = nil

local PANEL_WIDTH = 900
local PANEL_HEIGHT = 700

local UI = {}
local ApplicantData = {}
local RulesEngine = {}
local Actions = {}
local NotesStore = {}

local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
local ROLE_LABELS = {
  TANK = "Tank",
  HEALER = "Healer",
  DAMAGER = "Damage",
}
local FIT_LABEL_BY_STEPS = {
  [1] = "Awful Fit",
  [2] = "Bad Fit",
  [3] = "Maybe",
  [4] = "Good Fit",
  [5] = "Great Fit",
}

local RATING_PALETTE = {
  { min = 3800, hex = "ff8000" }, { min = 3645, hex = "f9753f" }, { min = 3525, hex = "f16961" },
  { min = 3405, hex = "e75e7f" }, { min = 3285, hex = "db529c" }, { min = 3165, hex = "cc47b9" },
  { min = 3045, hex = "b83dd6" }, { min = 2915, hex = "9c3eed" }, { min = 2795, hex = "715be5" },
  { min = 2675, hex = "2c6dde" }, { min = 2515, hex = "397ece" }, { min = 2395, hex = "5090bb" },
  { min = 2275, hex = "5ba2a8" }, { min = 2155, hex = "5fb494" }, { min = 2035, hex = "5ec67e" },
  { min = 1915, hex = "56d966" }, { min = 1795, hex = "46ec47" }, { min = 1675, hex = "1eff00" },
  { min = 1550, hex = "4fff35" }, { min = 1425, hex = "6bff4f" }, { min = 1300, hex = "81ff65" },
  { min = 1175, hex = "94ff78" }, { min = 1050, hex = "a5ff8b" }, { min = 925, hex = "b4ff9c" },
  { min = 800, hex = "c3ffae" }, { min = 675, hex = "d0ffbf" }, { min = 550, hex = "ddffd0" },
  { min = 425, hex = "eeffe1" }, { min = 300, hex = "f6fff1" }, { min = 200, hex = "ffffff" },
}

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99QueueUp|r: " .. tostring(msg))
end

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end

  local ok, a, b, c, d, e, f, g, h, i, j, k, l = pcall(fn, ...)
  if not ok then
    return nil
  end
  return a, b, c, d, e, f, g, h, i, j, k, l
end

local function HexToRGB(hex)
  if type(hex) ~= "string" or #hex ~= 6 then
    return 1, 1, 1
  end
  local r = tonumber(hex:sub(1, 2), 16) or 255
  local g = tonumber(hex:sub(3, 4), 16) or 255
  local b = tonumber(hex:sub(5, 6), 16) or 255
  return r / 255, g / 255, b / 255
end

local function GetRatingColor(rating)
  rating = tonumber(rating) or 0
  for i = 1, #RATING_PALETTE do
    if rating >= RATING_PALETTE[i].min then
      return HexToRGB(RATING_PALETTE[i].hex)
    end
  end
  return 1, 1, 1
end

local function NormalizeDungeonToken(text)
  text = tostring(text or ""):lower()
  text = text:gsub("%b()", "")
  text = text:gsub("[^%w]+", "")
  return text
end

local function GetActiveListingDungeonContext()
  local out = {
    activityID = nil,
    name = nil,
    token = nil,
  }
  if not C_LFGList or type(C_LFGList.GetActiveEntryInfo) ~= "function" then
    return out
  end

  local info = SafeCall(C_LFGList.GetActiveEntryInfo)
  if type(info) ~= "table" then
    return out
  end

  local activityID = tonumber(info.activityID)
  if not activityID and type(info.activityIDs) == "table" then
    activityID = tonumber(info.activityIDs[1])
  end
  out.activityID = activityID

  local name = nil
  if activityID and C_LFGList.GetActivityInfoTable then
    local t = SafeCall(C_LFGList.GetActivityInfoTable, activityID)
    if type(t) == "table" then
      name = t.fullName or t.shortName
    end
  end
  if (not name or name == "") and activityID and C_LFGList.GetActivityFullName then
    name = SafeCall(C_LFGList.GetActivityFullName, activityID)
  end
  if not name or name == "" then
    name = info.title or info.name
  end

  out.name = tostring(name or "")
  out.token = NormalizeDungeonToken(out.name)
  return out
end

local function GetActiveListingContext()
  if not C_LFGList or type(C_LFGList.GetActiveEntryInfo) ~= "function" then
    return "Not currently listed"
  end

  local info = SafeCall(C_LFGList.GetActiveEntryInfo)
  if type(info) ~= "table" then
    return "Not currently listed"
  end

  local activityName = nil
  local activityID = tonumber(info.activityID)
  if not activityID and type(info.activityIDs) == "table" then
    activityID = tonumber(info.activityIDs[1])
  end
  if activityID and C_LFGList.GetActivityInfoTable then
    local t = SafeCall(C_LFGList.GetActivityInfoTable, activityID)
    if type(t) == "table" then
      activityName = t.fullName or t.shortName
    end
  end
  if not activityName and activityID and C_LFGList.GetActivityFullName then
    activityName = SafeCall(C_LFGList.GetActivityFullName, activityID)
  end

  local title = tostring(info.title or info.name or activityName or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local comment = tostring(info.comment or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if title ~= "" and comment ~= "" then
    return title .. " - " .. comment
  end
  if title ~= "" then
    return title
  end
  if comment ~= "" then
    return comment
  end
  return "Not currently listed"
end

local function TryExtractBestLevel(profile)
  if type(profile) ~= "table" then
    return nil
  end
  local candidates = {
    profile.mythicKeystoneProfile and profile.mythicKeystoneProfile.maxDungeonLevel,
    profile.mythicKeystoneProfile and profile.mythicKeystoneProfile.maxMythicLevel,
    profile.maxDungeonLevel,
    profile.maxMythicLevel,
    profile.highestKeyLevel,
  }
  for i = 1, #candidates do
    local v = tonumber(candidates[i])
    if v and v > 0 then
      return math.floor(v)
    end
  end
  return nil
end

local function TryExtractRaiderIOScore(profile)
  if type(profile) ~= "table" then
    return nil
  end
  local mkp = profile.mythicKeystoneProfile or {}
  local candidates = {
    mkp.currentScore, mkp.score, mkp.mplusScore,
    profile.currentScore, profile.score, profile.mplusScore,
  }
  for i = 1, #candidates do
    local n = tonumber(candidates[i])
    if n and n > 0 then
      return math.floor(n + 0.5)
    end
  end
  local fort = tonumber(mkp.fortifiedScore or mkp.fortified)
  local tyr = tonumber(mkp.tyrannicalScore or mkp.tyrannical)
  if fort and tyr and fort > 0 and tyr > 0 then
    return math.floor((fort + tyr) + 0.5)
  end
  return nil
end


local function ExtractLevelFromTable(t)
  if type(t) ~= "table" then
    return nil
  end
  local candidates = {
    t.level, t.mythicLevel, t.keystoneLevel, t.dungeonLevel, t.maxLevel,
    t.bestLevel, t.highestLevel, t.completedLevel, t.completedKeystoneLevel,
    t.bestRunLevel, t.bestOverallLevel, t.maxDungeonLevel, t.maxMythicLevel,
  }
  for i = 1, #candidates do
    local n = tonumber(candidates[i])
    if n and n > 0 then
      return math.floor(n)
    end
  end
  if type(t.bestRun) == "table" then
    local n = ExtractLevelFromTable(t.bestRun)
    if n then
      return n
    end
  end
  return nil
end

local function DungeonTableMatchesContext(t, ctx)
  if type(t) ~= "table" or type(ctx) ~= "table" then
    return false
  end
  local targetID = tonumber(ctx.activityID)
  if targetID then
    local idCandidates = {
      t.activityID, t.id, t.mapID, t.challengeModeID, t.instanceID, t.dungeonID,
      t.keystone_instance, t.challengeModeMapID,
    }
    for i = 1, #idCandidates do
      if tonumber(idCandidates[i]) == targetID then
        return true
      end
    end
  end

  local targetToken = tostring(ctx.token or "")
  if targetToken ~= "" then
    local nameCandidates = {
      t.name, t.fullName, t.shortName, t.dungeon, t.instance, t.mapName,
      t.zoneName, t.keystone_instance, t.slug, t.abbreviation,
    }
    for i = 1, #nameCandidates do
      local token = NormalizeDungeonToken(nameCandidates[i])
      if token ~= "" and (token:find(targetToken, 1, true) or targetToken:find(token, 1, true)) then
        return true
      end
    end
  end
  return false
end

local function TryExtractBestLevelForDungeon(profile, ctx)
  if type(profile) ~= "table" or type(ctx) ~= "table" then
    return nil
  end
  local targetToken = tostring(ctx.token or "")
  local targetID = tonumber(ctx.activityID)
  if targetToken == "" and not targetID then
    return nil
  end

  local visited = {}
  local best = nil

  local function scan(node, depth)
    if type(node) ~= "table" or depth > 8 or visited[node] then
      return
    end
    visited[node] = true

    if DungeonTableMatchesContext(node, ctx) then
      local level = ExtractLevelFromTable(node)
      if level and (not best or level > best) then
        best = level
      end
    end

    for _, v in pairs(node) do
      if type(v) == "table" then
        scan(v, depth + 1)
      end
    end
  end

  scan(profile, 0)
  return best
end

local function GetRaiderIOHighestCompletion(playerName, dungeonCtx)
  if type(playerName) ~= "string" or playerName == "" then
    return nil
  end

  local profile = nil
  if _G.RaiderIO then
    if type(_G.RaiderIO.GetProfile) == "function" then
      profile = SafeCall(_G.RaiderIO.GetProfile, playerName)
    end
    if profile == nil and type(_G.RaiderIO.GetProfileByName) == "function" then
      profile = SafeCall(_G.RaiderIO.GetProfileByName, playerName)
    end
    if profile == nil and type(_G.RaiderIO.GetPlayerProfile) == "function" then
      profile = SafeCall(_G.RaiderIO.GetPlayerProfile, playerName)
    end
  end

  local best = TryExtractBestLevelForDungeon(profile, dungeonCtx)
  if not best then
    best = TryExtractBestLevel(profile)
  end
  if best then
    return best
  end
  return nil
end

local function GetRaiderIOScore(playerName)
  if type(playerName) ~= "string" or playerName == "" then
    return nil
  end
  local profile = nil
  if _G.RaiderIO then
    if type(_G.RaiderIO.GetProfile) == "function" then
      profile = SafeCall(_G.RaiderIO.GetProfile, playerName)
    end
    if profile == nil and type(_G.RaiderIO.GetProfileByName) == "function" then
      profile = SafeCall(_G.RaiderIO.GetProfileByName, playerName)
    end
    if profile == nil and type(_G.RaiderIO.GetPlayerProfile) == "function" then
      profile = SafeCall(_G.RaiderIO.GetPlayerProfile, playerName)
    end
  end
  return TryExtractRaiderIOScore(profile)
end

local function NormalizePlayerKey(name)
  if not name or name == "" then
    return ""
  end

  if name:find("-") then
    return name
  end

  local realm = GetRealmName() or ""
  realm = realm:gsub("%s+", "")
  if realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end

local function IsRoleToken(v)
  return v == "TANK" or v == "HEALER" or v == "DAMAGER" or v == "NONE"
end

local function NormalizeRoleMask(mask, fallbackRole)
  mask = mask or {}
  if mask.TANK or mask.HEALER or mask.DAMAGER then
    return mask
  end
  if fallbackRole and fallbackRole ~= "" and fallbackRole ~= "NONE" then
    mask[fallbackRole] = true
    return mask
  end
  mask.DAMAGER = true
  return mask
end

local function ParseMemberInfo(applicantID, memberIndex)
  local raw = { SafeCall(C_LFGList.GetApplicantMemberInfo, applicantID, memberIndex) }
  if #raw == 0 or raw[1] == nil then
    return nil
  end

  if type(raw[1]) == "table" then
    local t = raw[1]
    local roleMask = {
      TANK = t.tank == true,
      HEALER = t.healer == true,
      DAMAGER = t.damager == true or t.damage == true or t.dps == true,
    }
    local assignedRole = tostring(t.assignedRole or t.role or "")
    roleMask = NormalizeRoleMask(roleMask, IsRoleToken(assignedRole) and assignedRole or nil)

    local hasDeserter = false
    for k, v in pairs(t) do
      local key = string.lower(tostring(k or ""))
      if key:find("desert") then
        if v == true or tonumber(v) == 71041 or (type(v) == "string" and string.lower(v):find("desert")) then
          hasDeserter = true
        end
      end
    end

    return {
      name = tostring(t.name or t.memberName or ""),
      classLocalized = tostring(t.className or t.localizedClass or ""),
      classFile = tostring(t.classFile or t.classFilename or t.class or ""),
      spec = tostring(t.specName or t.specializationName or t.spec or ""),
      ilvl = tonumber(t.itemLevel or t.ilvl or t.itemLvl) or 0,
      rating = tonumber(t.dungeonScore or t.score or t.mythicRating) or 0,
      role = (IsRoleToken(assignedRole) and assignedRole ~= "NONE") and assignedRole or "",
      roles = roleMask,
      hasDeserter = hasDeserter,
    }
  end

  local name = tostring(raw[1] or "")
  local classLocalized = tostring(raw[2] or "")
  local classFile = tostring(raw[3] or "")
  local rolePos4 = tostring(raw[4] or "")
  local ilvl = tonumber(raw[5]) or 0
  local assignedRole = tostring(raw[10] or "")
  local role = ""
  if IsRoleToken(assignedRole) and assignedRole ~= "NONE" then
    role = assignedRole
  elseif IsRoleToken(rolePos4) and rolePos4 ~= "NONE" then
    role = rolePos4
  end

  local roleMask = {
    TANK = raw[7] == true,
    HEALER = raw[8] == true,
    DAMAGER = raw[9] == true,
  }
  roleMask = NormalizeRoleMask(roleMask, role)

  local spec = ""
  if type(raw[11]) == "string" and raw[11] ~= "" and not IsRoleToken(raw[11]) then
    spec = raw[11]
  elseif type(raw[12]) == "string" and raw[12] ~= "" and not IsRoleToken(raw[12]) then
    spec = raw[12]
  end

  return {
    name = name,
    classLocalized = classLocalized,
    classFile = classFile,
    spec = spec,
    ilvl = ilvl,
    rating = tonumber(raw[6]) or 0,
    role = role,
    roles = roleMask,
    hasDeserter = false,
  }
end

function NotesStore.Get(key)
  key = NormalizePlayerKey(key)
  return DB.playerNotes[key]
end

function NotesStore.Set(key, note)
  key = NormalizePlayerKey(key)
  if key == "" then
    return
  end

  note = tostring(note or "")
  if note == "" then
    DB.playerNotes[key] = nil
  else
    DB.playerNotes[key] = note
  end
end

function NotesStore.Keys()
  local out = {}
  for k in pairs(DB.playerNotes) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

local function GetApplicantInfoData(applicantID)
  local raw1, raw2, raw3, raw4, raw5, raw6, raw7, raw8, raw9, raw10, raw11, raw12 = SafeCall(C_LFGList.GetApplicantInfo, applicantID)
  if type(raw1) == "table" then
    local t = raw1
    return {
      applicantName = tostring(t.applicantName or t.name or ""),
      applicantStatus = tostring(t.applicationStatus or t.applicantStatus or ""),
      pendingStatus = tostring(t.pendingStatus or ""),
      numMembers = tonumber(t.numMembers) or 1,
      ilvl = tonumber(t.itemLevel) or 0,
      rating = tonumber(t.dungeonScore or t.rating) or 0,
      comment = tostring(t.comment or t.message or ""),
      raw = t,
    }
  end
  return {
    applicantName = tostring(raw1 or ""),
    applicantStatus = tostring(raw2 or ""),
    pendingStatus = tostring(raw3 or ""),
    numMembers = tonumber(raw4) or 1,
    ilvl = tonumber(raw8) or 0,
    rating = tonumber(raw10) or tonumber(raw9) or 0,
    comment = tostring(raw11 or raw12 or ""),
    raw = nil,
  }
end

local function ResolveDisplayedRating(blizzApplicantRating, blizzMemberRating, rioRating)
  local b1 = tonumber(blizzApplicantRating) or 0
  local b2 = tonumber(blizzMemberRating) or 0
  local blizz = math.max(b1, b2)
  local rio = tonumber(rioRating) or 0
  if blizz >= 200 then
    return blizz
  end
  if rio >= 200 then
    return rio
  end
  return blizz
end

local function IsInvitedState(status, pending)
  local s = string.lower(tostring(status or ""))
  local p = string.lower(tostring(pending or ""))
  return s:find("invite", 1, true) ~= nil or p:find("invite", 1, true) ~= nil
end

local function IsJoinedOrFinalState(status, pending)
  local s = string.lower(tostring(status or ""))
  local p = string.lower(tostring(pending or ""))
  if s:find("accept", 1, true) or p:find("accept", 1, true) then
    return true
  end
  if s:find("joined", 1, true) or p:find("joined", 1, true) then
    return true
  end
  if s:find("declin", 1, true) or p:find("declin", 1, true) then
    return true
  end
  if s:find("cancel", 1, true) or p:find("cancel", 1, true) then
    return true
  end
  return false
end

function ApplicantData.GetApplicants()
  if not C_LFGList then
    return {}
  end

  local applicantIDs = SafeCall(C_LFGList.GetApplicants)
  if type(applicantIDs) ~= "table" then
    return {}
  end

  local rows = {}
  local listingDungeon = GetActiveListingDungeonContext()
  local bestCache = {}
  local rioScoreCache = {}
  local function GetCachedBest(playerKey)
    if bestCache[playerKey] ~= nil then
      if bestCache[playerKey] == false then
        return nil
      end
      return bestCache[playerKey]
    end
    local v = GetRaiderIOHighestCompletion(playerKey, listingDungeon)
    bestCache[playerKey] = v or false
    return v
  end
  local function GetCachedRioScore(playerKey)
    if rioScoreCache[playerKey] ~= nil then
      if rioScoreCache[playerKey] == false then
        return nil
      end
      return rioScoreCache[playerKey]
    end
    local v = GetRaiderIOScore(playerKey)
    rioScoreCache[playerKey] = v or false
    return v
  end
  for _, applicantID in ipairs(applicantIDs) do
    local info = GetApplicantInfoData(applicantID)
    local numMembers = info.numMembers
    local applicantStatus = info.applicantStatus
    local pendingStatus = info.pendingStatus
    if not IsJoinedOrFinalState(applicantStatus, pendingStatus) then
      local applicantRating = info.rating
      local applicationNote = info.comment

      local members = {}
      local groupRoles = {}
      local primary = ParseMemberInfo(applicantID, 1)
      if primary then
        members[#members + 1] = primary
        for roleKey, enabled in pairs(primary.roles or {}) do
          if enabled then
            groupRoles[roleKey] = true
          end
        end
      end

      for memberIndex = 2, numMembers do
        local m = ParseMemberInfo(applicantID, memberIndex)
        if m then
          members[#members + 1] = m
          for roleKey, enabled in pairs(m.roles or {}) do
            if enabled then
              groupRoles[roleKey] = true
            end
          end
        end
      end

      local displayMember = primary or members[1] or {}
      local leaderName = tostring(displayMember.name or info.applicantName or ("Applicant " .. tostring(applicantID)))

      local classLocalized = tostring(displayMember.classLocalized or "")
      local classFile = tostring(displayMember.classFile or "")
      local role = tostring(displayMember.role or "")
      if role == "" or role == "NONE" then
        for _, roleKey in ipairs(ROLE_ORDER) do
          if groupRoles[roleKey] then
            role = roleKey
            break
          end
        end
        if role == "" then
          role = "DAMAGER"
        end
      end

      local ilvl = tonumber(displayMember.ilvl) or tonumber(info.ilvl) or 0
      local leaderKey = NormalizePlayerKey(leaderName)
      local leaderMemberRating = tonumber(displayMember.rating) or 0
      local leaderRioScore = GetCachedRioScore(leaderKey) or 0
      applicantRating = ResolveDisplayedRating(applicantRating, leaderMemberRating, leaderRioScore)
      local spec = tostring(displayMember.spec or "")
      if spec == "" and numMembers > 1 then
        spec = "Group"
      end

      local leaderHighest = GetCachedBest(leaderKey)

      local row = {
        applicantID = applicantID,
        memberIndex = 1,
        name = leaderName,
        playerKey = leaderKey,
        classLocalized = classLocalized,
        classFile = classFile,
        spec = spec,
        role = role,
        roles = NormalizeRoleMask(groupRoles, role),
        ilvl = ilvl,
        rating = applicantRating,
        numMembers = numMembers,
        applicantStatus = applicantStatus,
        pendingStatus = pendingStatus,
        isInvited = IsInvitedState(applicantStatus, pendingStatus),
        note = NotesStore.Get(leaderName),
        applicationNote = applicationNote,
        highestCompletion = leaderHighest,
        groupRootID = tostring(applicantID),
        hasDeserter = primary and primary.hasDeserter == true or false,
        isGroupLeader = numMembers > 1,
        isGroupMember = false,
      }

      rows[#rows + 1] = row

      if numMembers > 1 then
        for memberIndex = 2, #members do
          local member = members[memberIndex]
          local memberName = tostring(member.name or ("Member " .. tostring(memberIndex)))
          local memberRole = tostring(member.role or "")
          if memberRole == "" or memberRole == "NONE" then
            memberRole = "DAMAGER"
          end
          local memberKey = NormalizePlayerKey(memberName)
          local memberRioScore = GetCachedRioScore(memberKey) or 0
          local memberRating = ResolveDisplayedRating(applicantRating, tonumber(member.rating) or 0, memberRioScore)
          rows[#rows + 1] = {
            applicantID = applicantID,
            memberIndex = memberIndex,
            name = memberName,
            playerKey = memberKey,
            classLocalized = tostring(member.classLocalized or ""),
            classFile = tostring(member.classFile or ""),
            spec = tostring(member.spec or ""),
            role = memberRole,
            roles = NormalizeRoleMask(member.roles or {}, memberRole),
            ilvl = tonumber(member.ilvl) or ilvl,
            rating = memberRating,
            numMembers = numMembers,
            applicantStatus = applicantStatus,
            pendingStatus = pendingStatus,
            isInvited = IsInvitedState(applicantStatus, pendingStatus),
            note = NotesStore.Get(memberName),
            applicationNote = "",
            highestCompletion = GetCachedBest(memberKey),
            groupRootID = tostring(applicantID),
            hasDeserter = member.hasDeserter == true,
            isGroupLeader = false,
            isGroupMember = true,
          }
        end
      end
    end
  end

  return rows
end

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
  local rules = DB.rules
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

  local ratingNorm = flags.useRating and Normalize(row.rating or 0, 1000, 3400) or 0.5
  local ilvlNorm = flags.useIlvl and Normalize(row.ilvl or 0, 620, 675) or 0.5
  if flags.useIlvl then
    ilvlNorm = Pow(ilvlNorm, 1.6)
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

  local finalNorm = Clamp01(qualityNorm * gateMultiplier)
  local score = math.floor((finalNorm * 100) + 0.5)

  local fitSteps
  if finalNorm >= 0.70 then
    fitSteps = 5
  elseif finalNorm >= 0.52 then
    fitSteps = 4
  elseif finalNorm >= 0.34 then
    fitSteps = 3
  elseif finalNorm >= 0.18 then
    fitSteps = 2
  else
    fitSteps = 1
  end
  local badge = FIT_LABEL_BY_STEPS[fitSteps] or "Awful Fit"

  row.fitSteps = fitSteps
  row.hardFailRole = hardFailRole
  row.hardFailRating = hardFailRating
  row.hardFailIlvl = hardFailIlvl
  row.fitBreakdown = string.format(
    "Gates: role %s, rating %s, ilvl %s | Q: R %.2f I %.2f B %.2f | Final: %.0f%% (x%.2f) | Tier %d/5",
    rolePass and "pass" or "fail",
    ratingPass and "pass" or "fail",
    ilvlPass and "pass" or "fail",
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
    reasons[#reasons + 1] = "Rating " .. (ratingPass and "pass" or "fail")
  end
  if ilvlGateEnabled then
    reasons[#reasons + 1] = "iLvl " .. (ilvlPass and "pass" or "fail")
  end
  reasons[#reasons + 1] = "Quality " .. string.format("%.0f%%", qualityNorm * 100)
  return score, badge, table.concat(reasons, ", ")
end

local function CompareRows(a, b)
  local mode = DB.sort.mode
  local dir = DB.sort.direction

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
  local classFile = tostring(row.classFile or "")
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

local function MakeHeaderButton(parent, text, width, x, y, key)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(width, 24)
  btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

  local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("CENTER")
  label:SetText(text)
  label:SetTextColor(0.96, 0.83, 0.34)
  btn.label = label

  local hl = btn:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(0.35, 0.2, 0.08, 0.35)

  if key then
    btn:SetScript("OnEnter", function(self)
      if self.label then
        self.label:SetTextColor(1, 0.9, 0.5)
      end
    end)
    btn:SetScript("OnLeave", function(self)
      if self.label then
        self.label:SetTextColor(0.96, 0.83, 0.34)
      end
    end)
    btn:SetScript("OnClick", function()
      if DB.sort.mode == key then
        DB.sort.direction = (DB.sort.direction == "desc") and "asc" or "desc"
      else
        DB.sort.mode = key
        DB.sort.direction = "desc"
      end
      UI.RefreshApplicants()
    end)
  else
    btn:EnableMouse(false)
    btn:SetScript("OnEnter", nil)
    btn:SetScript("OnLeave", nil)
    btn:SetScript("OnClick", nil)
  end

  return btn
end

local function CreateDataRow(parent, index, layout)
  local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  row._index = index
  row._layout = layout
  row._container = parent
  row:SetSize(layout.width, layout.height)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", layout.left, layout.top - ((index - 1) * (layout.height + layout.gap)))
  row:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  row:SetBackdropColor(0.05, 0.05, 0.06, 0.9)
  row:SetBackdropBorderColor(0.24, 0.24, 0.24, 0.9)

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  local baseAlpha = (index % 2 == 0) and 0.28 or 0.18
  bg:SetColorTexture(0.09, 0.09, 0.1, baseAlpha)
  row.baseAlpha = baseAlpha
  row.bg = bg

  local leftAccent = row:CreateTexture(nil, "BORDER")
  leftAccent:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
  leftAccent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
  leftAccent:SetWidth(3)
  leftAccent:SetColorTexture(0.78, 0.66, 0.3, 0.8)
  row.leftAccent = leftAccent

  local groupConnector = row:CreateTexture(nil, "BORDER")
  groupConnector:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -2)
  groupConnector:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 12, 2)
  groupConnector:SetWidth(1)
  groupConnector:SetColorTexture(0.62, 0.56, 0.32, 0.7)
  groupConnector:Hide()
  row.groupConnector = groupConnector

  local hover = row:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 0.9, 0.45, 0.08)
  hover:Hide()
  row.hover = hover

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
  row.name:SetWidth(220)
  row.name:SetJustifyH("LEFT")

  row.fitSquares = {}
  local squareColors = {
    { 0.86, 0.15, 0.15 }, -- red
    { 0.92, 0.48, 0.14 }, -- orange
    { 0.96, 0.84, 0.18 }, -- yellow
    { 0.47, 0.85, 0.34 }, -- light green
    { 0.10, 0.58, 0.23 }, -- dark green
  }
  for i = 1, 5 do
    local square = row:CreateTexture(nil, "ARTWORK")
    square:SetSize(10, 10)
    square:SetPoint("LEFT", row, "LEFT", 260 + ((i - 1) * 12), 0)
    square:SetColorTexture(squareColors[i][1], squareColors[i][2], squareColors[i][3], 0.96)
    row.fitSquares[i] = square
  end

  row.rating = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.rating:SetPoint("LEFT", row, "LEFT", 336, 0)
  row.rating:SetWidth(64)
  row.rating:SetJustifyH("CENTER")

  row.best = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.best:SetPoint("LEFT", row, "LEFT", 404, 0)
  row.best:SetWidth(44)
  row.best:SetJustifyH("CENTER")

  row.ilvl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.ilvl:SetPoint("LEFT", row, "LEFT", 452, 0)
  row.ilvl:SetWidth(52)
  row.ilvl:SetJustifyH("CENTER")

  row.role = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.role:SetPoint("LEFT", row, "LEFT", 508, 0)
  row.role:SetWidth(104)
  row.role:SetJustifyH("CENTER")

  row.roleIcons = {}
  for iconIndex = 1, 3 do
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
    icon:Hide()
    row.roleIcons[iconIndex] = icon
  end
  row.roleIcons[1]:SetPoint("CENTER", row.role, "CENTER", -18, 0)
  row.roleIcons[2]:SetPoint("CENTER", row.role, "CENTER", 0, 0)
  row.roleIcons[3]:SetPoint("CENTER", row.role, "CENTER", 18, 0)

  row.specIcon = row:CreateTexture(nil, "ARTWORK")
  row.specIcon:SetSize(16, 16)
  row.specIcon:SetPoint("CENTER", row.role, "RIGHT", -8, 0)
  row.specIcon:Hide()

  row.deserterButton = CreateFrame("Button", nil, row)
  row.deserterButton:SetSize(14, 14)
  row.deserterButton:Hide()
  row.deserterButton.icon = row.deserterButton:CreateTexture(nil, "ARTWORK")
  row.deserterButton.icon:SetAllPoints()
  row.deserterButton.icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertOther")
  row.deserterButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.deserterButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetSpellByID then
      GameTooltip:SetSpellByID(71041)
      GameTooltip:AddLine("Detected on this applicant", 1, 0.35, 0.35, true)
    else
      GameTooltip:SetText("Dungeon Deserter")
      GameTooltip:AddLine("Detected on this applicant", 1, 0.35, 0.35, true)
    end
    GameTooltip:Show()
  end)
  row.deserterButton:SetScript("OnLeave", function()
    GameTooltip_Hide()
  end)

  row.noteButton = CreateFrame("Button", nil, row)
  row.noteButton:SetSize(14, 14)
  row.noteButton:Hide()
  row.noteButton.icon = row.noteButton:CreateTexture(nil, "ARTWORK")
  row.noteButton.icon:SetAllPoints()
  row.noteButton.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
  row.noteButton:SetScript("OnEnter", function(self)
    if not self.noteText or self.noteText == "" then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Signup Note")
    GameTooltip:AddLine(self.noteText, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  row.noteButton:SetScript("OnLeave", function()
    GameTooltip_Hide()
  end)

  row.score = nil

  row.decline = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.decline:SetSize(24, 22)
  row.decline:SetPoint("LEFT", row, "LEFT", 788, 0)
  row.decline:SetText("")
  row.decline.icon = row.decline:CreateTexture(nil, "ARTWORK")
  row.decline.icon:SetSize(14, 14)
  row.decline.icon:SetPoint("CENTER")
  row.decline.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")

  row.invite = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.invite:SetSize(24, 22)
  row.invite:SetPoint("RIGHT", row.decline, "LEFT", -4, 0)
  row.invite:SetText("")
  row.invite.icon = row.invite:CreateTexture(nil, "ARTWORK")
  row.invite.icon:SetSize(14, 14)
  row.invite.icon:SetPoint("CENTER")
  row.invite.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")

  return row
end

local function GetMythicSummary()
  local lines = {}

  lines[#lines + 1] = "Group: " .. ((IsInGroup() and "In Group") or "Solo")
  lines[#lines + 1] = "Leader: " .. ((UnitName("player") and UnitIsGroupLeader("player") and "Yes") or "No")

  if C_LFGList then
    local activeInfo = SafeCall(C_LFGList.GetActiveEntryInfo)
    if type(activeInfo) == "table" then
      lines[#lines + 1] = "Listing: " .. tostring(activeInfo.name or "Active")
      if activeInfo.activityID then
        lines[#lines + 1] = "Activity ID: " .. tostring(activeInfo.activityID)
      end
    else
      lines[#lines + 1] = "Listing: None"
    end
  end

  if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
    local score = SafeCall(C_ChallengeMode.GetOverallDungeonScore)
    if score then
      lines[#lines + 1] = "M+ Rating: " .. tostring(score)
    end
  end

  return table.concat(lines, "\n")
end

local function ParseClassSpecPrefs(text)
  local prefs = {}
  for token in string.gmatch(string.upper(text or ""), "[^,%s]+") do
    prefs[token] = true
  end
  return prefs
end

local function FormatClassSpecPrefs()
  local keys = {}
  for key in pairs(DB.rules.classSpecPrefs) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return table.concat(keys, ",")
end

local function HasDungeonDeserter(unit)
  unit = unit or "player"
  if not UnitExists(unit) then
    return false, 0
  end
  for i = 1, 40 do
    local name, _, _, _, duration, expirationTime, _, _, _, spellID = UnitDebuff(unit, i)
    if not name then
      break
    end
    if tonumber(spellID) == 71041 then
      local remaining = 0
      if expirationTime and expirationTime > 0 and GetTime then
        remaining = math.max(0, expirationTime - GetTime())
      elseif duration and duration > 0 then
        remaining = duration
      end
      return true, remaining
    end
  end
  return false, 0
end

local function TryShowNativeApplicantTooltip(owner, data)
  if not owner or not data or type(data.applicantID) ~= "number" or data.applicantID <= 0 then
    return false
  end

  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()

  if type(LFGListUtil_SetApplicantMemberTooltip) == "function" and type(data.memberIndex) == "number" then
    SafeCall(LFGListUtil_SetApplicantMemberTooltip, GameTooltip, data.applicantID, data.memberIndex)
    if GameTooltip:IsShown() and (GameTooltip:NumLines() or 0) > 0 then
      return true
    end
    GameTooltip:ClearLines()
  end

  if type(LFGListUtil_SetApplicantTooltip) == "function" then
    SafeCall(LFGListUtil_SetApplicantTooltip, GameTooltip, data.applicantID)
    if GameTooltip:IsShown() and (GameTooltip:NumLines() or 0) > 0 then
      return true
    end
    GameTooltip:ClearLines()
  end

  if type(LFGListUtil_SetSearchEntryTooltip) == "function" then
    SafeCall(LFGListUtil_SetSearchEntryTooltip, GameTooltip, data.applicantID)
    if GameTooltip:IsShown() and (GameTooltip:NumLines() or 0) > 0 then
      return true
    end
    GameTooltip:ClearLines()
  end

  GameTooltip:Hide()
  return false
end

local function TryShowNativePlayerTooltip(owner, data)
  if not owner or not data then
    return false
  end
  local key = tostring(data.playerKey or data.name or "")
  key = key:gsub("^%s+", ""):gsub("%s+$", "")
  if key == "" then
    return false
  end

  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()

  local ok = SafeCall(GameTooltip.SetHyperlink, GameTooltip, "player:" .. key)
  if ok ~= nil and GameTooltip:IsShown() and (GameTooltip:NumLines() or 0) > 0 then
    return true
  end

  GameTooltip:Hide()
  return false
end

function UI.RefreshApplicants()
  if not addon.lfgTab or not addon.rows then
    return
  end

  local rows = ApplicantData.GetApplicants()
  for _, entry in ipairs(rows) do
    entry.score, entry.badge, entry.reason = RulesEngine.Score(entry)
  end

  local leaders = {}
  local membersByRoot = {}
  for _, row in ipairs(rows) do
    if row.isGroupMember then
      local root = tostring(row.groupRootID or row.applicantID or row.name)
      membersByRoot[root] = membersByRoot[root] or {}
      membersByRoot[root][#membersByRoot[root] + 1] = row
    else
      leaders[#leaders + 1] = row
    end
  end

  SortRows(leaders)
  for _, memberRows in pairs(membersByRoot) do
    SortRows(memberRows)
  end

  local displayRows = {}
  for _, leader in ipairs(leaders) do
    local root = tostring(leader.groupRootID or leader.applicantID or leader.name)
    displayRows[#displayRows + 1] = leader
    local children = membersByRoot[root]
    if children then
      for _, child in ipairs(children) do
        displayRows[#displayRows + 1] = child
      end
    end
  end

  addon.currentRows = displayRows
  local rowsPerPage = #addon.rows
  local maxOffset = math.max(0, #displayRows - rowsPerPage)

  if addon.applicantScrollFrame and addon.applicantScrollFrame.offset and addon.applicantScrollFrame.offset > maxOffset then
    addon.applicantScrollFrame.offset = maxOffset
  end

  if addon.applicantScrollFrame and FauxScrollFrame_Update and FauxScrollFrame_GetOffset then
    FauxScrollFrame_Update(addon.applicantScrollFrame, #displayRows, rowsPerPage, addon.rowStep or 40)
  end

  local offset = 0
  if addon.applicantScrollFrame and FauxScrollFrame_GetOffset then
    offset = FauxScrollFrame_GetOffset(addon.applicantScrollFrame) or 0
  end
  local startIndex = offset + 1

  for i = 1, #addon.rows do
    local widget = addon.rows[i]
    local dataIndex = startIndex + i - 1
    local data = displayRows[dataIndex]

    if data then
      local layout = widget._layout or { left = 0, top = 0, width = 834, height = 34, gap = 6 }
      local indent = data.isGroupMember and 18 or 0
      widget:ClearAllPoints()
      widget:SetPoint("TOPLEFT", widget._container or widget:GetParent(), "TOPLEFT", layout.left, layout.top - ((widget._index - 1) * (layout.height + layout.gap)))
      widget:SetSize(layout.width, layout.height)
      widget:Show()
      widget.name:ClearAllPoints()
      widget.name:SetPoint("LEFT", widget, "LEFT", 12 + indent, 0)
      widget.name:SetText(tostring(data.name or "-"))

      local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.classFile or ""]
      if classColor then
        widget.name:SetTextColor(classColor.r, classColor.g, classColor.b)
      else
        widget.name:SetTextColor(0.95, 0.95, 0.95)
      end
      if data.isInvited then
        widget.name:SetTextColor(0.45, 1, 0.45)
      end

      local fitSteps = tonumber(data.fitSteps) or 1
      local fitColor = { 0.86, 0.15, 0.15 } -- awful red
      if fitSteps >= 5 then
        fitColor = { 0.10, 0.58, 0.23 } -- dark green
      elseif fitSteps == 4 then
        fitColor = { 0.47, 0.85, 0.34 } -- light green
      elseif fitSteps == 3 then
        fitColor = { 0.96, 0.84, 0.18 } -- yellow
      elseif fitSteps == 2 then
        fitColor = { 0.92, 0.48, 0.14 } -- orange/red
      end
      for s = 1, 5 do
        local sq = widget.fitSquares and widget.fitSquares[s]
        if sq then
          if s <= fitSteps then
            sq:SetColorTexture(fitColor[1], fitColor[2], fitColor[3], 0.96)
          else
            sq:SetColorTexture(0.32, 0.32, 0.34, 0.9)
          end
        end
      end

      widget.rating:SetText(tostring(data.rating or 0))
      local best = tonumber(data.highestCompletion)
      if best and best > 0 then
        widget.best:SetText("+" .. tostring(best))
      else
        widget.best:SetText("--")
      end
      widget.ilvl:SetText(tostring(math.floor(data.ilvl or 0)))

      local primaryRole = nil
      for _, roleKey in ipairs(ROLE_ORDER) do
        if data.roles and data.roles[roleKey] then
          primaryRole = roleKey
          break
        end
      end
      if not primaryRole then
        primaryRole = data.role or "DAMAGER"
      end

      if primaryRole then
        widget.role:SetText("")
      else
        widget.role:SetText("-")
      end
      for idx = 1, #widget.roleIcons do
        local icon = widget.roleIcons[idx]
        if icon and idx == 1 and primaryRole then
          icon:SetPoint("CENTER", widget.role, "CENTER", 0, 0)
          icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
          if GetTexCoordsForRole then
            icon:SetTexCoord(GetTexCoordsForRole(primaryRole))
          else
            icon:SetTexCoord(GetRoleTexCoords(primaryRole))
          end
          icon:Show()
        elseif icon then
          icon:Hide()
        end
      end

      local specIcon = GetSpecIconForRow(data)
      if specIcon then
        widget.specIcon:SetTexture(specIcon)
        widget.specIcon:SetDesaturated(false)
        widget.specIcon:Show()
      else
        widget.specIcon:Hide()
      end

      if data.hasDeserter then
        local textOffset = math.min((widget.name:GetStringWidth() or 0) + 8, 200)
        widget.deserterButton:ClearAllPoints()
        widget.deserterButton:SetPoint("LEFT", widget.name, "LEFT", textOffset, 0)
        widget.deserterButton:Show()
      else
        widget.deserterButton:Hide()
      end

      if data.applicationNote and data.applicationNote ~= "" and not data.isGroupMember then
        widget.noteButton.noteText = data.applicationNote
        widget.noteButton:ClearAllPoints()
        local noteOffset = math.min((widget.name:GetStringWidth() or 0) + 8, 182)
        widget.noteButton:SetPoint("LEFT", widget.name, "LEFT", noteOffset, 0)
        if widget.deserterButton:IsShown() then
          widget.noteButton:SetPoint("LEFT", widget.deserterButton, "RIGHT", 2, 0)
        end
        widget.noteButton:Show()
      else
        widget.noteButton.noteText = nil
        widget.noteButton:Hide()
      end
      widget.role:SetTextColor(0.95, 0.82, 0.3)
      local rr, rg, rb = GetRatingColor(data.rating or 0)
      widget.rating:SetTextColor(rr, rg, rb)
      widget.best:SetTextColor(0.7, 0.85, 1)
      widget.ilvl:SetTextColor(0.88, 0.88, 0.88)

      if data.badge == "Great Fit" then
        widget.leftAccent:SetColorTexture(0.14, 0.62, 0.22, 0.9)
      elseif data.badge == "Good Fit" then
        widget.leftAccent:SetColorTexture(0.3, 0.9, 0.36, 0.9)
      elseif data.badge == "Maybe" then
        widget.leftAccent:SetColorTexture(0.92, 0.7, 0.2, 0.9)
      elseif data.badge == "Bad Fit" then
        widget.leftAccent:SetColorTexture(0.95, 0.45, 0.45, 0.9)
      else
        widget.leftAccent:SetColorTexture(0.7, 0.08, 0.08, 0.95)
      end

      if data.isGroupMember then
        if widget.bg then
          if data.hasDeserter then
            widget.bg:SetColorTexture(0.28, 0.05, 0.05, 0.42)
            widget:SetBackdropBorderColor(0.56, 0.18, 0.18, 0.9)
          elseif data.isInvited then
            widget.bg:SetColorTexture(0.05, 0.24, 0.09, 0.42)
            widget:SetBackdropBorderColor(0.25, 0.66, 0.34, 0.9)
          else
            widget.bg:SetColorTexture(0.07, 0.08, 0.1, 0.36)
            widget:SetBackdropBorderColor(0.24, 0.24, 0.24, 0.9)
          end
        end
        if widget.groupConnector then
          widget.groupConnector:Show()
        end
      else
        if widget.bg then
          if data.hasDeserter then
            widget.bg:SetColorTexture(0.36, 0.06, 0.06, 0.52)
            widget:SetBackdropBorderColor(0.62, 0.2, 0.2, 0.95)
          elseif data.isInvited then
            widget.bg:SetColorTexture(0.07, 0.3, 0.12, 0.54)
            widget:SetBackdropBorderColor(0.30, 0.72, 0.40, 0.95)
          else
            widget.bg:SetColorTexture(0.08, 0.08, 0.07, widget.baseAlpha or 0.14)
            widget:SetBackdropBorderColor(0.24, 0.24, 0.24, 0.9)
          end
        end
        if widget.groupConnector then
          widget.groupConnector:Hide()
        end
      end

      widget:SetScript("OnEnter", function(self)
        if self.hover then
          self.hover:Show()
        end
        local usedNative = TryShowNativePlayerTooltip(self, data) or TryShowNativeApplicantTooltip(self, data)
        if not usedNative then
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText(data.name)
          local rolesText = {}
          for _, roleKey in ipairs(ROLE_ORDER) do
            if data.roles and data.roles[roleKey] then
              rolesText[#rolesText + 1] = ROLE_LABELS[roleKey] or roleKey
            end
          end
          if #rolesText == 0 then
            rolesText[1] = ROLE_LABELS[data.role] or data.role or "-"
          end
          local classText = (data.classLocalized ~= "" and data.classLocalized) or (data.classFile ~= "" and data.classFile) or "Unknown"
          local specText = (data.spec and data.spec ~= "") and data.spec or "-"
          GameTooltip:AddLine("Role: " .. table.concat(rolesText, " + "), 1, 1, 1)
          GameTooltip:AddLine("Class - Spec: " .. classText .. " - " .. specText, 1, 1, 1)
          GameTooltip:AddLine("Score: " .. tostring(data.score), 1, 1, 1)
          if data.highestCompletion then
            GameTooltip:AddLine("Highest completion: +" .. tostring(data.highestCompletion), 0.7, 0.85, 1)
          end
        end
        if data.fitBreakdown and data.fitBreakdown ~= "" then
          GameTooltip:AddLine(data.fitBreakdown, 0.78, 0.9, 1, true)
        end
        GameTooltip:Show()
      end)
      widget:SetScript("OnLeave", function(self)
        if self.hover then
          self.hover:Hide()
        end
        GameTooltip_Hide()
      end)

      widget.invite:SetScript("OnClick", function()
        if Actions.Invite(data.applicantID) then
          Print("Invited " .. data.name)
        else
          Print("Invite failed for " .. data.name)
        end
      end)

      widget.decline:SetScript("OnClick", function()
        if Actions.Decline(data.applicantID) then
          Print("Declined " .. data.name)
        else
          Print("Decline failed for " .. data.name)
        end
      end)

      local canAct = (not data.isGroupMember)
      widget.invite:SetEnabled(canAct)
      widget.decline:SetEnabled(canAct)
      if widget.invite.icon then
        widget.invite.icon:SetDesaturated(not canAct)
        widget.invite.icon:SetVertexColor(canAct and 1 or 0.6, canAct and 1 or 0.6, canAct and 1 or 0.6)
      end
      if widget.decline.icon then
        widget.decline.icon:SetDesaturated(not canAct)
        widget.decline.icon:SetVertexColor(canAct and 1 or 0.6, canAct and 1 or 0.6, canAct and 1 or 0.6)
      end
      widget.invite:SetShown(not data.isGroupMember)
      widget.decline:SetShown(not data.isGroupMember)

      widget.invite:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Invite")
        GameTooltip:Show()
      end)
      widget.invite:SetScript("OnLeave", function()
        GameTooltip_Hide()
      end)
      widget.decline:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Decline")
        GameTooltip:Show()
      end)
      widget.decline:SetScript("OnLeave", function()
        GameTooltip_Hide()
      end)
    else
      widget:Hide()
    end
  end

  if addon.applicantCountText then
    addon.applicantCountText:SetText("Applicants: " .. tostring(#leaders))
  end
  if addon.listingContextText then
    addon.listingContextText:SetText("Listing: " .. GetActiveListingContext())
  end
  if addon.applicantDeserterText then
    local count = 0
    for _, row in ipairs(rows) do
      if row.hasDeserter then
        count = count + 1
      end
    end
    if count > 0 then
      addon.applicantDeserterText:SetText("Applicant deserter: " .. tostring(count))
      addon.applicantDeserterText:SetTextColor(1, 0.35, 0.35)
    else
      addon.applicantDeserterText:SetText("Applicant deserter: 0")
      addon.applicantDeserterText:SetTextColor(0.45, 0.95, 0.45)
    end
  end
  if addon.deserterStatusText then
    local hasDeserter, remaining = HasDungeonDeserter("player")
    if hasDeserter then
      local mins = math.floor((remaining or 0) / 60)
      local secs = math.floor((remaining or 0) % 60)
      addon.deserterStatusText:SetText(string.format("Your deserter: ACTIVE (%d:%02d)", mins, secs))
      addon.deserterStatusText:SetTextColor(1, 0.3, 0.3)
    else
      addon.deserterStatusText:SetText("Your deserter: Clear")
      addon.deserterStatusText:SetTextColor(0.45, 0.95, 0.45)
    end
  end
end

local function BuildGroupUnits()
  local units = {}
  if IsInRaid() then
    local count = GetNumGroupMembers() or 0
    for i = 1, count do
      units[#units + 1] = "raid" .. i
    end
  elseif IsInGroup() then
    units[#units + 1] = "player"
    local count = GetNumSubgroupMembers() or 0
    for i = 1, count do
      units[#units + 1] = "party" .. i
    end
  else
    units[#units + 1] = "player"
  end
  return units
end

local SPEC_LABELS = {
  [62] = "Arcane", [63] = "Fire", [64] = "Frost",
  [65] = "Holy", [66] = "Protection", [70] = "Retribution",
  [71] = "Arms", [72] = "Fury", [73] = "Protection",
  [102] = "Balance", [103] = "Feral", [104] = "Guardian", [105] = "Restoration",
  [250] = "Blood", [251] = "Frost", [252] = "Unholy",
  [253] = "Beast Mastery", [254] = "Marksmanship", [255] = "Survival",
  [256] = "Discipline", [257] = "Holy", [258] = "Shadow",
  [259] = "Assassination", [260] = "Outlaw", [261] = "Subtlety",
  [262] = "Elemental", [263] = "Enhancement", [264] = "Restoration",
  [265] = "Destruction", [266] = "Affliction", [267] = "Demonology",
  [268] = "Brewmaster", [269] = "Windwalker", [270] = "Mistweaver",
  [577] = "Havoc", [581] = "Vengeance",
  [1467] = "Devastation", [1468] = "Preservation", [1473] = "Augmentation",
}

local CLASS_LABELS = {
  DEATHKNIGHT = "Death Knight",
  DEMONHUNTER = "Demon Hunter",
  DRUID = "Druid",
  EVOKER = "Evoker",
  HUNTER = "Hunter",
  MAGE = "Mage",
  MONK = "Monk",
  PALADIN = "Paladin",
  PRIEST = "Priest",
  ROGUE = "Rogue",
  SHAMAN = "Shaman",
  WARLOCK = "Warlock",
  WARRIOR = "Warrior",
}

local function Specs(...)
  local out = {}
  local n = select("#", ...)
  for i = 1, n do
    out[#out + 1] = select(i, ...)
  end
  return out
end

local UTILITY_ENTRIES = {
  { category = "Death Knight", spellID = 47528, name = "Mind Freeze", providers = { { class = "DEATHKNIGHT" } } },
  { category = "Death Knight", spellID = 207167, name = "Blinding Sleet", providers = { { class = "DEATHKNIGHT" } } },
  { category = "Death Knight", spellID = 221562, name = "Asphyxiate", providers = { { class = "DEATHKNIGHT" } } },
  { category = "Death Knight", spellID = 49576, name = "Death Grip", providers = { { class = "DEATHKNIGHT" } } },
  { category = "Death Knight", spellID = 45524, name = "Chains of Ice", providers = { { class = "DEATHKNIGHT" } } },
  { category = "Death Knight", spellID = 61999, name = "Raise Ally", providers = { { class = "DEATHKNIGHT" } } },
  { category = "Death Knight", spellID = 51052, name = "Anti-Magic Zone", providers = { { class = "DEATHKNIGHT" } } },

  { category = "Druid", spellID = 1126, name = "Mark of the Wild", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 106839, name = "Skull Bash", providers = { { class = "DRUID", specs = Specs(103, 104) } } },
  { category = "Druid", spellID = 78675, name = "Solar Beam", providers = { { class = "DRUID", specs = Specs(102) } } },
  { category = "Druid", spellID = 339, name = "Entangling Roots", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 102359, name = "Mass Entanglement", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 2637, name = "Hibernate", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 33786, name = "Cyclone", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 132469, name = "Typhoon", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 102793, name = "Ursol's Vortex", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 20484, name = "Rebirth", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 102342, name = "Ironbark", providers = { { class = "DRUID", specs = Specs(105) } } },
  { category = "Druid", spellID = 29166, name = "Innervate", providers = { { class = "DRUID" } } },
  { category = "Druid", spellID = 77761, name = "Stampeding Roar", providers = { { class = "DRUID" } } },

  { category = "Evoker", spellID = 381748, name = "Blessing of the Bronze", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 395152, name = "Ebon Might", providers = { { class = "EVOKER", specs = Specs(1473) } } },
  { category = "Evoker", spellID = 351338, name = "Quell", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 360806, name = "Sleep Walk", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 358385, name = "Landslide", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 357214, name = "Wing Buffet", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 368970, name = "Tail Swipe", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 357170, name = "Time Dilation", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 370665, name = "Rescue", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 374227, name = "Zephyr", providers = { { class = "EVOKER" } } },
  { category = "Evoker", spellID = 363534, name = "Rewind", providers = { { class = "EVOKER", specs = Specs(1468) } } },

  { category = "Mage", spellID = 1459, name = "Arcane Intellect", providers = { { class = "MAGE" } } },
  { category = "Mage", spellID = 2139, name = "Counterspell", providers = { { class = "MAGE" } } },
  { category = "Mage", spellID = 118, name = "Polymorph", providers = { { class = "MAGE" } } },
  { category = "Mage", spellID = 31661, name = "Dragon's Breath", providers = { { class = "MAGE", specs = Specs(63) } } },
  { category = "Mage", spellID = 122, name = "Frost Nova", providers = { { class = "MAGE" } } },
  { category = "Mage", spellID = 113724, name = "Ring of Frost", providers = { { class = "MAGE" } } },
  { category = "Mage", spellID = 414660, name = "Mass Barrier", providers = { { class = "MAGE" } } },
  { category = "Mage", spellID = 80353, name = "Time Warp", providers = { { class = "MAGE" } } },

  { category = "Monk", spellID = 113746, name = "Mystic Touch", providers = { { class = "MONK" } } },
  { category = "Monk", spellID = 116705, name = "Spear Hand Strike", providers = { { class = "MONK" } } },
  { category = "Monk", spellID = 119381, name = "Leg Sweep", providers = { { class = "MONK" } } },
  { category = "Monk", spellID = 115078, name = "Paralysis", providers = { { class = "MONK" } } },
  { category = "Monk", spellID = 116844, name = "Ring of Peace", providers = { { class = "MONK" } } },
  { category = "Monk", spellID = 116849, name = "Life Cocoon", providers = { { class = "MONK", specs = Specs(270) } } },
  { category = "Monk", spellID = 115310, name = "Revival", providers = { { class = "MONK", specs = Specs(270) } } },
  { category = "Monk", spellID = 116841, name = "Tiger's Lust", providers = { { class = "MONK" } } },

  { category = "Paladin", spellID = 465, name = "Devotion Aura", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 183435, name = "Retribution Aura", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 96231, name = "Rebuke", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 853, name = "Hammer of Justice", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 20066, name = "Repentance", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 115750, name = "Blinding Light", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 6940, name = "Blessing of Sacrifice", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 1022, name = "Blessing of Protection", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 1044, name = "Blessing of Freedom", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 633, name = "Lay on Hands", providers = { { class = "PALADIN" } } },
  { category = "Paladin", spellID = 31821, name = "Aura Mastery", providers = { { class = "PALADIN", specs = Specs(65) } } },

  { category = "Hunter", spellID = 264667, name = "Primal Rage", providers = { { class = "HUNTER" } } },
  { category = "Hunter", spellID = 147362, name = "Counter Shot", providers = { { class = "HUNTER" } } },
  { category = "Hunter", spellID = 187707, name = "Muzzle", providers = { { class = "HUNTER", specs = Specs(255) } } },
  { category = "Hunter", spellID = 187650, name = "Freezing Trap", providers = { { class = "HUNTER" } } },
  { category = "Hunter", spellID = 187698, name = "Tar Trap", providers = { { class = "HUNTER" } } },
  { category = "Hunter", spellID = 19577, name = "Intimidation", providers = { { class = "HUNTER" } } },
  { category = "Hunter", spellID = 109248, name = "Binding Shot", providers = { { class = "HUNTER" } } },
  { category = "Hunter", spellID = 34477, name = "Misdirection", providers = { { class = "HUNTER" } } },

  { category = "Priest", spellID = 21562, name = "Power Word: Fortitude", providers = { { class = "PRIEST" } } },
  { category = "Priest", spellID = 15487, name = "Silence", providers = { { class = "PRIEST", specs = Specs(258) } } },
  { category = "Priest", spellID = 8122, name = "Psychic Scream", providers = { { class = "PRIEST" } } },
  { category = "Priest", spellID = 605, name = "Mind Control", providers = { { class = "PRIEST" } } },
  { category = "Priest", spellID = 9484, name = "Shackle Undead", providers = { { class = "PRIEST" } } },
  { category = "Priest", spellID = 64044, name = "Psychic Horror", providers = { { class = "PRIEST" } } },
  { category = "Priest", spellID = 10060, name = "Power Infusion", providers = { { class = "PRIEST" } } },
  { category = "Priest", spellID = 33206, name = "Pain Suppression", providers = { { class = "PRIEST", specs = Specs(256) } } },
  { category = "Priest", spellID = 47788, name = "Guardian Spirit", providers = { { class = "PRIEST", specs = Specs(257) } } },
  { category = "Priest", spellID = 73325, name = "Leap of Faith", providers = { { class = "PRIEST" } } },

  { category = "Rogue", spellID = 1766, name = "Kick", providers = { { class = "ROGUE" } } },
  { category = "Rogue", spellID = 6770, name = "Sap", providers = { { class = "ROGUE" } } },
  { category = "Rogue", spellID = 2094, name = "Blind", providers = { { class = "ROGUE" } } },
  { category = "Rogue", spellID = 1833, name = "Cheap Shot", providers = { { class = "ROGUE" } } },
  { category = "Rogue", spellID = 408, name = "Kidney Shot", providers = { { class = "ROGUE" } } },
  { category = "Rogue", spellID = 1776, name = "Gouge", providers = { { class = "ROGUE" } } },
  { category = "Rogue", spellID = 57934, name = "Tricks of the Trade", providers = { { class = "ROGUE" } } },

  { category = "Shaman", spellID = 2825, name = "Bloodlust", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 32182, name = "Heroism", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 204330, name = "Skyfury", providers = { { class = "SHAMAN", specs = Specs(263) } } },
  { category = "Shaman", spellID = 57994, name = "Wind Shear", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 51514, name = "Hex", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 192058, name = "Capacitor Totem", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 51485, name = "Earthgrab Totem", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 98008, name = "Spirit Link Totem", providers = { { class = "SHAMAN", specs = Specs(264) } } },
  { category = "Shaman", spellID = 207399, name = "Ancestral Protection Totem", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 192077, name = "Wind Rush Totem", providers = { { class = "SHAMAN" } } },
  { category = "Shaman", spellID = 8143, name = "Tremor Totem", providers = { { class = "SHAMAN" } } },

  { category = "Warlock", spellID = 6201, name = "Healthstone", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 19647, name = "Spell Lock", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 5782, name = "Fear", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 710, name = "Banish", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 30283, name = "Shadowfury", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 6789, name = "Mortal Coil", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 20707, name = "Soulstone", providers = { { class = "WARLOCK" } } },
  { category = "Warlock", spellID = 111771, name = "Demonic Gateway", providers = { { class = "WARLOCK" } } },

  { category = "Warrior", spellID = 6673, name = "Battle Shout", providers = { { class = "WARRIOR" } } },
  { category = "Warrior", spellID = 6552, name = "Pummel", providers = { { class = "WARRIOR" } } },
  { category = "Warrior", spellID = 107570, name = "Storm Bolt", providers = { { class = "WARRIOR" } } },
  { category = "Warrior", spellID = 46968, name = "Shockwave", providers = { { class = "WARRIOR" } } },
  { category = "Warrior", spellID = 5246, name = "Intimidating Shout", providers = { { class = "WARRIOR" } } },
  { category = "Warrior", spellID = 97462, name = "Rallying Cry", providers = { { class = "WARRIOR" } } },
  { category = "Warrior", spellID = 3411, name = "Intervene", providers = { { class = "WARRIOR" } } },

  { category = "Demon Hunter", spellID = 1490, name = "Chaos Brand", providers = { { class = "DEMONHUNTER" } } },
  { category = "Demon Hunter", spellID = 183752, name = "Disrupt", providers = { { class = "DEMONHUNTER" } } },
  { category = "Demon Hunter", spellID = 179057, name = "Chaos Nova", providers = { { class = "DEMONHUNTER" } } },
  { category = "Demon Hunter", spellID = 217832, name = "Imprison", providers = { { class = "DEMONHUNTER" } } },
  { category = "Demon Hunter", spellID = 207684, name = "Sigil of Misery", providers = { { class = "DEMONHUNTER" } } },
  { category = "Demon Hunter", spellID = 202137, name = "Sigil of Silence", providers = { { class = "DEMONHUNTER" } } },
  { category = "Demon Hunter", spellID = 196718, name = "Darkness", providers = { { class = "DEMONHUNTER" } } },
}

local function GetUnitSpecID(unit)
  if UnitIsUnit(unit, "player") then
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex and specIndex > 0 then
      local specID = GetSpecializationInfo(specIndex)
      return tonumber(specID) or 0
    end
  end
  if GetInspectSpecialization and CanInspect and CanInspect(unit) then
    local specID = GetInspectSpecialization(unit)
    return tonumber(specID) or 0
  end
  return 0
end

local function ProviderMatches(member, provider)
  if not member or not provider then
    return false
  end
  if tostring(member.classFile) ~= tostring(provider.class) then
    return false
  end
  if type(provider.specs) ~= "table" then
    return true
  end
  if not member.specID or member.specID <= 0 then
    return false
  end
  for _, sid in ipairs(provider.specs) do
    if member.specID == sid then
      return true
    end
  end
  return false
end

local function BuildRosterMembers()
  local roster = {}
  local units = BuildGroupUnits()
  for _, unit in ipairs(units) do
    if UnitExists(unit) then
      local name = UnitName(unit) or unit
      local className, classFile = UnitClass(unit)
      roster[#roster + 1] = {
        unit = unit,
        name = name,
        className = className or classFile or "",
        classFile = tostring(classFile or ""),
        specID = GetUnitSpecID(unit),
      }
    end
  end
  return roster
end

local function BuildProviderText(providers)
  local out = {}
  for _, p in ipairs(providers or {}) do
    local classLabel = CLASS_LABELS[p.class] or p.class
    if type(p.specs) == "table" and #p.specs > 0 then
      local specNames = {}
      for _, sid in ipairs(p.specs) do
        specNames[#specNames + 1] = SPEC_LABELS[sid] or tostring(sid)
      end
      out[#out + 1] = classLabel .. " (" .. table.concat(specNames, "/") .. ")"
    else
      out[#out + 1] = classLabel
    end
  end
  return table.concat(out, ", ")
end

local function GetUtilityIcon(spellID)
  if C_Spell and C_Spell.GetSpellTexture then
    local tex = C_Spell.GetSpellTexture(spellID)
    if tex then
      return tex
    end
  end
  local _, _, icon = GetSpellInfo(spellID)
  return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local UTILITY_TYPE_ORDER = {
  "Party Buffs",
  "External CDs",
  "Battle Res",
  "Bloodlust/Heroism",
  "Interrupts",
  "Stuns",
  "Slows",
  "Incapacitate",
  "Other",
}

local UTILITY_CRITICAL_TYPES = {
  "Interrupts",
  "Battle Res",
  "Bloodlust/Heroism",
}

local UTILITY_CRITICAL_LOOKUP = {}
for _, typeName in ipairs(UTILITY_CRITICAL_TYPES) do
  UTILITY_CRITICAL_LOOKUP[typeName] = true
end

local UTILITY_TYPE_BY_SPELL = {
  [1126] = "Party Buffs", [381748] = "Party Buffs", [395152] = "Party Buffs",
  [1459] = "Party Buffs", [113746] = "Party Buffs", [465] = "Party Buffs",
  [183435] = "Party Buffs", [21562] = "Party Buffs", [204330] = "Party Buffs",
  [6201] = "Party Buffs", [6673] = "Party Buffs", [1490] = "Party Buffs",

  [33206] = "External CDs", [47788] = "External CDs", [10060] = "External CDs", [73325] = "External CDs",
  [102342] = "External CDs", [29166] = "External CDs", [77761] = "External CDs", [357170] = "External CDs",
  [374227] = "External CDs", [363534] = "External CDs", [116849] = "External CDs", [115310] = "External CDs",
  [116841] = "External CDs", [6940] = "External CDs", [1022] = "External CDs", [1044] = "External CDs",
  [633] = "External CDs", [31821] = "External CDs", [34477] = "External CDs", [57934] = "External CDs",
  [98008] = "External CDs", [207399] = "External CDs", [192077] = "External CDs", [8143] = "External CDs",
  [111771] = "External CDs", [97462] = "External CDs", [3411] = "External CDs", [196718] = "External CDs",
  [51052] = "External CDs", [370665] = "External CDs", [414660] = "External CDs",

  [61999] = "Battle Res", [20484] = "Battle Res", [20707] = "Battle Res",
  [2825] = "Bloodlust/Heroism", [32182] = "Bloodlust/Heroism", [264667] = "Bloodlust/Heroism", [80353] = "Bloodlust/Heroism",

  [47528] = "Interrupts", [106839] = "Interrupts", [78675] = "Interrupts", [351338] = "Interrupts",
  [2139] = "Interrupts", [116705] = "Interrupts", [96231] = "Interrupts", [147362] = "Interrupts",
  [187707] = "Interrupts", [15487] = "Interrupts", [1766] = "Interrupts", [57994] = "Interrupts",
  [19647] = "Interrupts", [6552] = "Interrupts", [183752] = "Interrupts",

  [221562] = "Stuns", [119381] = "Stuns", [853] = "Stuns", [115750] = "Stuns", [19577] = "Stuns",
  [64044] = "Stuns", [1833] = "Stuns", [408] = "Stuns", [192058] = "Stuns", [30283] = "Stuns",
  [107570] = "Stuns", [46968] = "Stuns", [179057] = "Stuns",

  [45524] = "Slows", [187698] = "Slows", [51485] = "Slows", [102793] = "Slows",

  [207167] = "Incapacitate", [339] = "Incapacitate", [102359] = "Incapacitate", [2637] = "Incapacitate",
  [33786] = "Incapacitate", [360806] = "Incapacitate", [358385] = "Incapacitate", [357214] = "Incapacitate",
  [368970] = "Incapacitate", [118] = "Incapacitate", [31661] = "Incapacitate", [122] = "Incapacitate",
  [113724] = "Incapacitate", [115078] = "Incapacitate", [116844] = "Incapacitate", [20066] = "Incapacitate",
  [187650] = "Incapacitate", [8122] = "Incapacitate", [605] = "Incapacitate", [9484] = "Incapacitate",
  [6770] = "Incapacitate", [2094] = "Incapacitate", [1776] = "Incapacitate", [51514] = "Incapacitate",
  [5782] = "Incapacitate", [710] = "Incapacitate", [6789] = "Incapacitate", [5246] = "Incapacitate",
  [217832] = "Incapacitate", [207684] = "Incapacitate", [202137] = "Incapacitate",
}

local function ResolveUtilityType(entry)
  local spellID = tonumber(entry.spellID) or 0
  local t = UTILITY_TYPE_BY_SPELL[spellID]
  if t then
    return t
  end
  return "Other"
end

local function BuildUtilityState()
  local roster = BuildRosterMembers()
  local byType = {}
  local summaryByType = {}

  for _, typeName in ipairs(UTILITY_TYPE_ORDER) do
    summaryByType[typeName] = {
      typeKey = typeName,
      presentCount = 0,
      totalCount = 0,
    }
  end

  for _, entry in ipairs(UTILITY_ENTRIES) do
    local typeKey = ResolveUtilityType(entry)
    byType[typeKey] = byType[typeKey] or {
      classKey = typeKey,
      entries = {},
    }
    summaryByType[typeKey] = summaryByType[typeKey] or {
      typeKey = typeKey,
      presentCount = 0,
      totalCount = 0,
    }

    local contributors = {}
    for _, m in ipairs(roster) do
      for _, provider in ipairs(entry.providers or {}) do
        if ProviderMatches(m, provider) then
          local specLabel = (m.specID and m.specID > 0 and SPEC_LABELS[m.specID]) and (" - " .. SPEC_LABELS[m.specID]) or ""
          contributors[#contributors + 1] = tostring(m.name) .. " (" .. tostring(m.className) .. specLabel .. ")"
          break
        end
      end
    end

    local present = (#contributors > 0)
    summaryByType[typeKey].totalCount = (summaryByType[typeKey].totalCount or 0) + 1
    if present then
      summaryByType[typeKey].presentCount = (summaryByType[typeKey].presentCount or 0) + 1
    end

    byType[typeKey].entries[#byType[typeKey].entries + 1] = {
      name = entry.name,
      category = entry.category,
      spellID = entry.spellID,
      icon = GetUtilityIcon(entry.spellID),
      providersText = BuildProviderText(entry.providers),
      present = present,
      contributors = contributors,
    }
  end

  for _, group in pairs(byType) do
    table.sort(group.entries, function(a, b)
      if a.present ~= b.present then
        return a.present
      end
      return tostring(a.name or "") < tostring(b.name or "")
    end)
  end

  local groups = {}
  for _, typeName in ipairs(UTILITY_TYPE_ORDER) do
    if byType[typeName] then
      groups[#groups + 1] = byType[typeName]
      byType[typeName] = nil
    end
  end
  for _, group in pairs(byType) do
    groups[#groups + 1] = group
  end

  local summary = {}
  local seen = {}
  for _, typeName in ipairs(UTILITY_TYPE_ORDER) do
    summary[#summary + 1] = summaryByType[typeName] or {
      typeKey = typeName,
      presentCount = 0,
      totalCount = 0,
    }
    seen[typeName] = true
  end
  for typeName, item in pairs(summaryByType) do
    if not seen[typeName] then
      summary[#summary + 1] = item
    end
  end

  return {
    groups = groups,
    summary = summary,
    summaryByType = summaryByType,
  }
end

function UI.RefreshUtilityTab()
  if not addon.utilityClassCards then
    return
  end

  local state = BuildUtilityState()
  local groups = state.groups or {}
  local summaryByType = state.summaryByType or {}
  local layout = addon.utilityLayout or {}
  local columns = layout.columns or 2
  local gapX = layout.gapX or 6
  local gapY = layout.gapY or 6
  local cardW = layout.cardW or 286
  local iconSize = layout.iconSize or 28
  local iconGap = layout.iconGap or 4
  local iconsPerRow = layout.iconsPerRow or 8
  local cardTop = layout.cardTop or 0

  if addon.utilitySummaryCriticalRows then
    for _, row in ipairs(addon.utilitySummaryCriticalRows) do
      local typeKey = row.typeKey
      local item = summaryByType[typeKey] or { presentCount = 0 }
      local count = tonumber(item.presentCount) or 0
      row:SetText(string.format("%s: %d", tostring(typeKey), count))
      if count > 0 then
        row:SetTextColor(0.95, 0.86, 0.38)
      else
        row:SetTextColor(1.0, 0.55, 0.55)
      end
    end
  end

  if addon.utilitySummaryRows then
    for _, row in ipairs(addon.utilitySummaryRows) do
      local typeKey = row.typeKey
      local item = summaryByType[typeKey] or { presentCount = 0 }
      local count = tonumber(item.presentCount) or 0
      row:SetText(string.format("%s: %d", tostring(typeKey), count))
      if count > 0 then
        row:SetTextColor(0.9, 0.9, 0.9)
      else
        row:SetTextColor(1.0, 0.55, 0.55)
      end
    end
  end

  local colX = {}
  for c = 1, columns do
    colX[c] = (c - 1) * (cardW + gapX)
  end
  local colY = {}
  for c = 1, columns do
    colY[c] = cardTop
  end

  local function PickColumn()
    local best = 1
    for c = 2, columns do
      if colY[c] < colY[best] then
        best = c
      end
    end
    return best
  end

  local maxCards = #addon.utilityClassCards
  for i = 1, maxCards do
    local card = addon.utilityClassCards[i]
    local group = groups[i]
    if not group then
      card:Hide()
    else
      card:Show()
      local s = summaryByType[group.classKey] or {}
      local presentCount = tonumber(s.presentCount) or 0
      local totalCount = tonumber(s.totalCount) or #group.entries
      card.title:SetText(string.format("%s (%d/%d)", tostring(group.classKey), presentCount, totalCount))

      local totalEntries = #group.entries
      local maxIcons = #card.icons
      local visibleCount = math.min(totalEntries, maxIcons)
      local rowsNeeded = math.max(1, math.ceil(visibleCount / iconsPerRow))
      local cardH = 36 + (rowsNeeded * (iconSize + iconGap)) + 10

      local col = PickColumn()
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", card:GetParent(), "TOPLEFT", colX[col], -colY[col])
      card:SetHeight(cardH)
      colY[col] = colY[col] + cardH + gapY

      for idx = 1, maxIcons do
        local iconButton = card.icons[idx]
        local entry = group.entries[idx]
        if entry then
          iconButton:Show()
          iconButton.icon:SetTexture(entry.icon)
          iconButton.icon:SetDesaturated(not entry.present)
          iconButton.icon:SetVertexColor(1, 1, 1, entry.present and 1 or 0.30)
          iconButton.entry = entry
        else
          iconButton.entry = nil
          iconButton:Hide()
        end
      end
    end
  end
end

function UI.RefreshMythicTab()
  if addon.mythicSummary then
    addon.mythicSummary:SetText(GetMythicSummary())
  end

  if addon.notesListText then
    local keys = NotesStore.Keys()
    addon.notesListText:SetText((#keys > 0) and table.concat(keys, "\n") or "No notes yet")
  end
end

local function SelectTab(name)
  addon.activeTab = name

  if addon.lfgTab then
    addon.lfgTab:SetShown(name == "lfg")
  end
  if addon.mythicTab then
    addon.mythicTab:SetShown(name == "mythic")
  end
  if addon.utilityTab then
    addon.utilityTab:SetShown(name == "utility")
  end

  if name == "lfg" then
    SafeCall(UI.RefreshApplicants)
  elseif name == "mythic" then
    SafeCall(UI.RefreshMythicTab)
  else
    SafeCall(UI.RefreshUtilityTab)
  end
end

local function BuildLFGTab(parent)
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()

  local sectionWidth = PANEL_WIDTH - 28
  local rowLayout = {
    left = 10,
    top = -42,
    width = sectionWidth - 20,
    height = 30,
    gap = 4,
  }

  local topBar = CreateFrame("Frame", nil, tab)
  topBar:SetPoint("TOPLEFT", tab, "TOPLEFT", 14, -58)
  topBar:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -14, -58)
  topBar:SetHeight(30)
  topBar:SetFrameLevel(tab:GetFrameLevel() + 3)

  tab.sortInfo = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  tab.sortInfo:SetPoint("LEFT", topBar, "LEFT", 10, 0)
  tab.sortInfo:SetWidth(175)
  tab.sortInfo:SetJustifyH("LEFT")
  tab.sortInfo:SetText("Sort: Name / Fit / Rating / iLvl")
  tab.sortInfo:SetTextColor(0.94, 0.94, 0.94)
  tab.sortInfo:Hide()

  local deserterStatus = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  deserterStatus:SetPoint("RIGHT", topBar, "RIGHT", -14, 0)
  deserterStatus:SetWidth(148)
  deserterStatus:SetJustifyH("RIGHT")
  deserterStatus:SetText("Your deserter: Clear")
  deserterStatus:SetTextColor(0.45, 0.95, 0.45)
  addon.deserterStatusText = deserterStatus
  deserterStatus:Hide()

  local applicantDeserter = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  applicantDeserter:SetPoint("RIGHT", deserterStatus, "LEFT", -10, 0)
  applicantDeserter:SetWidth(158)
  applicantDeserter:SetJustifyH("RIGHT")
  applicantDeserter:SetText("Applicant deserter: 0")
  applicantDeserter:SetTextColor(0.45, 0.95, 0.45)
  addon.applicantDeserterText = applicantDeserter
  applicantDeserter:Hide()

  tab.applicantCount = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  tab.applicantCount:SetPoint("RIGHT", applicantDeserter, "LEFT", -10, 0)
  tab.applicantCount:SetText("Applicants: 0")
  tab.applicantCount:SetTextColor(0.98, 0.86, 0.4)
  addon.applicantCountText = tab.applicantCount

  local listingContext = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  listingContext:SetPoint("RIGHT", tab.applicantCount, "LEFT", -18, 0)
  listingContext:SetWidth(260)
  listingContext:SetJustifyH("RIGHT")
  listingContext:SetText("Listing: Not currently listed")
  listingContext:SetTextColor(0.8, 0.9, 1)
  addon.listingContextText = listingContext

  local listPanel = CreateFrame("Frame", nil, tab, "BackdropTemplate")
  listPanel:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -6)
  listPanel:SetPoint("TOPRIGHT", topBar, "BOTTOMRIGHT", 0, -6)
  listPanel:SetHeight(368)
  listPanel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  listPanel:SetBackdropColor(0.02, 0.02, 0.02, 0.55)
  listPanel:SetBackdropBorderColor(0.5, 0.38, 0.18, 0.8)

  local headerStrip = CreateFrame("Frame", nil, listPanel, "BackdropTemplate")
  headerStrip:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 8, -8)
  headerStrip:SetPoint("TOPRIGHT", listPanel, "TOPRIGHT", -8, -8)
  headerStrip:SetHeight(26)
  headerStrip:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  headerStrip:SetBackdropColor(0.2, 0.1, 0.05, 0.8)
  headerStrip:SetBackdropBorderColor(0.5, 0.38, 0.18, 0.85)

  MakeHeaderButton(headerStrip, "Name", 220, 14, -1, "name")
  MakeHeaderButton(headerStrip, "Fit", 86, 250, -1, "score")
  MakeHeaderButton(headerStrip, "Rating", 64, 338, -1, "rating")
  MakeHeaderButton(headerStrip, "Best", 44, 404, -1, nil)
  MakeHeaderButton(headerStrip, "iLvl", 52, 452, -1, "ilvl")
  MakeHeaderButton(headerStrip, "Role", 104, 508, -1, nil)
  MakeHeaderButton(headerStrip, "Actions", 116, 714, -1, nil)

  local scrollContainer = CreateFrame("Frame", nil, listPanel)
  scrollContainer:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 10, -38)
  scrollContainer:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -26, 8)
  scrollContainer:SetClipsChildren(true)

  local scrollFrame = CreateFrame("ScrollFrame", nil, listPanel, "FauxScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", scrollContainer, "TOPLEFT", 0, 0)
  scrollFrame:SetPoint("BOTTOMRIGHT", scrollContainer, "BOTTOMRIGHT", 0, 0)
  scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, rowLayout.height + rowLayout.gap, function()
      UI.RefreshApplicants()
    end)
  end)
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    if not self.ScrollBar then
      return
    end
    local step = addon.rowStep or 40
    self.ScrollBar:SetValue(self.ScrollBar:GetValue() - (delta * step))
  end)
  addon.applicantScrollFrame = scrollFrame
  addon.rowStep = rowLayout.height + rowLayout.gap

  rowLayout.left = 0
  rowLayout.top = 0
  rowLayout.width = 834

  addon.rows = {}
  for i = 1, 9 do
    addon.rows[i] = CreateDataRow(scrollContainer, i, rowLayout)
  end

  local rulesPanel = CreateFrame("Frame", nil, tab, "BackdropTemplate")
  rulesPanel:SetPoint("TOPLEFT", listPanel, "BOTTOMLEFT", 0, -10)
  rulesPanel:SetPoint("TOPRIGHT", listPanel, "BOTTOMRIGHT", 0, -10)
  rulesPanel:SetHeight(192)
  rulesPanel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  rulesPanel:SetBackdropColor(0.02, 0.02, 0.02, 0.55)
  rulesPanel:SetBackdropBorderColor(0.5, 0.38, 0.18, 0.8)

  local scoringPane = CreateFrame("Frame", nil, rulesPanel)
  scoringPane:SetPoint("TOPLEFT", rulesPanel, "TOPLEFT", 10, -10)
  scoringPane:SetPoint("BOTTOMRIGHT", rulesPanel, "BOTTOMRIGHT", -10, 8)

  local function AttachTooltip(widget, title, body)
    if not widget then
      return
    end
    widget:EnableMouse(true)
    widget:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(title or "QueueUp")
      if body and body ~= "" then
        GameTooltip:AddLine(body, 1, 1, 1, true)
      end
      GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
      GameTooltip_Hide()
    end)
  end

  local rulesHelp = scoringPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rulesHelp:SetPoint("TOPLEFT", scoringPane, "TOPLEFT", 4, -2)
  rulesHelp:SetWidth(800)
  rulesHelp:SetJustifyH("LEFT")
  rulesHelp:SetText("How applicants are scored and sorted. Enable the checks you care about, then set role and minimum thresholds.")
  rulesHelp:SetTextColor(0.78, 0.78, 0.78)

  local ratingLabel = scoringPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ratingLabel:SetPoint("TOPLEFT", scoringPane, "TOPLEFT", 4, -26)
  ratingLabel:SetText("Min rating")

  local ratingBox = CreateFrame("EditBox", nil, scoringPane, "InputBoxTemplate")
  ratingBox:SetSize(56, 22)
  ratingBox:SetPoint("LEFT", ratingLabel, "RIGHT", 8, 0)
  ratingBox:SetAutoFocus(false)
  ratingBox:SetNumeric(true)
  ratingBox:SetNumber(DB.rules.minRating)
  ratingBox:SetScript("OnEnterPressed", function(self)
    DB.rules.minRating = self:GetNumber() or DB.rules.minRating
    self:ClearFocus()
    UI.RefreshApplicants()
  end)
  AttachTooltip(ratingBox, "Minimum M+ Rating", "Applicants at or above this value get the minimum-rating bonus.")

  local ilvlLabel = scoringPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ilvlLabel:SetPoint("LEFT", ratingBox, "RIGHT", 12, 0)
  ilvlLabel:SetText("Min ilvl")

  local ilvlBox = CreateFrame("EditBox", nil, scoringPane, "InputBoxTemplate")
  ilvlBox:SetSize(56, 22)
  ilvlBox:SetPoint("LEFT", ilvlLabel, "RIGHT", 8, 0)
  ilvlBox:SetAutoFocus(false)
  ilvlBox:SetNumeric(true)
  ilvlBox:SetNumber(DB.rules.minIlvl)
  ilvlBox:SetScript("OnEnterPressed", function(self)
    DB.rules.minIlvl = self:GetNumber() or DB.rules.minIlvl
    self:ClearFocus()
    UI.RefreshApplicants()
  end)
  AttachTooltip(ilvlBox, "Minimum Item Level", "Applicants at or above this value get the item-level bonus.")

  local function AttachCheckLabel(parentFrame, check, text)
    local label = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 1)
    label:SetText(text)
    return label
  end

  local roleCheck = CreateFrame("CheckButton", nil, scoringPane, "UICheckButtonTemplate")
  roleCheck:SetPoint("TOPLEFT", scoringPane, "TOPLEFT", 4, -54)
  AttachCheckLabel(scoringPane, roleCheck, "Include role match in score")
  roleCheck:SetChecked(DB.rules.enableFlags.useRole)
  roleCheck:SetScript("OnClick", function(self)
    DB.rules.enableFlags.useRole = self:GetChecked() and true or false
    UI.RefreshApplicants()
  end)
  AttachTooltip(roleCheck, "Use Role Match", "When enabled, needed role match contributes to fit score.")

  local ratingCheck = CreateFrame("CheckButton", nil, scoringPane, "UICheckButtonTemplate")
  ratingCheck:SetPoint("LEFT", roleCheck, "RIGHT", 150, 0)
  AttachCheckLabel(scoringPane, ratingCheck, "Include rating in score")
  ratingCheck:SetChecked(DB.rules.enableFlags.useRating)
  ratingCheck:SetScript("OnClick", function(self)
    DB.rules.enableFlags.useRating = self:GetChecked() and true or false
    UI.RefreshApplicants()
  end)
  AttachTooltip(ratingCheck, "Use Rating", "When enabled, rating contributes to score.")

  local ilvlCheck = CreateFrame("CheckButton", nil, scoringPane, "UICheckButtonTemplate")
  ilvlCheck:SetPoint("LEFT", ratingCheck, "RIGHT", 150, 0)
  AttachCheckLabel(scoringPane, ilvlCheck, "Include ilvl in score")
  ilvlCheck:SetChecked(DB.rules.enableFlags.useIlvl)
  ilvlCheck:SetScript("OnClick", function(self)
    DB.rules.enableFlags.useIlvl = self:GetChecked() and true or false
    UI.RefreshApplicants()
  end)
  AttachTooltip(ilvlCheck, "Use Item Level", "When enabled, item level contributes to score.")

  local needRolesLabel = scoringPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  needRolesLabel:SetPoint("TOPLEFT", scoringPane, "TOPLEFT", 4, -96)
  needRolesLabel:SetText("Needed roles:")

  local needTankCheck = CreateFrame("CheckButton", nil, scoringPane, "UICheckButtonTemplate")
  needTankCheck:SetPoint("TOPLEFT", needRolesLabel, "BOTTOMLEFT", 0, -2)
  AttachCheckLabel(scoringPane, needTankCheck, "Tank")
  needTankCheck:SetChecked((DB.rules.neededRoles and DB.rules.neededRoles.TANK) and true or false)
  needTankCheck:SetScript("OnClick", function(self)
    DB.rules.neededRoles = DB.rules.neededRoles or {}
    DB.rules.neededRoles.TANK = self:GetChecked() and true or false
    UI.RefreshApplicants()
  end)
  AttachTooltip(needTankCheck, "Need Tank", "Applicants offering Tank role are considered role matches.")

  local needHealerCheck = CreateFrame("CheckButton", nil, scoringPane, "UICheckButtonTemplate")
  needHealerCheck:SetPoint("LEFT", needTankCheck, "RIGHT", 100, 0)
  AttachCheckLabel(scoringPane, needHealerCheck, "Healer")
  needHealerCheck:SetChecked((DB.rules.neededRoles and DB.rules.neededRoles.HEALER) and true or false)
  needHealerCheck:SetScript("OnClick", function(self)
    DB.rules.neededRoles = DB.rules.neededRoles or {}
    DB.rules.neededRoles.HEALER = self:GetChecked() and true or false
    UI.RefreshApplicants()
  end)
  AttachTooltip(needHealerCheck, "Need Healer", "Applicants offering Healer role are considered role matches.")

  local needDamageCheck = CreateFrame("CheckButton", nil, scoringPane, "UICheckButtonTemplate")
  needDamageCheck:SetPoint("LEFT", needHealerCheck, "RIGHT", 100, 0)
  AttachCheckLabel(scoringPane, needDamageCheck, "Damage")
  needDamageCheck:SetChecked((DB.rules.neededRoles and DB.rules.neededRoles.DAMAGER) and true or false)
  needDamageCheck:SetScript("OnClick", function(self)
    DB.rules.neededRoles = DB.rules.neededRoles or {}
    DB.rules.neededRoles.DAMAGER = self:GetChecked() and true or false
    UI.RefreshApplicants()
  end)
  AttachTooltip(needDamageCheck, "Need Damage", "Applicants offering Damage role are considered role matches.")

  addon.lfgClassBox = nil
  addon.lfgClassLabel = nil
  addon.lfgWhisperBox = nil
  addon.lfgWhisperHelp = nil
  addon.lfgTab = tab
end

local function BuildMythicTab(parent)
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()

  local contentPanel = CreateFrame("Frame", nil, tab, "BackdropTemplate")
  contentPanel:SetPoint("TOPLEFT", tab, "TOPLEFT", 14, -54)
  contentPanel:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -14, 14)
  contentPanel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  contentPanel:SetBackdropColor(0.02, 0.02, 0.02, 0.55)
  contentPanel:SetBackdropBorderColor(0.5, 0.38, 0.18, 0.8)

  local summaryTitle = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  summaryTitle:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", 12, -14)
  summaryTitle:SetText("Current Context")
  summaryTitle:SetTextColor(0.96, 0.83, 0.34)

  local summary = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  summary:SetPoint("TOPLEFT", summaryTitle, "BOTTOMLEFT", 0, -8)
  summary:SetWidth(840)
  summary:SetJustifyH("LEFT")
  summary:SetJustifyV("TOP")
  summary:SetText("")
  addon.mythicSummary = summary

  local noteTitle = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  noteTitle:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", 12, -130)
  noteTitle:SetText("Per-player Notes")
  noteTitle:SetTextColor(0.96, 0.83, 0.34)

  local playerKeyBox = CreateFrame("EditBox", nil, tab, "InputBoxTemplate")
  playerKeyBox:SetSize(260, 22)
  playerKeyBox:SetPoint("TOPLEFT", noteTitle, "BOTTOMLEFT", 0, -8)
  playerKeyBox:SetAutoFocus(false)
  playerKeyBox:SetText("")

  local noteBox = CreateFrame("EditBox", nil, tab, "InputBoxTemplate")
  noteBox:SetSize(580, 22)
  noteBox:SetPoint("TOPLEFT", playerKeyBox, "BOTTOMLEFT", 0, -8)
  noteBox:SetAutoFocus(false)
  noteBox:SetText("")

  local loadBtn = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
  loadBtn:SetSize(52, 20)
  loadBtn:SetPoint("LEFT", playerKeyBox, "RIGHT", 8, 0)
  loadBtn:SetText("Load")
  loadBtn:SetScript("OnClick", function()
    local key = NormalizePlayerKey(playerKeyBox:GetText())
    local note = NotesStore.Get(key) or ""
    noteBox:SetText(note)
  end)

  local saveBtn = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
  saveBtn:SetSize(52, 20)
  saveBtn:SetPoint("LEFT", loadBtn, "RIGHT", 6, 0)
  saveBtn:SetText("Save")
  saveBtn:SetScript("OnClick", function()
    local key = NormalizePlayerKey(playerKeyBox:GetText())
    if key == "" then
      Print("Enter player-realm key first.")
      return
    end
    NotesStore.Set(key, noteBox:GetText())
    Print("Saved note for " .. key)
    UI.RefreshApplicants()
    UI.RefreshMythicTab()
  end)

  local delBtn = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
  delBtn:SetSize(60, 20)
  delBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
  delBtn:SetText("Delete")
  delBtn:SetScript("OnClick", function()
    local key = NormalizePlayerKey(playerKeyBox:GetText())
    if key == "" then
      return
    end
    NotesStore.Set(key, "")
    noteBox:SetText("")
    Print("Deleted note for " .. key)
    UI.RefreshApplicants()
    UI.RefreshMythicTab()
  end)

  local notesLabel = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  notesLabel:SetPoint("TOPLEFT", noteBox, "BOTTOMLEFT", 0, -12)
  notesLabel:SetText("Saved players")

  local notesList = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  notesList:SetPoint("TOPLEFT", notesLabel, "BOTTOMLEFT", 0, -6)
  notesList:SetWidth(840)
  notesList:SetJustifyH("LEFT")
  notesList:SetText("")
  addon.notesListText = notesList

  addon.mythicTab = tab
end

local function BuildUtilityTab(parent)
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()

  local contentPanel = CreateFrame("Frame", nil, tab, "BackdropTemplate")
  contentPanel:SetPoint("TOPLEFT", tab, "TOPLEFT", 14, -54)
  contentPanel:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -14, 14)
  contentPanel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  contentPanel:SetBackdropColor(0.02, 0.02, 0.02, 0.55)
  contentPanel:SetBackdropBorderColor(0.5, 0.38, 0.18, 0.8)

  local title = contentPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", 12, -14)
  title:SetText("Party Utility")
  title:SetTextColor(0.96, 0.83, 0.34)

  local subtitle = contentPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  subtitle:SetText("Left: coverage summary. Right: grouped utility icons. Dark icon = missing.")
  subtitle:SetTextColor(0.86, 0.86, 0.86)

  local split = CreateFrame("Frame", nil, contentPanel)
  split:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
  split:SetPoint("BOTTOMRIGHT", contentPanel, "BOTTOMRIGHT", -8, 8)

  local summaryWidth = 248
  local splitGap = 8

  local summaryPanel = CreateFrame("Frame", nil, split, "BackdropTemplate")
  summaryPanel:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 0)
  summaryPanel:SetPoint("BOTTOMLEFT", split, "BOTTOMLEFT", 0, 0)
  summaryPanel:SetWidth(summaryWidth)
  summaryPanel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  summaryPanel:SetBackdropColor(0.07, 0.07, 0.08, 0.82)
  summaryPanel:SetBackdropBorderColor(0.35, 0.28, 0.14, 0.72)

  local iconsGrid = CreateFrame("Frame", nil, split)
  iconsGrid:SetPoint("TOPLEFT", summaryPanel, "TOPRIGHT", splitGap, 0)
  iconsGrid:SetPoint("BOTTOMRIGHT", split, "BOTTOMRIGHT", 0, 0)

  local summaryTitle = summaryPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  summaryTitle:SetPoint("TOPLEFT", summaryPanel, "TOPLEFT", 10, -10)
  summaryTitle:SetText("Coverage Summary")
  summaryTitle:SetTextColor(0.96, 0.83, 0.34)

  local criticalTitle = summaryPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  criticalTitle:SetPoint("TOPLEFT", summaryTitle, "BOTTOMLEFT", 0, -12)
  criticalTitle:SetText("Critical Utility")
  criticalTitle:SetTextColor(0.96, 0.83, 0.34)

  addon.utilitySummaryCriticalRows = {}
  local previous = criticalTitle
  for _, typeName in ipairs(UTILITY_CRITICAL_TYPES) do
    local line = summaryPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
    line:SetWidth(summaryWidth - 20)
    line:SetJustifyH("LEFT")
    line:SetText(typeName .. ": 0")
    line.typeKey = typeName
    addon.utilitySummaryCriticalRows[#addon.utilitySummaryCriticalRows + 1] = line
    previous = line
  end

  local otherTitle = summaryPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  otherTitle:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -14)
  otherTitle:SetText("Other Coverage")
  otherTitle:SetTextColor(0.9, 0.9, 0.9)

  addon.utilitySummaryRows = {}
  previous = otherTitle
  for _, typeName in ipairs(UTILITY_TYPE_ORDER) do
    if not UTILITY_CRITICAL_LOOKUP[typeName] then
      local line = summaryPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
      line:SetWidth(summaryWidth - 20)
      line:SetJustifyH("LEFT")
      line:SetText(typeName .. ": 0")
      line.typeKey = typeName
      addon.utilitySummaryRows[#addon.utilitySummaryRows + 1] = line
      previous = line
    end
  end

  local columns = 2
  local rows = 5
  local cardW = 286
  local cardH = 110
  local gapX = 6
  local gapY = 6
  local iconsPerRow = 8
  local iconSize = 28
  local iconGap = 4

  addon.utilityLayout = {
    columns = columns,
    cardW = cardW,
    gapX = gapX,
    gapY = gapY,
    iconsPerRow = iconsPerRow,
    iconSize = iconSize,
    iconGap = iconGap,
    cardTop = 0,
  }

  addon.utilityClassCards = {}
  for rowIndex = 1, rows do
    for colIndex = 1, columns do
      local idx = ((rowIndex - 1) * columns) + colIndex
      local card = CreateFrame("Frame", nil, iconsGrid, "BackdropTemplate")
      card:SetSize(cardW, cardH)
      card:SetPoint("TOPLEFT", iconsGrid, "TOPLEFT", (colIndex - 1) * (cardW + gapX), -((rowIndex - 1) * (cardH + gapY)))
      card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
      })
      card:SetBackdropColor(0.07, 0.07, 0.08, 0.82)
      card:SetBackdropBorderColor(0.35, 0.28, 0.14, 0.72)

      card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -8)
      card.title:SetTextColor(0.96, 0.83, 0.34)
      card.title:SetJustifyH("LEFT")
      card.title:SetText("")

      card.icons = {}
      local iconStartX = 8
      local iconStartY = -34
      local iconRows = 6
      for ir = 1, iconRows do
        for ic = 1, iconsPerRow do
          local iconIndex = ((ir - 1) * iconsPerRow) + ic
          local btn = CreateFrame("Button", nil, card)
          btn:SetSize(iconSize, iconSize)
          btn:SetPoint("TOPLEFT", card, "TOPLEFT", iconStartX + ((ic - 1) * (iconSize + iconGap)), iconStartY - ((ir - 1) * (iconSize + iconGap)))

          btn.icon = btn:CreateTexture(nil, "ARTWORK")
          btn.icon:SetAllPoints()
          btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

          btn:SetScript("OnEnter", function(self)
            if not self.entry then
              return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.entry.name)
            GameTooltip:AddLine("Class: " .. tostring(self.entry.category or "Other"), 0.85, 0.85, 0.85)
            GameTooltip:AddLine("Class/Spec: " .. tostring(self.entry.providersText or "-"), 1, 1, 1, true)
            if self.entry.present then
              GameTooltip:AddLine("Present: " .. table.concat(self.entry.contributors or {}, ", "), 0.4, 0.95, 0.4, true)
            else
              GameTooltip:AddLine("Missing in current group", 1, 0.35, 0.35)
            end
            GameTooltip:Show()
          end)
          btn:SetScript("OnLeave", function(self)
            GameTooltip_Hide()
          end)

          card.icons[iconIndex] = btn
        end
      end

      addon.utilityClassCards[idx] = card
    end
  end

  addon.utilityTab = tab
end

local function EnsurePanel()
  if addon.panel then
    return addon.panel
  end

  local panel = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
  panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("DIALOG")
  panel:SetFrameLevel(200)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:Hide()

  panel.TitleText:SetText("QueueUp")
  panel.TitleText:SetTextColor(0.95, 0.82, 0.3)

  local tabLFG = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  tabLFG:SetSize(104, 22)
  tabLFG:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -28)
  tabLFG:SetText("LFG Tools")

  local tabUtility = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  tabUtility:SetSize(86, 22)
  tabUtility:SetPoint("LEFT", tabLFG, "RIGHT", 6, 0)
  tabUtility:SetText("Utility")

  SafeCall(BuildLFGTab, panel)
  SafeCall(BuildMythicTab, panel)
  SafeCall(BuildUtilityTab, panel)

  tabLFG:SetScript("OnClick", function()
    SelectTab("lfg")
  end)

  tabUtility:SetScript("OnClick", function()
    SelectTab("utility")
  end)

  panel:SetScript("OnShow", function()
    panel:Raise()
    SafeCall(UI.RefreshApplicants)
    SafeCall(UI.RefreshMythicTab)
    SafeCall(UI.RefreshUtilityTab)
  end)

  addon.panel = panel
  addon.tabLFG = tabLFG
  addon.tabUtility = tabUtility

  if addon.lfgTab then addon.lfgTab:Hide() end
  if addon.mythicTab then addon.mythicTab:Hide() end
  if addon.utilityTab then addon.utilityTab:Hide() end

  SafeCall(SelectTab, "lfg")

  return panel
end

local function TogglePanel()
  local panel = EnsurePanel()
  if not panel then
    Print("Panel failed to initialize.")
    return
  end
  panel:SetShown(not panel:IsShown())
  if panel:IsShown() then
    if addon.pveButton then
      addon.pveButton:Hide()
    end
    SafeCall(UI.RefreshApplicants)
    SafeCall(UI.RefreshMythicTab)
  else
    if addon.pveButton then
      addon.pveButton:Show()
    end
  end
end

local function CreateLauncherButton(parent, name, tooltipText)
  local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  button:SetSize(96, 24)
  button:RegisterForClicks("LeftButtonUp")
  button:SetFrameStrata("TOOLTIP")
  button:SetFrameLevel(100)
  button:SetClampedToScreen(true)
  button:SetIgnoreParentAlpha(true)
  button:SetIgnoreParentScale(true)
  button:SetText("QueueUp")

  button:SetScript("OnClick", TogglePanel)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("QueueUp")
    GameTooltip:AddLine(tooltipText, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)

  return button
end

local function FindBestHostFrame()
  local candidateNames = {
    "PVEFrame",
    "LFGListFrame",
    "LFGParentFrame",
    "ChallengesFrame",
    "WeeklyRewardsFrame",
  }

  for _, name in ipairs(candidateNames) do
    local frameObj = _G[name]
    if frameObj and frameObj.GetObjectType and frameObj:GetObjectType() == "Frame" then
      if frameObj.IsVisible and frameObj:IsVisible() then
        return frameObj, true
      end
    end
  end

  return nil, false
end

local function EnsureButton()
  if addon.pveButton then
    return addon.pveButton
  end

  addon.pveButton = CreateLauncherButton(UIParent, "QueueUpPVEButton", "Open QueueUp panel")
  addon.pveButton:ClearAllPoints()
  addon.pveButton:SetPoint("TOP", UIParent, "TOP", 0, -120)
  addon.pveButton:Hide()
  return addon.pveButton
end

local function ReanchorButton()
  local button = EnsureButton()
  if addon.panel and addon.panel:IsShown() then
    button:Hide()
    return false
  end

  local hostFrame, hostVisible = FindBestHostFrame()

  if hostFrame and hostVisible then
    button:ClearAllPoints()
    if hostFrame.CloseButton then
      button:SetPoint("RIGHT", hostFrame.CloseButton, "LEFT", -4, 0)
    else
      button:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", -34, -24)
    end
    button:Show()
    return true
  end

  button:Hide()
  return false
end

local function EnsureEmbeddedButtons()
  EnsureButton()
  ReanchorButton()
end

local function TryInstallFrameHooks()
  local candidateNames = {
    "PVEFrame",
    "LFGListFrame",
    "LFGParentFrame",
    "ChallengesFrame",
    "WeeklyRewardsFrame",
  }

  for _, name in ipairs(candidateNames) do
    local frameObj = _G[name]
    if frameObj and frameObj.GetObjectType and frameObj:GetObjectType() == "Frame" and not hookedFrames[name] then
      frameObj:HookScript("OnShow", EnsureEmbeddedButtons)
      frameObj:HookScript("OnHide", EnsureEmbeddedButtons)
      hookedFrames[name] = true
    end
  end
end

local function StartApplicantRefreshTicker()
  if applicantTicker or not C_Timer or not C_Timer.NewTicker then
    return
  end

  applicantTicker = C_Timer.NewTicker(1, function()
    if addon.panel and addon.panel:IsShown() and addon.activeTab == "lfg" then
      UI.RefreshApplicants()
    end
  end)
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
frame:RegisterEvent("LFG_LIST_APPLICANT_UPDATED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("UNIT_AURA")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    DB = EnsureDB()

    if DB.firstRun then
      Print("installed. Use the QueueUp icon in Dungeons & Raids.")
      DB.firstRun = false
    end

    EnsurePanel()
    EnsureEmbeddedButtons()
    TryInstallFrameHooks()
    StartApplicantRefreshTicker()

    if not reanchorTicker and C_Timer and C_Timer.NewTicker then
      reanchorTicker = C_Timer.NewTicker(2, function()
        TryInstallFrameHooks()
        EnsureEmbeddedButtons()
      end)
    end
    return
  end

  if event == "ADDON_LOADED" and type(arg1) == "string" and arg1:find("^Blizzard_") then
    TryInstallFrameHooks()
    EnsureEmbeddedButtons()
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    TryInstallFrameHooks()
    EnsureEmbeddedButtons()
    UI.RefreshApplicants()
    UI.RefreshMythicTab()
    UI.RefreshUtilityTab()
    return
  end

  if event == "UNIT_AURA" and arg1 == "player" then
    if addon.panel and addon.panel:IsShown() and addon.activeTab == "lfg" then
      UI.RefreshApplicants()
    end
    return
  end

  if event == "LFG_LIST_APPLICANT_LIST_UPDATED" or event == "LFG_LIST_APPLICANT_UPDATED" or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
    UI.RefreshApplicants()
    UI.RefreshMythicTab()
    UI.RefreshUtilityTab()
    return
  end
end)

SLASH_QUEUEUP1 = "/queueup"
SLASH_QUEUEUP2 = "/gu"

SlashCmdList.QUEUEUP = function(msg)
  local command = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  if command == "" then
    TogglePanel()
    return
  end

  if command == "help" then
    Print("Commands:")
    Print("  /queueup         - toggle panel")
    Print("  /queueup help    - show this help")
    Print("  /queueup reset   - reset saved variables")
    Print("Rules are in LFG tab. Notes are in Mythic+ tab. Utility is in Utility tab.")
    return
  end

  if command == "reset" then
    QueueUpDB = CopyTable(DEFAULTS)
    DB = QueueUpDB
    Print("settings reset.")
    UI.RefreshApplicants()
    UI.RefreshMythicTab()
    return
  end

  Print("Unknown command: " .. command .. " (try /queueup help)")
end
