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
-- The recharge window, built from OpenMW-UIToolkit components.
--
-- This module only knows how to display a list of rechargeable items. All of the
-- game logic (costs, which items qualify, how to perform a recharge) lives in
-- recharge.lua, which talks to this module through open/refresh/close.
--
-- OpenMW-UIToolkit is looked up lazily (the first time the window is opened) so
-- that a missing or mis-ordered toolkit install produces a readable in-game
-- message instead of a script load error.
local core         = require("openmw.core")
local ui           = require("openmw.ui")
local util         = require("openmw.util")
local input        = require("openmw.input")
local pself        = require("openmw.self")
local I            = require("openmw.interfaces")
local MOD_NAME     = require("scripts.ErnEnchantersRecharge.ns")

local localization = core.l10n(MOD_NAME)
local v2           = util.vector2

local WINDOW_ID    = MOD_NAME .. ":RechargeWindow"
local WINDOW_SIZE  = v2(520, 520)
local WINDOW_MIN   = v2(380, 280)
local FOOTER_H     = 34
local MIN_ROW_H    = 34
local ICON_SIZE    = 32
local CHARGE_COL_W = 130
local COST_COL_W   = 64

---@class RechargeWindowArgs
---@field entries RechargeEntity[]
---@field gold number
---@field onRecharge fun(entry: RechargeEntity)

-- Everything that belongs to the currently open window.
local S            = {
    ---@type RechargeWindowArgs?
    args = nil,
    ---@type RechargeEntity[]
    entries = {},
    gold = 0,
    sorted = nil,
    footer = nil,
    goldLayout = nil,
    emptyElement = nil,
}

local M            = {}

-- Set by init().
local initialized  = false
local Handler
local ColumnItem

local function goldText()
    return localization("currentGold", { gold = S.gold })
end

local function listSize(innerSize)
    return v2(innerSize.x, math.max(0, innerSize.y - FOOTER_H))
end

local function activate(row)
    if row and row.entry and S.args then
        S.args.onRecharge(row.entry)
    end
end

---@param entries RechargeEntity[]
local function buildRows(entries)
    local rows = {}
    for i, entry in ipairs(entries) do
        rows[i] = {
            id = tostring(entry.item.id),
            entry = entry,
            icon = entry.record.icon,
            name = entry.record.name,
            charge = entry.charge,
            capacity = entry.capacity,
            cost = entry.cost,
            tooltip = { object = entry.item, observer = pself },
            -- Rows the player can't afford are drawn in the "disabled" color.
            isDisabled = function() return S.gold < entry.cost end,
        }
    end
    return rows
end

-- Charge column. This mirrors what the toolkit's progressBar draws (thin border,
-- themed bar texture and a centered "charge/capacity" label), but is built as a
-- plain layout. The progressBar component registers its own mouse handlers, which
-- would steal hover and click events from the list row it sits in.
local function renderCharge(data, cfg, height)
    local toolkit = I.UIToolkit
    local theme = toolkit.getTheme()
    local T = toolkit.Templates

    local ratio = 0
    if data.capacity > 0 then
        ratio = util.clamp(data.charge / data.capacity, 0, 1)
    end
    local label = string.format("%d/%d", math.floor(data.charge + 0.5), math.floor(data.capacity + 0.5))

    local layout = {
        name = cfg.id,
        type = ui.TYPE.Widget,
        props = {},
        content = ui.content { {
            name = "bar",
            template = T.border { style = "thin" },
            props = {
                size = v2((cfg.width or 100) - 8, height - 8),
                anchor = v2(0, 0.5),
                relativePosition = v2(0, 0.5),
                position = v2(4, 0),
            },
            content = ui.content { {
                type = ui.TYPE.Widget,
                props = { relativeSize = v2(1, 1) },
                content = ui.content {
                    {
                        type = ui.TYPE.Image,
                        props = {
                            resource = theme.Colors.menuBarGray,
                            color = theme.Colors.MAGICK,
                            relativeSize = v2(ratio, 1),
                        },
                    },
                    {
                        template = T.text(),
                        props = {
                            text = label,
                            textShadow = true,
                            textAlignH = ui.ALIGNMENT.Center,
                            textAlignV = ui.ALIGNMENT.Center,
                            autoSize = false,
                            relativeSize = v2(1, 1),
                        },
                        userData = { colorable = true },
                    },
                },
            } },
        } },
    }
    ColumnItem.applySize(layout, cfg, height)
    return layout
end

local function compareNames(a, b)
    local an, bn = string.lower(a.name or ""), string.lower(b.name or "")
    if an == bn then return 0 end
    return an < bn and -1 or 1
