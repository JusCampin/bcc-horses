local MAX_TRADE_DISTANCE <const> = 5.0
local TRADE_TIMEOUT_SECONDS <const> = 60
local sessionsByRecipient = {}
local recipientBySender = {}

local function playersAreNearby(firstSource, secondSource)
    local firstPed = GetPlayerPed(firstSource)
    local secondPed = GetPlayerPed(secondSource)
    if firstPed == 0 or secondPed == 0 then return false end

    return #(GetEntityCoords(firstPed) - GetEntityCoords(secondPed)) <= MAX_TRADE_DISTANCE
end

local function clearSession(recipientSource, session)
    sessionsByRecipient[recipientSource] = nil
    if session then recipientBySender[session.senderSource] = nil end
end

RegisterNetEvent('bcc-horses:ProposeHorseTrade', function(targetServerId, horseId)
    local src = source
    local recipientSource = tonumber(targetServerId)
    local targetHorseId = tonumber(horseId)
    if not recipientSource or recipientSource == src or not targetHorseId then return end
    if not playersAreNearby(src, recipientSource) then return end

    local senderCharacter, senderCharId = ServerUtils.getCharacter(src, 'horse trade proposal')
    local _, recipientCharId = ServerUtils.getCharacter(recipientSource, 'horse trade recipient')
    if not senderCharacter or not senderCharId or not recipientCharId then return end

    local existing = sessionsByRecipient[recipientSource]
    if existing then
        if os.time() - existing.createdAt < TRADE_TIMEOUT_SECONDS then return end
        clearSession(recipientSource, existing)
    end

    local outgoingRecipient = recipientBySender[src]
    if outgoingRecipient then
        local outgoingSession = sessionsByRecipient[outgoingRecipient]
        if outgoingSession and os.time() - outgoingSession.createdAt < TRADE_TIMEOUT_SECONDS then return end
        clearSession(outgoingRecipient, outgoingSession)
        recipientBySender[src] = nil
    end

    MySQL.scalar(
        'SELECT `name` FROM `bcc_player_horses` WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0 LIMIT 1',
        { targetHorseId, senderCharId },
        function(horseName)
            if type(horseName) ~= 'string' or not playersAreNearby(src, recipientSource) then return end

            local session = {
                senderSource = src,
                horseId = targetHorseId,
                senderCharId = senderCharId,
                senderFullName = ('%s %s'):format(senderCharacter.firstname or 'Unknown', senderCharacter.lastname or 'Player'),
                createdAt = os.time()
            }

            sessionsByRecipient[recipientSource] = session
            recipientBySender[src] = recipientSource
            TriggerClientEvent('bcc-horses:ReceiveTradeProposal', recipientSource, src, horseName)
        end
    )
end)

RegisterNetEvent('bcc-horses:RespondToTradeProposal', function(senderId, accepted)
    local recipientSource = source
    local session = sessionsByRecipient[recipientSource]
    if not session or session.senderSource ~= tonumber(senderId) then return end
    clearSession(recipientSource, session)

    if os.time() - session.createdAt >= TRADE_TIMEOUT_SECONDS or not playersAreNearby(session.senderSource, recipientSource) then
        return
    end

    if accepted ~= true then
        Core.NotifyRightTip(session.senderSource, 'The recipient declined your transfer proposal.', 4000)
        return
    end

    local recipientCharacter, recipientCharId = ServerUtils.getCharacter(recipientSource, 'accepted horse trade')
    if not recipientCharacter or not recipientCharId then return end

    MySQL.scalar(
        'SELECT COUNT(*) FROM `bcc_player_horses` WHERE `charid` = ? AND `is_dead` = 0',
        { recipientCharId },
        function(count)
            if (tonumber(count) or 0) >= ServerUtils.getHorseLimit(recipientSource) then
                Core.NotifyRightTip(recipientSource, _U('horseLimit') or 'Your stable is full.', 4000)
                Core.NotifyRightTip(session.senderSource, 'The recipient stable is full.', 4000)
                return
            end

            MySQL.transaction({
                {
                    query = 'DELETE FROM `bcc_horse_tack_loadouts` WHERE `horse_id` = ?',
                    values = { session.horseId }
                },
                {
                    query = 'UPDATE `bcc_player_horses` SET `charid` = ?, `is_selected` = 0 WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0',
                    values = { recipientCharId, session.horseId, session.senderCharId }
                }
            }, function(success)
                    if not success then return end

                    HorseXpCache[session.horseId] = nil
                    EmitHorseServerLifecycleEvent('bcc-horses:server:horseOwnerChanged', {
                        id = session.horseId,
                        previousOwnerCharId = session.senderCharId,
                        ownerCharId = recipientCharId,
                        previousOwnerSource = session.senderSource,
                        ownerSource = recipientSource,
                    })
                    local recipientName = ('%s %s'):format(recipientCharacter.firstname or 'Unknown', recipientCharacter.lastname or 'Player')
                    Core.NotifyRightTip(session.senderSource, (_U('youGave') or 'You gave ') .. recipientName .. (_U('aHorse') or ' a horse.'), 4000)
                    Core.NotifyRightTip(recipientSource, session.senderFullName .. (_U('gaveHorse') or ' gave you a horse.'), 4000)
                    TriggerClientEvent('bcc-horses:ConfirmTradeExecutionComplete', session.senderSource)
                    TriggerClientEvent('bcc-horses:ForceRosterRefresh', recipientSource)
                    LogToDiscord(session.senderCharId, ('Traded horse ID %d to character: %s'):format(session.horseId, recipientCharId))
                end)
        end
    )
end)

AddEventHandler('playerDropped', function()
    local src = source
    local recipient = recipientBySender[src]
    if recipient then clearSession(recipient, sessionsByRecipient[recipient]) end

    local session = sessionsByRecipient[src]
    if session then clearSession(src, session) end
end)
