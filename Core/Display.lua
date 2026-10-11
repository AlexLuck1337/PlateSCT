local _, BD = ...
local L = BD.L
local Anim = BD.Anim

local ICON_GAP = 4
local CRIT_LABEL_GAP = 3

local function AnchorCritLabel(frame)
    if frame.critLabel and frame.critLabel:IsShown() then
        frame.critLabel:SetPoint("BOTTOMLEFT", frame.text, "BOTTOMRIGHT", CRIT_LABEL_GAP, 0)
    end
end

local function ScaleSpawnLanes(lanes, scale)
    if not lanes or scale == 1 then
        return lanes
    end
    local scaled = {}
    for index, lane in ipairs(lanes) do
        scaled[index] = { lane[1] * scale, lane[2] * scale }
    end
    return scaled
end

local function ApplyTextLayout(frame, fontSize, fontPath, fontFlags, preset, layoutOpts)
    layoutOpts = layoutOpts or {}
    local showIcon = layoutOpts.showIcon
    local iconSize = layoutOpts.iconSize
    local iconTexture = layoutOpts.iconTexture
    local iconPosition = layoutOpts.iconPosition or "left"
    local showCritLabel = layoutOpts.showCritLabel
    local r = layoutOpts.r or 1
    local g = layoutOpts.g or 1
    local b = layoutOpts.b or 1

    frame.text:ClearAllPoints()
    frame.icon:ClearAllPoints()
    if frame.critLabel then
        frame.critLabel:ClearAllPoints()
    end

    local critLabelW = 0
    if showCritLabel and frame.critLabel then
        local critSize = math.max(8, math.floor(fontSize * 0.55 + 0.5))
        BD.SafeSetFont(frame.critLabel, fontPath, critSize, fontFlags)
        frame.critLabel:SetText(L["CRITICAL"])
        frame.critLabel:SetTextColor(r, g, b, 1)
        if preset.shadowOffset then
            frame.critLabel:SetShadowOffset(preset.shadowOffset[1], preset.shadowOffset[2])
            frame.critLabel:SetShadowColor(0, 0, 0, 1)
        else
            frame.critLabel:SetShadowOffset(0, 0)
        end
        frame.critLabel:Show()
        critLabelW = (frame.critLabel:GetStringWidth() or 0) + CRIT_LABEL_GAP
    elseif frame.critLabel then
        frame.critLabel:SetText("")
        frame.critLabel:Hide()
    end

    local resolvedIcon = showIcon and iconTexture
    if resolvedIcon then
        local size = iconSize or math.max(12, math.floor((fontSize * 1.1) + 0.5))
        frame.icon:SetSize(size, size)
        local ok = pcall(frame.icon.SetTexture, frame.icon, resolvedIcon)
        if not ok then
            resolvedIcon = nil
        end
    end

    if not resolvedIcon then
        frame.icon:SetTexture(nil)
        frame.icon:Hide()
        frame.text:SetPoint("CENTER", frame, "CENTER", -critLabelW * 0.5, 0)
        AnchorCritLabel(frame)
        return
    end

    frame.icon:SetVertexColor(1, 1, 1, 1)
    frame.icon:Show()
    local size = frame.icon:GetWidth() or iconSize

    local pos = iconPosition
    if pos == "right" then
        local shift = (size + ICON_GAP + critLabelW) * 0.5
        frame.text:SetPoint("CENTER", frame, "CENTER", -shift, 0)
        AnchorCritLabel(frame)
        if showCritLabel and frame.critLabel then
            frame.icon:SetPoint("LEFT", frame.critLabel, "RIGHT", ICON_GAP, 0)
        else
            frame.icon:SetPoint("LEFT", frame.text, "RIGHT", ICON_GAP, 0)
        end
    elseif pos == "top" then
        frame.text:SetPoint("CENTER", frame, "CENTER", -critLabelW * 0.5, -(size + ICON_GAP) * 0.5)
        AnchorCritLabel(frame)
        frame.icon:SetPoint("BOTTOM", frame.text, "TOP", 0, ICON_GAP)
    elseif pos == "bottom" then
        frame.text:SetPoint("CENTER", frame, "CENTER", -critLabelW * 0.5, (size + ICON_GAP) * 0.5)
        AnchorCritLabel(frame)
        frame.icon:SetPoint("TOP", frame.text, "BOTTOM", 0, -ICON_GAP)
    else
        local shift = (size + ICON_GAP - critLabelW) * 0.5
        frame.text:SetPoint("CENTER", frame, "CENTER", shift, 0)
        frame.icon:SetPoint("RIGHT", frame.text, "LEFT", -ICON_GAP, 0)
        AnchorCritLabel(frame)
    end