end

local function compareCharge(a, b)
    local ar = a.capacity > 0 and (a.charge / a.capacity) or 0
    local br = b.capacity > 0 and (b.charge / b.capacity) or 0
    if ar == br then return 0 end
    return ar < br and -1 or 1
end

local function makeColumns(rowHeight)
    return {
        -- No `sort` makes a column display-only.
        { id = "icon", render = ColumnItem.renderIcon, arg = { sz = ICON_SIZE }, width = rowHeight + 4 },
        { id = "name", name = localization("magicalItems"), render = ColumnItem.renderText, sort = compareNames },
        { id = "charge", name = localization("charge"), render = renderCharge, width = CHARGE_COL_W, sort = compareCharge },
        {
            id = "cost",
            name = localization("cost"),
            render = ColumnItem.renderText,
            arg = { textAlignH = ui.ALIGNMENT.End },
            align = ui.ALIGNMENT.End,
            width = COST_COL_W,
            sort = { numeric = true },
        },
    }
end

local function updateGold()
    if not S.goldLayout or not S.footer or not S.footer.layout then return end
    S.goldLayout.props.text = goldText()
    I.UIToolkit.queueUpdate(S.footer)
end

local function updateEmptyLabel()
    local element = S.emptyElement
    if not element or not element.layout then return end
    element.layout.props.visible = #S.entries == 0
    I.UIToolkit.queueUpdate(element)
end

local function buildFooter()
    local toolkit = I.UIToolkit
    local T = toolkit.Templates

    S.goldLayout = {
        name = "gold",
        template = T.text(),
        props = {
            text = goldText(),
            anchor = v2(1, 0.5),
            relativePosition = v2(1, 0.5),
            position = v2(-6, 0),
        },
    }

    local cancel = toolkit.Components.textButton {
        text = localization("cancel"),
        width = 90,
        onClick = function() M.close() end,
    }
    cancel:updateProps {
        anchor = v2(0.5, 0.5),
        relativePosition = v2(0.5, 0.5),
    }

    return ui.create {
        name = "footer",
        props = {
            anchor = v2(0, 1),
            relativePosition = v2(0, 1),
            relativeSize = v2(1, 0),
            size = v2(0, FOOTER_H),
        },
        content = ui.content { cancel.element, S.goldLayout },
    }
end

local function buildEmptyLabel()
    return ui.create {
        name = "emptyLabel",
        template = I.UIToolkit.Templates.text(),
        props = {
            text = localization("noItems"),
            anchor = v2(0.5, 0.5),
            relativePosition = v2(0.5, 0.45),
            visible = #S.entries == 0,
        },
    }
end

-- Window handler callbacks. These are installed on a toolkit WindowHandler
-- subclass in init(); `self` is that class and holds no state of its own.

local function onOpened(self, wnd)
    local toolkit = I.UIToolkit
    local theme = toolkit.getTheme()
    local rowHeight = math.max(MIN_ROW_H, util.round(theme.Sizes.listRowScale * theme.Sizes.lineHeight))
    local inner = wnd:getInnerSize()

    S.sorted = toolkit.Components.sortedList {
        size = listSize(inner),
        rowHeight = rowHeight,
        columns = makeColumns(rowHeight),
        onItemClicked = function(row) activate(row) end,
    }
    -- Start sorted by name, ascending (also shows the sort arrow in the header).
    S.sorted.header:toggleColumn("name")
    S.sorted:setItems(buildRows(S.entries))

    S.footer = buildFooter()
    S.emptyElement = buildEmptyLabel()

    wnd:setContent(ui.content { S.sorted.element, S.emptyElement, S.footer })
end

local function onClosed(self)
    S.sorted = nil
    S.footer = nil
    S.goldLayout = nil
    S.emptyElement = nil
    S.args = nil
    S.entries = {}
    return nil
end

local function onResized(self, innerSize)
    if S.sorted and not S.sorted:isDestroyed() then
        S.sorted:setSize(listSize(innerSize))
    end
end

local function shiftSelection(delta)
    if S.sorted and not S.sorted:isDestroyed() then
        S.sorted.list:shiftHoveredItem(delta)
    end
end

local function activateSelection()
    if not S.sorted or S.sorted:isDestroyed() then return end
    local row = S.sorted.list:getHovered()
    if row then
        activate(row)
    elseif #S.entries > 0 then
        -- Nothing highlighted yet: first press highlights the first row.
        shiftSelection(1)
    else
        M.close()
    end
end

