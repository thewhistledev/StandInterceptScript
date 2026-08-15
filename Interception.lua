----------------------------------------------------------------------
-- Script Name: Player Intercept Course Detection
-- Description: Predicts whether another player's measured movement
--              is likely to cross dangerously close to the local player.
-- Author: whistledev
-- Version: 2.0.0
----------------------------------------------------------------------

local VERSION = "2.0.0"

local settings = {
    enabled = false,
    notifications = true,
    ignoreFriends = false,
    debugOverlay = false,
    interceptRadius = 25,
    predictionHorizon = 8,
    minClosingSpeed = 3,
    maxVerticalSeparation = 20,
    joinGraceMs = 5000,
    sampleIntervalMs = 250,
    alertCooldownMs = 10000,
    velocitySmoothing = 0.35
}

local runtime = {
    sessionActive = false,
    localSample = nil,
    players = {},
    lastScanAt = 0,
    lastStatusAt = 0,
    stats = {
        scans = 0,
        trackedPlayers = 0,
        activeThreats = 0,
        totalAlerts = 0,
        closestPredicted = math.huge,
        closestPlayer = "None",
        lastScanMs = 0
    }
}

local statusRefs = {}

local COLOUR_TEXT = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 }
local COLOUR_MUTED = { r = 0.75, g = 0.78, b = 0.82, a = 1.0 }
local COLOUR_DANGER = { r = 1.0, g = 0.30, b = 0.25, a = 1.0 }
local COLOUR_BACKGROUND = { r = 0.03, g = 0.03, b = 0.04, a = 0.72 }

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function copyPosition(position)
    return { x = position.x, y = position.y, z = position.z }
end

local function velocityBetween(current, previous, dt)
    return {
        x = (current.x - previous.x) / dt,
        y = (current.y - previous.y) / dt,
        z = (current.z - previous.z) / dt
    }
end

local function smoothVelocity(previous, current)
    if previous == nil then return current end

    local alpha = settings.velocitySmoothing
    local inverse = 1.0 - alpha
    return {
        x = previous.x * inverse + current.x * alpha,
        y = previous.y * inverse + current.y * alpha,
        z = previous.z * inverse + current.z * alpha
    }
end

local function updateSample(sample, position, now)
    local currentPosition = copyPosition(position)

    if sample == nil then
        return { position = currentPosition, time = now, velocity = nil }, nil, false
    end

    local dt = (now - sample.time) / 1000.0
    if dt < 0.05 then return sample, sample.velocity, false end

    -- A long scheduling gap makes the derived velocity meaningless.
    if dt > 3.0 then
        return { position = currentPosition, time = now, velocity = nil }, nil, false
    end

    local rawVelocity = velocityBetween(currentPosition, sample.position, dt)
    local smoothedVelocity = smoothVelocity(sample.velocity, rawVelocity)
    return { position = currentPosition, time = now, velocity = smoothedVelocity }, smoothedVelocity, true
end

local function resetTracking(resetCounters)
    runtime.localSample = nil
    runtime.players = {}
    runtime.lastScanAt = 0
    runtime.stats.trackedPlayers = 0
    runtime.stats.activeThreats = 0
    runtime.stats.closestPredicted = math.huge
    runtime.stats.closestPlayer = "None"
    runtime.stats.lastScanMs = 0

    if resetCounters then
        runtime.stats.scans = 0
        runtime.stats.totalAlerts = 0
    end
end

local function isPastJoinGrace(playerId, playerState, now)
    local discoveredFor = players.get_millis_since_discovery(playerId)
    if discoveredFor ~= nil then return discoveredFor >= settings.joinGraceMs end
    return (now - playerState.firstSeenAt) >= settings.joinGraceMs
end

