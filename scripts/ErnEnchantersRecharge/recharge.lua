--[[
ErnEnchantersRecharge for OpenMW.
Copyright (C) 2026 Erin Pentecost

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]
local MOD_NAME       = require("scripts.ErnEnchantersRecharge.ns")
local core           = require("openmw.core")
local localization   = core.l10n(MOD_NAME)
local pself          = require("openmw.self")
local ui             = require("openmw.ui")
local types          = require("openmw.types")
local util           = require("openmw.util")
local ambient           = require("openmw.ambient")
local enchantUtil    = require('scripts.ErnEnchantersRecharge.enchantutil')
local rechargeWindow = require('scripts.ErnEnchantersRecharge.rechargewindow')
local settings       = require("scripts.ErnEnchantersRecharge.settings")
local aux_util       = require('openmw_aux.util')

local topic = string.lower(localization("rechargeTopic"))

pself.type.addTopic(pself, topic)

local rechargeCostMult = core.getGMST('fMagicItemChargeRechargeMult') or 1.0

---@return integer
local function cost(charge, capacity, itemCost, enchanter)
    -- you pay the square root of the total item cost, prorated by missing charge %,
    -- plus .3 gp per missing charge.
    local base = ((1 - (charge / capacity)) * math.sqrt(itemCost)) + (capacity - charge) * .3
    -- costs are plus or minus 50% based on mercantile.
    local playerBarter = pself.type.stats.skills.mercantile(pself).modified
    local enchanterBarter = pself.type.stats.skills.mercantile(enchanter).modified
    return math.ceil(settings.main.costScale * rechargeCostMult * base *
        util.remap(util.clamp(enchanterBarter / playerBarter, 0, 2), 0, 2, 0.5, 1.5))
end

---@class RechargeEntity
---@field charge number
---@field capacity number
---@field cost number
---@field record any
---@field item any

---comment
---@param item any
---@param record any
---@return RechargeEntity?
local function missingCharge(item, record, enchanter)
    if not item:isValid() then
        return nil
    end
    if item.count > 1 then
        -- stacks are so busted
        return nil
    end
    if record.enchant == nil then
        return nil
    end
    -- enchantRecord.charge is not the same as item max charge capacity!!!
    -- this returns 105 for "steel staff of the ancestors", but that max charge is actually 75
    -- 105 is for the enchantment record, but that's not the whole story.
    -- the staff item itself has a "Enchantment Points" value of 70.
    --
    local enchantRecord = core.magic.enchantments.records[record.enchant]
    if enchantRecord.type == core.magic.ENCHANTMENT_TYPE.CastOnce or enchantRecord.type == core.magic.ENCHANTMENT_TYPE.ConstantEffect then
        return nil
    end

    local capacity = enchantUtil.getMaxEnchantmentCharge(enchantRecord)
    if capacity < 1 then
        return nil
    end
    --print("capacity: " .. tostring(record.name) .. " - " .. tostring(capacity))

    local data = types.Item.itemData(item)
    if not data or (data.enchantmentCharge == nil) then
        return nil
    end
    if data.enchantmentCharge >= capacity then
        return nil
    end

    local out = {
        charge = data.enchantmentCharge,
        capacity = capacity,
        record = record,
        item = item,
        cost = cost(data.enchantmentCharge, capacity, record.value, enchanter)
    }
    settings.debugPrint("item missing charge: " .. aux_util.deepToString(out, 4))
    return out
end

---@return RechargeEntity[]
local function getRechargableItems(enchanter)
    local out = {}
    for _, item in ipairs(pself.type.inventory(pself):getAll(types.Weapon)) do
        local recharge = missingCharge(item, types.Weapon.record(item), enchanter)
        if recharge then
            table.insert(out, recharge)
        end
    end
    for _, item in ipairs(pself.type.inventory(pself):getAll(types.Armor)) do
        local recharge = missingCharge(item, types.Armor.record(item), enchanter)
        if recharge then
            table.insert(out, recharge)
        end
    end
    for _, item in ipairs(pself.type.inventory(pself):getAll(types.Clothing)) do
        local recharge = missingCharge(item, types.Clothing.record(item), enchanter)
        if recharge then
            table.insert(out, recharge)
        end
    end
    table.sort(out, function(a, b)
        if a.record.name == b.record.name then
            return a.item.id < b.item.id
        end
        return a.record.name < b.record.name
    end)
    return out
end

local function currentGold()
    return pself.type.inventory(pself):countOf("gold_001")
end

---@param recharge RechargeEntity
local function doRecharge(recharge)
    if currentGold() < recharge.cost then
        ui.showMessage(localization("notEnoughGold"))
        -- payed recharge sound
         ambient.playSoundFile("Sound\\Fx\\magic\\enchantFAIL.wav")
         core.sendGlobalEvent(MOD_NAME .. 'onRecharge', {
             player = pself,
             cost = recharge.cost,
             item = recharge.item,
             charge = recharge.charge,
             capacity = recharge.capacity
         })
        return
    end
    core.sendGlobalEvent(MOD_NAME .. 'onRecharge', {
        player = pself,
        cost = recharge.cost,
        item = recharge.item,
        charge = recharge.charge,
        capacity = recharge.capacity
    })
    -- payed recharge sound
     ambient.playSoundFile("Sound\\Fx\\magic\\enchant.wav")
     core.sendGlobalEvent(MOD_NAME .. 'onRecharge', {
         player = pself,
         cost = recharge.cost,
         item = recharge.item,
         charge = recharge.charge,
         capacity = recharge.capacity
     })
end

-- The enchanter we are currently talking to. Only meaningful while the window is open.
local enchanter = nil

local function openRechargeWindow(enchanterActor)
    enchanter = enchanterActor
    local items = getRechargableItems(enchanter)
    settings.debugPrint("Found " .. #items .. " rechargeable items.")
    rechargeWindow.open({
        entries = items,
        gold = currentGold(),
        onRecharge = doRecharge,
    })
end

-- Sent by the global script once a recharge has been applied.
local function onUpdateUI()
    if not rechargeWindow.isOpen() or not enchanter then
        return
    end
    local items = getRechargableItems(enchanter)
    settings.debugPrint("Found " .. #items .. " rechargeable items.")
    rechargeWindow.refresh(items, currentGold())
end

return {
    eventHandlers = {
        [MOD_NAME .. "onUpdateUI"] = onUpdateUI,
        UiModeChanged = rechargeWindow.onUiModeChanged,
        DialogueResponse = function(e)
            if e.recordId == topic then
                openRechargeWindow(e.actor)
            end
        end
    },
}