local function onKeyboardButtonPress(self, key)
    if key == input.KEY.UpArrow then
        shiftSelection(-1)
    elseif key == input.KEY.DownArrow then
        shiftSelection(1)
    elseif key == input.KEY.Enter or key == input.KEY.NP_Enter then
        -- Only on the initial press; holding Enter must not buy repeatedly.
        activateSelection()
    end
end

local function onKeyboardButtonRepeat(self, key)
    if key == input.KEY.UpArrow then
        shiftSelection(-1)
    elseif key == input.KEY.DownArrow then
        shiftSelection(1)
    end
end

local function onControllerButtonPress(self, button)
    local B = input.CONTROLLER_BUTTON
    if button == B.DPadUp then
        shiftSelection(-1)
    elseif button == B.DPadDown then
        shiftSelection(1)
    elseif button == B.A then
        activateSelection()
    elseif button == B.B then
        M.close()
    end
end

local function onControllerButtonRepeat(self, button)
    local B = input.CONTROLLER_BUTTON
    if button == B.DPadUp then
        shiftSelection(-1)
    elseif button == B.DPadDown then
        shiftSelection(1)
    end
end

-- Lets the toolkit scroll the list with the controller's right stick.
local function getFocusedScrollable(self)
    if S.sorted and not S.sorted:isDestroyed() then
        return S.sorted.list
    end
    return nil
end

---@return boolean true if the toolkit is available
local function init()
    if initialized then return true end

    local toolkit = I.UIToolkit
    if not toolkit or not toolkit.WindowManager or not toolkit.Components then
        return false
    end
    local ok, Class, WindowHandler, ColumnItemModule = pcall(function()
        return require("scripts.UIToolkit.class"),
            require("scripts.UIToolkit.window_handler"),
            require("scripts.UIToolkit.components.list_items.column_item")
    end)
    if not ok then
        print("ErnEnchantersRecharge: could not load UIToolkit modules: " .. tostring(Class))
        return false
    end

    ColumnItem = ColumnItemModule
    Handler = Class(WindowHandler)
    Handler.onOpened = onOpened
    Handler.onClosed = onClosed
    Handler.onResized = onResized
    Handler.onKeyboardButtonPress = onKeyboardButtonPress
    Handler.onKeyboardButtonRepeat = onKeyboardButtonRepeat
    Handler.onControllerButtonPress = onControllerButtonPress
    Handler.onControllerButtonRepeat = onControllerButtonRepeat
    Handler.getFocusedScrollable = getFocusedScrollable

    initialized = true
    return true
end

---@return boolean
function M.isOpen()
    return initialized and I.UIToolkit.WindowManager.isOpen(WINDOW_ID) or false
end

---Open the window (or refresh it if it's already open).
---@param args RechargeWindowArgs
---@return boolean opened
function M.open(args)
    if not init() then
        ui.showMessage(localization("missingToolkit"))
        return false
    end
    if M.isOpen() then
        M.refresh(args.entries, args.gold)
        return true
    end

    S.args = args
    S.entries = args.entries
    S.gold = args.gold

    local windows = I.UIToolkit.WindowManager
    -- Re-registering on every open keeps the default position centered even if
    -- the screen size changed. A position saved when the window was last closed
    -- takes precedence over this default.
    windows.register(WINDOW_ID, {
        title = localization("windowTitle"),
        handler = Handler,
        size = WINDOW_SIZE,
        minSize = WINDOW_MIN,
        position = windows.getCenterPositionForSize(WINDOW_SIZE),
        draggable = true,
        resizing = true,
    })
    -- Stack on top of the dialogue mode so closing returns to the conversation.
    I.UI.addMode(I.UI.MODE.Interface, { windows = {} })
    windows.open(WINDOW_ID)
    return true
end

---Replace the displayed items and gold total, e.g. after a recharge.
---@param entries RechargeEntity[]
---@param gold number
function M.refresh(entries, gold)
    S.entries = entries
    S.gold = gold
    if not S.sorted or S.sorted:isDestroyed() then return end
    -- Row components are cached by id. Drop them so costs, charge bars and
    -- affordability are all rebuilt from the new data.
    S.sorted.provider:clear()
    S.sorted:setItems(buildRows(entries))
    updateGold()
    updateEmptyLabel()
end

function M.close()
    if not M.isOpen() then return end
    I.UIToolkit.WindowManager.close(WINDOW_ID, true)
    if I.UI.getMode() == I.UI.MODE.Interface then
        I.UI.removeMode(I.UI.MODE.Interface)
    end
end

---UiModeChanged handler: close if the player leaves our interface mode
---(Escape, end of dialogue, etc).
function M.onUiModeChanged(data)
    if data.newMode ~= I.UI.MODE.Interface then
        M.close()
    end
end

return M