local function predictClosestApproach(localPosition, localVelocity, playerPosition, playerVelocity)
    local rx = playerPosition.x - localPosition.x
    local ry = playerPosition.y - localPosition.y
    local rz = playerPosition.z - localPosition.z
    local rvx = playerVelocity.x - localVelocity.x
    local rvy = playerVelocity.y - localVelocity.y
    local rvz = playerVelocity.z - localVelocity.z
    local horizontalDistance = math.sqrt(rx * rx + ry * ry)
    local relativeSpeedSquared = rvx * rvx + rvy * rvy

    if horizontalDistance < 0.001 or relativeSpeedSquared < 0.01 then
        return { threat = false, closestDistance = horizontalDistance, verticalSeparation = math.abs(rz), timeToClosest = 0, closingSpeed = 0 }
    end

    local dot = rx * rvx + ry * rvy
    local closingSpeed = -dot / horizontalDistance

    if dot >= 0 then
        return { threat = false, closestDistance = horizontalDistance, verticalSeparation = math.abs(rz), timeToClosest = 0, closingSpeed = closingSpeed }
    end

    local timeToClosest = clamp(-dot / relativeSpeedSquared, 0, settings.predictionHorizon)
    local closestX = rx + rvx * timeToClosest
    local closestY = ry + rvy * timeToClosest
    local closestZ = rz + rvz * timeToClosest
    local closestDistance = math.sqrt(closestX * closestX + closestY * closestY)
    local verticalSeparation = math.abs(closestZ)
    local threat = closingSpeed >= settings.minClosingSpeed
        and closestDistance <= settings.interceptRadius
        and verticalSeparation <= settings.maxVerticalSeparation
        and timeToClosest > 0

    return {
        threat = threat,
        closestDistance = closestDistance,
        verticalSeparation = verticalSeparation,
        timeToClosest = timeToClosest,
        closingSpeed = closingSpeed
    }
end

local function alertForPlayer(playerId, prediction, now, playerState)
    local cooldownPassed = playerState.lastAlertAt == nil or (now - playerState.lastAlertAt) >= settings.alertCooldownMs

    if prediction.threat and (not playerState.threat or cooldownPassed) then
        playerState.lastAlertAt = now
        runtime.stats.totalAlerts = runtime.stats.totalAlerts + 1

        if settings.notifications then
            util.toast(string.format(
                "%s may intercept: %.1fm closest approach in %.1fs (closing %.1fm/s)",
                players.get_name(playerId), prediction.closestDistance, prediction.timeToClosest, prediction.closingSpeed
            ), TOAST_ABOVE_MAP)
        end
    end

    playerState.threat = prediction.threat
end

local function scanPlayers(now)
    local startedAt = util.current_time_millis()
    local userId = players.user()
    local localPosition = players.get_position(userId)
    local localVelocity
    local localReady
    runtime.localSample, localVelocity, localReady = updateSample(runtime.localSample, localPosition, now)

    local playerIds = players.list(false, not settings.ignoreFriends, true)
    local seenPlayers = {}
    runtime.stats.trackedPlayers = #playerIds
    runtime.stats.activeThreats = 0
    runtime.stats.closestPredicted = math.huge
    runtime.stats.closestPlayer = "None"

    for _, playerId in ipairs(playerIds) do
        seenPlayers[playerId] = true

        if players.exists(playerId) then
            local playerState = runtime.players[playerId]
            if playerState == nil then
                playerState = { firstSeenAt = now, sample = nil, threat = false, lastAlertAt = nil, prediction = nil }
                runtime.players[playerId] = playerState
            end

            local playerPosition = players.get_position(playerId)
            local playerVelocity
            local playerReady
            playerState.sample, playerVelocity, playerReady = updateSample(playerState.sample, playerPosition, now)

            if localReady and playerReady and isPastJoinGrace(playerId, playerState, now) then
                local prediction = predictClosestApproach(
                    runtime.localSample.position,
                    localVelocity,
                    playerState.sample.position,
                    playerVelocity
                )

                playerState.prediction = prediction
                if prediction.closestDistance < runtime.stats.closestPredicted then
                    runtime.stats.closestPredicted = prediction.closestDistance
                    runtime.stats.closestPlayer = players.get_name(playerId)
                end
                if prediction.threat then runtime.stats.activeThreats = runtime.stats.activeThreats + 1 end
                alertForPlayer(playerId, prediction, now, playerState)
            else
                playerState.threat = false
                playerState.prediction = nil
            end
        end
    end

    -- Also clears players hidden by an Ignore Friends setting change.
    for playerId in pairs(runtime.players) do
        if not seenPlayers[playerId] then runtime.players[playerId] = nil end
    end

    runtime.stats.scans = runtime.stats.scans + 1
    runtime.stats.lastScanMs = util.current_time_millis() - startedAt
