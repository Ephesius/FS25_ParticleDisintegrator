--
-- HandToolParticleDisintegrator.lua
-- A hand tool specialization that removes fill type heaps from the terrain.
-- Modeled on HandToolHPWLance; swaps vehicle washing for terrain fill removal.
--


---Hand tool specialization for the Particle Disintegrator.
-- Raycasts forward from the tool, hits terrain, and removes fill in a small radius.
-- @category Handtools
HandToolParticleDisintegrator = {}

-- Resolved dynamically on first use since the spec_ key includes the mod name prefix.
HandToolParticleDisintegrator.specKey = nil

---Returns the spec table for this specialization on the given hand tool instance.
function HandToolParticleDisintegrator.getSpec(self)
    if HandToolParticleDisintegrator.specKey ~= nil then
        return self[HandToolParticleDisintegrator.specKey]
    end

    -- Find the key by scanning for a spec_ key containing "disintegrator".
    for k, v in pairs(self) do
        if type(k) == "string" and k:find("^spec_") and k:lower():find("particledisintegrator") then
            HandToolParticleDisintegrator.specKey = k
            Logging.info("[ParticleDisintegrator] Resolved spec key: %s", k)
            return v
        end
    end

    Logging.error("[ParticleDisintegrator] Could not find spec_ key for disintegrator!")
    return nil
end


---Registers XML schema paths for this specialization.
function HandToolParticleDisintegrator.registerXMLPaths(xmlSchema)
    xmlSchema:setXMLSpecializationType("HandToolParticleDisintegrator")

    -- Core tool settings.
    xmlSchema:register(XMLValueType.NODE_INDEX, "handTool.particleDisintegrator#raycastNode", "The node from which the raycast is fired", nil, false)
    xmlSchema:register(XMLValueType.FLOAT, "handTool.particleDisintegrator#raycastDistance", "The max distance in metres the raycast can reach", "5", false)
    xmlSchema:register(XMLValueType.FLOAT, "handTool.particleDisintegrator#radius", "The radius in metres around the hit point within which fill is removed", "0.5", false)
    xmlSchema:register(XMLValueType.FLOAT, "handTool.particleDisintegrator#litersPerSecond", "How many litres of fill to remove per second while active", "500", false)
    xmlSchema:register(XMLValueType.FLOAT, "handTool.particleDisintegrator#pricePerMinute", "The cost of using this tool for a minute", "0", false)
    xmlSchema:register(XMLValueType.NODE_INDEX, "handTool.particleDisintegrator#laserBeamNode", "The visual laser beam node, shown while active", nil, false)

    -- Optional fill type filter: space-separated list of fill type names. If omitted, all types are removed.
    xmlSchema:register(XMLValueType.STRING, "handTool.particleDisintegrator#fillTypes", "Space-separated fill type names to remove (empty = all)", nil, false)

    -- Sound.
    SoundManager.registerSampleXMLPaths(xmlSchema, "handTool.particleDisintegrator.sounds", "disintegrate")

    xmlSchema:setXMLSpecializationType()
end


---Registers specialization functions on the hand tool type.
function HandToolParticleDisintegrator.registerFunctions(handToolType)
    SpecializationUtil.registerFunction(handToolType, "onDisintegrateAction", HandToolParticleDisintegrator.onDisintegrateAction)
    SpecializationUtil.registerFunction(handToolType, "setIsDisintegrating", HandToolParticleDisintegrator.setIsDisintegrating)
    SpecializationUtil.registerFunction(handToolType, "onDisintegratorRaycastCallback", HandToolParticleDisintegrator.onDisintegratorRaycastCallback)
end


---Registers event listeners on the hand tool type.
function HandToolParticleDisintegrator.registerEventListeners(handToolType)
    SpecializationUtil.registerEventListener(handToolType, "onLoad", HandToolParticleDisintegrator)
    SpecializationUtil.registerEventListener(handToolType, "onDelete", HandToolParticleDisintegrator)
    SpecializationUtil.registerEventListener(handToolType, "onUpdate", HandToolParticleDisintegrator)
    SpecializationUtil.registerEventListener(handToolType, "onWriteUpdateStream", HandToolParticleDisintegrator)
    SpecializationUtil.registerEventListener(handToolType, "onReadUpdateStream", HandToolParticleDisintegrator)
    SpecializationUtil.registerEventListener(handToolType, "onRegisterActionEvents", HandToolParticleDisintegrator)
    SpecializationUtil.registerEventListener(handToolType, "onHeldEnd", HandToolParticleDisintegrator)
    SpecializationUtil.registerEventListener(handToolType, "onDebugDraw", HandToolParticleDisintegrator)
end


---No prerequisite specializations required.
function HandToolParticleDisintegrator.prerequisitesPresent(specializations)
    return true
