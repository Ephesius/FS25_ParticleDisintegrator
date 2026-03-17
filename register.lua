--
-- register.lua
-- Registers the Particle Disintegrator hand tool specialization and type.
--

local modDirectory = g_currentModDirectory
local modName = g_currentModName


local function register()
    if g_handToolSpecializationManager == nil or g_handToolTypeManager == nil then
        Logging.error("[ParticleDisintegrator] Hand tool managers not available, cannot register.")
        return
    end

    -- Register the specialization.
    local specFilename = modDirectory .. "HandToolParticleDisintegrator.lua"
    g_handToolSpecializationManager:addSpecialization("particleDisintegrator", "HandToolParticleDisintegrator", specFilename, nil)

    -- Create the hand tool type.
    g_handToolTypeManager:addType("particleDisintegrator", "HandTool", "base", modName)

    -- Attach the storable specialization and the custom specialization.
    g_handToolTypeManager:addSpecialization("particleDisintegrator", "storable")
    g_handToolTypeManager:addSpecialization("particleDisintegrator", modName .. ".particleDisintegrator")

    Logging.info("[ParticleDisintegrator] Registration complete.")
end

register()