end

local function updateStatusMenu()
    if statusRefs.session == nil then return end

    menu.set_value(statusRefs.session, runtime.sessionActive and "Active" or "Not in session")
    menu.set_value(statusRefs.tracked, tostring(runtime.stats.trackedPlayers))
    menu.set_value(statusRefs.threats, tostring(runtime.stats.activeThreats))
    menu.set_value(statusRefs.alerts, tostring(runtime.stats.totalAlerts))
    menu.set_value(statusRefs.scans, tostring(runtime.stats.scans))
    menu.set_value(statusRefs.scanTime, string.format("%d ms", runtime.stats.lastScanMs))

    if runtime.stats.closestPredicted == math.huge then
        menu.set_value(statusRefs.closest, "No prediction yet")
    else
        menu.set_value(statusRefs.closest, string.format("%s - %.1f m", runtime.stats.closestPlayer, runtime.stats.closestPredicted))
    end
end

local function drawDebugOverlay()
    if not settings.debugOverlay then return end

    local closestText = "No prediction"
    if runtime.stats.closestPredicted ~= math.huge then
        closestText = string.format("%s / %.1fm", runtime.stats.closestPlayer, runtime.stats.closestPredicted)
    end

    directx.draw_rect(0.015, 0.045, 0.34, 0.19, COLOUR_BACKGROUND)
    directx.draw_text(0.025, 0.055, "Intercept Detection v" .. VERSION, ALIGN_TOP_LEFT, 0.55, COLOUR_TEXT)
    directx.draw_text(0.025, 0.085, "Session: " .. (runtime.sessionActive and "active" or "waiting"), ALIGN_TOP_LEFT, 0.45, COLOUR_MUTED)
    directx.draw_text(0.025, 0.112, "Tracked players: " .. runtime.stats.trackedPlayers, ALIGN_TOP_LEFT, 0.45, COLOUR_MUTED)
    directx.draw_text(0.025, 0.139, "Active threats: " .. runtime.stats.activeThreats, ALIGN_TOP_LEFT, 0.45, runtime.stats.activeThreats > 0 and COLOUR_DANGER or COLOUR_MUTED)
    directx.draw_text(0.025, 0.166, "Closest approach: " .. closestText, ALIGN_TOP_LEFT, 0.45, COLOUR_MUTED)
    directx.draw_text(0.025, 0.193, "Scan time: " .. runtime.stats.lastScanMs .. "ms", ALIGN_TOP_LEFT, 0.45, COLOUR_MUTED)
end

-- Menu -----------------------------------------------------------------------

local root = menu.my_root()
menu.divider(root, "Intercept Detection v" .. VERSION)

local detectionMenu = menu.list(root, "Detection", {}, "Configure movement prediction and alert behaviour.")
menu.toggle(detectionMenu, "Enable Intercept Detection", { "interceptdetect" }, "Measure player movement and warn when a player is predicted to pass dangerously close to you.", function(on)
    settings.enabled = on
    resetTracking(false)

    if on then
        if util.is_session_started() then
            util.toast("Intercept Detection enabled.", TOAST_ABOVE_MAP)
        else
            util.toast("Intercept Detection enabled; waiting for a multiplayer session.", TOAST_ABOVE_MAP)
        end
    end
end, false)

menu.toggle(detectionMenu, "Notifications", { "interceptnotifications" }, "Show an above-map notification when a new intercept threat is detected.", function(on)
    settings.notifications = on
end, true)

menu.toggle(detectionMenu, "Ignore Friends", { "interceptignorefriends" }, "Exclude friends from intercept analysis.", function(on)
    settings.ignoreFriends = on
    resetTracking(false)
end, false)

