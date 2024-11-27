local playersInfo, SaveLeave = {}, {}
local waitingRoomActive, waitingRoomDuration = true, 60
local queueConfigPath, information = "data/data.json", ""

Config.DiscordBotToken = ""


MySQL.ready(function()
    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS `js_queue` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `identifier` VARCHAR(255) NOT NULL UNIQUE,
            `points` INT DEFAULT 0
        )
    ]])
end)

local function GetIdentifiers(player)
    local identifiers = {}
    for i = 0, GetNumPlayerIdentifiers(player) - 1 do
        local raw = GetPlayerIdentifier(player, i)
        local tag, value = raw:match("^([^:]+):(.+)$")
        if tag and value then identifiers[tag] = value end
    end
    return identifiers
end

local function GetPlayerPoints(identifier, cb)
    if not identifier then cb(0) return end

    if SaveLeave[identifier] then
        cb(150000) 
        return
    end

    MySQL.Async.fetchAll("SELECT `points` FROM `js_queue` WHERE `identifier` = @identifier", {
        ['@identifier'] = identifier
    }, function(result)
        cb(result[1] and tonumber(result[1].points) or 0)
    end)
end


local function Main(name, role, avatarUrl)
    local cardBody = {
        {
            type = "Container",
            items = {
                {
                    type = "Image",
                    url = avatarUrl or Config.ServerIcon,
                    size = Config.DiscordAvatar.size or "medium",
                    horizontalAlignment = "center",
                    style = Config.DiscordAvatar.style or "person",
                },
                { type = "FactSet", facts = { { value = "" } } },
                { type = "TextBlock", text = ('Witaj, %s'):format(name), weight = "bolder", size = "extraLarge", horizontalAlignment = "center" },
                { type = "TextBlock", text = "Twój priorytet: " .. role, weight = "bolder", size = "medium", horizontalAlignment = "center" }
            }
        }
    }
    if information and information ~= "" then
        table.insert(cardBody[1].items, {
            type = "TextBlock",
            text = information,
            weight = "bolder",
            size = "medium",
            color = "accent",
            horizontalAlignment = "center"
        })
    end

    table.insert(cardBody[1].items, {
        type = "ActionSet",
        actions = {
            { type = "Action.Submit", id = "submit_join", title = "Dołącz do kolejki", style = "positive" },
            { type = "Action.OpenUrl", title = "Odwiedź nasz Sklep", url = Config.ShopURL, style = "positive" },
            { type = "Action.OpenUrl", title = "Dołącz na Discord", url = Config.DiscordURL, style = "positive" }
        }
    })

    return {
        ["$schema"] = "http://adaptivecards.io/schemas/adaptive-card.json",
        version = "1.6",
        type = "AdaptiveCard",
        body = cardBody
    }
end


local function Discord()
    return {
        ["$schema"] = "http://adaptivecards.io/schemas/adaptive-card.json",
        version = "1.0",
        type = "AdaptiveCard",
        body = {
            { type = "Image", url = Config.ServerIcon, horizontalAlignment = "Center", size = "Small" },
            { type = "TextBlock", text = "Musisz dołączyć na Discord", weight = "bolder",  size = "extraLarge", horizontalAlignment = "Center" },
            { type = "TextBlock", text = "Aby grać na naszym serwerze, musisz dołączyć na nasz Discord", size = "Medium", horizontalAlignment = "Center" },
            {
                type = "ActionSet",
                actions = {
                    { type = "Action.OpenUrl", title = "Dołącz na Discord", url = Config.DiscordURL, style = "positive" }
                }
            }
        }
    }
end

local function Steam()
    return {
        ["$schema"] = "http://adaptivecards.io/schemas/adaptive-card.json",
        version = "1.0",
        type = "AdaptiveCard",
        body = {
            { type = "Image", url = Config.ServerIcon, horizontalAlignment = "Center", size = "Small" },
            { type = "TextBlock", text = "Brak STEAM", weight = "bolder",  size = "extraLarge", horizontalAlignment = "Center" },
            { type = "TextBlock", text = "Uruchom klienta Steam i spróbuj ponownie", size = "Medium", horizontalAlignment = "Center" }
        }
    }
end

local function GetQueuePosition(source)
    for i, v in ipairs(playersInfo) do
        if v.source == source then
            return i, #playersInfo
        end
    end
    return false, #playersInfo
