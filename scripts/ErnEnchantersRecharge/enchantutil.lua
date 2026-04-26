--- Enchanting functions
-- @module enchanting
-- @usage local enchanting = require('openmw.enchanting')

local core = require('openmw.core')

---
-- Get the charge multiplier for an enchantment type from game settings.
-- These multipliers determine how many charge points are added per base cost point.
--
-- @function getChargeMultiplier
-- @param enchantmentType The enchantment type (one of core.magic.ENCHANTMENT_TYPE values)
-- @return #number The charge multiplier
-- @usage
-- local multiplier = enchanting.getChargeMultiplier(core.magic.ENCHANTMENT_TYPE.WhenUsed)

local function getChargeMultiplier(enchantmentType)
    local settings = core.magic.getGMST

    if enchantmentType == core.magic.ENCHANTMENT_TYPE.CastOnce then
        return core.magic.getGMST('iMagicItemChargeOnce') or 1
    elseif enchantmentType == core.magic.ENCHANTMENT_TYPE.WhenStrikes then
        return core.magic.getGMST('iMagicItemChargeStrike') or 1
    elseif enchantmentType == core.magic.ENCHANTMENT_TYPE.WhenUsed then
        return core.magic.getGMST('iMagicItemChargeUse') or 1
    elseif enchantmentType == core.magic.ENCHANTMENT_TYPE.ConstantEffect then
        return core.magic.getGMST('iMagicItemChargeConst') or 1
    end

    return 1
end

---
-- Calculate the cost of a single magic effect within an enchantment context.
-- Uses the enchantment cost formula which differs from spell and potion costs.
--
-- @function getEffectCost
-- @param effect The magic effect with parameters (mData field)
-- @param enchantmentType The enchantment type for context
-- @return #number The calculated cost of this effect
-- @usage
-- local effectCost = enchanting.getEffectCost(effect, core.magic.ENCHANTMENT_TYPE.WhenUsed)

local function getEffectCost(effect, enchantmentType)
    if not effect or not effect.mData then
        return 0
    end

    local fEffectCostMult = core.magic.getGMST('fEffectCostMult') or 1.0
    local fEnchantmentConstantDurationMult = core.magic.getGMST('fEnchantmentConstantDurationMult') or 1.0

    -- Get magic effect base cost
    local magicEffect = core.magic.effects.records[effect.mData.mEffectID]
    if not magicEffect then
        return 0
    end

    local baseCost = magicEffect.baseCost or 0

    -- Ensure min/max magnitude and area are at least 1
    local magMin = math.max(1, effect.mData.mMagnMin or 0)
    local magMax = math.max(1, effect.mData.mMagnMax or 0)
    local area = math.max(1, effect.mData.mArea or 0)

    local duration = effect.mData.mDuration or 0
    if enchantmentType == core.magic.ENCHANTMENT_TYPE.ConstantEffect then
        duration = fEnchantmentConstantDurationMult
    end

    -- Vanilla enchant cost formula:
    -- ((min + max) * duration + area) * baseCost * fEffectCostMult * 0.05
    local cost = ((magMin + magMax) * duration + area) * baseCost * fEffectCostMult * 0.05

    -- Ensure minimum cost of 1
    cost = math.max(1.0, cost)

    -- Apply target range multiplier
    if effect.mData.mRange == 2 then -- ESM::RT_Target
        cost = cost * 1.5
    end

    return cost
end

---
-- Calculate the maximum enchantment points available on an item.
-- This is the capacity of an item to be enchanted, based on its type and base properties.
--
-- @function getMaxEnchantmentPoints
-- @param item The item object (enchantable item)
-- @return #number The maximum enchantment points available
-- @usage
-- local item = types.Item.record(myItem)
-- local maxPoints = enchanting.getMaxEnchantmentPoints(item)

local function getMaxEnchantmentPoints(item)
    if not item then
        return 0
    end

    -- Get the enchantment points from the item class
    local enchantPoints = item.enchantmentPoints or 0

    -- Multiply by the enchantment multiplier setting
    local fEnchantmentMult = core.magic.getGMST('fEnchantmentMult') or 1.0

    return math.floor(enchantPoints * fEnchantmentMult)
end

---
-- Calculate the maximum charge capacity for an enchanted item.
--
-- The maximum charge depends on three factors:
-- 1. The enchantment record's charge capacity (from enchantment.charge)
-- 2. Whether the enchantment uses autocalc
-- 3. The enchantment type (CastOnce, WhenStrikes, WhenUsed, ConstantEffect)
--
-- For autocalc enchantments, the charge is calculated based on effect costs and game settings.
-- For constant effect enchantments, the maximum charge is 0 (they don't consume charge).
-- For other types, the charge multiplier from game settings determines the final capacity.
--
-- @function getMaxEnchantmentCharge
-- @param enchantment The enchantment record (from core.magic.enchantments.records)
-- @return #number The maximum charge capacity for this enchantment
-- @usage
-- local enchantment = core.magic.enchantments.records['my_enchantment_id']
-- local maxCharge = enchanting.getMaxEnchantmentCharge(enchantment)
-- if maxCharge > 0 then
--     print("This enchantment can store up to " .. maxCharge .. " charge")
-- else
--     print("This is a constant effect enchantment with no charge")
-- end

local function getMaxEnchantmentCharge(enchantment)
    if not enchantment then
        return 0
    end

    -- Constant effect enchantments have no charge
    if enchantment.type == core.magic.ENCHANTMENT_TYPE.ConstantEffect then
        return 0
    end

    -- If autocalc flag is set, calculate charge from effect costs
    if enchantment.isAutocalc then
        local baseCost = 0

        -- Sum up all effect costs
        for _, effect in ipairs(enchantment.effects) do
            baseCost = baseCost + getEffectCost(effect, enchantment.type)
        end

        -- Round to nearest integer
        baseCost = math.floor(baseCost + 0.5)

        -- Apply type-specific multiplier from game settings
        local chargeMultiplier = getChargeMultiplier(enchantment.type)
        return baseCost * chargeMultiplier
    end

    -- Otherwise, use the stored charge value from the enchantment record
    return enchantment.charge
end

return {
    getMaxEnchantmentCharge = getMaxEnchantmentCharge,
    getChargeMultiplier = getChargeMultiplier,
    getEffectCost = getEffectCost,
    getMaxEnchantmentPoints = getMaxEnchantmentPoints,
}
