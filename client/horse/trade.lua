local TRADE_DISTANCE <const> = 2.0
local TRADE_IDLE_DELAY_MS <const> = 1000
local TRADE_PROPOSAL_TIMEOUT_MS <const> = 15000

local tradePromptLoopRunning = false

local function runTradePromptLoop()
    if tradePromptLoopRunning then return end

    tradePromptLoopRunning = true

    local horse = MyHorse
    local horseId = tonumber(MyHorseId)
    local promptLabel = CreateVarString(10, 'LITERAL_STRING', tostring(HorseName or 'Horse'))

    while IsMyHorseActive and MyHorse == horse do
        local delay = TRADE_IDLE_DELAY_MS
        local playerPed = PlayerPedId()

        if horseId and horse ~= 0 and DoesEntityExist(horse) and not IsEntityDead(playerPed) then
            local lastLedMount = Citizen.InvokeNative(0x693126B5D0457D0D, playerPed) -- GetLastLedMount
            local isLeadingHorse = Citizen.InvokeNative(0xEFC4303DDC6E60D3, playerPed) -- IsPedLeadingHorse

            if lastLedMount == horse and isLeadingHorse then
                local closestPlayer, closestDistance = GetClosestPlayer()

                if closestPlayer and closestDistance <= TRADE_DISTANCE then
                    delay = 0
                    UiPromptSetActiveGroupThisFrame(TradeGroup, promptLabel, 1, 0, 0, 0)

                    if UiPromptHasHoldModeCompleted(TradeHorse) then
                        TriggerServerEvent(
                            'bcc-horses:ProposeHorseTrade',
                            GetPlayerServerId(closestPlayer),
                            horseId
                        )
                        break
                    end
                end
            end
        end

        Wait(delay)
    end

    tradePromptLoopRunning = false
end

AddEventHandler('bcc-horses:TradeHorse', function()
    CreateThread(runTradePromptLoop)
end)

RegisterNetEvent('bcc-horses:ReceiveTradeProposal', function(senderId, horseName)
    local responseSent = false
    local tradeMenu

    local function respond(accepted, notification)
        if responseSent then return end

        responseSent = true
        TriggerServerEvent('bcc-horses:RespondToTradeProposal', senderId, accepted)

        if notification then
            Core.NotifyRightTip(notification, 4000)
        end
    end

    tradeMenu = FeatherMenu:RegisterMenu('bcc-horses:horse_trade_handshake', {
        top = '15%',
        left = '3%',
        ['720width'] = '400px',
        ['1080width'] = '500px',
        ['2kwidth'] = '600px',
        ['4kwidth'] = '800px',
        style = {},
        contentslot = {
            style = {
                height = '200px',
                ['min-height'] = '150px',
            },
        },
        draggable = true,
        canclose = true,
    }, {
        closed = function()
            respond(false, 'Transaction declined or closed.')
        end,
    })

    local tradePage = tradeMenu:RegisterPage('main_proposal_page')

    tradePage:RegisterElement('header', {
        value = 'Horse Trade',
        slot = 'header',
        style = { color = '#999' },
    })

    tradePage:RegisterElement('subheader', {
        value = horseName,
        slot = 'header',
        style = {
            ['font-size'] = '1.778vmin',
            color = '#CC9900',
        },
    })

    tradePage:RegisterElement('line', {
        id = 'my_horses_line',
        slot = 'header',
    })

    tradePage:RegisterElement('textdisplay', {
        value = ('The following horse is being offered to you:\n\nName: ^2%s^0\n\nDo you accept ownership of this animal?')
            :format(horseName),
        slot = 'content',
        style = {
            ['margin-top'] = '10px',
            ['margin-bottom'] = '15px',
            color = '#C0C0C0',
            ['font-variant'] = 'small-caps',
            ['font-size'] = '1.481vmin',
        },
    })

    tradePage:RegisterElement('button', {
        id = 'trade_ui_accept',
        label = '✅ Accept Horse',
        slot = 'content',
        style = { color = '#4CAF50' },
    }, function()
        respond(true)
        tradeMenu:Close()
    end)

    tradePage:RegisterElement('button', {
        id = 'trade_ui_decline',
        label = '❌ Decline Horse',
        slot = 'content',
        style = { color = '#F44336' },
    }, function()
        respond(false)
        tradeMenu:Close()
    end)

    tradeMenu:Open({ startupPage = tradePage })

    CreateThread(function()
        Wait(TRADE_PROPOSAL_TIMEOUT_MS)

        if not responseSent then
            tradeMenu:Close()
        end
    end)
end)

RegisterNetEvent('bcc-horses:ConfirmTradeExecutionComplete', function()
    FleeHorse()
end)