end

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()

    local identifiers = GetIdentifiers(src)
    local steamID = identifiers.steam
    local discordID = identifiers.discord

    if not steamID then
        deferrals.presentCard(json.encode(Steam()), function(_, _) end)
        CancelEvent()
        return
    end

    local function fetchDiscordAvatar(discordID, cb)
        local userID = discordID and discordID:match("%d+")
        if not userID then cb(false) return end

        PerformHttpRequest("https://discord.com/api/users/" .. userID, function(status, data)
            if status == 200 then
                local user = json.decode(data)
                if user and user.avatar and Config.DiscordAvatar.state then
                    local avatarUrl = string.format("https://cdn.discordapp.com/avatars/%s/%s.png", userID, user.avatar)
                    cb(avatarUrl)
                else
                    cb(false)
                end
            else
                cb(false)
            end
        end, "GET", "", { ["Authorization"] = "Bot " .. Config.DiscordBotToken })

    end

    fetchDiscordAvatar(discordID, function(avatarUrl)
        GetPlayerPoints(steamID, function(points)
            local role = Config.Roles[points] and Config.Roles[points].name or "Brak roli"
            local card = Main(name, role, avatarUrl)
            local presented = false
            local line = "―"

            CreateThread(function()
                while not presented do
                    local card = Main(name, role, avatarUrl)

                    line = (#line < 50) and (line .. "―") or "―"
                    card.body[1].items[2].facts[1].value = line

                    if information and information ~= "" then
                        for _, item in ipairs(card.body[1].items) do
                            if item.type == "TextBlock" and item.text == information then
                                item.text = information
                            end
                        end
                    end

                    deferrals.presentCard(json.encode(card))
                    Wait(5000)
                end
            end)

            deferrals.presentCard(json.encode(card), function(response, _)
                if response.submitId == "submit_join" then
                    presented = true
                    if not ProccessQueue({ steam = steamID, dc = discordID, points = points }, deferrals, src) then
                        CancelEvent()
                    end
                end
            end)
        end)
    end)
end)

local function SavePlayerToQueue(steamID)
    SaveLeave[steamID] = steamID
    Citizen.Wait(120000)
    SaveLeave[steamID] = nil
end

AddEventHandler("playerDropped", function(reason)
    local _source = source
    local identifier = GetIdentifiers(_source)
    SavePlayerToQueue(identifier.steam)
end)

CreateThread(function()
    Wait(waitingRoomDuration * 1000)
    waitingRoomActive = false
    lib.print.info("Blokada kolejki zdjeta, gracze moga aktualnie wchodzic na serwis")
end)

function RemoveFromQueue(source)
    for i, player in ipairs(playersInfo) do
        if player.source == source then
            table.remove(playersInfo, i)
            break
        end
    end
end

function AddPlayerToQueue(steamID, discordID, points, source, deferrals)
    local newPlayer = {
        steamID = steamID,
        discordID = discordID,
        points = points,
        source = source,
        joinTime = os.time(),
        deferrals = deferrals
    }

    local inserted = false
    for i, v in ipairs(playersInfo) do
        if v.points < points or (v.points == points and v.joinTime > newPlayer.joinTime) then
            table.insert(playersInfo, i, newPlayer)
            inserted = true
            break
        end
    end

    if not inserted then
        table.insert(playersInfo, newPlayer)
    end

    lib.print.info(("Dodano gracza do kolejki: SteamID: %s, Punkty: %d, Aktualna pozycja: %d"):format(steamID, points, GetQueuePosition(source)))
end

local function AreSlotsAvailable()
    local connectedPlayers = #GetPlayers()
    return connectedPlayers < Config.maxServerSlots
end

