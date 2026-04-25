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
local MOD_NAME     = require("scripts.ErnEnchantersRecharge.ns")
local core         = require("openmw.core")
local localization = core.l10n(MOD_NAME)
local pself        = require("openmw.self")
local ui           = require("openmw.ui")
local types        = require("openmw.types")
local util         = require("openmw.util")
local input        = require("openmw.input")

local interfaces   = require('openmw.interfaces')

local topic        = string.lower(localization("topic"))

pself.type.addTopic(pself, topic)

local function missingCharge(item, record)
    if record.enchant == nil then
        return nil
    end
    local enchantRecord = core.magic.enchantments.records[record.enchant]
    if enchantRecord.type == core.magic.ENCHANTMENT_TYPE.CastOnce or enchantRecord.type == core.magic.ENCHANTMENT_TYPE.ConstantEffect then
        return nil
    end
    local data = types.Item.itemData(item)
    if not data or (data.enchantmentCharge == nil) then
        return nil
    end
    if data.enchantmentCharge >= enchantRecord.charge then
        return nil
    end
    return {
        charge = data.enchantmentCharge,
        capacity = enchantRecord.charge,
        record = record,
        item = item,
    }
end

local function getRechargableItems()
    local out = {}
    for _, item in ipairs(pself.type.inventory(pself):getAll(types.Weapon)) do
        local recharge = missingCharge(item, types.Weapon.record(item))
        if recharge then
            table.insert(out, recharge)
        end
    end
    for _, item in ipairs(pself.type.inventory(pself):getAll(types.Armor)) do
        local recharge = missingCharge(item, types.Armor.record(item))
        if recharge then
            table.insert(out, recharge)
        end
    end
    for _, item in ipairs(pself.type.inventory(pself):getAll(types.Clothing)) do
        local recharge = missingCharge(item, types.Clothing.record(item))
        if recharge then
            table.insert(out, recharge)
        end
    end
    table.sort(out, function(a, b) return a.record.name > b.record.name end)
    return out
end

local window
local items = {}

-- close window
local function UiModeChanged(data)
    if window ~= nil and ((data.newMode == nil) or (data.newMode ~= "Interface")) then
        window:destroy()
        window = nil
        items = {}
    end
end

---@type VirtualListExt
local List = require("scripts.ErnEnchantersRecharge.VirtualList.virtual_list.extras").VirtualListExt


local windowPosition = util.vector2(0.5, 0.5)
local windowSize = util.vector2(400, 400)
local itemSize = util.vector2(400, 20)

local function openRechargeWindow(enchanter)
    items = getRechargableItems()
    print("Found " .. #items .. " rechargeable items.")

    interfaces.UI.addMode("Interface", { windows = {} })
    -- Note the list must know the sizes involved to do its math.
    local list = List.create({
        viewportSize = windowSize,
        itemSize = itemSize,
        itemCount = #items,
        itemLayout = function(i, list)
            return list:createItemLayout({
                index = i,
                props = {
                    text = items[i].record.name,
                },
                onMousePress = function(e) -- Optional mouse press handler
                    if e.button == 1 then
                        list:changeSelection(i)
                        ui.showMessage("Mouse press: " .. items[i].record.name)
                    end
                end,
            })
        end,
    })

    -- Optionally we can set a key press handler for the list.
    list:setKeyPressHandler({
        setSelectedIndex = function(i)
            list:changeSelection(i)
            ui.showMessage("Key press: " .. items[i])
        end,
    })

    -- Put our list in a bordered window with a black background.
    window = ui.create({
        layer = "Windows",
        type = ui.TYPE.Image,
        template = interfaces.MWUI.templates.borders,
        props = {
            size = windowSize,
            anchor = windowPosition,
            relativePosition = windowPosition,
            resource = ui.texture({ path = "black" }),
        },
        content = ui.content({ list:getElement() }),
    })
end




return {
    eventHandlers = {
        UiModeChanged = UiModeChanged,
        DialogueResponse = function(e)
            print(e.recordId)
            if e.recordId == topic then
                openRechargeWindow(e.actor)
            end
        end
    },
    engineHandlers = {
        -- Optional mouse wheel handling for scrolling.
        onMouseWheel = List.getMouseWheelHandler(),
    },
}
