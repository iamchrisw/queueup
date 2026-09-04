local addonName, addon = ...

local priv = addon._priv
local util = priv.util
local const = priv.const
local state = priv.state

local SafeCall = util.SafeCall
local ROLE_ORDER = const.ROLE_ORDER

local ApplicantData = addon.ApplicantData
local NotesStore = addon.NotesStore

local GetRaidProgressFromRaiderIOProfileForTarget

local function NormalizeDungeonToken(text)
  text = tostring(text or ""):lower()
  text = text:gsub("%b()", "")
  text = text:gsub("[^%w]+", "")
  return text
end

local function GetActiveListingDungeonContext()
  local out = {
    activityID = nil,
    mapID = nil,
    name = nil,
    mapName = nil,
    token = nil,
    mapToken = nil,
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

      local mapID = tonumber(t.mapID or t.challengeModeMapID or t.challengeModeID or t.mapChallengeModeID)
      if mapID then
        out.mapID = mapID
      end

      local mapName = t.mapName or t.mapFullName
      if (not mapName or mapName == "") and out.mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        mapName = SafeCall(C_ChallengeMode.GetMapUIInfo, out.mapID)
      end
      out.mapName = tostring(mapName or "")
      out.mapToken = NormalizeDungeonToken(out.mapName)
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
  local debugMod = priv.debug
  if debugMod and type(debugMod.GetListingKind) == "function" then
    local simulatedKind = debugMod.GetListingKind()
    if simulatedKind == "dungeon" then
      return "Debug listing - simulated dungeon queue"
    elseif simulatedKind == "raid" then
      return "Debug listing - simulated raid queue"
    end
  end

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

local function DetectListingKindFromText(text)
  text = string.lower(tostring(text or ""))
  if text == "" then
    return nil
  end
  if text:find("raid", 1, true) then
    return "raid"
  end
  if text:find("dungeon", 1, true) or text:find("mythic", 1, true) or text:find("keystone", 1, true) then
    return "dungeon"
  end
  return nil
end

local function GetActiveListingKind()
  local debugMod = priv.debug
  if debugMod and type(debugMod.GetListingKind) == "function" then
    local simulatedKind = debugMod.GetListingKind()
    if simulatedKind == "dungeon" or simulatedKind == "raid" then
      return simulatedKind
    end
  end

  if not C_LFGList or type(C_LFGList.GetActiveEntryInfo) ~= "function" then
    return "none"
  end

  local info = SafeCall(C_LFGList.GetActiveEntryInfo)
  if type(info) ~= "table" then
    return "none"
  end

  local activityID = tonumber(info.activityID)
  if not activityID and type(info.activityIDs) == "table" then
    activityID = tonumber(info.activityIDs[1])
  end

  local activity = nil
  if activityID and C_LFGList.GetActivityInfoTable then
    activity = SafeCall(C_LFGList.GetActivityInfoTable, activityID)
  end

  local categoryID = tonumber((type(activity) == "table" and activity.categoryID) or info.categoryID)
  if categoryID then
    if categoryID == 2 then
      return "dungeon"
    end
    if categoryID == 3 then
      return "raid"
    end
  end

  local activityGroupID = tonumber((type(activity) == "table" and (activity.groupFinderActivityGroupID or activity.activityGroupID)) or info.activityGroupID)

  local probeTexts = {
    type(activity) == "table" and activity.fullName or nil,
    type(activity) == "table" and activity.shortName or nil,
    tostring(info.name or ""),
    tostring(info.title or ""),
  }

  if categoryID and C_LFGList and C_LFGList.GetLfgCategoryInfo then
    local c1 = SafeCall(C_LFGList.GetLfgCategoryInfo, categoryID)
    if type(c1) == "table" then
      probeTexts[#probeTexts + 1] = c1.name
      probeTexts[#probeTexts + 1] = c1.shortName
    else
      probeTexts[#probeTexts + 1] = c1
    end
  end

  if activityGroupID and C_LFGList and C_LFGList.GetActivityGroupInfo then
    local g1 = SafeCall(C_LFGList.GetActivityGroupInfo, activityGroupID)
    if type(g1) == "table" then
      probeTexts[#probeTexts + 1] = g1.name
      probeTexts[#probeTexts + 1] = g1.shortName
    else
      probeTexts[#probeTexts + 1] = g1
    end
  end

  for i = 1, #probeTexts do
    local kind = DetectListingKindFromText(probeTexts[i])
    if kind then
      return kind
    end
  end

  return "other"
end

local function GetActiveListingRaidContext()
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

local function NormalizeProgress(killed, total)
  killed = tonumber(killed)
  total = tonumber(total)
  if killed and killed >= 0 then
    if total and total > 0 then
      return math.floor(killed + 0.5), math.floor(total + 0.5)
    end
    return math.floor(killed + 0.5), nil
  end
  return nil, nil
end

local function TrySetProgressSlot(slot, killed, total)
  local k, t = NormalizeProgress(killed, total)
  if not k then
    return
  end
  if slot.killed == nil or k > slot.killed or (k == slot.killed and (t or 0) > (slot.total or 0)) then
    slot.killed = k
    slot.total = t
  end
end

local function ReadKilledTotalFromTable(t)
  if type(t) ~= "table" then
    return nil, nil
  end
  local killed = t.killed or t.killCount or t.kills or t.bossesKilled or t.defeated or t.completed
  local total = t.total or t.totalBosses or t.maxBosses or t.encounters or t.bossCount or t.max
  return NormalizeProgress(killed, total)
end

local function TryExtractRaidProgressFromNode(node)
  if type(node) ~= "table" then
    return nil
  end

  local progress = {
    normal = { killed = nil, total = nil },
    heroic = { killed = nil, total = nil },
    mythic = { killed = nil, total = nil },
  }

  local totalBosses = tonumber(node.totalBosses or node.bossCount or node.maxBosses or node.encounters)

  TrySetProgressSlot(progress.normal, node.normalBossesKilled or node.normalKills, node.normalTotalBosses or totalBosses)
  TrySetProgressSlot(progress.heroic, node.heroicBossesKilled or node.heroicKills or node.hcBossesKilled or node.hcKills, node.heroicTotalBosses or node.hcTotalBosses or totalBosses)
  TrySetProgressSlot(progress.mythic, node.mythicBossesKilled or node.mythicKills, node.mythicTotalBosses or totalBosses)

  for k, v in pairs(node) do
    local key = string.lower(tostring(k or ""))
    local slot = nil
    if key:find("mythic", 1, true) then
      slot = progress.mythic
    elseif key:find("heroic", 1, true) or key == "hc" then
      slot = progress.heroic
    elseif key:find("normal", 1, true) then
      slot = progress.normal
    end

    if slot then
      if type(v) == "table" then
        local killed, total = ReadKilledTotalFromTable(v)
        TrySetProgressSlot(slot, killed, total or totalBosses)
      else
        local val = tonumber(v)
        if val and key:find("killed", 1, true) then
          TrySetProgressSlot(slot, val, totalBosses)
        end
      end
    end
  end

  local any = (progress.normal.killed ~= nil) or (progress.heroic.killed ~= nil) or (progress.mythic.killed ~= nil)
  if not any then
    return nil
  end
  return progress
end

local function RaidNodeMatchesContext(node, keyHint, ctx)
  if type(node) ~= "table" or type(ctx) ~= "table" then
    return false
  end
  local targetToken = tostring(ctx.token or "")
  if targetToken == "" then
    return false
  end

  local candidates = {
    keyHint,
    node.name, node.fullName, node.shortName, node.title,
    node.raid, node.instance, node.zoneName, node.mapName, node.slug,
  }

  for i = 1, #candidates do
    local token = NormalizeDungeonToken(candidates[i])
    if token ~= "" and (token:find(targetToken, 1, true) or targetToken:find(token, 1, true)) then
      return true
    end
  end

  return false
end

local function ScoreRaidProgress(progress)
  if type(progress) ~= "table" then
    return -1
  end
  local function pct(slot)
    if not slot or slot.killed == nil then
      return -1
    end
    local total = tonumber(slot.total) or 0
    if total <= 0 then
      return slot.killed
    end
    return slot.killed + (slot.killed / total)
  end

  return (pct(progress.mythic) * 10000) + (pct(progress.heroic) * 100) + pct(progress.normal)
end

local function MergeRaidProgress(best, candidate)
  if type(candidate) ~= "table" then
    return best
  end
  if not best then
    return candidate
  end

  local out = {
    normal = { killed = best.normal.killed, total = best.normal.total },
    heroic = { killed = best.heroic.killed, total = best.heroic.total },
    mythic = { killed = best.mythic.killed, total = best.mythic.total },
  }

  local function mergeSlot(dst, src)
    if not src or src.killed == nil then
      return
    end
    if dst.killed == nil or src.killed > dst.killed or (src.killed == dst.killed and (src.total or 0) > (dst.total or 0)) then
      dst.killed = src.killed
      dst.total = src.total
    end
  end

  mergeSlot(out.normal, candidate.normal)
  mergeSlot(out.heroic, candidate.heroic)
  mergeSlot(out.mythic, candidate.mythic)
  return out
end

local function FormatRaidProgress(progress)
  if type(progress) ~= "table" then
    return nil
  end

  local parts = {}
  local function add(slot, label)
    if not slot or slot.killed == nil then
      return
    end
    if slot.total and slot.total > 0 then
      parts[#parts + 1] = string.format("%d/%d %s", slot.killed, slot.total, label)
    else
      parts[#parts + 1] = string.format("%d/? %s", slot.killed, label)
    end
  end

  add(progress.normal, "Normal")
  add(progress.heroic, "HC")
  add(progress.mythic, "Mythic")

  if #parts == 0 then
    return nil
  end
  return table.concat(parts, " ")
end

local function TryExtractRaidProgressForRaid(profile, raidCtx)
  if type(profile) ~= "table" or type(raidCtx) ~= "table" then
    return nil
  end
  if tostring(raidCtx.token or "") == "" then
    return nil
  end

  local visited = {}
  local bestProgress = nil
  local bestScore = -1

  local function scan(node, depth, keyHint)
    if type(node) ~= "table" or depth > 9 or visited[node] then
      return
    end
    visited[node] = true

    if RaidNodeMatchesContext(node, keyHint, raidCtx) then
      local p = TryExtractRaidProgressFromNode(node)
      local score = ScoreRaidProgress(p)
      if score > bestScore then
        bestScore = score
        bestProgress = p
      elseif score >= 0 then
        bestProgress = MergeRaidProgress(bestProgress, p)
        bestScore = math.max(bestScore, ScoreRaidProgress(bestProgress))
      end
    end

    for k, v in pairs(node) do
      if type(v) == "table" then
        scan(v, depth + 1, tostring(k))
      end
    end
  end

  scan(profile, 0, nil)
  if not bestProgress then
    return nil, nil
  end
  return FormatRaidProgress(bestProgress), bestProgress
end

local function GetRaiderIOProfile(playerName)
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
  return profile
end

local function GetRaiderIORaidProgress(playerName, raidCtx)
  local profile = GetRaiderIOProfile(playerName)
  local target = {
    name = tostring((type(raidCtx) == "table" and raidCtx.name) or ""),
    aliases = {},
    bosses = nil,
  }

  local seasonRaid = const.CURRENT_SEASON and const.CURRENT_SEASON.raid
  local contextToken = tostring((type(raidCtx) == "table" and raidCtx.token) or "")
  if type(seasonRaid) == "table" then
    local aliases = seasonRaid.aliases or { seasonRaid.name }
    for i = 1, #aliases do
      local aliasToken = NormalizeDungeonToken(aliases[i])
      if aliasToken ~= "" and contextToken ~= ""
        and (contextToken:find(aliasToken, 1, true) or aliasToken:find(contextToken, 1, true)) then
        target.name = seasonRaid.name
        target.aliases = aliases
        target.bosses = seasonRaid.bosses
        break
      end
    end
  end

  if #target.aliases == 0 and target.name ~= "" then
    target.aliases[1] = target.name
  end

  if type(GetRaidProgressFromRaiderIOProfileForTarget) == "function" then
    local progress = GetRaidProgressFromRaiderIOProfileForTarget(profile, target)
    if progress then
      return FormatRaidProgress(progress), progress
    end
  end

  return TryExtractRaidProgressForRaid(profile, raidCtx)
end

local function DifficultyToSlot(difficultyID, difficultyName)
  local id = tonumber(difficultyID)
  if id == 16 then
    return "mythic"
  elseif id == 15 then
    return "heroic"
  elseif id == 14 then
    return "normal"
  end

  local nameToken = string.lower(tostring(difficultyName or ""))
  if nameToken:find("mythic", 1, true) then
    return "mythic"
  elseif nameToken:find("heroic", 1, true) or nameToken:find("hc", 1, true) then
    return "heroic"
  elseif nameToken:find("normal", 1, true) then
    return "normal"
  end
  return nil
end

local function TrySetRaidProgressSlot(progress, slotName, killed, total)
  if type(progress) ~= "table" or type(progress[slotName]) ~= "table" then
    return
  end
  local k = tonumber(killed)
  local t = tonumber(total)
  if not k or k < 0 then
    return
  end
  k = math.floor(k + 0.5)
  if t and t > 0 then
    t = math.floor(t + 0.5)
  else
    t = nil
  end
  local slot = progress[slotName]
  if slot.killed == nil or k > slot.killed or (k == slot.killed and (t or 0) > (slot.total or 0)) then
    slot.killed = k
    slot.total = t
  end
end

local function TargetMatchesRaidToken(target, raidToken)
  if type(target) ~= "table" or raidToken == "" then
    return false
  end
  local aliases = target.aliases or {}
  for i = 1, #aliases do
    local alias = NormalizeDungeonToken(aliases[i])
    if alias ~= "" and (raidToken:find(alias, 1, true) or alias:find(raidToken, 1, true)) then
      return true
    end
  end
  local nameToken = NormalizeDungeonToken(target.name)
  if nameToken ~= "" and (raidToken:find(nameToken, 1, true) or nameToken:find(raidToken, 1, true)) then
    return true
  end
  return false
end

local function NewRaidProgressTable()
  return {
    normal = { killed = nil, total = nil },
    heroic = { killed = nil, total = nil },
    mythic = { killed = nil, total = nil },
  }
end

local HISTORIC_RAID_ACHIEVEMENTS = {
  ["Voidspire"] = { normal = 61366, heroic = 61368, mythic = 61370 },
  ["Dreamrift"] = { normal = 61487, heroic = 61488, mythic = 61489 },
  ["Quel'Danas"] = { normal = 61367, heroic = 61369, mythic = 61371 },
  ["Venomous Abyss"] = { normal = 63521, heroic = 63520, mythic = 63522 },
}

local RAID_FULL_CLEAR_ACHIEVEMENT_ALIASES = {
  ["Voidspire"] = {
    normal = { "normal: the voidspire", "normal: voidspire" },
    heroic = { "heroic: the voidspire", "heroic: voidspire" },
    mythic = { "mythic: the voidspire", "mythic: voidspire" },
  },
  ["Dreamrift"] = {
    normal = { "normal: the dreamrift", "normal: dreamrift" },
    heroic = { "heroic: the dreamrift", "heroic: dreamrift" },
    mythic = { "mythic: the dreamrift", "mythic: dreamrift" },
  },
  ["Quel'Danas"] = {
    normal = { "normal: march on quel'danas", "normal: march on queldanas", "normal: quel'danas", "normal: queldanas" },
    heroic = { "heroic: march on quel'danas", "heroic: march on queldanas", "heroic: quel'danas", "heroic: queldanas" },
    mythic = { "mythic: march on quel'danas", "mythic: march on queldanas", "mythic: quel'danas", "mythic: queldanas" },
  },
  ["Venomous Abyss"] = {
    normal = { "the venomous abyss", "normal: the venomous abyss", "normal: venomous abyss" },
    heroic = { "heroic: the venomous abyss", "heroic: venomous abyss" },
    mythic = { "mythic: the venomous abyss", "mythic: venomous abyss" },
  },
}

local function CountCompletedCriteria(achievementID)
  if type(GetAchievementNumCriteria) ~= "function" or type(GetAchievementCriteriaInfo) ~= "function" then
    return nil, nil
  end
  local n = tonumber(GetAchievementNumCriteria(achievementID)) or 0
  if n <= 0 or n > 64 then
    return nil, nil
  end
  local completed = 0
  local total = 0
  for i = 1, n do
    local criteriaString, _, isCompleted, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, i, true)
    if type(criteriaString) == "string" and criteriaString ~= "" then
      total = total + 1
      if isCompleted == true then
        completed = completed + 1
      else
        local q = tonumber(quantity) or 0
        local r = tonumber(reqQuantity) or 0
        if r > 0 and q >= r then
          completed = completed + 1
        end
      end
    end
  end
  if total <= 0 then
    return nil, nil
  end
  return completed, total
end

local function ParseStatisticValueToNumber(value)
  if type(value) == "number" then
    if value > 0 then
      return math.floor(value + 0.5)
    end
    return nil
  end
  local s = tostring(value or "")
  if s == "" then
    return nil
  end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local n = s:match("([%d%.,]+)")
  if not n then
    return nil
  end
  n = n:gsub("[^%d]", "")
  if n == "" then
    return nil
  end
  local out = tonumber(n)
  if not out or out <= 0 then
    return nil
  end
  return math.floor(out + 0.5)
end

local function GetHistoricalRaidProgressForTarget(target)
  if type(target) ~= "table" or type(GetAchievementInfo) ~= "function" then
    return nil
  end

  local ids = HISTORIC_RAID_ACHIEVEMENTS[target.short]
  if type(ids) ~= "table" then
    return nil
  end

  local totalBosses = tonumber(target.bosses) or 0
  if totalBosses <= 0 then
    return nil
  end

  local progress = NewRaidProgressTable()
  local foundAny = false

  local function apply(slotName, achievementID)
    local id = tonumber(achievementID)
    if not id or id <= 0 then
      return
    end
    local _, _, _, completed = GetAchievementInfo(id)
    if completed then
      TrySetRaidProgressSlot(progress, slotName, totalBosses, totalBosses)
      foundAny = true
      return
    end
    local completedCriteria = CountCompletedCriteria(id)
    if completedCriteria and completedCriteria > 0 then
      TrySetRaidProgressSlot(progress, slotName, math.min(totalBosses, completedCriteria), totalBosses)
      foundAny = true
    end
  end

  apply("normal", ids.normal)
  apply("heroic", ids.heroic)
  apply("mythic", ids.mythic)

  if not foundAny then
    return nil
  end
  return progress
end

local function RioDifficultyToSlot(difficulty)
  local d = tonumber(difficulty)
  if not d then
    return nil
  end
  -- RaiderIO retail: 1=Normal, 2=Heroic, 3=Mythic.
  if d == 1 then
    return "normal"
  elseif d == 2 then
    return "heroic"
  elseif d == 3 then
    return "mythic"
  end
  -- Fallback for game difficulty IDs if exposed.
  return DifficultyToSlot(d, nil)
end

GetRaidProgressFromRaiderIOProfileForTarget = function(profile, target)
  if type(profile) ~= "table" or type(target) ~= "table" then
    return nil
  end
  local raidProfile = profile.raidProfile
  if type(raidProfile) ~= "table" then
    return nil
  end

  local out = NewRaidProgressTable()
  local foundAny = false

  local function apply(raidNode, difficulty, kills, total)
    if type(raidNode) ~= "table" then
      return
    end
    local token = NormalizeDungeonToken(raidNode.name or raidNode.fullName or raidNode.shortName or raidNode.slug)
    if token == "" or not TargetMatchesRaidToken(target, token) then
      return
    end
    local slot = RioDifficultyToSlot(difficulty)
    if not slot then
      return
    end
    local targetTotal = tonumber(target.bosses) or tonumber(total) or 0
    if targetTotal <= 0 then
      targetTotal = tonumber(total) or 0
    end
    if targetTotal <= 0 then
      return
    end
    local count = tonumber(kills) or 0
    if count <= 0 then
      return
    end
    TrySetRaidProgressSlot(out, slot, math.min(targetTotal, count), targetTotal)
    foundAny = true
  end

  local function consumeFlatProgressList(list)
    if type(list) ~= "table" then
      return
    end
    for i = 1, #list do
      local item = list[i]
      if type(item) == "table" then
        local prog = item.progress or item
        local raidNode = prog.raid or item.raid
        local kills = prog.progressCount or item.progressCount or item.kills
        local total = (raidNode and raidNode.bossCount) or prog.bossCount or item.total
        local difficulty = prog.difficulty or item.difficulty
        apply(raidNode, difficulty, kills, total)
      end
    end
  end

  consumeFlatProgressList(raidProfile.progress)
  consumeFlatProgressList(raidProfile.mainProgress)
  consumeFlatProgressList(raidProfile.previousProgress)
  consumeFlatProgressList(raidProfile.sortedProgress)

  if type(raidProfile.raidProgress) == "table" then
    for i = 1, #raidProfile.raidProgress do
      local raidEntry = raidProfile.raidProgress[i]
      if type(raidEntry) == "table" and type(raidEntry.progress) == "table" then
        local raidNode = raidEntry.raid
        local total = raidNode and raidNode.bossCount
        for j = 1, #raidEntry.progress do
          local group = raidEntry.progress[j]
          if type(group) == "table" then
            apply(raidNode, group.difficulty, group.kills or group.progressCount, total)
          end
        end
      end
    end
  end

  if not foundAny then
    return nil
  end
  return out
end

local function GetRaidProgressFromRaiderIOProfile(profile, targets)
  if type(targets) ~= "table" then
    return nil
  end
  local out = {}
  local foundAny = false
  for i = 1, #targets do
    local progress = GetRaidProgressFromRaiderIOProfileForTarget(profile, targets[i])
    out[i] = progress or NewRaidProgressTable()
    if progress then
      foundAny = true
    end
  end
  if not foundAny then
    return nil
  end
  return out
end

local function GetRaidProgressFromFullClearAchievements(targets)
  if type(targets) ~= "table"
    or type(GetCategoryList) ~= "function"
    or type(GetCategoryNumAchievements) ~= "function"
    or type(GetAchievementInfo) ~= "function" then
    return nil
  end

  local categories = GetCategoryList()
  if type(categories) ~= "table" or #categories == 0 then
    return nil
  end

  local out = {}
  local foundAny = false
  for i = 1, #targets do
    out[i] = NewRaidProgressTable()
  end

  local function matchesAnyAlias(nameLower, aliases)
    if type(aliases) ~= "table" then
      return false
    end
    for i = 1, #aliases do
      local alias = tostring(aliases[i] or "")
      if alias ~= "" and nameLower:find(alias, 1, true) then
        return true
      end
    end
    return false
  end

  for _, categoryID in ipairs(categories) do
    local total = tonumber(GetCategoryNumAchievements(categoryID, true)) or 0
    if total > 0 then
      for index = 1, total do
        local _, achievementName, _, isCompleted = GetAchievementInfo(categoryID, index)
        if isCompleted and type(achievementName) == "string" and achievementName ~= "" then
          local lowerName = string.lower(achievementName)
          for t = 1, #targets do
            local target = targets[t]
            local aliases = RAID_FULL_CLEAR_ACHIEVEMENT_ALIASES[target.short]
            if type(aliases) == "table" then
              if matchesAnyAlias(lowerName, aliases.normal) then
                TrySetRaidProgressSlot(out[t], "normal", target.bosses or 0, target.bosses or 0)
                foundAny = true
              end
              if matchesAnyAlias(lowerName, aliases.heroic) then
                TrySetRaidProgressSlot(out[t], "heroic", target.bosses or 0, target.bosses or 0)
                foundAny = true
              end
              if matchesAnyAlias(lowerName, aliases.mythic) then
                TrySetRaidProgressSlot(out[t], "mythic", target.bosses or 0, target.bosses or 0)
                foundAny = true
              end
            end
          end
        end
      end
    end
  end

  if not foundAny then
    return nil
  end
  return out
end

local function GetRaidProgressFromStatistics(targets)
  if type(targets) ~= "table"
    or type(GetCategoryList) ~= "function"
    or type(GetCategoryNumAchievements) ~= "function"
    or type(GetAchievementInfo) ~= "function"
    or type(GetStatistic) ~= "function" then
    return nil
  end

  local categories = GetCategoryList()
  if type(categories) ~= "table" or #categories == 0 then
    return nil
  end

  local out = {}
  for i = 1, #targets do
    out[i] = NewRaidProgressTable()
  end

  local foundAny = false
  for _, categoryID in ipairs(categories) do
    local total = tonumber(GetCategoryNumAchievements(categoryID, true)) or 0
    if total > 0 then
      for index = 1, total do
        local achievementID, achievementName = GetAchievementInfo(categoryID, index)
        if achievementID and type(achievementName) == "string" and achievementName ~= "" then
          local lowerName = string.lower(achievementName)
          local slot = DifficultyToSlot(nil, lowerName)
          if slot
            and (lowerName:find("boss", 1, true)
              or lowerName:find("defeat", 1, true)
              or lowerName:find("killed", 1, true)
              or lowerName:find("kill", 1, true)
              or lowerName:find("progress", 1, true)) then
            local statValue = SafeCall(GetStatistic, achievementID)
            local count = ParseStatisticValueToNumber(statValue)
            if count and count > 0 then
              local nameToken = NormalizeDungeonToken(achievementName)
              for t = 1, #targets do
                local target = targets[t]
                if TargetMatchesRaidToken(target, nameToken) then
                  local targetTotal = tonumber(target.bosses) or count
                  local killed = math.min(targetTotal, count)
                  TrySetRaidProgressSlot(out[t], slot, killed, targetTotal)
                  foundAny = true
                end
              end
            end
          end
        end
      end
    end
  end

  if not foundAny then
    return nil
  end
  return out
end

local function GetRaidProgressFromAchievements(targets)
  if type(targets) ~= "table"
    or type(GetCategoryList) ~= "function"
    or type(GetCategoryNumAchievements) ~= "function"
    or type(GetAchievementInfo) ~= "function"
    or type(GetAchievementNumCriteria) ~= "function"
    or type(GetAchievementCriteriaInfo) ~= "function" then
    return nil
  end

  local categories = GetCategoryList()
  if type(categories) ~= "table" or #categories == 0 then
    return nil
  end

  local out = {}
  local foundAny = false
  for i = 1, #targets do
    out[i] = NewRaidProgressTable()
  end

  for _, categoryID in ipairs(categories) do
    local total = tonumber(GetCategoryNumAchievements(categoryID, true)) or 0
    if total > 0 then
      for index = 1, total do
        local achievementID, achievementName = GetAchievementInfo(categoryID, index)
        if achievementID and type(achievementName) == "string" and achievementName ~= "" then
          local nameToken = NormalizeDungeonToken(achievementName)
          local lowerName = string.lower(achievementName)
          local isGuildRun = lowerName:find("guild run", 1, true) ~= nil
          if not isGuildRun then
            local slot = nil
            if lowerName:find("mythic:", 1, true) then
              slot = "mythic"
            elseif lowerName:find("heroic:", 1, true) then
              slot = "heroic"
            elseif lowerName:find("mythic", 1, true) then
              slot = "mythic"
            elseif lowerName:find("heroic", 1, true) then
              slot = "heroic"
            else
              slot = "normal"
            end

            if slot then
              local _, _, _, completedAchievement = GetAchievementInfo(achievementID)
              if completedAchievement then
                for t = 1, #targets do
                  local target = targets[t]
                  if TargetMatchesRaidToken(target, nameToken) then
                    local targetTotal = tonumber(target.bosses) or 0
                    if targetTotal > 0 then
                      -- Full completion of a raid difficulty achievement represents historic max completion.
                      TrySetRaidProgressSlot(out[t], slot, targetTotal, targetTotal)
                      foundAny = true
                    end
                  end
                end
              else
                local completedCriteria, countedCriteria = CountCompletedCriteria(achievementID)
                if completedCriteria and countedCriteria and countedCriteria > 0 then
                  for t = 1, #targets do
                    local target = targets[t]
                    if TargetMatchesRaidToken(target, nameToken) then
                      local targetTotal = tonumber(target.bosses) or countedCriteria
                      local killed = math.min(targetTotal, completedCriteria)
                      TrySetRaidProgressSlot(out[t], slot, killed, targetTotal)
                      foundAny = true
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  if not foundAny then
    return nil
  end
  return out
end

local function GetSavedRaidProgressForTarget(target)
  if type(GetNumSavedInstances) ~= "function" or type(GetSavedInstanceInfo) ~= "function" then
    return nil
  end

  local progress = {
    normal = { killed = nil, total = nil },
    heroic = { killed = nil, total = nil },
    mythic = { killed = nil, total = nil },
  }

  local count = tonumber(GetNumSavedInstances()) or 0
  for i = 1, count do
    local name, _, _, difficultyID, locked, _, _, isRaid, _, difficultyName, numEncounters, numCompleted = GetSavedInstanceInfo(i)
    if isRaid then
      local completed = tonumber(numCompleted) or 0
      local total = tonumber(numEncounters) or 0
      -- Skip entries with no boss kills unless the instance is explicitly locked.
      -- Modern normal/heroic loot-lock entries often report locked=false but still have completed bosses.
      if completed > 0 or locked then
        local raidToken = NormalizeDungeonToken(name)
        if TargetMatchesRaidToken(target, raidToken) then
          local slot = DifficultyToSlot(difficultyID, difficultyName)
          if slot then
            TrySetRaidProgressSlot(progress, slot, completed, total)
          end
        end
      end
    end
  end

  if (progress.normal.killed == nil) and (progress.heroic.killed == nil) and (progress.mythic.killed == nil) then
    return nil
  end
  return progress
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
  local targetActivityID = tonumber(ctx.activityID)
  if targetActivityID then
    local activityCandidates = {
      t.activityID, t.activityId, t.activity, t.lfgActivityID,
    }
    for i = 1, #activityCandidates do
      if tonumber(activityCandidates[i]) == targetActivityID then
        return true
      end
    end
  end

  local targetMapID = tonumber(ctx.mapID)
  if targetMapID then
    local mapCandidates = {
      t.mapID, t.challengeModeMapID, t.challengeModeID, t.mapChallengeModeID,
      t.instanceID, t.dungeonID, t.id,
    }
    for i = 1, #mapCandidates do
      if tonumber(mapCandidates[i]) == targetMapID then
        return true
      end
    end
  end

  local targetTokens = {}
  local mapToken = tostring(ctx.mapToken or "")
  local listingToken = tostring(ctx.token or "")
  if mapToken ~= "" then
    targetTokens[#targetTokens + 1] = mapToken
  end
  if listingToken ~= "" and listingToken ~= mapToken then
    targetTokens[#targetTokens + 1] = listingToken
  end

  if #targetTokens > 0 then
    local nameCandidates = {
      t.name, t.fullName, t.shortName, t.dungeon, t.instance, t.mapName,
      t.zoneName, t.keystone_instance, t.slug, t.abbreviation,
    }
    for i = 1, #nameCandidates do
      local token = NormalizeDungeonToken(nameCandidates[i])
      if token ~= "" then
        for j = 1, #targetTokens do
          local targetToken = targetTokens[j]
          if token:find(targetToken, 1, true) or targetToken:find(token, 1, true) then
            return true
          end
        end
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
  local targetMapToken = tostring(ctx.mapToken or "")
  local targetActivityID = tonumber(ctx.activityID)
  local targetMapID = tonumber(ctx.mapID)
  if targetToken == "" and targetMapToken == "" and not targetActivityID and not targetMapID then
    return nil
  end

  local visited = {}
  local best = nil

  local function scan(node, depth)
    if type(node) ~= "table" or depth > 8 or visited[node] then
      return
    end
    visited[node] = true

    local matchesContext = DungeonTableMatchesContext(node, ctx)
    if not matchesContext and type(node.dungeon) == "table" then
      matchesContext = DungeonTableMatchesContext(node.dungeon, ctx)
    end

    if matchesContext then
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

  local strictContext = false
  if type(dungeonCtx) == "table" then
    strictContext = (tonumber(dungeonCtx.activityID) ~= nil)
      or (tonumber(dungeonCtx.mapID) ~= nil)
      or (tostring(dungeonCtx.mapToken or "") ~= "")
      or (tostring(dungeonCtx.token or "") ~= "")
  end

  local byDungeon = TryExtractBestLevelForDungeon(profile, dungeonCtx)
  if byDungeon then
    return byDungeon
  end

  if strictContext then
    -- If we know the active listing context, avoid falling back to overall best.
    return nil
  end

  return TryExtractBestLevel(profile)
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

local function TryExtractRaiderIOItemLevel(profile)
  if type(profile) ~= "table" then
    return nil
  end

  local mkp = profile.mythicKeystoneProfile or {}
  local preferredCandidates = {
    mkp.currentEquippedItemLevel,
    mkp.currentItemLevel,
    mkp.equippedItemLevel,
    mkp.itemLevel,
    mkp.ilvl,
    profile.currentEquippedItemLevel,
    profile.currentItemLevel,
    profile.equippedItemLevel,
    profile.itemLevel,
    profile.ilvl,
    profile.gearItemLevel,
    mkp.gearItemLevel,
  }

  for i = 1, #preferredCandidates do
    local v = tonumber(preferredCandidates[i])
    if v and v > 0 then
      return math.floor(v + 0.5)
    end
  end

  return nil
end

local function GetRaiderIOItemLevel(playerName)
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

  return TryExtractRaiderIOItemLevel(profile)
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
    local assignedRole = string.upper(tostring(t.assignedRole or t.role or ""))
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
  local rolePos4 = string.upper(tostring(raw[4] or ""))
  local ilvl = tonumber(raw[5]) or 0
  local assignedRole = string.upper(tostring(raw[10] or ""))

  -- The positional return list has changed more than once. Recover role,
  -- class and specialization by inspecting all returned values as well.
  for i = 2, #raw do
    local value = raw[i]
    if type(value) == "string" then
      local token = string.upper(value)
      if IsRoleToken(token) and not IsRoleToken(assignedRole) then
        assignedRole = token
      elseif RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then
        classFile = token
      end
    end
  end
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

  if spec == "" and type(GetSpecializationInfoByID) == "function" then
    for i = 2, #raw do
      local candidate = tonumber(raw[i])
      if candidate and candidate > 0 then
        local specName = SafeCall(GetSpecializationInfoByID, candidate)
        if type(specName) == "string" and specName ~= "" then
          spec = specName
          break
        end
      end
    end
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

local GROUP_GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local ENCHANTABLE_SLOTS = {
  [3] = true, -- shoulders
  [11] = true, -- ring 1
  [12] = true, -- ring 2
  [16] = true, -- main hand
  [17] = true, -- off hand
}
local SLOT_LABELS = {
  [1] = "Head",
  [2] = "Neck",
  [3] = "Shoulder",
  [5] = "Chest",
  [6] = "Waist",
  [7] = "Legs",
  [8] = "Feet",
  [9] = "Wrist",
  [10] = "Hands",
  [11] = "Ring 1",
  [12] = "Ring 2",
  [13] = "Trinket 1",
  [14] = "Trinket 2",
  [15] = "Back",
  [16] = "Main Hand",
  [17] = "Off Hand",
}
local function GetUnitSpecTexture(unit)
  if not unit then
    return nil
  end
  local specID = nil
  if UnitIsUnit and UnitIsUnit(unit, "player") and GetSpecialization and GetSpecializationInfo then
    local idx = GetSpecialization()
    if idx and idx > 0 then
      local sid = GetSpecializationInfo(idx)
      specID = tonumber(sid)
    end
  elseif GetInspectSpecialization then
    specID = tonumber(GetInspectSpecialization(unit) or 0)
  end
  if specID and specID > 0 and GetSpecializationInfoByID then
    local _, _, _, icon = GetSpecializationInfoByID(specID)
    return icon
  end
  return nil
end

local function GetUnitRoleFallback(unit, currentRole)
  local role = tostring(currentRole or "NONE")
  if role ~= "" and role ~= "NONE" then
    return role
  end

  if UnitIsUnit and UnitIsUnit(unit, "player") and type(GetSpecialization) == "function" and type(GetSpecializationRole) == "function" then
    local idx = GetSpecialization()
    if idx and idx > 0 then
      local specRole = tostring(GetSpecializationRole(idx) or "")
      if specRole ~= "" and specRole ~= "NONE" then
        return specRole
      end
    end
  end

  if type(GetInspectSpecialization) == "function" and type(GetSpecializationInfoByID) == "function" then
    local specID = tonumber(GetInspectSpecialization(unit) or 0)
    if specID and specID > 0 then
      local _, _, _, _, specRole = GetSpecializationInfoByID(specID)
      specRole = tostring(specRole or "")
      if specRole ~= "" and specRole ~= "NONE" then
        return specRole
      end
    end
  end

  return "DAMAGER"
end

local function GetSocketCountFromItemLink(link)
  if type(GetItemStats) ~= "function" then
    return 0
  end
  local stats = SafeCall(GetItemStats, link)
  if type(stats) ~= "table" then
    return 0
  end
  local sockets = 0
  for k, v in pairs(stats) do
    local key = tostring(k or "")
    if key:find("EMPTY_SOCKET_", 1, true) then
      sockets = sockets + (tonumber(v) or 1)
    end
  end
  return math.max(0, math.floor((tonumber(sockets) or 0) + 0.5))
end

local function GetSocketCountForUnitSlot(unit, slot, link)
  local slotID = tonumber(slot) or 0
  if slotID <= 0 then
    return 0
  end

  if unit == "player" and type(ItemLocation) == "table" and type(ItemLocation.CreateFromEquipmentSlot) == "function"
    and type(C_Item) == "table" and type(C_Item.GetItemNumSockets) == "function" then
    local loc = SafeCall(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slotID)
    if type(loc) == "table" and (not loc.IsValid or loc:IsValid()) then
      local n = tonumber(SafeCall(C_Item.GetItemNumSockets, loc))
      if n and n > 0 then
        return math.floor(n + 0.5)
      end
    end
  end

  if type(link) == "string" and link ~= "" then
    return GetSocketCountFromItemLink(link)
  end
  return 0
end

local function GetTooltipAudit(unit, slot)
  local notEnchantedToken = tostring(_G.ITEM_NOT_ENCHANTED or "Not Enchanted")
  local emptySocketToken = tostring(_G.EMPTY_SOCKET_PRISMATIC or "Empty Socket")
  local missingEnchant = false
  local emptySockets = 0
  local modernTooltipRead = false
  local function GatherTextParts(v, out)
    if type(v) == "string" then
      out[#out + 1] = v
      return
    end
    if type(v) ~= "table" then
      return
    end
    for _, sub in pairs(v) do
      if type(sub) == "string" then
        out[#out + 1] = sub
      elseif type(sub) == "table" then
        GatherTextParts(sub, out)
      end
    end
  end
  if type(C_TooltipInfo) == "table" and type(C_TooltipInfo.GetInventoryItem) == "function" then
    local data = SafeCall(C_TooltipInfo.GetInventoryItem, unit, slot)
    if type(data) == "table" and type(data.lines) == "table" then
      modernTooltipRead = true
      for i = 1, #data.lines do
        local line = data.lines[i]
        if type(line) == "table" then
          local texts = {}
          GatherTextParts(line, texts)
          for t = 1, #texts do
            local txt = tostring(texts[t] or "")
            if txt ~= "" then
              if notEnchantedToken ~= "" and txt:find(notEnchantedToken, 1, true) then
                missingEnchant = true
              end
              if txt:find("Empty Socket", 1, true) or (emptySocketToken ~= "" and txt:find(emptySocketToken, 1, true)) then
                emptySockets = emptySockets + 1
              end
            end
          end
        end
      end
    end
  end

  -- Fallback: legacy hidden tooltip scan (very reliable for "Not Enchanted"/"Empty Socket" lines).
  if (not modernTooltipRead or (not missingEnchant and emptySockets == 0))
    and type(CreateFrame) == "function" and type(UIParent) == "table" then
    if not state._auditTooltip then
      state._auditTooltip = CreateFrame("GameTooltip", "QueueUpAuditTooltip", UIParent, "GameTooltipTemplate")
      if state._auditTooltip and state._auditTooltip.SetOwner then
        state._auditTooltip:SetOwner(UIParent, "ANCHOR_NONE")
      end
    end
    local tip = state._auditTooltip
    if tip and tip.SetInventoryItem then
      tip:ClearLines()
      SafeCall(tip.SetInventoryItem, tip, unit, slot)
      local n = tonumber(tip:NumLines() or 0) or 0
      for i = 1, n do
        local leftFS = _G["QueueUpAuditTooltipTextLeft" .. tostring(i)]
        local txt = leftFS and leftFS.GetText and tostring(leftFS:GetText() or "") or ""
        if txt ~= "" then
          if notEnchantedToken ~= "" and txt:find(notEnchantedToken, 1, true) then
            missingEnchant = true
          end
          if txt:find("Empty Socket", 1, true) or (emptySocketToken ~= "" and txt:find(emptySocketToken, 1, true)) then
            emptySockets = emptySockets + 1
          end
        end
      end
      tip:Hide()
    end
  end
  return missingEnchant, emptySockets
end

local function ParseItemLinkAudit(unit, link, slot)
  if type(link) ~= "string" then
    return 0, 0, nil
  end
  local payload = link:match("item:([%-:%d]+)")
  if not payload then
    return 0, 0, nil
  end
  local fields = {}
  -- Keep empty fields so enchant/gem indices stay correct.
  -- Example: itemID:enchant:gem1:gem2:gem3...
  local idx = 1
  for part in (payload .. ":"):gmatch("(.-):") do
    fields[idx] = tonumber(part) or 0
    idx = idx + 1
  end
  local enchantID = fields[2] or 0
  local gem1 = fields[3] or 0
  local gem2 = fields[4] or 0
  local gem3 = fields[5] or 0
  local missing = 0
  local low = 0
  local details = {}
  local slotID = tonumber(slot) or 0
  local slotLabel = SLOT_LABELS[slotID] or ("Slot " .. tostring(slotID))

  local tooltipMissingEnchant, tooltipEmptySockets = GetTooltipAudit(unit, slotID)
  if ENCHANTABLE_SLOTS[slotID] and (tooltipMissingEnchant or enchantID == 0) then
    missing = missing + 1
    details[#details + 1] = slotLabel .. ": missing enchant"
  end

  local socketCount = GetSocketCountForUnitSlot(unit, slotID, link)
  if socketCount <= 0 then
    socketCount = tonumber(tooltipEmptySockets) or 0
  end
  if socketCount > 0 then
    local gems = { gem1, gem2, gem3 }
    for i = 1, math.min(3, socketCount) do
      if tonumber(gems[i] or 0) <= 0 then
        missing = missing + 1
        details[#details + 1] = slotLabel .. ": missing gem"
      end
    end
  end
  return missing, low, details
end

local function BuildGroupOverviewRows()
  local rows = {}
  local units = {}
  if IsInRaid and IsInRaid() then
    for i = 1, (GetNumGroupMembers() or 0) do
      units[#units + 1] = "raid" .. i
    end
  elseif IsInGroup and IsInGroup() then
    units[#units + 1] = "player"
    for i = 1, (GetNumSubgroupMembers() or 0) do
      units[#units + 1] = "party" .. i
    end
  else
    units[#units + 1] = "player"
  end

  state.groupInspectCache = state.groupInspectCache or {}
  state.groupInspectStarted = state.groupInspectStarted or {}
  state.nextInspectAt = state.nextInspectAt or 0

  for i = 1, #units do
    local unit = units[i]
    local name = GetUnitName and GetUnitName(unit, true) or UnitName(unit)
    name = tostring(name or unit)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"
    role = GetUnitRoleFallback(unit, role)

    local key = UnitGUID and UnitGUID(unit) or name
    local cached = state.groupInspectCache[key]
    local now = type(GetTime) == "function" and (tonumber(GetTime()) or 0) or 0
    if (not cached or (now - (cached.ts or 0)) > 20) and CanInspect and CanInspect(unit) and UnitIsConnected and UnitIsConnected(unit) then
      if now >= (state.nextInspectAt or 0) and unit ~= "player" then
        if NotifyInspect then
          NotifyInspect(unit)
          state.groupInspectStarted[key] = now
          state.nextInspectAt = now + 1.5
        end
      end
    end

    local missing = 0
    local low = 0
    local issueDetails = {}
    local scannedAny = false
    for s = 1, #GROUP_GEAR_SLOTS do
      local slot = GROUP_GEAR_SLOTS[s]
      local link = GetInventoryItemLink and GetInventoryItemLink(unit, slot) or nil
      if link then
        local m, l, d = ParseItemLinkAudit(unit, link, slot)
        missing = missing + (m or 0)
        low = low + (l or 0)
        if type(d) == "table" then
          for di = 1, #d do
            issueDetails[#issueDetails + 1] = tostring(d[di])
          end
        end
        scannedAny = true
      end
    end

    if scannedAny then
      state.groupInspectCache[key] = { ts = now, missing = missing, low = low, details = issueDetails }
      cached = state.groupInspectCache[key]
    end

    local issueCount = (cached and ((cached.missing or 0) + (cached.low or 0))) or 0
    local quality = "good"
    if not cached then
      quality = "unknown"
    elseif issueCount >= 3 then
      quality = "bad"
    elseif issueCount >= 1 then
      quality = "warn"
    end

    rows[#rows + 1] = {
      unit = unit,
      name = name,
      role = role,
      specIcon = GetUnitSpecTexture(unit),
      quality = quality,
      issues = issueCount,
      issueDetails = (cached and cached.details) or issueDetails,
      scanning = cached == nil and unit ~= "player"
        and state.groupInspectStarted[key] ~= nil
        and (now - (state.groupInspectStarted[key] or now)) < 8,
    }
  end
  return rows
end

local function ClearGroupOverviewCache()
  state.groupInspectCache = {}
  state.groupInspectStarted = {}
  state.nextInspectAt = 0
end

local function ResolveDisplayedIlvl(memberIlvl, applicantIlvl, rioIlvl)
  local member = tonumber(memberIlvl) or 0
  local applicant = tonumber(applicantIlvl) or 0
  local rio = tonumber(rioIlvl) or 0

  if member > 0 then
    return math.floor(member + 0.5)
  end
  if applicant > 0 then
    return math.floor(applicant + 0.5)
  end
  if rio > 0 then
    return math.floor(rio + 0.5)
  end
  return 0
end

function NotesStore.Get(key)
  key = NormalizePlayerKey(key)
  return state.DB.playerNotes[key]
end

function NotesStore.Set(key, note)
  key = NormalizePlayerKey(key)
  if key == "" then
    return
  end

  note = tostring(note or "")
  if note == "" then
    state.DB.playerNotes[key] = nil
  else
    state.DB.playerNotes[key] = note
  end
end

function NotesStore.Keys()
  local out = {}
  for k in pairs(state.DB.playerNotes) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

local function GetApplicantInfoData(applicantID)
  local raw1, raw2, raw3, raw4, raw5, raw6, raw7, raw8, raw9, raw10, raw11, raw12 = SafeCall(C_LFGList.GetApplicantInfo, applicantID)
  if type(raw1) == "table" then
    local t = raw1
    local ilvl = tonumber(t.itemLevel or t.ilvl or t.itemLvl or t.equippedItemLevel) or 0
    return {
      applicantName = tostring(t.applicantName or t.name or ""),
      applicantStatus = tostring(t.applicationStatus or t.applicantStatus or ""),
      pendingStatus = tostring(t.pendingStatus or ""),
      numMembers = tonumber(t.numMembers) or 1,
      ilvl = ilvl,
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
  local listingKind = GetActiveListingKind()
  local listingRaid = nil
  if listingKind == "raid" then
    listingRaid = GetActiveListingRaidContext()
  end
  local bestCache = {}
  local rioScoreCache = {}
  local rioIlvlCache = {}
  local raidProgressCache = {}
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
  local function GetCachedRioIlvl(playerKey)
    if rioIlvlCache[playerKey] ~= nil then
      if rioIlvlCache[playerKey] == false then
        return nil
      end
      return rioIlvlCache[playerKey]
    end
    local v = GetRaiderIOItemLevel(playerKey)
    rioIlvlCache[playerKey] = v or false
    return v
  end
  local function GetCachedRaidProgress(playerKey)
    if not listingRaid then
      return nil
    end
    if raidProgressCache[playerKey] ~= nil then
      if raidProgressCache[playerKey] == false then
        return nil
      end
      return raidProgressCache[playerKey]
    end
    local v = GetRaiderIORaidProgress(playerKey, listingRaid)
    raidProgressCache[playerKey] = v or false
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

      local leaderKey = NormalizePlayerKey(leaderName)
      local leaderRioIlvl = GetCachedRioIlvl(leaderKey) or 0
      local ilvl = ResolveDisplayedIlvl(displayMember.ilvl, info.ilvl, leaderRioIlvl)
      local leaderMemberRating = tonumber(displayMember.rating) or 0
      local leaderRioScore = GetCachedRioScore(leaderKey) or 0
      applicantRating = ResolveDisplayedRating(applicantRating, leaderMemberRating, leaderRioScore)
      local spec = tostring(displayMember.spec or "")
      if spec == "" and numMembers > 1 then
        spec = "Group"
      end

      local leaderHighest = GetCachedBest(leaderKey)
      local leaderRaidProgress = GetCachedRaidProgress(leaderKey)

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
        raidProgressText = leaderRaidProgress,
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
          local memberRioIlvl = GetCachedRioIlvl(memberKey) or 0
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
            ilvl = ResolveDisplayedIlvl(member.ilvl, info.ilvl, memberRioIlvl),
            rating = memberRating,
            numMembers = numMembers,
            applicantStatus = applicantStatus,
            pendingStatus = pendingStatus,
            isInvited = IsInvitedState(applicantStatus, pendingStatus),
            note = NotesStore.Get(memberName),
            applicationNote = "",
            highestCompletion = GetCachedBest(memberKey),
            raidProgressText = GetCachedRaidProgress(memberKey),
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

priv.data.GetActiveListingContext = GetActiveListingContext
priv.data.GetActiveListingKind = GetActiveListingKind
priv.data.GetGroupOverviewRows = BuildGroupOverviewRows
priv.data.ClearGroupOverviewCache = ClearGroupOverviewCache
priv.data.NormalizePlayerKey = NormalizePlayerKey