function ProccessQueue(data, deferrals, src)
    local roleConfig = Config.Roles[data.points]

    if roleConfig and roleConfig.bypass then
        lib.print.info(("Gracz: ^3%s (%s) ^0 przepuszczony w kolejce jako ^3(%s)"):format(GetPlayerName(src), data.points, roleConfig.name))
        RemoveFromQueue(src)
        deferrals.done()
        return true
    end

    local connectTime = os.time()
    PerformHttpRequest("https://discordapp.com/api/guilds/" .. Config.DiscordServerID .. "/members/" .. data.dc, function(err, text)
        if err == 200 and text then
            local member = json.decode(text)
            lib.print.info(("Gracz: ^3%s ^0 dołączył do kolejki. Discord: ^3%s"):format(GetPlayerName(src), member.user.username))
            AddPlayerToQueue(data.steam, data.dc, data.points, src, deferrals)

            CreateThread(function()
                while true do
                    if GetPlayerPing(src) == 0 then
                        RemoveFromQueue(src)
                        CancelEvent()
                        break
                    end

                    if waitingRoomActive then
                        local waitingTime = waitingRoomDuration - (os.time() - connectTime)
                        if waitingTime > 0 then
                            local card = GetMessage(src, connectTime, data.points)
                            card.body[1].items[2].text = "Za: " .. os.date("!%M:%S", waitingTime) .. " zostaniesz przeniesiony do kolejki."
                            card.body[1].items[3].text = "Oczekuj, serwer ma przerwę techniczna.."
                            deferrals.presentCard(json.encode(card))
                            Wait(1000)
                        else
                            waitingRoomActive = false
                            break
                        end
                    else
                        local card = GetMessage(src, connectTime, data.points)
                        deferrals.presentCard(json.encode(card))
                        Wait(1000)
                    end
                end
            end)
        else
            deferrals.presentCard(json.encode(Discord()))
            CancelEvent()
        end
    end, "GET", "", { ["Authorization"] = "Bot " .. Config.DiscordBotToken })

    return false
end

function GetMessage(playerId, connectTime, points)
    local role = Config.Roles[points] and Config.Roles[points].name or "Brak priorytetu"
    local queueTime = os.time() - connectTime
    local position, totalPlayers = GetQueuePosition(playerId)

    return {
        ["$schema"] = "http://adaptivecards.io/schemas/adaptive-card.json",
        version = "1.6",
        type = "AdaptiveCard",
        body = {
            {
                type = "Container",
                items = {
                    { type = "TextBlock", text = "Twój priorytet: " .. role, weight = "bolder", size = "medium", horizontalAlignment = "center" },
                    { type = "TextBlock", text = "Czas w kolejce: " .. os.date("!%M:%S", queueTime), weight = "light", size = "medium", horizontalAlignment = "center" },
                    { type = "TextBlock", text = position and ("Pozycja w kolejce: " .. position .. "/" .. totalPlayers) or "Błąd.", weight = "light", size = "medium", horizontalAlignment = "center" },
                    { type = "TextBlock", text = "Kolejka aktywna. Czekaj na swoją kolej.", weight = "light", size = "medium", horizontalAlignment = "center" },
                    {
                        type = "ActionSet",
                        actions = {
                            { type = "Action.OpenUrl", title = "Sklep", url = Config.ShopURL, style = "positive" },
                            { type = "Action.OpenUrl", title = "Discord", url = Config.DiscordURL, style = "positive" }
                        }
                    }
                }
            }
        }
    }
end

function ProcessFirstInQueue()
    if waitingRoomActive then
        return
    end

    if #playersInfo == 0 then
        return
    end

    if AreSlotsAvailable() then
        local firstPlayer = playersInfo[1]

        if firstPlayer and firstPlayer.source then
            local playerName = GetPlayerName(firstPlayer.source) or "Nieznany"
            local discordName = firstPlayer.discordID and ("DiscordID: " .. firstPlayer.discordID) or "Nie podano"
            local points = firstPlayer.points or 0

            lib.print.info(("Przepuszczono gracza: Nick Steam: %s, %s, Punkty: %d, Pozycja: 1"):format(playerName, discordName, points))
            
            if firstPlayer.deferrals then
                firstPlayer.deferrals.done() 
            end

            RemoveFromQueue(firstPlayer.source) 
        end
    end
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(10000)
        ProcessFirstInQueue()
    end
end)

local function LoadQueueConfig()
    local config = LoadResourceFile(GetCurrentResourceName(), queueConfigPath)
    if config then
        local data = json.decode(config)
        if data then
            waitingRoomActive = data.waitingRoomActive
            waitingRoomDuration = data.waitingRoomDuration
            information = data.information and data.information.name or information
            lib.print.info(("Wczytane informacje z daty: blokada: %s, czas: %d, Informacja przy wejściu: %s"):format(
                tostring(waitingRoomActive), waitingRoomDuration, information
            ))
        end
    end
end

local function SaveQueueConfig()
    local data = {
        waitingRoomActive = waitingRoomActive,
        waitingRoomDuration = waitingRoomDuration,
        information = { name = information }
    }
    SaveResourceFile(GetCurrentResourceName(), queueConfigPath, json.encode(data, { indent = true }), -1)
    lib.print.info("Zapisano nowy config")
