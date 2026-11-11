-- Server-owned round/match transitions. Inject rules, clock and random choices.
return function(Cards, S, Rules, Scoring, Trained)
  local Practice = {}
  -- Trained-bot decisions must never stall a table: any failure falls back to
  -- the built-in heuristics for that one decision.
  local function useTrained(state, seat)
    if not Trained then return false end
    if state.trainedSeats then return state.trainedSeats[seat] == true end
    -- Trained at four players; it also beats the built-in bots at six
    -- (58% of rounds) but not at eight or ten, so those keep the old bots.
    return state.playerCount == 4 or state.playerCount == 6
  end
  local function trained(choose, ...)
    local ok, result = pcall(choose, ...)
    if ok then return result, true end
    if warn then warn('[Tractor] Trained bot failed: ' .. tostring(result)) end
    return nil, false
  end
  local function botBurialIds(state, seat)
    if useTrained(state, seat) then
      local ids, ok = trained(Trained.chooseBurial, state.hands[seat], state.kittySize, state.trump)
      if ok then return ids end
    end
    local ids = {}
    for _, c in ipairs(Rules.chooseBurial(state.hands[seat], state.kittySize, state.trump)) do table.insert(ids, c.id) end
    return ids
  end
  -- Thinking time (seconds) for the timed decisions.
  Practice.DECLARE_SECONDS = 12 -- to declare / overtake trump after dealing
  Practice.CHAODI_SECONDS = 10  -- each player's Chao Di decision
  function Practice.new(pick, now, options)
    options, now = options or {}, now or 0
    local count = options.playerCount or 4
    local config = Cards.config(count)
    local deck = Cards.deck(count)
    for i = #deck,2,-1 do
      local j = pick(i); assert(j>=1 and j<=i and j%1==0,'Invalid shuffle choice')
      deck[i],deck[j] = deck[j],deck[i]
    end
    local startingLevel = options.quickMatch and Cards.ranks[pick(#Cards.ranks)] or options.level or '2'
    local levels = options.levels or {A=startingLevel,B=startingLevel}
    local attackingTeam = options.attackingTeam or 'A'
    local dealer = options.dealer or 1
    local duration = options.dealingDuration or 0
    local state = {quickMatch=options.quickMatch or false,playerCount=count,kittySize=config.kittySize,handSize=config.handSize,round=options.round or 1,
      levels={A=levels.A,B=levels.B},attackingTeam=attackingTeam,scheduledDealer=dealer,paced=options.paced or false,
      hands={},kitty={},trump={level=levels[attackingTeam]},phase='declaration',dealingStartedAt=now,
      dealingDuration=duration,deadline=now+duration+Practice.DECLARE_SECONDS,events={},turn=dealer,trick={},lastTrick={},history={},
      tricks=0,points={0,0},penaltyPoints=0,revision=options.revision or 0,done=false,botDeclarations={},
      humans=options.humans or {[1]=true}}
    -- Ranked plays for Rank Points only, so it has no Double (a coin stake).
    state.ranked = options.ranked == true or nil
    for seat=1,count do state.hands[seat]={} end
    for i,card in ipairs(deck) do
      if i<=config.cardCount-config.kittySize then table.insert(state.hands[(dealer+i-2)%count+1],card)
      else table.insert(state.kitty,card) end
    end
    if state.quickMatch then table.insert(state.events,{kind='quick-level',level=startingLevel,at=now}) end
    return state
  end
  -- Seats played by people; every other seat is a bot.
  local function isHuman(state, seat) return state.humans ~= nil and state.humans[seat] == true end
  Practice.isHuman = isHuman
  function Practice.setHuman(state, seat, human)
    state.humans = state.humans or {}
    state.humans[seat] = human and true or nil
    state.revision = state.revision + 1
  end

  function Practice.options(state, seat)
    local result = {}
    if state.phase~='declaration' then return result end
    local hand = state.hands[seat]
    for _,suit in ipairs(Cards.suits) do
      local ids = {}
      for _,card in ipairs(hand) do if card.rank==state.trump.level and card.suit==suit then table.insert(ids,card.id) end end
      for count=1,#ids do
        local selected={}; for i=1,count do selected[i]=ids[i] end
        table.insert(result,{seat=seat,suit=suit,count=count,cardIds=selected})
      end
    end
    local minimum = state.playerCount==4 and 3 or 4
    local all,small,big={},{},{}
    for _,card in ipairs(hand) do if card.joker then
      table.insert(all,card.id); table.insert(card.joker=='small' and small or big,card.id)
    end end
    for _,kind in ipairs({'small','big'}) do
      local ids = kind=='small' and small or big
      -- Tencent rule: two of the same joker is enough to call no-trump.
      for count=2,#ids do
        local selected={}; for i=1,count do selected[i]=ids[i] end
        table.insert(result,{seat=seat,joker=kind,count=count,cardIds=selected})
      end
    end
    if #all>=minimum and #small>0 and #big>0 then
      -- Every size from the minimum up, so no joker in hand goes to waste.
      for count=minimum,#all do
        local ids={}; for i=1,count do ids[i]=all[i] end
        local hasSmall,hasBig=false,false
        for _,id in ipairs(ids) do
          for _,card in ipairs(hand) do if card.id==id then
            if card.joker=='small' then hasSmall=true else hasBig=true end
          end end
        end
        -- Keep at least one of each kind in a mixed call.
        if not hasSmall then ids[count]=small[1] elseif not hasBig then ids[count]=big[1] end
        table.insert(result,{seat=seat,joker='mixed',count=count,cardIds=ids})
      end
    end
    return result
  end
  -- One rule in every round: more cards win. At the same size, jokers beat a
  -- suit and big jokers beat small jokers.
  local function stronger(current,option)
    if not current then return true end
    if option.count~=current.count then return option.count>current.count end
    if current.suit then return not option.suit end
    return current.joker=='small' and option.joker=='big'
  end
  function Practice.declare(state,seat,index,now)
    if state.phase~='declaration' or now>=state.deadline then return false,'The declaration window has closed.' end
    if type(index)~='number' or index~=index or index%1~=0 then return false,'Choose a declaration from your hand.' end
    local option=Practice.options(state,seat)[index]
    if not option then return false,'Choose a declaration from your hand.' end
    local dealt = state.dealingDuration>0 and math.min(state.handSize,math.floor(math.max(0,now-state.dealingStartedAt)/state.dealingDuration*state.handSize)+1) or state.handSize
    local visible={}; for i=1,math.min(dealt,#state.hands[seat]) do visible[state.hands[seat][i].id]=true end
    for _,id in ipairs(option.cardIds) do if not visible[id] then return false,'Wait for those cards to be dealt.' end end
    if not stronger(state.declaration,option) then return false,'Reveal a stronger declaration.' end
    -- Changing the trump suit (or to or from no-trump) doubles the stakes.
    if state.declaration and state.declaration.suit~=option.suit then
      state.chaodiMultiplier=(state.chaodiMultiplier or 1)*2
    end
    state.declaration,state.deadline=option,math.max(now+Practice.DECLARE_SECONDS,state.dealingStartedAt+state.dealingDuration+Practice.DECLARE_SECONDS)
    state.revision=state.revision+1
    table.insert(state.events,{kind='declare',declaration=option,at=now})
    return true
  end
  -- Bots call no-trump on a bare joker pair only with enough other trump to back
  -- it up; otherwise nearly every round would become no-trump.
  local function botWants(state,seat,option)
    if option.joker and option.count==2 then return Practice.trumpCount(state.hands[seat],state.trump.level,nil)>=5 end
    return true
  end
  function Practice.botDeclare(state,now)
    if state.phase~='declaration' or now>=state.deadline or now<state.dealingStartedAt+state.dealingDuration+2 then return false end
    local changed=false
    for seat=1,state.playerCount do
      if not isHuman(state,seat) and not state.botDeclarations[seat] then
        local options=Practice.options(state,seat)
        local chosen
        for index,option in ipairs(options) do
          if stronger(state.declaration,option) and botWants(state,seat,option) and
            (not chosen or (not option.suit and options[chosen].suit) or (option.suit==options[chosen].suit and option.count>options[chosen].count)) then chosen=index end
        end
        if useTrained(state, seat) then
          local legal, indexes = {}, {}
          for index, option in ipairs(options) do
            if stronger(state.declaration, option) and botWants(state, seat, option) then
              table.insert(legal, option); table.insert(indexes, index)
            end
          end
          local picked, ok = trained(Trained.chooseDeclaration, legal, state.hands[seat], state.trump.level)
          if ok then
            chosen = nil
            for position, option in ipairs(legal) do if option == picked then chosen = indexes[position] end end
          end
        end
        state.botDeclarations[seat]=true
        if chosen then changed=Practice.declare(state,seat,chosen,now) or changed end
      end
    end
    return changed
  end
  local function resolve(hand,ids,maximum)
    if type(ids)~='table' or #ids<1 or #ids>maximum then return nil end
    local owned,seen,result,count={},{},{},0
    for _,c in ipairs(hand) do owned[c.id]=c end
    for key,id in pairs(ids) do
      if type(key)~='number' or key%1~=0 or key<1 or key>#ids or type(id)~='string' or #id>60 or seen[id] or not owned[id] then return nil end
      count=count+1; seen[id]=true
    end
    if count~=#ids then return nil end
    for _,id in ipairs(ids) do table.insert(result,owned[id]) end
    return result
  end
  -- Chao Di suit order (WeChat rules): diamonds < clubs < hearts < spades.
  local suitRanking = { diamonds = 1, clubs = 2, hearts = 3, spades = 4 }
  Practice.suitRanking = suitRanking
  local function chaodiStronger(current, option)
    if not current then return true end
    if current.count == 1 then
      return option.count >= 2
    end
    if current.suit then
      -- More cards always wins.
      if option.count > current.count then return true end
      if option.count < current.count then return false end
      -- Same size: jokers beat any suit, otherwise the higher suit wins.
      if not option.suit then return true end
      return (suitRanking[option.suit] or 0) > (suitRanking[current.suit] or 0)
    end
    -- Jokers on the table: more cards win, and at the same size big beats small.
    if option.count ~= current.count then return option.count > current.count end
    return current.joker == 'small' and option.joker == 'big'
  end

  function Practice.chaodiOptions(state, seat)
    local result = {}
    if state.phase ~= 'chaodi' then return result end
    local hand = state.hands[seat]
    if not hand then return result end
    for _, suit in ipairs(Cards.suits) do
      local ids = {}
      for _, card in ipairs(hand) do
        if card.rank == state.trump.level and card.suit == suit then
          table.insert(ids, card.id)
        end
      end
      if #ids >= 2 then
        for count = 2, #ids do
          local selected = {}
          for i = 1, count do selected[i] = ids[i] end
          local opt = { seat = seat, suit = suit, count = count, cardIds = selected }
          if chaodiStronger(state.declaration, opt) then
            table.insert(result, opt)
          end
        end
      end
    end
    local smallJokers, bigJokers = {}, {}
    for _, card in ipairs(hand) do
      if card.joker == 'small' then table.insert(smallJokers, card.id)
      elseif card.joker == 'big' then table.insert(bigJokers, card.id) end
    end
    if #smallJokers >= 2 then
      for count = 2, #smallJokers do
        local ids = {}
        for i = 1, count do ids[i] = smallJokers[i] end
        local opt = { seat = seat, joker = 'small', count = count, cardIds = ids }
        if chaodiStronger(state.declaration, opt) then table.insert(result, opt) end
      end
    end
    if #bigJokers >= 2 then
      for count = 2, #bigJokers do
        local ids = {}
        for i = 1, count do ids[i] = bigJokers[i] end
        local opt = { seat = seat, joker = 'big', count = count, cardIds = ids }
        if chaodiStronger(state.declaration, opt) then table.insert(result, opt) end
      end
    end
    return result
  end

  function Practice.bury(state,seat,ids,now)
    now = now or 0
    if state.phase~='kitty' or (state.kittyHolder or state.dealer)~=seat then return false,'Only the player holding the kitty can bury it.' end
    local selected=resolve(state.hands[seat],ids,state.kittySize)
    if not selected or #selected~=state.kittySize then return false,'Bury exactly ' .. state.kittySize .. ' distinct cards from your hand.' end
    state.hands[seat],state.kitty=S.without(state.hands[seat],selected),selected
    state.phase = 'chaodi'
    state.chaodiMultiplier = state.chaodiMultiplier or 1
    state.chaodiPasses = {}
    state.chaodiTurn = ((state.kittyHolder or state.dealer) % state.playerCount) + 1
    state.chaodiDeadline = now + Practice.CHAODI_SECONDS
    state.revision = state.revision + 1
    table.insert(state.events, { kind = 'bury', seat = seat, at = now })
    return true
  end

  function Practice.chaodi(state, seat, index, now)
    now = now or 0
    if state.phase ~= 'chaodi' or state.chaodiTurn ~= seat then return false, 'Wait for your Chao Di turn.' end
    local options = Practice.chaodiOptions(state, seat)
    local option = options[index]
    if not option then return false, 'Choose a valid Chao Di declaration.' end
    -- Chao Di only changes the trump suit and who re-buries the kitty; the
    -- dealer and the attacking/defending teams stay the same.
    state.chaodiMultiplier = (state.chaodiMultiplier or 1) * 2
    state.chaodiCount = (state.chaodiCount or 0) + 1
    state.declaration = option
    state.trump = { level = state.trump.level, suit = option.suit }
    for _, c in ipairs(state.kitty) do table.insert(state.hands[seat], c) end
    state.kitty = {}
    state.kittyHolder = seat
    state.phase = 'kitty'
    state.chaodiPasses = {}
    state.revision = state.revision + 1
    table.insert(state.events, { kind = 'chaodi', seat = seat, declaration = option, multiplier = state.chaodiMultiplier, at = now })
    if not isHuman(state, seat) then
      assert(Practice.bury(state, seat, botBurialIds(state, seat), now))
    end
    return true
  end

  function Practice.chaodiPass(state, seat, now)
    now = now or 0
    if state.phase ~= 'chaodi' or state.chaodiTurn ~= seat then return false, 'Wait for your Chao Di turn.' end
    state.chaodiPasses = state.chaodiPasses or {}
    state.chaodiPasses[seat] = true

    local passCount = 0
    for s = 1, state.playerCount do
      if s ~= state.kittyHolder and state.chaodiPasses[s] then
        passCount = passCount + 1
      end
    end

    if passCount >= state.playerCount - 1 then
      -- Chao Di is over: open the short Double (加倍) window before the first trick.
      state.phase = 'doubling'
      state.turn = state.dealer
      state.doubleDeadline = now + Practice.DOUBLE_SECONDS
      state.revision = state.revision + 1
      table.insert(state.events, { kind = 'chaodi_done', dealer = state.dealer, multiplier = state.chaodiMultiplier or 1, at = now })
      if state.ranked then Practice.endDoubling(state, now, true) end
      return true
    else
      local nextSeat = (seat % state.playerCount) + 1
      if nextSeat == state.kittyHolder then
        nextSeat = (nextSeat % state.playerCount) + 1
      end
      state.chaodiTurn = nextSeat
      state.chaodiDeadline = now + Practice.CHAODI_SECONDS
      state.revision = state.revision + 1
      return true
    end
  end

  -- How many cards in a hand would be trump under a level and suit (nil suit
  -- means no-trump: only jokers and level cards).
  local function trumpCount(hand, level, suit)
    local count = 0
    for _, card in ipairs(hand) do
      if Cards.category(card, { level = level, suit = suit }) == 'trump' then count = count + 1 end
    end
    return count
  end
  Practice.trumpCount = trumpCount

  -- Bots challenge only when the new suit clearly strengthens their hand:
  -- at least 2 more trumps (4 when overriding their own team's choice) and a
  -- quarter of the hand in trump. Among those, the most trumps wins.
  function Practice.chooseChaodi(state, seat)
    local options = Practice.chaodiOptions(state, seat)
    local hand = state.hands[seat]
    local current = trumpCount(hand, state.trump.level, state.trump.suit)
    local sameTeam = Cards.team(seat) == Cards.team(state.kittyHolder or state.dealer)
    local needed = sameTeam and 4 or 2
    local bestIndex, bestCount
    for index, option in ipairs(options) do
      local count = trumpCount(hand, state.trump.level, option.suit)
      if count - current >= needed and count >= #hand / 4 and (not bestCount or count >= bestCount) then
        bestIndex, bestCount = index, count
      end
    end
    return bestIndex
  end

  -- Seconds players get to Double after Chao Di ends; play starts afterwards.
  Practice.DOUBLE_SECONDS = 8
  -- Closes the Double window and starts the first trick. `force` ends it early.
  function Practice.endDoubling(state, now, force)
    if state.phase ~= 'doubling' then return false end
    if not force and now < (state.doubleDeadline or 0) then return false end
    state.phase = 'tricks'
    state.turn = state.dealer
    state.doubleDeadline = nil
    state.revision = state.revision + 1
    table.insert(state.events, { kind = 'doubling_done', at = now })
    if not state.paced and not isHuman(state, state.dealer) then
      Practice.bots(state)
    end
    return true
  end

  function Practice.stepChaodiBot(state, now)
    if state.phase ~= 'chaodi' or isHuman(state, state.chaodiTurn) then return false end
    local seat = state.chaodiTurn
    local choice = Practice.chooseChaodi(state, seat)
    -- A trained bot that learned Chao Di makes its own call.
    if useTrained(state, seat) and Trained.usesChaodi and Trained.usesChaodi() then
      local calls = Practice.chaodiOptions(state, seat)
      local sameTeam = Cards.team(seat) == Cards.team(state.kittyHolder or state.dealer)
      local picked, ok = trained(Trained.chooseChaodi, calls, state.hands[seat], state.trump, sameTeam, choice)
      if ok then choice = picked end
    end
    if choice then return Practice.chaodi(state, seat, choice, now) end
    return Practice.chaodiPass(state, seat, now)
  end
  function Practice.advance(state,now,pick)
    if state.phase~='declaration' or now<state.deadline then return false end
    if not state.declaration then
      local eligible={}
      for seat=1,state.playerCount do for _,option in ipairs(Practice.options(state,seat)) do
        if option.suit and option.count==1 then table.insert(eligible,option) end
      end end
      if #eligible==0 then state.phase,state.error='blocked','No dealt level card is available. Start a new match.'
      else
        local index=pick(#eligible); assert(index>=1 and index<=#eligible and index%1==0,'Invalid fallback choice')
        state.declaration,state.deadline=eligible[index],now+8
        table.insert(state.events,{kind='fallback',declaration=state.declaration,at=now})
      end
    else
      state.dealer=state.round==1 and state.declaration.seat or state.scheduledDealer
      if state.round==1 then state.attackingTeam=Cards.team(state.dealer) end
      state.trump={level=state.trump.level,suit=state.declaration.suit}
      state.phase='kitty'
      state.kittyHolder=state.dealer
      for _,card in ipairs(state.kitty) do table.insert(state.hands[state.dealer],card) end
      state.kitty={}
      table.insert(state.events,{kind='lock',at=now})
      if not isHuman(state,state.dealer) then
        assert(Practice.bury(state, state.dealer, botBurialIds(state, state.dealer)))
        if not state.paced then Practice.bots(state) end
      end
    end
    state.revision=state.revision+1
    return true
  end
  function Practice.play(state,seat,ids)
    if state.phase~='tricks' or state.done or state.turn~=seat then return false,'Wait for your turn.' end
    local selected=resolve(state.hands[seat],ids,state.handSize)
    if not selected then return false,'Choose distinct cards from your own hand.' end
    local cards,components,matches,reduced,penalty=selected,nil,true,false,0
    if #state.trick==0 then
      components=S.decompose(selected,state.trump)
      if not components then return false,'Lead cards must belong to one suit category or to trump.' end
      local others={}; for index,hand in ipairs(state.hands) do if index~=seat then table.insert(others,hand) end end
      local gamble=Rules.gamble(components,others,state.trump,Cards.team(seat)==state.attackingTeam and 'attackers' or 'defenders')
      cards,components,reduced,penalty=gamble.cards,gamble.components,gamble.reduced,gamble.penalty
    else
      local follow=Rules.follow(state.hands[seat],selected,state.trick[1].components,state.trump)
      if not follow.legal then return false,follow.message end
      components,matches=follow.components,follow.matchesLead
    end
    local currentWinner
    for _,play in ipairs(state.trick) do if play.seat==state.winnerSeat then currentWinner=play end end
    local winning=currentWinner and matches and Rules.winning(cards,state.trick[1].components,currentWinner.components,state.trump) or nil
    if winning then components=winning end
    local winnerSeat=(not currentWinner or winning) and seat or currentWinner.seat
    -- Only mutate after every validation succeeds.
    state.hands[seat]=S.without(state.hands[seat],cards)
    table.insert(state.trick,{seat=seat,cards=cards,components=components,matchesLead=matches})
    state.winnerSeat=winnerSeat
    state.penaltyPoints=state.penaltyPoints+penalty
    state.turn=seat%state.playerCount+1
    state.lastMessage=reduced and ('Gamble failed: ' .. S.describe(components) .. ' played; remaining cards returned. Defender adjustment ' .. (penalty>0 and '+' or '') .. penalty .. '.') or nil
    if #state.trick==state.playerCount then
      local points,winner=0,nil
      for _,play in ipairs(state.trick) do
        for _,c in ipairs(play.cards) do points=points+Cards.points(c) end
        if play.seat==winnerSeat then winner=play end
      end
      local team=Cards.team(winnerSeat)=='A' and 1 or 2
      state.points[team]=state.points[team]+points
      state.turn,state.lastTrick,state.trick=winnerSeat,state.trick,{}
      state.lastWinnerSeat,state.winnerSeat=winnerSeat,nil
      state.tricks=state.tricks+1
      table.insert(state.history,{number=state.tricks,plays=state.lastTrick,winnerSeat=winnerSeat,points=points})
      for _,hand in ipairs(state.hands) do assert(#hand==#state.hands[1],'Trick card-count invariant violated') end
      state.phase='trick-review'
      if #state.hands[1]==0 then
        state.done,state.phase=true,'finished'
        local largest={}
        for _,component in ipairs(winner.components) do table.insert(largest,component) end
        table.sort(largest,S.compare)
        state.settlement=Scoring.settle({playerCount=state.playerCount,attackingTeam=state.attackingTeam,levels=state.levels,
          trickPoints=state.points[state.attackingTeam=='A' and 2 or 1],finalTrickWinnerTeam=Cards.team(winnerSeat),
          finalWinningCards=winner.cards,finalWinningStructure=largest[1],
          kitty=state.kitty,gamblePenaltyPoints=state.penaltyPoints})
        if state.quickMatch then
          state.settlement.winner=state.settlement.outcome.advancingRole=='attackers' and state.attackingTeam or (state.attackingTeam=='A' and 'B' or 'A')
        end
      end
    end
    state.revision=state.revision+1
    return true,state.lastMessage
  end
  -- Concede: the seat's team gives up the round once play has started.
  -- Challengers are settled on the points they hold now (at least 5); a conceding dealer
  -- team is overturned (at least the minimum overturn score). No kitty bonus.
  function Practice.forfeit(state, seat, now)
    if state.done then return false, 'This round is already over.' end
    if state.phase ~= 'tricks' and state.phase ~= 'trick-review' then return false, 'You can concede once play has started.' end
    local team = Cards.team(seat)
    local challengerPoints = (state.points[state.attackingTeam == 'A' and 2 or 1] or 0) + (state.penaltyPoints or 0)
    local overturn = 2 * 20 * (state.playerCount / 2)
    local score
    if team == state.attackingTeam then score = math.max(challengerPoints, overturn)
    -- A conceding challenger team is never charged the full Total Shutout (x4):
    -- with no points yet it settles as a Near Shutout (x2).
    else score = math.min(math.max(challengerPoints, 5), overturn - 5) end
    state.done, state.phase = true, 'finished'
    state.forfeitTeam = team
    state.settlement = Scoring.settle({ playerCount = state.playerCount, attackingTeam = state.attackingTeam, levels = state.levels,
      trickPoints = score, finalTrickWinnerTeam = state.attackingTeam, finalWinningCards = {}, finalWinningStructure = nil,
      kitty = state.kitty or {}, gamblePenaltyPoints = 0 })
    if state.quickMatch then
      state.settlement.winner = state.settlement.outcome.advancingRole == 'attackers' and state.attackingTeam or (state.attackingTeam == 'A' and 'B' or 'A')
    end
    table.insert(state.events, { kind = 'forfeit', seat = seat, team = team, at = now or 0 })
    state.revision = state.revision + 1
    return true
  end
  function Practice.stepBot(state)
    if state.phase~='tricks' or state.done or isHuman(state,state.turn) then return false end
    local seat=state.turn
    local lead=state.trick[1] and state.trick[1].components
    if useTrained(state,seat) then
      local ids,chose
      if lead then ids,chose=trained(Trained.choosePlay,state.hands[seat],lead,state.trump,Trained.playContext(state,seat))
      else ids,chose=trained(Trained.chooseLead,state.hands[seat],state.trump,Trained.leadContext(state,seat)) end
      if chose then
        local played,message=Practice.play(state,seat,ids)
        if played then return true,message end
        if warn then warn('[Tractor] Trained bot chose an illegal play: '..tostring(message)) end
      end
    end
    local context = Rules.playContext(state, seat)
    local chosen=Rules.choose(state.hands[seat],lead,state.trump, context)
    local ids={}; for _,c in ipairs(chosen) do table.insert(ids,c.id) end
    local ok,message=Practice.play(state,seat,ids); assert(ok,message)
    return true,message
  end
  function Practice.bots(state)
    local messages={}
    while state.phase=='tricks' and not state.done and not isHuman(state,state.turn) do
      local ok,message=Practice.stepBot(state)
      if not ok then break end
      if message then table.insert(messages,message) end
    end
    return #messages>0 and table.concat(messages,' ') or nil
  end
  function Practice.nextTrick(state)
    if state.phase~='trick-review' or state.done then return false,'Finish the current trick first.' end
    state.phase='tricks'
    state.revision=state.revision+1
    return true
  end
  function Practice.nextRound(state,pick,now)
    if not state.done or not state.settlement or state.settlement.winner then return nil,'Finish this round before continuing; start a new match after victory.' end
    local settlement=state.settlement
    local nextDealer=(state.dealer-1+(settlement.rolesSwapped and 1 or 2))%state.playerCount+1
    return Practice.new(pick,now,{playerCount=state.playerCount,round=state.round+1,levels=settlement.levels,
      attackingTeam=settlement.attackingTeam,dealer=nextDealer,revision=state.revision+1,dealingDuration=state.dealingDuration,paced=state.paced,
      humans=state.humans})
  end
  function Practice.hint(state, seat)
    if not state or state.done then return nil end
    seat = seat or 1
    if state.phase == 'kitty' and (state.kittyHolder or state.dealer) == seat then
      local buried = Rules.chooseBurial(state.hands[seat], state.kittySize, state.trump)
      local ids = {}; for _, c in ipairs(buried) do table.insert(ids, c.id) end
      return ids
    elseif state.phase == 'chaodi' and state.chaodiTurn == seat then
      local opts = Practice.chaodiOptions(state, seat)
      if #opts > 0 then return opts[#opts].cardIds end
      return nil
    elseif state.phase == 'tricks' and state.turn == seat then
      local context = Rules.playContext(state, seat)
      local chosen = Rules.choose(state.hands[seat], state.trick[1] and state.trick[1].components, state.trump, context)
      local ids = {}; for _, c in ipairs(chosen) do table.insert(ids, c.id) end
      return ids
    end
    return nil
  end
  function Practice.view(state, seat)
    seat = seat or 1
    local counts={}; for i,hand in ipairs(state.hands) do counts[i]=#hand end
    return {quickMatch=state.quickMatch,playerCount=state.playerCount,kittySize=state.kittySize,handSize=state.handSize,round=state.round,levels=state.levels,
      attackingTeam=state.attackingTeam,defenderScore=state.points[state.attackingTeam=='A' and 2 or 1]+state.penaltyPoints,
      penaltyPoints=state.penaltyPoints,settlement=state.settlement,history=state.history,
      phase=state.phase,dealingStartedAt=state.dealingStartedAt,dealingDuration=state.dealingDuration,deadline=state.deadline,
      declaration=state.declaration,dealer=state.dealer,kittyHolder=state.kittyHolder,error=state.error,options=Practice.options(state,seat),hand=state.hands[seat],
      chaodiTurn=state.chaodiTurn,chaodiMultiplier=state.chaodiMultiplier or 1,chaodiCount=state.chaodiCount or 0,chaodiDeadline=state.chaodiDeadline,
      doubleDeadline=state.doubleDeadline,ranked=state.ranked,
      chaodiOptions=Practice.chaodiOptions(state,seat),
      counts=counts,trump=state.trump,turn=state.turn,trick=state.trick,lastTrick=state.lastTrick,winnerSeat=state.winnerSeat,
      lastWinnerSeat=state.lastWinnerSeat,tricks=state.tricks,points=state.points,revision=state.revision,done=state.done,tier=state.tier,
      botCoins=state.botCoins,
      hint=Practice.hint(state, seat)}
  end
  -- Acts for a human who ran out of time: plays a legal suggestion, buries
  -- the suggested cards, or passes Chao Di. Returns true if it acted.
  function Practice.autoAct(state, seat, now)
    if state.done then return false end
    if state.phase == 'tricks' and state.turn == seat then
      local context = Rules.playContext(state, seat)
      local chosen = Rules.choose(state.hands[seat], state.trick[1] and state.trick[1].components, state.trump, context)
      local ids = {}; for _, c in ipairs(chosen) do table.insert(ids, c.id) end
      return (Practice.play(state, seat, ids))
    elseif state.phase == 'kitty' and (state.kittyHolder or state.dealer) == seat then
      local buried = Rules.chooseBurial(state.hands[seat], state.kittySize, state.trump)
      local ids = {}; for _, c in ipairs(buried) do table.insert(ids, c.id) end
      return (Practice.bury(state, seat, ids, now))
    elseif state.phase == 'chaodi' and state.chaodiTurn == seat then
      return (Practice.chaodiPass(state, seat, now))
    end
    return false
  end

  -- The game as seen from `viewer`: seats rotate so the viewer is seat 1, and
  -- when the viewer sits on team B the team labels, levels and points swap so
  -- "your team" is always A. Only the viewer's hand is included.
  function Practice.relativeView(state, viewer)
    local view = Practice.view(state, viewer)
    local count = state.playerCount
    local flip = viewer % 2 == 0
    local function seat(s) if type(s) ~= 'number' then return s end return (s - viewer) % count + 1 end
    local function team(t) if not flip or (t ~= 'A' and t ~= 'B') then return t end return t == 'A' and 'B' or 'A' end
    local function teamMap(t) if not flip or type(t) ~= 'table' then return t end return { A = t.B, B = t.A } end
    local function copy(t) local out = {}; for k, v in pairs(t) do out[k] = v end; return out end
    local function plays(list)
      local out = {}
      for i, play in ipairs(list or {}) do out[i] = copy(play); out[i].seat = seat(play.seat) end
      return out
    end
    local function bySeat(map)
      if type(map) ~= 'table' then return map end
      local out = {}
      for s, v in pairs(map) do out[seat(s)] = v end
      return out
    end
    local function withSeat(t) if type(t) ~= 'table' then return t end local c = copy(t); c.seat = seat(t.seat); return c end
    local function optionList(list)
      local out = {}
      for i, option in ipairs(list or {}) do out[i] = withSeat(option) end
      return out
    end
    view.turn, view.dealer, view.winnerSeat = seat(view.turn), seat(view.dealer), seat(view.winnerSeat)
    view.lastWinnerSeat, view.chaodiTurn, view.kittyHolder = seat(view.lastWinnerSeat), seat(view.chaodiTurn), seat(view.kittyHolder)
    view.trick, view.lastTrick = plays(view.trick), plays(view.lastTrick)
    view.declaration = withSeat(view.declaration)
    view.options, view.chaodiOptions = optionList(view.options), optionList(view.chaodiOptions)
    local history = {}
    for i, entry in ipairs(view.history or {}) do
      history[i] = copy(entry)
      history[i].plays = plays(entry.plays)
      history[i].winnerSeat = seat(entry.winnerSeat)
    end
    view.history = history
    view.counts, view.botCoins = bySeat(view.counts), bySeat(view.botCoins)
    view.levels, view.attackingTeam = teamMap(view.levels), team(view.attackingTeam)
    if flip then view.points = { view.points[2], view.points[1] } end
    if view.settlement then
      local settlement = copy(view.settlement)
      settlement.levels, settlement.attackingTeam = teamMap(settlement.levels), team(settlement.attackingTeam)
      settlement.winner = team(settlement.winner)
      view.settlement = settlement
    end
    view.viewerSeat = viewer
    return view
  end
  return Practice
end
