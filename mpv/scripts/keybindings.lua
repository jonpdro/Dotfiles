local mp = require 'mp'
local utils = require 'mp.utils'
local assdraw = require 'mp.assdraw'

local visible = false
local current_category = 1
local categories = {}

-- Format key name to look nicer
local function format_key(key)
    -- Replace common key names
    local replacements = {
        ["SPACE"] = "Space",
        ["ESC"] = "Esc",
        ["BS"] = "Backspace",
        ["WHEEL_DOWN"] = "Wheel Down",
        ["WHEEL_UP"] = "Wheel Up",
        ["UP"] = "↑",
        ["DOWN"] = "↓",
        ["LEFT"] = "←",
        ["RIGHT"] = "→",
        ["left"] = "←",
        ["right"] = "→",
        ["up"] = "↑",
        ["down"] = "↓"
    }
    
    -- Handle modifier keys
    key = key:gsub("Ctrl%+", "Ctrl + ")
    key = key:gsub("Alt%+", "Alt + ")
    key = key:gsub("Shift%+", "Shift + ")
    key = key:gsub("CTRL%+", "Ctrl + ")
    key = key:gsub("ALT%+", "Alt + ")
    key = key:gsub("SHIFT%+", "Shift + ")
    
    -- Replace key names
    for old, new in pairs(replacements) do
        key = key:gsub("^" .. old .. "$", new)
        key = key:gsub("^" .. old:lower() .. "$", new)
    end
    
    -- Capitalize single letters after modifiers
    key = key:gsub("(%+ )(%w)$", function(space, letter)
        return space .. letter:upper()
    end)
    
    return key
end

-- Parse input.conf file
local function parse_input_conf()
    local input_file = mp.command_native({"expand-path", "~~/input.conf"})
    local file = io.open(input_file, "r")
    
    if not file then
        mp.osd_message("Could not open input.conf", 3)
        return
    end
    
    local current_cat = nil
    
    for line in file:lines() do
        -- Check for category headers
        local category = line:match("^###%s*(.-)%s*###$")
        if category then
            current_cat = {name = category, bindings = {}}
            table.insert(categories, current_cat)
        -- Skip pure comment lines (starting with # but not ###) and empty lines
        elseif line:match("^%s*$") or line:match("^%s*#[^#]") then
            -- Skip
        -- Parse binding lines
        elseif current_cat then
            local key, rest = line:match("^(%S+)%s+(.+)$")
            if key and rest then
                local description = nil
                
                -- First try to find # comment
                local comment = rest:match("#%s*(.*)$")
                if comment and comment ~= "" then
                    description = comment
                -- Then try to find show-text with quoted string
                elseif rest:match('show%-text%s+"([^"]+)"') then
                    description = rest:match('show%-text%s+"([^"]+)"')
                end
                
                if description then
                    table.insert(current_cat.bindings, {
                        key = format_key(key),
                        description = description
                    })
                end
            end
        end
    end
    
    file:close()
    
    -- Add "Empty for now." message to empty categories
    for _, cat in ipairs(categories) do
        if #cat.bindings == 0 then
            table.insert(cat.bindings, {key = "", description = "Empty for now."})
        end
    end
end

-- Generate ASS formatted text for display
local function generate_display()
    if #categories == 0 then
        return "{\\an5}No keybindings found"
    end
    
    local cat = categories[current_category]
    local ass = assdraw.ass_new()
    
    -- Title with bold and yellow color
    ass:new_event()
    ass:an(7)
    ass:pos(20, 20)
    ass:append("{\\fs9\\bord1\\shad0\\1c&H000000&\\1a&H00&\\b1\\c&H00FFFF&}" .. cat.name .. "{\\b0\\c&HFFFFFF&}\\N\\N")
    
    for _, binding in ipairs(cat.bindings) do
        if binding.key ~= "" then
            local spaces = string.rep(" ", math.max(1, 20 - #binding.key))
            ass:append("{\\c&H00FFFF&}" .. binding.key .. spaces .. "{\\c&HFFFFFF&}" .. binding.description .. "\\N")
        else
            ass:append(binding.description .. "\\N")
        end
    end
    
    ass:append("\\N{\\c&H666666&}[j/k: navigate] [?: close] [" .. current_category .. "/" .. #categories .. "]")
    
    return ass.text
end

-- Show the overlay
local function show_overlay()
    local ass = generate_display()
    mp.set_osd_ass(0, 0, ass)
end

-- Hide the overlay
local function hide_overlay()
    mp.set_osd_ass(0, 0, "")
end

-- Toggle visibility
local function toggle_display()
    visible = not visible
    if visible then
        mp.set_property("input-default-bindings", "no")
        show_overlay()
    else
        mp.set_property("input-default-bindings", "yes")
        hide_overlay()
    end
end

-- Navigate to previous category
local function prev_category()
    if not visible then return end
    current_category = current_category - 1
    if current_category < 1 then
        current_category = #categories
    end
    show_overlay()
end

-- Navigate to next category
local function next_category()
    if not visible then return end
    current_category = current_category + 1
    if current_category > #categories then
        current_category = 1
    end
    show_overlay()
end

-- Initialize
parse_input_conf()

-- Bind keys at startup
mp.add_forced_key_binding("?", "toggle-keybindings", toggle_display)
mp.add_forced_key_binding("Tab", "next-category", next_category)
