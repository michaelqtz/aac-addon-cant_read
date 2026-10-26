local api = require("api")
local base64 = require('cant_read/base64/rfc')

local cant_read_addon = {
	name = "Can't Read",
	author = "Michaelqt",
	version = "1.0",
	desc = "Automatic chat translation to language of choice."
}

local cantReadWindow

local clockTimer = 0
local clockResetTime = 100

-- Chat messages are queued for the translator script (scripts/google_translate.ps1) in
-- to_be_translated.lua, and it queues translations back in translated_messages. Each entry has
-- a session (so restarts are noticed) and an increasing id, so a burst of chat isn't lost.
local QUEUE_FILE = "cant_read/to_be_translated.lua"
local TRANSLATIONS_FILE = "cant_read/translated_messages"
local MAX_QUEUED = 30
local session = nil
local nextMessageId = 0
local queuedMessages = {}
-- Last translation shown: translator script session and id
local shownSession = nil
local shownId = 0

-- Base64 encoding alphabet
local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function split(s, sep)
    local fields = {}

    local sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)

    return fields
end

-- Whole numbers as plain digits (tostring gives "1.2e+007" for big numbers in the client)
local function digits(number)
    return string.format("%.0f", number)
end

local function itemName(itemId)
    local ok, itemInfo = pcall(api.Item.GetItemInfoByType, api.Item, tonumber(itemId))
    if ok and itemInfo ~= nil and itemInfo.name ~= nil then return itemInfo.name end
    return ""
end

-- Turn chat markup into plain text for the translator
local function cleanMessage(message)
    -- Item links look like |i<item id>,<grade>,<data>; -> the item's name
    local cleaned = string.gsub(message, "|i(%d+),[^;]*;", itemName)
    -- Colour codes
    cleaned = string.gsub(cleaned, "|c%x%x%x%x%x%x%x%x", "")
    cleaned = string.gsub(cleaned, "|r", "")
    -- Pipes separate the fields in the queue file, and newlines would split its lines
    cleaned = string.gsub(cleaned, "[|\r\n]", " ")
    return cleaned
end

local function queueChatForTranslation(channel, unit, isHostile, name, message, speakerInChatBound, specifyName, factionName, trialPosition)
    if name == nil or message == nil or #message <= 2 then return end
    -- Skip messages beginning with x and a space (looking for raid invites)
    if string.sub(message, 1, 2) == "x " then return end
    nextMessageId = nextMessageId + 1
    table.insert(queuedMessages, "||||" .. session .. "||||" .. digits(nextMessageId) .. "||||" .. tostring(channel)
        .. "||||" .. string.gsub(name, "|", "") .. "||||" .. cleanMessage(message) .. "||||")
    while #queuedMessages > MAX_QUEUED do table.remove(queuedMessages, 1) end
    api.File:Write(QUEUE_FILE, queuedMessages)
end

