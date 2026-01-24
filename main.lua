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
-- Base64 encoding alphabet
local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function split(s, sep)
    local fields = {}
    
    local sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    
    return fields
end
local function itemIdFromItemLinkText(itemLinkText)
    local itemIdStr = string.sub(itemLinkText, 3)
    itemIdStr = split(itemIdStr, ",")
    itemIdStr = itemIdStr[1]
    return itemIdStr
end 

local function writeChatToTranslatingFile(channel, unit, isHostile, name, message, speakerInChatBound, specifyName, factionName, trialPosition)
    if name ~= nil and #message > 2 then
        -- Skip messages beginning with x and a space (looking for raid invites)
        if string.sub(message, 1, 1) == "x" and string.sub(message, 2, 2) == " " then return end  
        -- Replace item link text with the item's name
        local cleanedMessage = message
        count = 0
        while string.find(cleanedMessage, "|i") and count > 5 do 
            local beginIndex, _ = string.find(cleanedMessage, "|i")
            local _, endIndex = string.find(cleanedMessage, '0;')
            if beginIndex ~= nil and endIndex ~= nil then 
                local itemLinkText = string.sub(cleanedMessage, beginIndex, endIndex)
                local itemId = itemIdFromItemLinkText(itemLinkText)
                local itemInfo = api.Item:GetItemInfoByType(tonumber(itemId))
                
                local beforeLink = string.sub(cleanedMessage, 0, beginIndex)
                local afterLink = string.sub(cleanedMessage, endIndex + 1, #cleanedMessage)
                cleanedMessage = beforeLink .. "" .. itemInfo.name .. " " .. afterLink 
            end 
            count = count + 1
        end 
        cleanedMessage = string.gsub(cleanedMessage, "%|", "")
        api.File:Write("cant_read/to_be_translated.lua", {chatMsg=tostring"||||"..(channel).."||||"..name.."||||"..cleanedMessage.."||||"})
    end 
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
-- encoding
function enc(data)
    return ((data:gsub('.', function(x) 
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

-- decoding
function dec(data)
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
local function readLatestTranslatedMessage()
    local message = api.File:Read("cant_read/translated_messages")
    if message == nil then return end
    if message.chatMsg ~= nil then 
        -- api.Log:Info(tostring(message.chatMsg))
        local messageInfo = split(message.chatMsg, ";;;")
        -- api.Log:Info("Channel: " .. tostring(messageInfo[1]))
        -- api.Log:Info("Name: " .. tostring(messageInfo[2]))
        
        local channelNumber = tonumber(messageInfo[1])
        -- api.Log:Info(dec(messageInfo[3]))
        sendDecoratedChatByChannel(dec(messageInfo[3]), messageInfo[2], messageInfo[1])
        -- X2Chat:DispatchChatMessage(channelNumber, messageInfo[3])
        api.File:Write("cant_read/translated_messages", {})
    end 
end 
local function OnUpdate(dt)
    if clockTimer + dt > clockResetTime then
		clockTimer = 0	
        readLatestTranslatedMessage()
    end 
    clockTimer = clockTimer + dt
end 

local function OnLoad()
	local settings = api.GetSettings("cant_read")
    base64 = require('cant_read/base64/rfc')

	cantReadWindow = api.Interface:CreateEmptyWindow("cantReadWindow", "UIParent")

	function cantReadWindow:OnEvent(event, ...)
		if event == "CHAT_MESSAGE" then
            if arg ~= nil then 
                writeChatToTranslatingFile(unpack(arg))
            end 
        end 
	end
	cantReadWindow:SetHandler("OnEvent", cantReadWindow.OnEvent)
	cantReadWindow:RegisterEvent("CHAT_MESSAGE")

    api.On("UPDATE", OnUpdate)
	api.SaveSettings()
end

local function OnUnload()
	api.On("UPDATE", function() return end)
	cantReadWindow:ReleaseHandler("OnEvent")
end

cant_read_addon.OnLoad = OnLoad
cant_read_addon.OnUnload = OnUnload

return cant_read_addon
