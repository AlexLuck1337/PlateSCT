local _, BD = ...

local pending = {}
local pendingPool = {}
local castMeta = {}
local lastAutoAttackFallbackTime = 0

-- Learned per spell from hits that only one pending cast could explain: the usual delay from
-- the cast to its first hit (travel time), and the hit's damage school when it is readable.
-- They tell apart several casts that are pending at the same time.
local learnedDelay = {}
local learnedSchool = {}
local learnedSchoolMiss = {}
local LEARN_RATE = 0.3

local function AcquirePending()
    local entry = table.remove(pendingPool)
    if not entry then
        entry = {}
    end
    return entry
end

local function ReleasePending(entry)
    wipe(entry)
    pendingPool[#pendingPool + 1] = entry
end

local function NormalizeStrictness(id)
    if id and BD.STRICTNESS[id] then
        return id
    end
    return "balanced"
end

function BD:DetectScenario()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or not instanceType or instanceType == "none" then
        return "openWorld"
    end
    if instanceType == "party" then
        return "dungeon"
    end
    if instanceType == "raid" then
        return "raid"
    end
    if instanceType == "pvp" then
        return "battleground"
    end
    if instanceType == "arena" then
        return "arena"
    end
    if instanceType == "scenario" then
        return "dungeon"
    end
    return "openWorld"
end

function BD:GetActiveStrictnessId()
    local db = self.db
    if not db then
        return "balanced"
    end
    if not db.attributionAuto then
        return NormalizeStrictness(db.attributionManual)
    end
    local scenario = self.scenario or self:DetectScenario()
    local key = BD.SCENARIO_DB_KEYS[scenario]
    if key and db[key] then
        return NormalizeStrictness(db[key])
    end
    return "balanced"
end

function BD:GetActiveStrictness()
    return BD.STRICTNESS[self:GetActiveStrictnessId()] or BD.STRICTNESS.balanced
end

function BD:RefreshScenario()
    local scenario = self:DetectScenario()
    self.scenario = scenario
    self.activeStrictnessId = self:GetActiveStrictnessId()
    self.activeStrictness = BD.STRICTNESS[self.activeStrictnessId] or BD.STRICTNESS.balanced
    return scenario
end

local function CaptureDestToken()
    if UnitExists("target") then
        return BD.GetNameplateTokenForUnit("target") or "target"
    end
    return nil
end

local function NoteCastMeta(castGUID, kind, destToken)
    if not castGUID then
        return
    end
    local meta = castMeta[castGUID]
    if not meta then
        meta = {}
        castMeta[castGUID] = meta
    end
    if kind then
        meta.kind = kind
    end
    if destToken and not meta.destToken then
        meta.destToken = destToken
    end
    meta.seenAt = GetTime()
end

local function TakeCastMeta(castGUID)
    if not castGUID then
        return nil
    end
    local meta = castMeta[castGUID]
    castMeta[castGUID] = nil
    return meta
end

local function ExpireStale(now)
    now = now or GetTime()
    for guid, meta in pairs(castMeta) do
        if not meta.seenAt or (now - meta.seenAt) > 12 then
            castMeta[guid] = nil
        end
    end

    local write = 1
    for read = 1, #pending do
        local entry = pending[read]
        local age = now - (entry.t0 or 0)
        local window = entry.window or 0
        local linger = entry.linger or 0
        local maxAge = math.max(window, linger)
        local keep = false
        if age <= maxAge then
            if (entry.hitsLeft or 0) > 0 then
                keep = true
            elseif linger > window and age <= linger then
                keep = true
            end
        end
        if keep then
            if write ~= read then
                pending[write] = entry
            end
            write = write + 1
        else
            ReleasePending(entry)
        end
    end
    for index = write, #pending do
        pending[index] = nil
    end
end

-- Plain spell IDs only: secret values cannot be table keys or compared.
local function Learnable(spellID)
    return type(spellID) == "number" and not BD.IsSecret(spellID)
end

-- A buff or heal that cannot deal damage (Power Word: Shield before the pull, say).
local function IsHelpfulOnly(spellID)
    if not Learnable(spellID) or not C_Spell or type(C_Spell.IsSpellHelpful) ~= "function"
        or type(C_Spell.IsSpellHarmful) ~= "function" then
        return false
    end
    local ok, helpfulOnly = pcall(function()
        return (C_Spell.IsSpellHelpful(spellID) and not C_Spell.IsSpellHarmful(spellID)) and true or false
    end)
    return ok and helpfulOnly
end

local function PushPending(spellID, source, destToken, kind)
    if not BD.ValuePresent(spellID) then
        return
    end
    local strict = BD:GetActiveStrictness()
    local now = GetTime()
    ExpireStale(now)

    while #pending >= BD.PENDING_CAP do
        local oldest = table.remove(pending, 1)
        if oldest then
            ReleasePending(oldest)
        else
            break
        end
    end

    local entry = AcquirePending()
    entry.spellID = spellID
    entry.source = source or "player"
    entry.destToken = destToken
    entry.t0 = now
    entry.kind = kind or "instant"
    entry.window = kind == "cast" and strict.castWindow or strict.instantWindow
    entry.hitsLeft = strict.hitsLeft
    entry.linger = strict.linger or 0
    entry.hits = 0
    entry.helpfulOnly = IsHelpfulOnly(spellID)
    pending[#pending + 1] = entry
    BD:DebugPrint("pending+", entry.kind, spellID, entry.destToken or "no-dest", entry.window)
end

function BD:NoteOutgoingSent(unit, destName, castGUID, spellID)
    BD.API.AssertModern("Attribution.NoteOutgoingSent")
    if unit ~= "player" and unit ~= "pet" then
        return
    end
    local destToken = CaptureDestToken()
    -- destName from the event is often a string name; prefer live unit token.
    NoteCastMeta(castGUID, nil, destToken)
end

function BD:NoteOutgoingStart(unit, castGUID, spellID)
    BD.API.AssertModern("Attribution.NoteOutgoingStart")
    if unit ~= "player" and unit ~= "pet" then
        return
    end
    NoteCastMeta(castGUID, "cast", CaptureDestToken())
end

function BD:NoteOutgoingSpell(unit, castGUID, spellID)
    BD.API.AssertModern("Attribution.NoteOutgoingSpell")
    if unit ~= "player" and unit ~= "pet" then
        return
    end
    if unit == "pet" and not (self.db and self.db.includePetDamage) then
        return
    end

    local meta = TakeCastMeta(castGUID)
    local kind = (meta and meta.kind == "cast") and "cast" or "instant"
    local destToken = (meta and meta.destToken) or CaptureDestToken()
    PushPending(spellID, unit, destToken, kind)
end

local function IsLikelySpellSchool(schoolMask)
    if not BD.ValuePresent(schoolMask) then
        return false
    end
    if BD.IsSecret(schoolMask) and not BD.CanAccessValue(schoolMask) then
        return true
    end
    local ok, isPhysical = pcall(function()
        return schoolMask == 1
    end)
    if ok and isPhysical then
        return false
    end
    return ok
end

local function DestMatches(entry, unit)
    if not entry.destToken then
        return false
    end
    if entry.destToken == unit then
        return true
    end
    return BD.UnitsMatch(entry.destToken, unit)
end

local function CanUsePendingOnUnit(entry, unit, strict)
    local destMatch = DestMatches(entry, unit)
    if destMatch then
        return true
    end
    if entry.destToken then
        if strict.destRequired then
            return false
        end
        -- Dest known but different plate: only allow on current target when dest is not required.
        return BD.UnitsMatch(unit, "target") or unit == "target"
    end
    -- No dest recorded: current target only (legacy gate).
    return BD.UnitsMatch(unit, "target") or unit == "target"
end

local function KnownSchool(schoolMask)
    if type(schoolMask) ~= "number" or BD.IsSecret(schoolMask) or not BD.CanAccessValue(schoolMask) then
        return nil
    end
    return schoolMask
end

-- Sets the rank fields of a pending cast that could have caused this hit; false if it cannot.
-- Stage 1: waiting for its first hit. 2: already hit, still in its window (multi-hit spells).
-- 3: only lingering (DoT and channel ticks).
local function RankCandidate(entry, unit, now, strict, school, isHeal)
    if entry.source == "pet" and not (BD.db and BD.db.includePetDamage) then
        return false
    end
    local age = now - (entry.t0 or 0)
    local window, linger = entry.window or 0, entry.linger or 0
    local stage
    if age <= window and (entry.hits or 0) == 0 then
        stage = 1
    elseif age <= window and (entry.hitsLeft or 0) > 0 then
        stage = 2
    elseif linger > window and age <= linger then
        stage = 3
    else
        return false
    end
    if not CanUsePendingOnUnit(entry, unit, strict) then
        return false
    end
    local spellID = entry.spellID
    local known = Learnable(spellID) and learnedSchool[spellID]
    entry.rankMismatch = (school and known and known ~= school) and 1 or 0
    entry.rankBuff = (not isHeal and entry.helpfulOnly) and 1 or 0
    entry.rankStage = stage
    entry.rankOther = DestMatches(entry, unit) and 0 or 1
    if stage == 1 then
        -- When its hit is due: casts in flight resolve in the order their hits arrive.
        entry.rankOrder = (entry.t0 or 0) + ((Learnable(spellID) and learnedDelay[spellID]) or 0)
    else
        -- Newest first, so a new cast is never shadowed by an older one that is still lingering.
        entry.rankOrder = -(entry.t0 or 0)
    end
    return true
end

-- The first difference decides: a learned school that differs from the hit's, a buff that
-- cannot deal damage, the stage, a cast on another plate (allowed only on your target), order.
local function RanksBefore(a, b)
    if a.rankMismatch ~= b.rankMismatch then
        return a.rankMismatch < b.rankMismatch
    end
    if a.rankBuff ~= b.rankBuff then
        return a.rankBuff < b.rankBuff
    end
    if a.rankStage ~= b.rankStage then
        return a.rankStage < b.rankStage
    end
    if a.rankOther ~= b.rankOther then
        return a.rankOther < b.rankOther
    end
    return a.rankOrder < b.rankOrder
end

-- Learn only from the first hit of a cast no other waiting cast could explain. A school is
-- replaced only after two such hits in a row disagree, so one stray hit cannot unlearn it.
local function Learn(entry, age, school, waiting, schoolTaken)
    local spellID = entry.spellID
    if entry.rankStage ~= 1 or waiting ~= 1 or not Learnable(spellID) then
        return
    end
    local delay = learnedDelay[spellID]
    learnedDelay[spellID] = delay and (delay + (age - delay) * LEARN_RATE) or age
    if not school or schoolTaken then
        return
    end
    if learnedSchool[spellID] == nil or learnedSchool[spellID] == school then
        learnedSchool[spellID], learnedSchoolMiss[spellID] = school, nil
    elseif learnedSchoolMiss[spellID] == school then
        learnedSchool[spellID], learnedSchoolMiss[spellID] = school, nil
    else
        learnedSchoolMiss[spellID] = school
    end
end

-- The hit being matched, set by MatchOutgoingHit: its readable school, whether it is a heal, and
-- whether it may be a white hit (you auto-attack, and it is physical on your target). A white
-- hit that only a lingering, other-school or buff cast could explain goes to the auto fallback.
local hitSchool, hitIsHeal, hitPreferAuto

local function TryMatchPending(unit, now, strict)
    local school, isHeal, preferAuto = hitSchool, hitIsHeal, hitPreferAuto
    ExpireStale(now)
    local best, bestIndex
    local waiting, schoolTaken = 0, false

    for index = 1, #pending do
        local entry = pending[index]
        if RankCandidate(entry, unit, now, strict, school, isHeal) then
            if entry.rankStage == 1 then
                waiting = waiting + 1
            end
            if school and Learnable(entry.spellID) and learnedSchool[entry.spellID] == school then
                schoolTaken = true
            end
            if not best or RanksBefore(entry, best) then
                best, bestIndex = entry, index
            end
        end
    end

    if not best then
        return nil
    end
    if preferAuto and (best.rankStage == 3 or best.rankMismatch == 1 or best.rankBuff == 1) then
        return nil
    end

    local spellID = best.spellID
    local age = now - (best.t0 or 0)
    Learn(best, math.min(age, best.window or age), school,
        waiting, schoolTaken and learnedSchool[spellID] ~= school)
    best.hits = (best.hits or 0) + 1
    if best.rankStage <= 2 and (best.hitsLeft or 0) > 0 then
        best.hitsLeft = best.hitsLeft - 1
        if best.hitsLeft <= 0 and not ((best.linger or 0) > (best.window or 0)) then
            table.remove(pending, bestIndex)
            ReleasePending(best)
        end
    end
    return spellID
end

local function IsAutoAttacking()
    local isCurrent = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
    if type(isCurrent) ~= "function" then
        return false
    end
    return BD.SafeUnitBoolean(isCurrent, BD.AUTO_ATTACK_SPELL_ID) or BD.SafeUnitBoolean(isCurrent, BD.AUTO_SHOT_SPELL_ID)
end

--- True while one of your casts is recent enough that its hit may still land. The first hit of a
--- pull often arrives before the client reports combat.
function BD:HasRecentOutgoingCast()
    local now = GetTime()
    for index = #pending, 1, -1 do
        if (now - (pending[index].t0 or 0)) <= BD.PULL_GRACE then
            return true
        end
    end
    return IsAutoAttacking()
end

local function CanUseAutoAttackFallback(now, strict)
    if not strict.autoFallback then
        return false
    end
    local gap = strict.autoFallbackGap or 0.9
    if lastAutoAttackFallbackTime > 0 and (now - lastAutoAttackFallbackTime) < gap then
        return false
    end
    return true
end

--- Returns spellID, usedAuto (or nil if no match).
-- isHeal: the hit is a heal, which a buff cast may explain and the auto-attack fallback never does.
function BD:MatchOutgoingHit(unit, schoolMask, isHeal)
    BD.API.AssertModern("Attribution.MatchOutgoingHit")
    local now = GetTime()
    local strict = self:GetActiveStrictness()
    local autoCandidate = not isHeal and not IsLikelySpellSchool(schoolMask)
        and (BD.UnitsMatch(unit, "target") or unit == "target")
    hitSchool, hitIsHeal = KnownSchool(schoolMask), isHeal
    hitPreferAuto = autoCandidate and IsAutoAttacking() and CanUseAutoAttackFallback(now, strict)
    local spellID = TryMatchPending(unit, now, strict)
    if spellID then
        return spellID, false
    end

    if autoCandidate and CanUseAutoAttackFallback(now, strict) then
        lastAutoAttackFallbackTime = now
        return BD.AUTO_ATTACK_SPELL_ID, true
    end

    return nil, false
end

function BD:PlayerIsEngagedWith(unit)
    if BD.UnitsMatch(unit, "target") or unit == "target" then
        return true
    end
    if BD.UnitsMatch(unit, "focus") then
        return true
    end
    if UnitExists("pet") and BD.UnitsMatch(unit, "pettarget") then
        return true
    end

    local ok, status = pcall(UnitThreatSituation, "player", unit)
    if not ok then
        return true
    end
    if not BD.CanAccessValue(status) then
        return true
    end
    return status ~= nil
end

function BD:ClearAttributionState()
    wipe(learnedDelay)
    wipe(learnedSchool)
    wipe(learnedSchoolMiss)
    for index = #pending, 1, -1 do
        ReleasePending(pending[index])
        pending[index] = nil
    end
    wipe(castMeta)
    lastAutoAttackFallbackTime = 0
end
