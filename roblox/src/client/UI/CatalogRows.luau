-- Happy Tractor client, part 9/14: CatalogRows.
-- Lines 3980-4116 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local Catalog, Players, arenaUI, button, categoryContainers, corner, emoteButtons, emoteLine = C.Catalog, C.Players, C.arenaUI, C.button, C.categoryContainers, C.corner, C.emoteButtons, C.emoteLine
local formatK, frame, label, make, outline, palette, remote, shopItemControls = C.formatK, C.frame, C.label, C.make, C.outline, C.palette, C.remote, C.shopItemControls

function arenaUI.initCatalogRows()
  for i, entry in ipairs(Catalog) do
    local item = entry
    -- Every shop tab now draws its own tiles: Coins & VIP in the CoinShop
    -- module, Emotes, Card Backs and Felts in ShopGrid. These rows are no
    -- longer built.
    if item.category == 'product' or item.category == 'cardBack' or item.category == 'felt' or item.category == 'emote' or not item.category then continue end
    local parentContainer = categoryContainers[item.category or 'emote'] or categoryContainers.emote

    local row = frame(parentContainer, 'ItemRow_' .. item.id, palette.tileBg, 10)
    outline(row, palette.panelBorder, 1)

    local isEmote = not item.category or item.category == 'emote'
    local icon
    if isEmote and arenaUI.emoteDefs[item.id] then
      icon = arenaUI.reactionToken(row, 'Icon', arenaUI.emoteDefs[item.id], 42)
      icon.Position = UDim2.fromOffset(8, 5)
    elseif item.image then
      icon = make('ImageLabel', row, 'Icon', {
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(36, 36),
        Position = UDim2.fromOffset(5, 5),
        Image = item.image,
        ZIndex = 2,
      })
      corner(icon, 6)
    else
      icon = label(row, 'Icon', '✦', 16, palette.goldBright)
    end
    local name = label(row, 'Name', isEmote and arenaUI.emoteDefs[item.id] and arenaUI.emoteDefs[item.id].name or item.label, 13, palette.cream)
    name.Font = Enum.Font.GothamBold
    name.TextXAlignment = Enum.TextXAlignment.Left

    local desc = label(row, 'Desc', item.desc or (item.robux and ('Unlock with ' .. item.robux .. ' Robux') or (item.price == 0 and 'Default Unlocked' or 'Available in shop')), 10, palette.muted)
    desc.TextXAlignment = Enum.TextXAlignment.Left

    -- Action Button
    local btnName = (item.category == 'emote' or not item.category) and ('Emote_' .. item.id) or ('Action_' .. item.id)
    local control = button(row, btnName, item.label, function()
      if not C.state then return end
      if item.category == 'cardBack' or item.category == 'felt' then
        if C.state.owned[item.id] then
          remote:FireServer('equip', item.id)
        elseif item.price and item.price > 0 then
          remote:FireServer('buy', item.id)
        elseif item.robux then
          remote:FireServer('buy_product', item.id)
        end
      elseif item.category == 'product' then
        -- Real Robux purchases go through Roblox's own prompt; the server pays
        -- coins in ProcessReceipt. Items without an ID are not on sale yet.
        local market = game:GetService('MarketplaceService')
        if (item.productId or 0) > 0 then
          market:PromptProductPurchase(Players.LocalPlayer, item.productId)
        elseif (item.gamePassId or 0) > 0 then
          if C.state.vip then return end
          market:PromptGamePassPurchase(Players.LocalPlayer, item.gamePassId)
        else
          remote:FireServer('buy_product', item.id)
        end
      else
        if C.state.owned[item.id] then arenaUI.sendReaction('emote', item.id, 'auto') else remote:FireServer('buy', item.id) end
      end
    end, palette.panelLight)
    control.TextSize = 12

    if item.category == 'emote' or not item.category then
      table.insert(emoteButtons, control)
    end

    shopItemControls[item.id] = {
      row = row,
      icon = icon,
      name = name,
      desc = desc,
      button = control,
      item = item,
    }
  end
end
arenaUI.initCatalogRows()


C.muteButton = button(C.shop, 'Mute', 'Mute reactions: off', function()
  C.muted = not C.muted
  C.muteButton.Text = C.muted and 'Mute reactions: on' or 'Mute reactions: off'
  if C.muted then emoteLine.Text = '' end
end, palette.panelLight)
local shopStatus = label(C.shop, 'ShopStatus', '', 11, palette.muted) C.shopStatus = shopStatus
C.shopBalance = label(C.shop, 'ShopBalance', '● 3K COINS', 12, palette.gold)
C.shopBalance.Font = Enum.Font.GothamBold

C.renderShopItems = function()
  if not C.state then return end
  C.shopBalance.Text = '●  ' .. formatK(C.state.coins) .. ' COINS'
  local saving = C.state.saving and C.state.saving.enabled
  shopStatus.Text = C.state.message or (saving and 'Coins and unlocks are saved to your account.' or 'Progress is not being saved this session.')

  local equippedCardBack = (C.state.equipped and C.state.equipped.cardBack) or 'cardback_classic'
  local equippedFelt = (C.state.equipped and C.state.equipped.felt) or 'felt_emerald'

  for id, ctrl in pairs(shopItemControls) do
    local item = ctrl.item
    local isOwned = C.state.owned[item.id] == true
    local isEquipped = (item.category == 'cardBack' and equippedCardBack == item.id)
      or (item.category == 'felt' and equippedFelt == item.id)

    if item.category == 'cardBack' or item.category == 'felt' then
      if isEquipped then
        ctrl.button.Text = '✓ EQUIPPED'
        ctrl.button.BackgroundColor3 = palette.tileHover
        ctrl.button.TextColor3 = palette.goldBright
      elseif isOwned then
        ctrl.button.Text = 'EQUIP'
        ctrl.button.BackgroundColor3 = palette.tileHover
        ctrl.button.TextColor3 = palette.white
      elseif item.price and item.price > 0 then
        ctrl.button.Text = formatK(item.price) .. ' COINS'
        ctrl.button.BackgroundColor3 = palette.panelLight
        ctrl.button.TextColor3 = palette.goldBright
      elseif item.robux then
        ctrl.button.Text = 'R$ ' .. item.robux
        ctrl.button.BackgroundColor3 = palette.panelLight
        ctrl.button.TextColor3 = palette.goldBright
      else
        ctrl.button.Text = 'EQUIP'
        ctrl.button.BackgroundColor3 = palette.tileHover
        ctrl.button.TextColor3 = palette.white
      end
    elseif item.category == 'product' then
      ctrl.button.Text = (item.gamePassId and C.state and C.state.vip) and '✓ OWNED' or ('R$ ' .. (item.robux or 0) .. ' BUY')
      ctrl.button.BackgroundColor3 = palette.goldDark
      ctrl.button.TextColor3 = palette.white
    else -- emote
      ctrl.button.Text = (item.icon or '') .. ' ' .. (isOwned and 'SEND' or (formatK(item.price) .. ' coins'))
      ctrl.button.BackgroundColor3 = isOwned and palette.tileBg or palette.panelLight
      ctrl.button.TextColor3 = isOwned and palette.white or palette.goldBright
    end
  end
  if C.renderCoinShop then C.renderCoinShop() end
  if C.renderShopGrid then C.renderShopGrid() end
end
end
