--[[
  Seekwell.Quest — learns quests and their item rewards from the quest frames you open.
  QUEST_DETAIL (offer) / QUEST_COMPLETE (turn-in) -> learned.quest[questID] = { n = title, g = giverNpcID, gn = giverName, t = turnInNpcID, r = { itemID, ... }, s = lastSeen }
  QUEST_FINISHED (frame closed) ends the current dialog. Secret values are skipped. About 3000 quests at most.
]]

Seekwell = Seekwell or {}
local Quest = {}
Seekwell.Quest = Quest

local CAP, PRUNE_TO, REWARDS_MAX = 3000, 2900, 20
Quest.CAP = CAP
local frame
local open -- questID of the dialog being shown

local function Sec()
  return Seekwell.Secret
end

local function Store()
  local l = Seekwell.Config.Learned()
  if type(l.quest) ~= "table" then
    l.quest = {}
  end
  return l.quest
end
Quest.Store = Store

local function Prune(store)
  local list = {}
  for id, e in pairs(store) do
    list[#list + 1] = { id = id, s = (type(e) == "table" and tonumber(e.s)) or 0 }
  end
  if #list <= CAP then
    return
  end
  table.sort(list, function(a, b)
    return a.s < b.s
  end)
  for i = 1, #list - PRUNE_TO do
    store[list[i].id] = nil
  end
end

local function Rewards()
  local S = Sec()
  local out, seen = {}, {}
  if not GetQuestItemLink then
    return out
  end
  local function Add(kind, n)
    for i = 1, math.min(tonumber(n) or 0, REWARDS_MAX) do
      local id = S.ItemIDFromLink(S.Get(GetQuestItemLink, kind, i))
      if id and not seen[id] and #out < REWARDS_MAX then
        seen[id] = true
        out[#out + 1] = id
      end
    end
  end
  Add("choice", GetNumQuestChoices and S.Get(GetNumQuestChoices))
  Add("reward", GetNumQuestRewards and S.Get(GetNumQuestRewards))
  return out
end
Quest.Rewards = Rewards

--- Record the quest shown in the quest frame. phase = "detail" | "complete". Returns questID or nil.
function Quest.Record(phase)
  local s = Seekwell.Config.Get()
  local z = type(s.zone) == "table" and s.zone or {}
  if not s.learn or z.quests == false then
    return nil
  end
  local S = Sec()
  local qid = GetQuestID and tonumber(S.Get(GetQuestID))
  if not qid or qid <= 0 then
    return nil
  end
  local store = Store()
  local e = store[qid]
  if type(e) ~= "table" then
    e = {}
    store[qid] = e
  end
  local title = GetTitleText and S.Str(S.Get(GetTitleText))
  if title and title ~= "" then
    e.n = title
  end
  local npc = S.NpcIDFromGUID(S.Get(UnitGUID, "npc"))
  if npc then
    if phase == "detail" then
      e.g = npc
      local gn = S.Str(S.Get(UnitName, "npc"))
      if gn and gn ~= "" then
        e.gn = gn
      end
    else
      e.t = npc
    end
  end
  local r = Rewards()
  if #r > 0 or type(e.r) ~= "table" then
    e.r = r
  end
  e.s = (time and time()) or 0
  open = qid
  Prune(store)
  return qid
end

function Quest.Get(questID)
  local e = Store()[tonumber(questID) or -1]
  return type(e) == "table" and e or nil
end

function Quest.Open()
  return open
end

function Quest.Start()
  if frame then
    return
  end
  frame = CreateFrame("Frame")
  frame:RegisterEvent("QUEST_DETAIL")
  frame:RegisterEvent("QUEST_COMPLETE")
  frame:RegisterEvent("QUEST_FINISHED")
  frame:SetScript("OnEvent", Seekwell.Safe("quest", function(_, event)
    if event == "QUEST_DETAIL" then
      Quest.Record("detail")
    elseif event == "QUEST_COMPLETE" then
      Quest.Record("complete")
    elseif event == "QUEST_FINISHED" then
      open = nil
    end
  end))
end

Seekwell.RegisterStart("quest", Quest.Start)