end


---Called when the hand tool XML is loaded. Reads configuration from the XML file.
function HandToolParticleDisintegrator:onLoad(xmlFile, baseDirectory)
    local spec = HandToolParticleDisintegrator.getSpec(self)

    -- Read core settings from XML.
    spec.raycastNode = xmlFile:getValue("handTool.particleDisintegrator#raycastNode", nil, self.components, self.i3dMappings)
    spec.raycastDistance = xmlFile:getValue("handTool.particleDisintegrator#raycastDistance", 5)
    spec.radius = xmlFile:getValue("handTool.particleDisintegrator#radius", 0.5)
    spec.litersPerSecond = xmlFile:getValue("handTool.particleDisintegrator#litersPerSecond", 500)
    spec.pricePerSecond = xmlFile:getValue("handTool.particleDisintegrator#pricePerMinute", 0) / 60

    -- Parse optional fill type filter.
    spec.allowedFillTypes = nil
    local fillTypesStr = xmlFile:getValue("handTool.particleDisintegrator#fillTypes", nil)
    if fillTypesStr ~= nil then
        spec.allowedFillTypes = {}
        local names = string.split(fillTypesStr, " ")
        for _, name in ipairs(names) do
            local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(name)
            if fillTypeIndex ~= nil then
                spec.allowedFillTypes[fillTypeIndex] = true
            else
                Logging.warning("HandToolParticleDisintegrator: Unknown fill type '%s' in filter list, ignoring.", name)
            end
        end
        -- If no valid types were parsed, treat as "allow all".
        if next(spec.allowedFillTypes) == nil then
            spec.allowedFillTypes = nil
        end
    end

    -- Load sound (client-side only).
    if self.isClient then
        spec.disintegrateSample = g_soundManager:loadSampleFromXML(xmlFile, "handTool.particleDisintegrator.sounds", "disintegrate", baseDirectory, self.components, 0, AudioGroup.VEHICLE, self.i3dMappings, self)
    end

    -- Load the laser beam visual node and hide it initially.
    spec.laserBeamNode = xmlFile:getValue("handTool.particleDisintegrator#laserBeamNode", nil, self.components, self.i3dMappings)
    if spec.laserBeamNode ~= nil then
        setVisibility(spec.laserBeamNode, false)
    end

    -- Runtime state.
    spec.isActive = false
    spec.isActiveSent = false
    spec.terrainHitX = nil
    spec.terrainHitY = nil
    spec.terrainHitZ = nil
    spec.activateActionEventId = nil

    spec.dirtyFlag = self:getNextDirtyFlag()
end


---Cleanup on delete.
function HandToolParticleDisintegrator:onDelete()
    local spec = HandToolParticleDisintegrator.getSpec(self)
    g_soundManager:deleteSample(spec.disintegrateSample)
end


---Network sync: write activation state and hit coordinates.
function HandToolParticleDisintegrator:onWriteUpdateStream(streamId, connection, dirtyMask)
    local spec = HandToolParticleDisintegrator.getSpec(self)

    if streamWriteBool(streamId, spec.isActiveSent) then
        -- Client sends hit coordinates to the server.
        if connection:getIsServer() then
            if streamWriteBool(streamId, spec.terrainHitX ~= nil) then
                streamWriteFloat32(streamId, spec.terrainHitX)
                streamWriteFloat32(streamId, spec.terrainHitY)
                streamWriteFloat32(streamId, spec.terrainHitZ)
            end
        end
    end
end


---Network sync: read activation state and hit coordinates.
function HandToolParticleDisintegrator:onReadUpdateStream(streamId, timestamp, connection)
    local spec = HandToolParticleDisintegrator.getSpec(self)

    local isActive = streamReadBool(streamId)

    if isActive then
        -- Server reads hit coordinates from the client.
        if not connection:getIsServer() then
            if streamReadBool(streamId) then
                spec.terrainHitX = streamReadFloat32(streamId)
                spec.terrainHitY = streamReadFloat32(streamId)
                spec.terrainHitZ = streamReadFloat32(streamId)
            else
                spec.terrainHitX = nil
                spec.terrainHitY = nil
                spec.terrainHitZ = nil
            end
        end
    end

    self:setIsDisintegrating(isActive)
end