-- Base 64 helper functions
-- This code was presented to me by the one and only Delarme.
--  Delarme saved me from a pretty fucking serious mental health episode
--  before the following code enlightened me on how to take UTF8 bullshit
--  languages like the glorious Hangul and Ruski ones and turn them into
--  strings that the game can read. I owe not only my full head of hair
--  to Delarme, but also my cat's life. Because who knows what I would've
--  done to everything I love if this code was not implemented.
-- working lua base64 codec (c) 2006-2008 by Alex Kloss
-- decoding
local function dec(data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end
local function sendDecoratedChatByChannel(message, sender, channel)
    -- TODO: Switch to using X2Locale:LocalizeUiText once available
    local prefix = " -> "
    if tostring(channel) == "-3" then 
        -- Incoming Whispers CMF_WHISPER
        local formatted = prefix .. sender .. " to you: " .. message
        api.Log:Info(formatted)
        return 
    elseif tostring(channel) == "0" then
        -- Local CMF_SAY
        local formatted = prefix .. "[" .. sender .. "]: " .. message
        api.Log:Info("|cFFfbfbfb" .. formatted)
        return
    elseif tostring(channel) == "1" then
        -- Shout CMF_ZONE
        local formatted = prefix .. "[" .. sender .. "]: " .. message
        api.Log:Info("|cFFee6890" .. formatted)
        return
    elseif tostring(channel) == "2" then
        -- Trade CMF_TRADE
        local formatted = prefix .. "[" .. sender .. "]: " .. message
        api.Log:Info("|cFF35edc8" .. formatted)
        return
    elseif tostring(channel) == "3" then
        -- Looking for Group CMF_FIND_PARTY
        local formatted = prefix .. "[" .. sender .. "]: " .. message
        api.Log:Info(formatted)
        return
    elseif tostring(channel) == "4" then
        -- Party CMF_PARTY
        local formatted = prefix .. "[" .. sender .. "]: " .. message
        api.Log:Info(formatted)
        return
    elseif tostring(channel) == "5" then
        -- Raid CMF_RAID
        local formatted = prefix .. "[" .. sender .. "]: " .. message
        api.Log:Info(formatted)
        return
    elseif tostring(channel) == "6" then
        -- Nation CMF_RACE 
        local formatted = prefix .. "[" .. sender .. "]: " .. message
        api.Log:Info("|cFF8eb131" .. formatted)
        return
    elseif tostring(channel) == "7" then
        -- Guild CMF_EXPEDITION
        local formatted = prefix .. "[" .. sender .. "]: " .. message
        api.Log:Info(formatted)
        return
    elseif tostring(channel) == "9" then
        -- Family CMF_FAMILY
        local formatted = prefix .. "[" .. sender .. "]: " .. message
        api.Log:Info(formatted)
        return
    elseif tostring(channel) == "10" then
        -- Command CMF_RAID_COMMAND
        local formatted = prefix .. "[" .. sender .. "]: " .. message
        api.Log:Info(formatted)
        return
    elseif tostring(channel) == "11" then
        -- Trial CMF_TRIAL
        local formatted = prefix .. "[" .. sender .. "]: " .. message
        api.Log:Info(formatted)
        return
    elseif tostring(channel) == "14" then
        -- Faction CMF_FACTION
        local formatted = prefix .. "[" .. sender .. "]: " .. message
        api.Log:Info("|cFFfcfc01" .. formatted)
        return
    else
        return nil
    end
end
-- Show every translation we haven't shown yet. Entries look like
-- "<session>;;;<id>;;;<channel>;;;<name>;;;<base64 translation>". With skip set, only
-- remember where we are (used at load, so old translations aren't shown again).
local function readNewTranslations(skip)
    local ok, entries = pcall(api.File.Read, api.File, TRANSLATIONS_FILE)
    if not ok or type(entries) ~= "table" then return end --> missing, or being written
    for _, entry in ipairs(entries) do
        local fields = split(tostring(entry), ";;;")
        local entryId = tonumber(fields[2])
        if fields[1] ~= shownSession then
            -- The translator script was restarted, its ids start over
            shownSession = fields[1]
            shownId = 0
        end
        if entryId ~= nil and entryId > shownId and #fields >= 5 then
            shownId = entryId
            if not skip then
                sendDecoratedChatByChannel(dec(fields[5]), fields[4], fields[3])
            end
        end
    end
end
local function OnUpdate(dt)
    if clockTimer + dt > clockResetTime then
		clockTimer = 0
        readNewTranslations(false)
    end
    clockTimer = clockTimer + dt
end

local function OnLoad()
	local settings = api.GetSettings("cant_read")
    session = digits(api.Time:GetUiMsec())
    nextMessageId = 0
    queuedMessages = {}
    readNewTranslations(true)

	cantReadWindow = api.Interface:CreateEmptyWindow("cantReadWindow", "UIParent")

	function cantReadWindow:OnEvent(event, ...)
		if event == "CHAT_MESSAGE" then
            queueChatForTranslation(...)
        end
	end
	cantReadWindow:SetHandler("OnEvent", cantReadWindow.OnEvent)
	cantReadWindow:RegisterEvent("CHAT_MESSAGE")

    api.On("UPDATE", OnUpdate)
	api.SaveSettings()
end

local function OnUnload()
	api.On("UPDATE", function() return end)
	if cantReadWindow ~= nil then
		cantReadWindow:ReleaseHandler("OnEvent")
	end
end

cant_read_addon.OnLoad = OnLoad
cant_read_addon.OnUnload = OnUnload

return cant_read_addon
