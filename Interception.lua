---------------------------------------------------------------------
-- Script Name: Player Intercept Course Detection
-- Description: This script detects potential intercept courses that 
--              other players may be taking towards the local player.
-- Author: whistledev
-- Version: 1.0.1 (beta)
---------------------------------------------------------------------

util.require_natives('1660775568-uno')

-- Constants
local INTERCEPT_DISTANCE = 20
local PROJECTION_INTERVAL = 5
local PLAYER_SPEED = 5 

local isModActive = false

function onModToggleChange(isOn)
    isModActive = isOn
    if isModActive then
        util.toast("Intercept Detection Mod activated!", TOAST_ABOVE_MAP)
    else
        util.toast("Intercept Detection Mod deactivated!", TOAST_ABOVE_MAP)
    end
end

local modToggle = menu.toggle(menu.my_root(), "Intercept Detection Mod", {}, "Toggle the Intercept Detection Mod on/off", onModToggleChange, false)

function checkInterceptCourses()
    local all_players = players.list()

    local local_player_pos = players.get_position(players.user())

    for _, player_id in ipairs(all_players) do
        -- Skip the local player
        if player_id ~= players.user() then
            local player_pos = players.get_position(player_id)
            local direction

            local waypoint_x, waypoint_y, waypoint_z, _ = players.get_waypoint(player_id)
            if waypoint_x and waypoint_y and waypoint_z then
                direction = v3.sub(v3.new(waypoint_x, waypoint_y, waypoint_z), player_pos)
            else
                local cam_pos = players.get_cam_pos(player_id)
                direction = v3.sub(cam_pos, player_pos)
            end

            direction = v3.normalise(direction)

            local projected_pos = v3.add(player_pos, v3.mul(direction, PLAYER_SPEED * PROJECTION_INTERVAL))

            local distance = v3.distance(local_player_pos, projected_pos)

            if distance < INTERCEPT_DISTANCE then
                util.toast("Player " .. players.get_name(player_id) .. " is on an intercept course!", TOAST_ABOVE_MAP)
            end
        end
    end
end

while true do
    if isModActive then
        checkInterceptCourses()
    end
    util.yield(1000)  -- Waits for 1 second before the next iteration. Adjust as needed.
end