end

local function ApplyMotionSpawnParams(frame, motionStyle, floatDistance)
    frame.motionStyle = motionStyle or "platesct"
    if frame.motionStyle == "fountain" then
        frame.arcX = Anim.NextFountainArcX()
        frame.arcTop = math.random(10, 28)
        frame.arcBottom = -math.random(8, 22)
    elseif frame.motionStyle == "rainfall" then
        frame.rainDistance = (floatDistance or 20) * 1.2
        frame.rainX = math.random(-18, 18)
        frame.rainStartY = math.random(4, 12)
    end
end

local function ConfigureFrameCommon(self, frame, preset, isCrit, hitKind, isIncoming)
    frame.isCrit = isCrit and true or false
    frame.incoming = isIncoming and true or false
    frame.hitKind = hitKind or (isCrit and "crit" or "hit")

    local durationMult = preset.durationMult
    if frame.isCrit and preset.critDurationMult then
        durationMult = durationMult * preset.critDurationMult
    end
    frame.duration = (self.db.duration or self.DEFAULTS.duration) * durationMult
    frame.floatDistance = (self.db.floatDistance or self.DEFAULTS.floatDistance) * preset.floatMult
    frame.scrollSpeed = self.db.scrollSpeed or self.DEFAULTS.scrollSpeed or 1
    frame.baseAlpha = 1
    frame.popScale = preset.popScale
    frame.popDuration = preset.popDuration
    frame.fadePower = preset.fadePower
    frame.fadeMode = preset.fadeMode
    frame.fadeInRatio = preset.fadeInRatio or 0
    frame.driftX = preset.driftX
    frame.floatEase = preset.floatEase
    frame.animMode = preset.animMode
    frame.critsHold = preset.critsHold and true or false
    frame.critRestScale = preset.critRestScale or 1.4
    frame.critPopStartScale = preset.critPopStartScale or 0.72
    frame.critSlapScale = preset.critSlapScale or 1.50
    frame.critSlapDuration = preset.critSlapDuration or 0
    frame.critSlapDrop = preset.critSlapDrop or 0
    frame.critPowStartScale = preset.critPowStartScale or 1
    frame.critPowPeakScale = preset.critPowPeakScale or 2.0
    frame.critPowDuration = preset.critPowDuration or 0.22

    -- Scale Modern-style spawn lanes with font size so larger numbers spread out.
    local defaultFontSize = self.DEFAULTS.fontSize or 14
    if defaultFontSize < 1 then
        defaultFontSize = 14
    end
    local fontSize = self.db.fontSize or defaultFontSize
    local spacingScale = fontSize / defaultFontSize
    frame.spawnLanes = ScaleSpawnLanes(preset.spawnLanes, spacingScale)
    frame.spawnMinDist = (preset.spawnMinDist or 20) * spacingScale
    frame.spawnMinDistCrit = (preset.spawnMinDistCrit or 26) * spacingScale
    frame.spawnJitter = (preset.spawnJitter or 10) * spacingScale
    frame.spawnCritY = preset.spawnCritY

    local motionStyle = self:ResolveMotionStyle(frame.hitKind)

    -- Classic Slap: Modern look, Classic grow-and-settle crit pow.
    if motionStyle == "classicSlap" and frame.isCrit then
        local classic = self.STYLE_PRESETS.classic
        frame.animMode = "classicPow"
        frame.critsHold = true
        frame.critRestScale = classic.critRestScale or 1.4
        frame.critPowStartScale = classic.critPowStartScale or 1.0
        frame.critPowPeakScale = classic.critPowPeakScale or 2.0
        frame.critPowDuration = classic.critPowDuration or 0.2
        frame.spawnCritY = classic.spawnCritY or 8
        frame.floatEase = classic.floatEase or "outQuad"
        frame.fadeMode = classic.fadeMode or "inExpo"
        frame.fadeInRatio = classic.fadeInRatio or 0.3
        frame.popScale = classic.popScale or 1
        frame.popDuration = classic.popDuration or 0
        -- Match Classic crit duration stretch while keeping Modern float distance base.
        local baseDuration = (self.db.duration or self.DEFAULTS.duration) * (preset.durationMult or 1)
        frame.duration = baseDuration * (classic.critDurationMult or 1.6)
    elseif BD.IsExtraMotionPath(motionStyle) then
        -- Extra Modern paths skip Classic-style crit hold.
        frame.critsHold = false
    end

    ApplyMotionSpawnParams(frame, motionStyle, frame.floatDistance)
