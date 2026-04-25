# OpenMW-Virtual-List

This library provides a performant virtual-list widget for use in OpenMW-lua mods.

It takes care of a lot of annoying complexities so you don't have to. Things like:    

- Creating the scrollbar and related buttons, with correct "native" look and feel.
- Ensuring the content and scrollbar are properly sized and synchronized together.
- Setting up all the conventional interaction events for mouse and keyboard input.
- Providing the necessary functions for programmatically manipulating the list UI.
- Exposing comprehensive type annotations so autocomplete and error checking work.
- Doing everything it does in a reasonably performant and memory conscious manner.


## Limitations

All items rendered in the list must have a uniform size.

If you need a list with variable item sizes you will have to find another solution.


## Performance

The widget's performance is independent of the size of the underlying data.
Lists with millions of items run just as fast as those with only a few.

All operations (scrolling, updating, rebuilding, queries, etc) run in constant
time regardless of how many items are in the list. 

Memory footprint is minimal. No per-item data is stored. The core data structure
contains just the user provided callback, a shared style reference, and a few
numbers for tracking geometry and scroll state. 

The element tree itself is also lean. User-provided item layouts are passed
through and positioned as-is. No extra wrapping or nesting.

Only the items visible in the viewport are ever created. As the user scrolls,
items leaving the view are recycled. Layout updates are only performed when
necessary, and only for items that are visible (no other items even exist).

https://github.com/user-attachments/assets/281e53c2-daa5-40c1-97f6-3546bfe47220


## Setup

The library is designed specifically to be just dropped into your mod's folder
and loaded through a basic `require()`. It intentionally uses relative requires
for all its internal structure, so there are no special requirements for how you
organize your own files. Nor do you need any extra `.omwscripts` file. 


## Examples

The `examples` folder contains minimal stand-alone implementations of both the
core and extended versions. Note: The library is not duplicated within the
example folder itself, either copy it beforehand or adjust the require paths
accordingly.


## Quick Start

```lua
local VirtualList = require("scripts.my_mod.virtual_list")

local items = {}

for i = 1, 10000 do
    items[i] = "Item " .. i
end

local list = VirtualList.create({
    viewportSize = util.vector2(400, 800),
    itemSize = util.vector2(400, 16),
    itemCount = #items,
    itemLayout = function(i)
        return {
            type = ui.TYPE.Text,
            props = {
                text = items[i],
                textColor = util.color.hex("caa560"),
                textSize = 16,
            },
        }
    end,
})
```


## Extended Version

The core `VirtualList` type is intentionally generic and unopinionated, it does
not make any assumptions about the composition of user provided layouts. As such 
it has limitations on what features it can provide.

For the more common use case of simple lists of text items, an alternative 
`extras` module is included that provides a `VirtualListExt` extension type.

This version of the list comes with additional features and conveniences,
including: standardized padding and colors, pressed/hovered/selected state
tracking, interaction sounds, keyboard navigation, and convenience functions for
constructing search and filtering related layouts.

This module is entirely optional and safe to omit or delete if you don't need
it. If you're building your own abstraction on top of the core list, it may be a
good reference for keyboard handling and other common behaviors.


```lua
local extras = require("scripts.my_mod.virtual_list.extras")

local List = extras.VirtualListExt

local list = List.create({
    viewportSize = viewportSize,
    itemSize = itemSize,
    itemCount = #items,
    itemLayout = function(i, list)
        -- The `createItemLayout` function provides an "opinionated" text
        -- layout with the native colors, builtin hovered/pressed/selected 
        -- event handlers, standard padding, and appropriate click sounds.
        return list:createItemLayout({
            index = i,
            props = { text = items[i] },
            onMousePress = function(i)
                list:changeSelection(i)
            end,
        })
    end,
})

-- Optional key press handlers that implement all the usual keyboard
-- navigation behaviors (home/end, page up/down, arrow up/down).
list:setKeyPressHandler({
    setSelectedIndex = function(i)
        list:changeSelection(i)
    end,
})

-- Not shown in this example: `createSearchBox` and `createPlaceholder` 
-- are also available for creating search and filtering implementations.

-- Mouse wheel support is available as well, but must be registered as an 
-- engine handler due to OpenMW's lack of per-element mouse wheel events.
local mouseWheelHandler = List.getMouseWheelHandler()
return {
    engineHandlers = {
        onMouseWheel = function(vertical, horizontal)
            mouseWheelHandler(vertical, horizontal)
        end,
    },
}
```


## API

### Core module

`require("scripts.my_mod.virtual_list")` returns the `VirtualList` type table.

| Function | Returns | Notes |
| --- | --- | --- |
| `VirtualList.create(params)` | `VirtualList` | Creates a virtual list. |
| `VirtualList.from(element)` | `VirtualList` | Retrieves the list from a pre-existing element. |
| `VirtualList.getMouseWheelHandler()` | `fun(y, x)` | Returns a shared mouse-wheel handler for focused lists. |
| `list:getElement()` | `Element` | Returns the underlying element, for passing to native functions. |
| `list:getItemLayout(index)` | `Layout?` | Returns the item layout for an index, or `nil` if the item is not visible. |
| `list:scrollToIndex(index, mode)` | `nil` | Scrolls an item into view, mode specifies the alignment or offset. |
| `list:rebuild(newItemCount?, newItemHeight?)` | `nil` | Allows rebuilding the visible slots after count or size changes. |
| `list:rebuildAndScroll(newCount, oldIndex?, newIndex?)` | `number?` | Rebuilds while preserving a given item's viewport position. |
| `list:getFirstVisibleIndex()` / `list:getLastVisibleIndex()` | `number` | Returns the current visible bounds. |
| `list:getFirstIndex()` / `list:getLastIndex()` | `number` | Returns the valid item bounds. |
| `list:getItemSize()` | `Vector2` | Returns the configured item dimensions. |
| `list:isItemFullyVisible(index)` | `boolean` | Returns true if the item is entirely within the viewport. |
| `list:getNextPageIndex(from, mode)` | `number` | Returns the index one page away, mode specifies the direction. |

### Extras module

| Function | Returns | Notes |
| --- | --- | --- |
| `list:createItemLayout(params)` | `Layout` | Builds a basic clickable text row. |
| `list:createSearchBox(params)` | `Element` | Builds a search box with placeholder support. |
| `list:createPlaceholder(params)` | `Layout` | Builds a simple disabled-text placeholder row. |
| `list:setKeyPressHandler(params)` | `nil` | Wires standard keyboard navigation onto the list. |
| `list:getSelectedIndex()` / `list:setSelectedIndex(index)` | `number?` / `nil` | Reads or writes selection state. |
| `list:isSelected(index)` | `boolean` | Returns true if the given index is currently selected. |
| `list:changeSelection(index, getTextLayout?)` | `nil` | Updates selection and refreshes text colors. |

### Style Options

Predefined styles are available via `require("scripts.my_mod.virtual_list.styles")`. They can be passed to `VirtualList.create` function to influence the look lists.

| Style | `edgePadding` | `buttonPadding` | `autoHideScrollBar` | Notes |
| --- | --- | --- | --- | --- |
| `Compact` | 1 | 1 | `true` | Minimal padding, for nested layouts. (Default) |
| `Full` | 6 | 3 | `true` | Standard padding, for top level layouts. |
