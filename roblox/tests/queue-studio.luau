-- Run against the Client datamodel in a fresh Studio Play session.
-- Exercises real server queue timing, validation, and projected state.
local remote = game.ReplicatedStorage.Tractor.Action
local latest
local connection = remote.OnClientEvent:Connect(function(value)
  if value.coins ~= nil then latest = value end
end)
local function command(action, value, delay)
  remote:FireServer(action, value)
  task.wait(delay or 0.3)
end
local results = {}
local ok, reason = pcall(function()
  for _, count in ipairs({4, 6, 8, 10}) do
    command('lobby')
    command('queue', {tier = 'novice', playerCount = count})
    assert(latest.queue.playerCount == count, 'Queue lost selected count')
    task.wait(2.7)
    assert(latest.game and latest.game.playerCount == count, 'Auto-start used wrong count')
    command('change_table')
    assert(latest.queue.playerCount == count, 'Change table lost count')
    command('start_now')
    assert(latest.game and latest.game.playerCount == count, 'Start Now used wrong count')
    command('queue', {tier = 'novice', playerCount = 5})
    assert(not latest.queue and latest.game.playerCount == count, 'Invalid queue replaced game')
    command('start_now', {playerCount = '10'})
    assert(latest.game.playerCount == count, 'Invalid start replaced game')
    command('lobby')
    command('queue', {tier = 'novice', playerCount = count})
    command('cancel_queue')
    task.wait(2.7)
    command('sync')
    assert(not latest.queue and not latest.game, 'Cancelled queue started a match')
    table.insert(results, tostring(count) .. ' players: auto-start, change table, Start Now, rejection, cancel passed')
  end
end)
connection:Disconnect()
assert(ok, reason)
return table.concat(results, '\n')