end

local function PreviewSpawnY(motionStyle)
    if motionStyle == "verticalDown" or motionStyle == "rainfall" then
        return 18
    end
    if motionStyle == "fountain" or motionStyle == "platesct" or motionStyle == "classicSlap" then
        return -14
    end
    return 0
end

local previewGeneration = 0
local previewReplayGeneration = 0
local previewReplayPending = false
local PREVIEW_STAGGER = 0.45
local PREVIEW_SAMPLES = {
    { hitKind = "hit", amount = 12400, spellID = 6603, school = 1, fallbackIcon = "Interface\\Icons\\INV_Sword_04" },
    { hitKind = "crit", amount = 214200, spellID = 133, school = 4, fallbackIcon = "Interface\\Icons\\Spell_Fire_FlameBolt" },
    { hitKind = "hit", amount = 18650, spellID = 116, school = 16, fallbackIcon = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
    { hitKind = "crit", amount = 1800000, spellID = 686, school = 32, fallbackIcon = "Interface\\Icons\\Spell_Shadow_ShadowBolt" },
    { hitKind = "miss", text = "MISS" },
    { hitKind = "miss", text = "DODGE" },
    { hitKind = "miss", text = "IMMUNE" },
}

local function MatchesPreviewKind(sample, sampleKind)
    if sampleKind ~= "hit" and sampleKind ~= "crit" and sampleKind ~= "miss" then
        return true
    end
    return sample.hitKind == sampleKind
end

local previewMeasureFrame
local previewMeasureText
local function MeasurePreviewText(text, fontPath, fontSize, fontFlags)
    if not previewMeasureText then
        previewMeasureFrame = CreateFrame("Frame", nil, UIParent)
        previewMeasureFrame:Hide()
        previewMeasureText = previewMeasureFrame:CreateFontString(nil, "ARTWORK")
    end
    BD.SafeSetFont(previewMeasureText, fontPath, fontSize, fontFlags)
    previewMeasureText:SetText(text)
    return previewMeasureText:GetStringWidth() or 0, math.max(fontSize, previewMeasureText:GetStringHeight() or 0)
end

function BD:GetOptionsPreviewBounds(sampleKind)
    local preset = self:GetStylePreset()
    local classicStyle = self:IsClassicNumberStyle()
    local baseFontSize = self.db.fontSize or self.DEFAULTS.fontSize
    local fontSize = baseFontSize * preset.fontScale
    local fontPath = BD.ResolveFontPath(self.db.fontFace)
    local spacingScale = baseFontSize / math.max(1, self.DEFAULTS.fontSize or 14)
    -- Include the mock nameplate as well as the full animation envelope.
    local left, right, bottom, top = -70, 70, -9, 9
    for _, sample in ipairs(PREVIEW_SAMPLES) do
        if MatchesPreviewKind(sample, sampleKind) then
            local isCrit = sample.hitKind == "crit"
            local motionStyle = self:ResolveMotionStyle(sample.hitKind)
            local critPreset = motionStyle == "classicSlap" and self.STYLE_PRESETS.classic or preset
            local classicPow = isCrit and (preset.animMode == "classicPow" or motionStyle == "classicSlap")
            local holdsCrit = isCrit and (preset.critsHold or motionStyle == "classicSlap")
                and not BD.IsExtraMotionPath(motionStyle)
            local peakScale = math.max(1, preset.popScale or 1)
            if isCrit then
                if classicPow then
                    peakScale = math.max(critPreset.critPowStartScale or 1,
                        critPreset.critPowPeakScale or 2, critPreset.critRestScale or 1.4)
                else
                    peakScale = math.max(preset.critPopStartScale or 0.72,
                        preset.critSlapScale or 1.5, preset.critRestScale or 1.4)
                end
            end
            if classicStyle then
                peakScale = peakScale * 1.3
            end

            local text = sample.text or BD.FormatAmount(sample.amount, self.db.abbreviate)
            local width, height = MeasurePreviewText(text, fontPath, fontSize, preset.fontFlags)
            local critLabelWidth = 0
            local iconYOffset = 0
            if isCrit and self.db.showCritLabel then
                local critSize = math.max(8, math.floor(fontSize * 0.55 + 0.5))
                local labelWidth, labelHeight = MeasurePreviewText(L["CRITICAL"], fontPath, critSize, preset.fontFlags)
                critLabelWidth = labelWidth + CRIT_LABEL_GAP
                width = width + critLabelWidth
                iconYOffset = math.abs(height - labelHeight) * 0.5
                height = math.max(height, labelHeight)
            end
            if sample.hitKind ~= "miss" and self.db.showSpellIcon then
                local iconSize = math.max(12, math.floor(fontSize * 1.1 + 0.5))
                if self.db.iconPosition == "top" or self.db.iconPosition == "bottom" then
                    width = math.max(width, iconSize + critLabelWidth)
                    height = height + iconSize + ICON_GAP
                else
                    width = width + iconSize + ICON_GAP
                    height = math.max(height, iconSize)
                    if self.db.iconPosition == "right" and critLabelWidth > 0 then
                        -- The right icon follows the label's lower baseline.
                        height = height + iconYOffset * 2
                    end
                end
            end
            local halfWidth = width * peakScale * 0.5 + 4
            local halfHeight = height * peakScale * 0.5 + 4
            local spawnY = PreviewSpawnY(motionStyle)
            if classicStyle and not holdsCrit then
                spawnY = spawnY + (preset.spawnBaseY or 36) - (critPreset.spawnCritY or 8)
            end
            local minX, maxX, minY, maxY = 0, 0, spawnY, spawnY
            if classicStyle then
                -- Clear-spawn's 35-pixel spiral plus Classic's capped 40-pixel shove.
                minX, maxX = -75, 75
                minY, maxY = spawnY - 75, spawnY + 75
            else
                local jitter = (preset.spawnJitter or 10) * spacingScale
                minX, maxX = -jitter, jitter
                maxY = spawnY + jitter
                for _, lane in ipairs(preset.spawnLanes or {}) do
                    minX = math.min(minX, lane[1] * spacingScale)
                    maxX = math.max(maxX, lane[1] * spacingScale)
                    minY = math.min(minY, spawnY + lane[2] * spacingScale)
                    maxY = math.max(maxY, spawnY + lane[2] * spacingScale)
                end
            end
            local distance = (self.db.floatDistance or self.DEFAULTS.floatDistance) * preset.floatMult
            if motionStyle == "fountain" then
                -- Fountain's quadratic apex is below 35px for all supported random arcs.
                minX, maxX = minX - 56, maxX + 56
                minY, maxY = minY - 22, maxY + 35
            elseif motionStyle == "rainfall" then
                minX, maxX = minX - 18, maxX + 18
                minY, maxY = minY + math.min(0, 4 - distance * 1.2), maxY + 12
            elseif motionStyle == "verticalDown" then
                minY = minY - (distance > 0 and distance or 20)
            elseif not holdsCrit then
                local drift = preset.driftX or 0
                minX, maxX = minX + math.min(0, drift), maxX + math.max(0, drift)
                minY, maxY = minY + math.min(0, distance), maxY + math.max(0, distance)
            end
            if isCrit and not classicPow then
                local drop = preset.critSlapDrop or 0
                minY, maxY = minY + math.min(0, drop), maxY + math.max(0, drop)
            end
            left, right = math.min(left, minX - halfWidth), math.max(right, maxX + halfWidth)
            bottom, top = math.min(bottom, minY - halfHeight), math.max(top, maxY + halfHeight)
        end
    end
    return left, right, bottom, top
end

local function SpawnMotionPreviewFrame(anchor, sample)
    sample = sample or PREVIEW_SAMPLES[1]
    local kind = sample.hitKind or "hit"
    local isCrit = kind == "crit"
    local isMiss = kind == "miss"

    local preset = BD:GetStylePreset()
    local frame = BD.Pool.Acquire()
    ConfigureFrameCommon(BD, frame, preset, isCrit, kind, false)

    frame.isPreview = true
    frame.anchor = anchor
    frame.anchorRelPoint = "CENTER"
    frame:SetParent(anchor)
    frame:ClearAllPoints()

    -- PreviewSpawnY is the near-plate slot. Classic combat puts crits there
    -- and hits higher (spawnBaseY 36 vs spawnCritY 8); keep that split.
    local spawnY = PreviewSpawnY(frame.motionStyle)
    if BD:IsClassicNumberStyle() then
        if not (frame.isCrit and frame.critsHold) then
            local hitY = preset.spawnBaseY or 36
            local critY = frame.spawnCritY or preset.spawnCritY or 8
            spawnY = spawnY + (hitY - critY)
        end
        frame.usesClassicShove = true
        local sx, sy = BD.Pool.PickClearSpawn(anchor, frame, 0, spawnY, isCrit, true)
        frame.classicBaseX = sx
        frame.classicBaseY = sy
        frame.startX = sx
        frame.startY = sy
    else
        frame.startX, frame.startY = BD.Pool.PickClearSpawn(anchor, frame, 0, spawnY, isCrit)
    end
    frame:SetPoint("CENTER", anchor, "CENTER", frame.startX, frame.startY)

    local fontSize = (BD.db.fontSize or BD.DEFAULTS.fontSize) * preset.fontScale
    local fontPath = BD.ResolveFontPath(BD.db.fontFace)
    fontPath = BD.SafeSetFont(frame.text, fontPath, fontSize, preset.fontFlags)
    if preset.shadowOffset then
        frame.text:SetShadowOffset(preset.shadowOffset[1], preset.shadowOffset[2])
        frame.text:SetShadowColor(0, 0, 0, 1)
    else
        frame.text:SetShadowOffset(0, 0)
    end

    local r, g, b
    local resolvedIcon
    if isMiss then
        frame.text:SetText(sample.text or "MISS")
        r, g, b = 1, 0.85, 0.2
    else
        frame.text:SetText(BD.FormatAmount(sample.amount, BD.db.abbreviate))
        if BD:ShouldUseSchoolColors() then
            r, g, b = BD.GetSchoolColor(sample.school)
        else
            r, g, b = preset.defaultColor[1], preset.defaultColor[2], preset.defaultColor[3]
        end
        resolvedIcon = BD:ResolveOutgoingSpellIcon(nil, sample.spellID)
        if not resolvedIcon then
            resolvedIcon = BD:ResolveOutgoingSpellIcon(sample.fallbackIcon, nil)
        end
    end

    local iconSize = math.max(12, math.floor((fontSize * 1.1) + 0.5))
    local showCritLabel = isCrit and BD.db.showCritLabel and true or false
    ApplyTextLayout(frame, fontSize, fontPath, preset.fontFlags, preset, {
        showIcon = resolvedIcon ~= nil,
        iconSize = iconSize,
        iconTexture = resolvedIcon,
        iconPosition = BD.db.iconPosition or "left",
        showCritLabel = showCritLabel,
        r = r,
        g = g,
        b = b,
    })

    frame.text:SetTextColor(r, g, b, 1)
    frame.baseAlpha = 1
    if frame.usesClassicShove then
        frame.amountScale = BD.ComputeClassicAmountScale(sample.amount)
    end
    frame:SetAlpha(1)
    if frame.isCrit then
        if frame.animMode == "classicPow" then
            frame:SetScale(frame.critPowStartScale or 1)
        else
            frame:SetScale(frame.critPopStartScale or 0.72)
        end
    else
        frame:SetScale(frame.popScale or 1)
    end
    frame:Show()
    if frame.usesClassicShove then
        BD.Pool.RelayoutClassic(anchor)
    end
end

function BD:ShowMotionPreview(anchor, sampleKind)
    if not anchor or not anchor:IsShown() then
        return
    end

    previewGeneration = previewGeneration + 1
    local generation = previewGeneration

    BD.Pool.ReleasePreviewFrames(anchor)

    local index = 0
    for _, sample in ipairs(PREVIEW_SAMPLES) do
        if MatchesPreviewKind(sample, sampleKind) then
            local previewSample = sample
            C_Timer.After(index * PREVIEW_STAGGER, function()
                if generation ~= previewGeneration then
                    return
                end
                if not anchor or not anchor:IsShown() then
                    return
                end
                SpawnMotionPreviewFrame(anchor, previewSample)
            end)
            index = index + 1
        end
    end
end

function BD:RequestOptionsPreview()
    local configFrame = self.configFrame
    local pane = configFrame and configFrame.previewPane
    if not pane then
        return
    end
    if not configFrame:IsShown() then
        self:ReleaseMotionPreviews()
        return
    end
    if pane.UpdateLayout then
        pane:UpdateLayout()
    elseif self.db and self.db.showOptionsPreview then
        pane:Show()
    else
        pane:Hide()
    end
    if not (self.db and self.db.showOptionsPreview) then
        self:ReleaseMotionPreviews()
        return
    end
    if not pane:IsShown() or not (pane.stage or pane):IsShown() then
        self:ReleaseMotionPreviews()
        return
    end
    if previewReplayPending then
        return
    end
    previewReplayPending = true
    local generation = previewReplayGeneration
    C_Timer.After(0.08, function()
        if generation ~= previewReplayGeneration then
            return
        end
        previewReplayPending = false
        if BD.configFrame ~= configFrame or configFrame.previewPane ~= pane or not configFrame:IsShown() then
            return
        end
        if not (BD.db and BD.db.showOptionsPreview) or not pane:IsShown() then
            return
        end
        local stage = pane.stage or pane
        if not stage:IsShown() then
            return
        end
        if pane.FitStage then
            pane:FitStage()
        end
        BD:ShowMotionPreview(stage, pane.sampleKind)
    end)
end

function BD:ReleaseMotionPreviews()
    previewGeneration = previewGeneration + 1
    previewReplayGeneration = previewReplayGeneration + 1
    previewReplayPending = false
    BD.Pool.ReleasePreviewFrames()
end

function BD:ShowOnNameplate(unit, text, r, g, b, amountForThreshold, isCrit, isHeal, spellIcon, hitKind, spellId)
    local plate = BD.GetNamePlateFrame(unit)
    if not plate then
        self:DebugPrint("No nameplate for", unit)
        return
    end

    local kind = hitKind
    if not kind then
        kind = isCrit and "crit" or "hit"
    end

    local preset = self:GetStylePreset()
    local frame = BD.Pool.Acquire()
    ConfigureFrameCommon(self, frame, preset, isCrit, kind, false)

    frame.anchor = plate
    frame.anchorRelPoint = "TOP"
    -- Parent UIParent. Host follows the plate while live. Death/reuse freezes
    -- at last world pin (do not read the plate). anchorGuid only when plaintext;
    -- Modern secrets: orphan on hide / NAME_PLATE_UNIT_REMOVED (see API.lua).
    do
        local guid = UnitGUID(unit)
        if guid and BD.CanAccessValue(guid) and not BD.IsSecret(guid) then
            frame.anchorGuid = guid
        else
            frame.anchorGuid = nil
        end
    end
    frame:SetParent(UIParent)
    frame:SetIgnoreParentScale(true)
    pcall(function()
        frame:SetIgnoreParentAlpha(true)
    end)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(100)
    frame.unitToken = unit
    BD.Pool.AttachLingerHost(frame, plate)

    local baseY = preset.spawnBaseY or 8
    if frame.isCrit and frame.critsHold then
        baseY = frame.spawnCritY or preset.spawnCritY or 8
    end
    if self:IsClassicNumberStyle() then
        frame.usesClassicShove = true
        -- Spread across plates in world space so AOE packs do not stack.
        local sx, sy = BD.Pool.PickClearSpawn(plate, frame, 0, baseY, frame.isCrit, true)
        frame.classicBaseX = sx
        frame.classicBaseY = sy
        frame.startX = sx
        frame.startY = sy
    else
        frame.startX, frame.startY = BD.Pool.PickClearSpawn(plate, frame, 0, baseY, frame.isCrit)
    end
    frame:ClearAllPoints()
    local lingerAt = frame.lingerHost or plate
    frame:SetPoint("CENTER", lingerAt, frame.lingerHost and "CENTER" or "TOP", frame.startX, frame.startY)

    local fontSize = (self.db.fontSize or self.DEFAULTS.fontSize) * preset.fontScale
    local fontPath = BD.ResolveFontPath(self.db.fontFace)
    fontPath = BD.SafeSetFont(frame.text, fontPath, fontSize, preset.fontFlags)
    if preset.shadowOffset then
        frame.text:SetShadowOffset(preset.shadowOffset[1], preset.shadowOffset[2])
        frame.text:SetShadowColor(0, 0, 0, 1)
    else
        frame.text:SetShadowOffset(0, 0)
    end
    frame.text:SetText(text)

    local resolvedIcon = self:ResolveOutgoingSpellIcon(spellIcon, spellId)
    local iconSize = math.max(12, math.floor((fontSize * 1.1) + 0.5))
    local showCritLabel = frame.isCrit and self.db.showCritLabel and true or false

    if isHeal then
        if self:ShouldUseSchoolColors() then
            if not r then
                r, g, b = BD.GetSchoolColor(nil)
            end
        else
            local heal = BD.HEAL_COLOR
            r, g, b = heal[1], heal[2], heal[3]
        end
    elseif self:ShouldUseSchoolColors() then
        if not r then
            r, g, b = BD.GetSchoolColor(nil)
        end
    else
        r, g, b = preset.defaultColor[1], preset.defaultColor[2], preset.defaultColor[3]
    end

    ApplyTextLayout(frame, fontSize, fontPath, preset.fontFlags, preset, {
        showIcon = resolvedIcon ~= nil,
        iconSize = iconSize,
        iconTexture = resolvedIcon,
        iconPosition = self.db.iconPosition or "left",
        showCritLabel = showCritLabel,
        r = r,
        g = g,
        b = b,
    })

    frame.text:SetTextColor(r, g, b, 1)

    local thresholdCurve = self:GetThresholdCurve()
    if amountForThreshold and self.db.minDamage and self.db.minDamage > 0 and BD.IsSecret(amountForThreshold) and thresholdCurve then
        local ok = pcall(function()
            local color = thresholdCurve:Evaluate(amountForThreshold)
            frame.baseAlpha = select(4, color:GetRGBA())
        end)
        if not ok then
            frame.baseAlpha = 1
        end
    end

    if frame.baseAlpha <= 0 then
        BD.Pool.Release(frame)
        return
    end

    if frame.usesClassicShove then
        frame.amountScale = BD.ComputeClassicAmountScale(amountForThreshold)
    end

    frame:SetAlpha(frame.baseAlpha)
    if frame.isCrit then
        if frame.animMode == "classicPow" then
            frame:SetScale(frame.critPowStartScale or 1)
        else
            frame:SetScale(frame.critPopStartScale or 0.72)
        end
    else
        frame:SetScale(frame.popScale or 1)
    end
    frame:Show()
    -- Show first so screen centers exist for Classic AOE deconflict.
    if frame.usesClassicShove then
        BD.Pool.RelayoutClassic(plate)
    end
    -- Layout exists now. Snapshot before death can hide the plate this frame.
    BD.Pool.SnapshotLingerHost(frame, true)

    if not isHeal and kind ~= "miss" then
        self:PlayOutgoingCritSound(amountForThreshold, frame.isCrit)
    end
end

function BD:ShowIncoming(text, r, g, b, amountForThreshold, isCrit, hitKind)
    local anchor, relPoint, unitToken = BD.GetIncomingAnchor()
    if not anchor then
        return
    end

    local kind = hitKind
    if not kind then
        kind = isCrit and "crit" or "hit"
    end

    local preset = self:GetStylePreset()
    local frame = BD.Pool.Acquire()
    ConfigureFrameCommon(self, frame, preset, isCrit, kind, true)

    frame.anchor = anchor
    frame.anchorRelPoint = relPoint or "CENTER"
    frame:SetParent(UIParent)
    frame:SetIgnoreParentScale(true)
    pcall(function()
        frame:SetIgnoreParentAlpha(true)
    end)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(120)
    frame.unitToken = unitToken

    local ox = self.db.incomingOffsetX or self.DEFAULTS.incomingOffsetX or 0
    local oy = self.db.incomingOffsetY or self.DEFAULTS.incomingOffsetY or -100
    -- On personal nameplate, keep spawn tight; offsets alone place the cluster.
    -- On UIParent, offsets are the whole placement (default center + Y -100).
    local baseY = 0
    if frame.isCrit and frame.critsHold then
        baseY = (frame.spawnCritY or -8) * 0.15
    end
    local spawnY = oy + baseY
    if self:IsClassicNumberStyle() then
        frame.usesClassicShove = true
        local sx, sy = BD.Pool.PickClearSpawn(anchor, frame, ox, spawnY, frame.isCrit, true)
        frame.classicBaseX = sx
        frame.classicBaseY = sy
        frame.startX = sx
        frame.startY = sy
    else
        frame.startX, frame.startY = BD.Pool.PickClearSpawn(anchor, frame, ox, spawnY, frame.isCrit)
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", anchor, frame.anchorRelPoint, frame.startX, frame.startY)

    local fontSize = (self.db.fontSize or self.DEFAULTS.fontSize) * preset.fontScale
    local fontPath = BD.ResolveFontPath(self.db.fontFace)
    fontPath = BD.SafeSetFont(frame.text, fontPath, fontSize, preset.fontFlags)
    if preset.shadowOffset then
        frame.text:SetShadowOffset(preset.shadowOffset[1], preset.shadowOffset[2])
        frame.text:SetShadowColor(0, 0, 0, 1)
    else
        frame.text:SetShadowOffset(0, 0)
    end
    frame.text:SetText(text)

    local color = BD.INCOMING_COLOR
    local textR = r or color[1]
    local textG = g or color[2]
    local textB = b or color[3]
    local showCritLabel = frame.isCrit and self.db.showCritLabel and true or false

    ApplyTextLayout(frame, fontSize, fontPath, preset.fontFlags, preset, {
        showCritLabel = showCritLabel,
        r = textR,
        g = textG,
        b = textB,
    })

    frame.text:SetTextColor(textR, textG, textB, 1)

    local thresholdCurve = self:GetThresholdCurve()
    if amountForThreshold and self.db.minDamage and self.db.minDamage > 0 and BD.IsSecret(amountForThreshold) and thresholdCurve then
        local ok = pcall(function()
            local colorCurve = thresholdCurve:Evaluate(amountForThreshold)
            frame.baseAlpha = select(4, colorCurve:GetRGBA())
        end)
        if not ok then
            frame.baseAlpha = 1
        end
    end

    if frame.baseAlpha <= 0 then
        BD.Pool.Release(frame)
        return
    end

    if frame.usesClassicShove then
        frame.amountScale = BD.ComputeClassicAmountScale(amountForThreshold)
    end

    frame:SetAlpha(frame.baseAlpha)
    if frame.isCrit then
        if frame.animMode == "classicPow" then
            frame:SetScale(frame.critPowStartScale or 1)
        else
            frame:SetScale(frame.critPopStartScale or 0.72)
        end
    else
        frame:SetScale(frame.popScale or 1)
    end
    frame:Show()
    if frame.usesClassicShove then
        BD.Pool.RelayoutClassic(anchor)
    end
end

function BD:ShowTestNumbers()
    if not UnitExists("target") then
        print("|cff66ccffPlateSCT:|r", L["Target something to preview test numbers."])
        return
    end

    local samples = {
        { amount = 12400, crit = false, spellID = 6603, hitKind = "hit" },
        { amount = 18650, crit = false, spellID = 133, hitKind = "hit" },
        { amount = 214200, crit = true, spellID = 116, hitKind = "crit" },
        { amount = 842, crit = false, spellID = 585, hitKind = "hit" },
        { amount = 1800000, crit = true, spellID = 686, hitKind = "crit" },
        { miss = true, text = "MISS", hitKind = "miss" },
        { miss = true, text = "DODGE", hitKind = "miss" },
        { miss = true, text = "IMMUNE", hitKind = "miss" },
    }
    for index, sample in ipairs(samples) do
        C_Timer.After((index - 1) * 0.12, function()
            if sample.miss then
                self:ShowOnNameplate("target", sample.text, 1, 0.85, 0.2, nil, false, false, nil, "miss")
                return
            end
            local display = BD.FormatAmount(sample.amount, self.db.abbreviate)
            local r, g, b = 1, 0.92, 0.35
            local spellIcon = self.db.showSpellIcon and BD.GetSpellIconTexture(sample.spellID) or nil
            self:ShowOnNameplate("target", display, r, g, b, sample.amount, sample.crit, false, spellIcon, sample.hitKind, sample.spellID)
        end)
    end

    if self.db.showIncoming then
        C_Timer.After(#samples * 0.12, function()
            local display = BD.FormatAmount(8420, self.db.abbreviate)
            local color = BD.INCOMING_COLOR
            self:ShowIncoming(display, color[1], color[2], color[3], 8420, false, "hit")
        end)
    end
end