---Main update loop. Raycasts forward and clears fill from terrain at the hit point.
function HandToolParticleDisintegrator:onUpdate(dt)
    local carryingPlayer = self:getCarryingPlayer()
    if carryingPlayer == nil then
        return
    end

    local spec = HandToolParticleDisintegrator.getSpec(self)

    if not spec.isActive then
        return
    end

    -- On the owning client, raycast forward to find where we're aiming on the terrain.
    if carryingPlayer.isOwner and spec.raycastNode ~= nil then
        local x, y, z = getWorldTranslation(spec.raycastNode)
        local dirX, dirY, dirZ = localDirectionToWorld(spec.raycastNode, 0, 0, 1)

        spec.terrainHitX = nil
        spec.terrainHitY = nil
        spec.terrainHitZ = nil

        raycastClosest(x, y, z, dirX, dirY, dirZ, spec.raycastDistance, "onDisintegratorRaycastCallback", self, CollisionFlag.TERRAIN)

        -- Raise dirty flag so hit coordinates are sent to the server.
        self:raiseDirtyFlags(spec.dirtyFlag)
    end

    -- On the server, clear fill at the hit point.
    if self.isServer then
        local hitX = spec.terrainHitX
        local hitZ = spec.terrainHitZ

        if hitX ~= nil and hitZ ~= nil then
            local radius = spec.radius

            -- Define a parallelogram area around the hit point.
            local startX  = hitX - radius
            local startZ  = hitZ - radius
            local widthX  = hitX + radius
            local widthZ  = hitZ - radius
            local heightX = hitX - radius
            local heightZ = hitZ + radius

            DensityMapHeightUtil.clearArea(startX, startZ, widthX, widthZ, heightX, heightZ)

            -- Charge the player if a cost is configured.
            if spec.pricePerSecond > 0 then
                local farmId = carryingPlayer.farmId
                local price = spec.pricePerSecond * dt * 0.001
                g_farmManager:updateFarmStats(farmId, "expenses", price)
                g_currentMission:addMoney(-price, farmId, MoneyType.VEHICLE_RUNNING_COSTS)
            end
        end
    end
end


---Raycast callback. Captures the terrain hit point for fill removal.
function HandToolParticleDisintegrator:onDisintegratorRaycastCallback(nodeId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
    if nodeId == 0 then
        return false
    end

    -- We only care about terrain hits.
    if nodeId == g_currentMission.terrainRootNode then
        local spec = HandToolParticleDisintegrator.getSpec(self)
        spec.terrainHitX = x
        spec.terrainHitY = y
        spec.terrainHitZ = z
        return false
    end

    -- Continue checking if we haven't hit terrain yet.
    return true
end


---Toggles the disintegration state on and off.
function HandToolParticleDisintegrator:setIsDisintegrating(isActive)
    local spec = HandToolParticleDisintegrator.getSpec(self)

    if spec.isActive == isActive then
        return
    end

    local carryingPlayer = self:getCarryingPlayer()
    if carryingPlayer == nil then
        return
    end

    spec.isActive = isActive

    if carryingPlayer.isOwner then
        spec.isActiveSent = isActive
        self:raiseDirtyFlags(spec.dirtyFlag)
    end

    -- Play or stop the disintegration sound.
    if spec.isActive then
        g_soundManager:playSample(spec.disintegrateSample)
    else
        g_soundManager:stopSample(spec.disintegrateSample)
    end

    -- Show or hide the laser beam.
    if spec.laserBeamNode ~= nil then
        setVisibility(spec.laserBeamNode, spec.isActive)
    end
end


---Registers the activation input action.
function HandToolParticleDisintegrator:onRegisterActionEvents()
    if not self:getIsActiveForInput(true) then
        return
    end

    local spec = HandToolParticleDisintegrator.getSpec(self)

    local _, actionEventId = self:addActionEvent(InputAction.ACTIVATE_HANDTOOL, self, HandToolParticleDisintegrator.onDisintegrateAction, false, false, true, true, nil)
    spec.activateActionEventId = actionEventId
    g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_HIGH)
    g_inputBinding:setActionEventText(actionEventId, self.activateText)
end


---Input callback: toggles activation based on input value.
function HandToolParticleDisintegrator:onDisintegrateAction(_, inputValue)
    self:setIsDisintegrating(inputValue > 0)
end


---Deactivate when the tool is put away.
function HandToolParticleDisintegrator:onHeldEnd()
    self:setIsDisintegrating(false)
end


---Debug overlay.
function HandToolParticleDisintegrator:onDebugDraw(x, y, textSize)
    local spec = HandToolParticleDisintegrator.getSpec(self)

    y = DebugUtil.renderTextLine(x, y, textSize, string.format("isActive: %s", tostring(spec.isActive)))
    y = DebugUtil.renderTextLine(x, y, textSize, string.format("radius: %.2f m", spec.radius))

    if spec.terrainHitX ~= nil then
        y = DebugUtil.renderTextLine(x, y, textSize, string.format("Hit: %.1f, %.1f, %.1f", spec.terrainHitX, spec.terrainHitY, spec.terrainHitZ))
    end

    return y
end