end

lib.addCommand("queuecontrol", {
    help = "Zarządzanie poczekalnią i informacjami",
    params = {
        { name = "action", help = "start/stop/info", optional = false },
        { name = "action2", type = "longString", help = "czas w sekundach dla start lub nowa informacja dla info", optional = true }
    },
    restricted = "group.admin"
}, function(source, args)
    local action = args.action
    local action2 = args.action2

    if action == "start" then
        local duration = tonumber(action2)
        if duration and duration > 0 then
            waitingRoomDuration = duration
        end
        waitingRoomActive = true
        SaveQueueConfig()
        lib.print.info(("Blokowanie wejścia włączono na czas %s"):format(waitingRoomDuration))
    elseif action == "stop" then
        waitingRoomActive = false
        SaveQueueConfig()
        lib.print.info("Blokada wyłączona")
    elseif action == "info" then
        if action2 then
            information = action2
            SaveQueueConfig()
            lib.print.info(("Zaktualizowano informację na: %s"):format(information))
        end
    end
end)

lib.addCommand("setpriority", {
    help = "Nadaje priorytet graczowi",
    params = {
        {
            name = "identifier",
            type = "string",
            help = "SteamHex gracza (bez steam:)",
        },
        {
            name = "points",
            type = "number",
            help = "Ilość punktów priorytetu do nadania",
        }
    },
    restricted = "group.admin"
}, function(source, args)
    local identifier = args.identifier
    local points = tonumber(args.points)

    if not identifier or not points then
        return
    end

    MySQL.Async.execute(
        "INSERT INTO `js_queue` (`identifier`, `points`) VALUES (@identifier, @points) ON DUPLICATE KEY UPDATE `points` = @points",
        {
            ['@identifier'] = identifier,
            ['@points'] = points
        },
        function(rowsChanged)
            if rowsChanged > 0 then
                lib.print.info(("Priorytet gracza %s ustawiony na %d punktów"):format(identifier, points))
            end
        end
    )
end)

lib.addCommand("checkpriority", {
    help = "Sprawdza priorytety graczy w bazie danych oraz role z configu",
    params = {
        {
            name = "identifier",
            type = "string",
            help = "SteamHex gracza (bez steam:)",
            optional = true
        }
    },
    restricted = "group.admin"
}, function(source, args)
    local identifier = args.identifier
    local src = source

    local function notifyPlayer(msg, type)
        if src > 0 then
            TriggerClientEvent('ox_lib:notify', src, { title = "Informacja", description = msg, type = type or "info", duration = 8000 })
        else
            lib.print.info(msg) 
        end
    end

    if identifier then
        MySQL.Async.fetchAll(
            "SELECT `points` FROM `js_queue` WHERE `identifier` = @identifier",
            { ['@identifier'] = identifier },
            function(result)
                if result[1] then
                    local points = tonumber(result[1].points)
                    local role = Config.Roles[points] and Config.Roles[points].name or "Nieznana Rola"
                    notifyPlayer(("Gracz %s ma %d punktów (Rola: %s)"):format(identifier, points, role))
                else
                    notifyPlayer(("Nie znaleziono gracza z SteamHex: %s"):format(identifier), "error")
                end
            end
        )
    else
        local sortedRoles = {}
        for points, roleData in pairs(Config.Roles) do
            table.insert(sortedRoles, { points = points, name = roleData.name })
        end
        table.sort(sortedRoles, function(a, b) return a.points < b.points end)

        notifyPlayer("Lista roli wypisanych w configu:")
        for _, role in ipairs(sortedRoles) do
            notifyPlayer(("- %d punktów: %s"):format(role.points, role.name))
        end

        MySQL.Async.fetchAll("SELECT `identifier`, `points` FROM `js_queue`", {}, function(results)
            if #results > 0 then
                notifyPlayer("Lista graczy ktorzy posiadaja:")
                for _, row in ipairs(results) do
                    local role = Config.Roles[tonumber(row.points)] and Config.Roles[tonumber(row.points)].name or "Nieznana Rola"
                    notifyPlayer(("- %s: %d punktów (Rola: %s)"):format(row.identifier, row.points, role))
                end
            else
                notifyPlayer("Zaden gracz nie posiada priorytetu")
            end
        end)
    end
end)



LoadQueueConfig()
