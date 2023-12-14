----------------------------------------------------------------------
-- Script Name: Player Intercept Course Detection
-- Description: This script detects potential intercept courses that 
--              other players may be taking towards the local player.
-- Author: whistledev
-- Version: 1.0.5 (beta)
----------------------------------------------------------------------

util.require_natives('1660775568-uno')

-- Constants
local INTERCEPT_DISTANCE = 20
local PROJECTION_INTERVAL = 5
local PLAYER_SPEED = 5 
local DEBUG_MODE = false
local isModActive = false
local policeBlips = false

local modToggleRef = nil

-- Utility functions (Created nessessary functions to make the code more readable)

-- Checks boolean and returns string for true or false, lua doesnt have it so i made it have it lol.
function ternary(condition, trueValue, falseValue)
    if condition then
        return trueValue
    else
        return falseValue
    end
end

-- Checks if the player is in a multiplayer session
function isMP()
    if NETWORK.NETWORK_IS_SESSION_STARTED() then
        return true
    else
        return false
    end
end

-- Debug information
local debugInfo = {
    playersDetected = 0,
    closestPlayerDistance = math.huge,
    interceptsDetected = 0
}


function onModToggleChange(isOn)
    isModActive = isOn
    if isMP() == false then
        util.toast("You are not in Multiplayer!", TOAST_ABOVE_MAP)
        modToggleRef.value = false
    else if isModActive then
        util.toast("Intercept Detection Mod activated!", TOAST_ABOVE_MAP)
    else
        util.toast("Intercept Detection Mod deactivated!", TOAST_ABOVE_MAP)
    end
    end
end

function onDebugToggleChange(isOn)
    DEBUG_MODE = isOn
    if DEBUG_MODE then
        util.toast("Debug Mode activated!", TOAST_ABOVE_MAP)
        util.create_tick_handler(function()
            displayDebugInfo(255)
        end)
    else
        util.toast("Debug Mode deactivated!", TOAST_ABOVE_MAP)
        displayDebugInfo(0)
    end
end


local modToggle = menu.toggle(menu.my_root(), "Intercept Detection Mod", {}, "Toggle the Intercept Detection Mod on/off", onModToggleChange, false)
local debugToggle = menu.toggle(menu.my_root(), "Debug Mode", {}, "Toggle Debug Mode on/off", onDebugToggleChange, false)
modToggleRef = modToggle


function checkInterceptCourses()
    local all_players = players.list()

    local local_player_pos = players.get_position(players.user())

    for _, player_id in ipairs(all_players) do
        -- Skip the local player
        if player_id ~= players.user() then
            local player_pos = players.get_position(player_id)
            
            local direction = v3.sub(local_player_pos, player_pos)
            direction = v3.normalise(direction)

            local projected_pos = v3.add(player_pos, v3.mul(direction, PLAYER_SPEED * PROJECTION_INTERVAL))
            local distance = v3.distance(local_player_pos, projected_pos)

            if distance < debugInfo.closestPlayerDistance then
                debugInfo.closestPlayerDistance = distance
            end

            if distance < INTERCEPT_DISTANCE then
                debugInfo.interceptsDetected = debugInfo.interceptsDetected + 1
                util.toast("Player " .. players.get_name(player_id) .. " is on an intercept course!", TOAST_ABOVE_MAP)
            end
        end
    end

    debugInfo.playersDetected = #all_players - 1  -- excluding the local player
end

function displayDebugInfo(opacity)
    if DEBUG_MODE then
        local yOffset = 0.05
        directx.draw_text(0.01, yOffset, "Players Detected: " .. debugInfo.playersDetected, ALIGN_TOP_LEFT, 1.0, 255, 255, 255, opacity)
        yOffset = yOffset + 0.05
        directx.draw_text(0.01, yOffset, "Closest Player Distance: " .. string.format("%.2f", debugInfo.closestPlayerDistance), ALIGN_TOP_LEFT, 1.0, 255, 255, 255, opacity)
        yOffset = yOffset + 0.05
        directx.draw_text(0.01, yOffset, "Intercepts Detected: " .. debugInfo.interceptsDetected, ALIGN_TOP_LEFT, 1.0, 255, 255, 255, opacity)
        yOffset = yOffset + 0.05
        directx.draw_text(0.01, yOffset, "In a Session?: " .. ternary(isMP(), "Yes", "No"), ALIGN_TOP_LEFT, 1.0, 255, 255, 255, opacity)
    end
    -- You can add more debug information here if needed
    
end


while true do
    if isModActive then
        checkInterceptCourses()
    end
    util.yield(1000)  -- Waits for 1 second before the next iteration. Adjust as needed.
end
