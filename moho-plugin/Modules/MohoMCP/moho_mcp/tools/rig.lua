-- rig.lua
-- Generic cutout-character construction for Moho bone layers.

local rig = {}

local function vector2(x, y)
    local value = LM.Vector2:new_local()
    value.x = x
    value.y = y
    return value
end

local function vector3(x, y, z)
    local value = LM.Vector3:new_local()
    value.x = x
    value.y = y
    value.z = z or 0
    return value
end

local function validate(params)
    if not params or type(params.name) ~= "string" or params.name == "" then
        return nil, "name must be a non-empty string"
    end
    if type(params.bones) ~= "table" or #params.bones == 0 then
        return nil, "bones must be a non-empty array"
    end
    if type(params.parts) ~= "table" or #params.parts == 0 then
        return nil, "parts must be a non-empty array"
    end
    if #params.bones > 100 or #params.parts > 100 then
        return nil, "cutout rigs are limited to 100 bones and 100 parts"
    end
    return true
end

local function setBoneRestState(skeleton, bone, boneId, spec, worldAngles)
    local parentId = spec.parentId or -1
    if parentId >= boneId or parentId < -1 then
        error("bone " .. tostring(boneId) .. " has an invalid parentId")
    end

    bone:SetName(spec.name or ("Bone " .. tostring(boneId + 1)))
    bone.fParent = parentId
    bone.fAnimParent:SetValue(0, parentId)

    local position = vector2(spec.x or 0, spec.y or 0)
    if parentId >= 0 then
        skeleton:UpdateBoneMatrix()
        local inverse = LM.Matrix:new_local()
        inverse:Set(skeleton:Bone(parentId).fRestMatrix)
        inverse:Invert()
        inverse:Transform(position)
    end

    local worldAngle = spec.angle or 0
    local parentWorldAngle = parentId >= 0 and worldAngles[parentId + 1] or 0
    local localAngle = worldAngle - parentWorldAngle

    bone.fAnimPos:SetValue(0, position)
    bone.fAnimAngle:SetValue(0, localAngle)
    bone.fLength = spec.length or 0.1
    bone.fPos:Set(position)
    bone.fTempPos:Set(position)
    bone.fAngle = localAngle
    bone.fTempAngle = localAngle
    bone.fTempLength = bone.fLength
    bone.fSelected = false
    worldAngles[boneId + 1] = worldAngle
    skeleton:UpdateBoneMatrix()
end

--- Create a bone layer, bones, image layers, and layer-to-bone bindings.
-- Coordinates use Moho document space. Parts are ordered back-to-front.
function rig.createCutout(moho, params)
    local valid, validationError = validate(params)
    if not valid then
        return nil, validationError
    end
    if not moho or not moho.document then
        return nil, "No active document"
    end

    local prepared, prepError = pcall(function()
        moho.document:PrepMultiUndo(true)
    end)
    if not prepared then
        return nil, "Failed to prepare undo: " .. tostring(prepError)
    end

    local ok, result = pcall(function()
        local layer = moho:CreateNewLayer(MOHO.LT_BONE, false)
        local boneLayer = moho:LayerAsBone(layer)
        if not boneLayer then
            error("Moho did not create a bone layer")
        end
        layer:SetName(params.name)

        local skeleton = boneLayer:Skeleton()
        local worldAngles = {}
        local boneNames = {}
        local createdBones = {}
        for index, spec in ipairs(params.bones) do
            local boneId = index - 1
            local bone = skeleton:AddBone(0)
            setBoneRestState(skeleton, bone, boneId, spec, worldAngles)
            boneNames[bone:Name()] = boneId
            createdBones[#createdBones + 1] = {
                id = boneId,
                name = bone:Name(),
                parentId = bone.fParent,
            }
        end

        local createdParts = {}
        for _, spec in ipairs(params.parts) do
            if type(spec.name) ~= "string" or spec.name == "" then
                error("every part needs a non-empty name")
            end
            if type(spec.path) ~= "string" or spec.path == "" then
                error("part " .. spec.name .. " needs an absolute image path")
            end
            local file = io.open(spec.path, "rb")
            if not file then
                error("image file not found: " .. spec.path)
            end
            file:close()

            local partLayer = moho:CreateNewLayer(MOHO.LT_IMAGE, false)
            local imageLayer = moho:LayerAsImage(partLayer)
            if not imageLayer then
                error("Moho did not create image layer " .. spec.name)
            end
            imageLayer:SetSourceImage(spec.path)
            partLayer:SetName(spec.name)
            moho:PlaceLayerInGroup(partLayer, boneLayer, true, false)

            partLayer.fTranslation:SetValue(0, vector3(spec.x or 0, spec.y or 0, 0))
            partLayer.fRotationZ:SetValue(0, spec.rotation or 0)
            local scale = spec.scale or 1
            partLayer.fScale:SetValue(0, vector3(scale, scale, 1))

            local boneId = -1
            if spec.boneName ~= nil then
                boneId = boneNames[spec.boneName]
                if boneId == nil then
                    error("unknown boneName for part " .. spec.name .. ": " .. tostring(spec.boneName))
                end
                partLayer:SetLayerParentBone(boneId)
            end

            createdParts[#createdParts + 1] = {
                id = moho.document:LayerAbsoluteID(partLayer),
                name = spec.name,
                boneId = boneId,
                pixelWidth = imageLayer:PixelWidth(),
                pixelHeight = imageLayer:PixelHeight(),
            }
        end

        skeleton:UpdateBoneMatrix()
        moho:SetSelLayer(layer)
        moho.document:SetDirty()
        moho:UpdateUI()

        return {
            success = true,
            layerId = moho.document:LayerAbsoluteID(layer),
            name = params.name,
            bones = createdBones,
            parts = createdParts,
        }
    end)

    if not ok then
        return nil, "Failed to create cutout rig: " .. tostring(result)
    end
    return result
end

return rig