menu.slider(detectionMenu, "Intercept Radius", { "interceptradius" }, "Predicted horizontal closest-approach distance required to count as an intercept, in metres.", 5, 100, 25, 1, function(value)
    settings.interceptRadius = value
end)

menu.slider(detectionMenu, "Prediction Horizon", { "intercepthorizon" }, "How many seconds into the future movement is projected.", 1, 30, 8, 1, function(value)
    settings.predictionHorizon = value
end)

menu.slider(detectionMenu, "Minimum Closing Speed", { "interceptclosingspeed" }, "Minimum relative closing speed required before a player can be treated as a threat, in metres per second.", 0, 50, 3, 1, function(value)
    settings.minClosingSpeed = value
end)

menu.slider(detectionMenu, "Vertical Tolerance", { "interceptvertical" }, "Maximum predicted vertical separation for an intercept, in metres. This suppresses players on bridges, aircraft, and stacked roads.", 1, 100, 20, 1, function(value)
    settings.maxVerticalSeparation = value
end)

local timingMenu = menu.list(root, "Timing & Stability", {}, "Tune sampling, smoothing, join grace, and notification cooldowns.")
menu.slider(timingMenu, "Sample Interval", { "interceptsample" }, "Milliseconds between movement samples. Lower values react faster but are noisier.", 100, 2000, 250, 50, function(value)
    settings.sampleIntervalMs = value
    resetTracking(false)
end)

menu.slider(timingMenu, "Velocity Smoothing", { "interceptsmoothing" }, "How strongly each new velocity sample affects the estimate. Higher values react faster; lower values filter jitter.", 5, 100, 35, 5, function(value)
    settings.velocitySmoothing = value / 100.0
end)

menu.slider(timingMenu, "Join Grace Period", { "interceptjoingrace" }, "Seconds to observe newly discovered players before allowing alerts.", 0, 30, 5, 1, function(value)
    settings.joinGraceMs = value * 1000
end)

menu.slider(timingMenu, "Alert Cooldown", { "interceptcooldown" }, "Minimum seconds between repeated alerts for the same player while a threat persists.", 1, 60, 10, 1, function(value)
    settings.alertCooldownMs = value * 1000
end)

local displayMenu = menu.list(root, "Display & Status", {}, "Live detector status and diagnostic information.")
menu.toggle(displayMenu, "Debug Overlay", { "interceptdebug" }, "Show live tracking and prediction statistics using Stand DirectX drawing.", function(on)
    settings.debugOverlay = on
end, false)

menu.action(displayMenu, "Reset Counters", { "interceptreset" }, "Reset scan and alert counters without changing settings.", function()
    resetTracking(true)
    util.toast("Intercept Detection counters reset.", TOAST_ABOVE_MAP)
end)

menu.divider(displayMenu, "Live Status")
statusRefs.session = menu.readonly(displayMenu, "Session", "Not in session")
statusRefs.tracked = menu.readonly(displayMenu, "Tracked Players", "0")
statusRefs.threats = menu.readonly(displayMenu, "Active Threats", "0")
statusRefs.closest = menu.readonly(displayMenu, "Closest Predicted Approach", "No prediction yet")
statusRefs.alerts = menu.readonly(displayMenu, "Alerts Raised", "0")
statusRefs.scans = menu.readonly(displayMenu, "Scans Completed", "0")
statusRefs.scanTime = menu.readonly(displayMenu, "Last Scan Time", "0 ms")

menu.apply_command_states()

-- Runtime --------------------------------------------------------------------

players.on_leave(function(playerId)
    runtime.players[playerId] = nil
end)

util.create_tick_handler(function()
    local now = util.current_time_millis()
    local sessionActive = util.is_session_started()

    if sessionActive ~= runtime.sessionActive then
        runtime.sessionActive = sessionActive
        resetTracking(false)
    end

    if settings.enabled and runtime.sessionActive and now - runtime.lastScanAt >= settings.sampleIntervalMs then
        runtime.lastScanAt = now
        scanPlayers(now)
    end

    if now - runtime.lastStatusAt >= 500 then
        runtime.lastStatusAt = now
        updateStatusMenu()
    end

    drawDebugOverlay()
end)
