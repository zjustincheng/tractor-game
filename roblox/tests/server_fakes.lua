-- Shared Roblox service doubles for server tests that need several servers'
-- worth of behaviour: MemoryStore sorted maps, MessagingService (delivered to
-- every subscriber at once, as across servers), TeleportService, players.
return function(options)
  local Cards = dofile('roblox/src/shared/Cards.luau')
  local Catalog = dofile('roblox/src/shared/Catalog.luau')
  local StructuresFactory = dofile('roblox/src/shared/Structures.luau')
  local RulesFactory = dofile('roblox/src/shared/PlayRules.luau')
  local ScoringFactory = dofile('roblox/src/shared/Scoring.luau')
  local fakes = { inbox = {}, events = {}, teleports = {}, published = {}, subscribers = {}, maps = {}, reserved = 0,
    clock = 0, wall = 1000000, Rules = RulesFactory(Cards, StructuresFactory(Cards)) }
  local function signal() return { Connect = function(self, handler) self.handler = handler end } end
  local function sortedMap(name)
    if fakes.maps[name] then return fakes.maps[name] end
    local data = {}
    local map = { data = data }
    function map:SetAsync(key, value) data[key] = value; return true end
    function map:GetAsync(key) return data[key] end
    function map:RemoveAsync(key) data[key] = nil end
    function map:UpdateAsync(key, transform)
      local result = transform(data[key])
      if result ~= nil then data[key] = result end
      return result
    end
    function map:GetRangeAsync(_, count)
      local keys = {}
      for key in pairs(data) do table.insert(keys, key) end
      table.sort(keys)
      local out = {}
      for i = 1, math.min(count, #keys) do out[i] = { key = keys[i], value = data[keys[i]] } end
      return out
    end
    fakes.maps[name] = map
    return map
  end
  local memory = { GetSortedMap = function(_, name) return sortedMap(name) end }
  local messaging = {
    SubscribeAsync = function(_, topic, callback) fakes.subscribers[topic] = callback end,
    PublishAsync = function(_, topic, data)
      table.insert(fakes.published, { topic = topic, data = data })
      if fakes.subscribers[topic] then fakes.subscribers[topic]({ Data = data }) end
    end,
  }
  local teleport = {
    ReserveServer = function() fakes.reserved = fakes.reserved + 1; return 'access-' .. fakes.reserved end,
    TeleportAsync = function(_, placeId, players, teleportOptions)
      table.insert(fakes.teleports, { placeId = placeId, players = players, options = teleportOptions })
    end,
  }
  local players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
  local shared = { Cards = Cards, Catalog = Catalog, Structures = StructuresFactory, PlayRules = RulesFactory, Scoring = ScoringFactory }
  local services = { Players = players, MemoryStoreService = memory, MessagingService = messaging, TeleportService = teleport,
    RunService = { IsStudio = function() return false end, IsRunning = function() return false end, IsServer = function() return false end },
    DataStoreService = { GetDataStore = function() return { GetAsync = function() return nil end, UpdateAsync = function(_, _, t) return t(nil) end } end } }
  game = { PlaceId = 7, JobId = options.jobId or 'server-A', PrivateServerId = options.privateServerId or '', PrivateServerOwnerId = 0,
    GetService = function(_, name) return services[name] or { WaitForChild = function() return shared end } end }
  script = { Parent = { TrainedBots = dofile('roblox/src/server/TrainedBots.luau'), ChampionModel = dofile('roblox/src/server/ChampionModel.luau'), Practice = dofile('roblox/src/server/Practice.luau'), Persistence = dofile('roblox/src/server/Persistence.luau'),
    Matchmaker = dofile('roblox/src/server/Matchmaker.luau'), CrossServer = dofile('roblox/src/server/CrossServer.luau') } }
  require = function(module) return module end
  Random = { new = function() return { NextInteger = function(_, _, maximum) return maximum end } end }
  os.clock = function() return fakes.clock end
  os.time = function() return fakes.wall end
  math.clamp = function(value, low, high) return math.max(low, math.min(high, value)) end
  warn = function() end
  task = { spawn = function() end, wait = function() end }
  workspace = {}
  Enum = { SortDirection = { Ascending = 'Ascending' } }
  Vector3 = { new = function() return {} end }
  Color3 = { fromRGB = function() return {} end }
  CFrame = { lookAt = function() return {} end }
  Instance = { new = function(class)
    local object = {}
    if class == 'RemoteEvent' then
      fakes.remote = object
      object.OnServerEvent = signal()
      object.FireClient = function(_, recipient, value)
        if value.type then fakes.events[recipient] = value else fakes.inbox[recipient] = value end
      end
    elseif class == 'TeleportOptions' then
      function object:SetTeleportData(data) self.data = data end
    end
    return object
  end }
  dofile('roblox/src/server/Main.server.luau')
  function fakes.person(name, userId, joinData)
    local person = { DisplayName = name, UserId = userId }
    function person:GetJoinData() return { TeleportData = joinData } end
    players.PlayerAdded.handler(person)
    return person
  end
  function fakes.command(person, action, value, revision)
    fakes.clock = fakes.clock + 0.2
    fakes.remote.OnServerEvent.handler(person, action, value, revision)
    return fakes.inbox[person]
  end
  fakes.players = players
  return fakes
end
