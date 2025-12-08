local mp = require "mp"

-- ============================================================
-- Configuration Section
-- ============================================================
local config = {
    min_skip_duration = 55,
    max_skip_duration = 140,
    print_on_file_load = true,
    case1_duration = 5,
    case2_duration = 10,
    opening_length = 85,  -- Estimated opening length (with error margin)
}

-- ============================================================
-- Global State
-- ============================================================

local auto_skip_enabled = true  -- Master toggle for all skip functionality

-- ============================================================
-- Skip Prompt State Variables (defined early for toggle function)
-- ============================================================

local skip_timer = nil
local is_skip_active = false
local skip_countdown = 0
local current_chapter_index = nil
local current_chapter_title = nil
local is_initial_load = true
local is_paused = false
local initial_prompt_duration = 0
local last_seek_time = nil
local skip_target_time = nil  -- Time to skip to

-- ============================================================
-- Auto-Skip Toggle Function (defined early)
-- ============================================================

local function toggle_auto_skip()
    auto_skip_enabled = not auto_skip_enabled
    local status = auto_skip_enabled and "ENABLED" or "DISABLED"
    mp.osd_message(string.format("Auto-skip: %s", status), 2)
    mp.msg.info(string.format("Auto-skip %s", status))
    
    -- If disabled while a prompt is active, cancel it immediately
    if not auto_skip_enabled and is_skip_active then
        -- Kill the timer
        if skip_timer then
            skip_timer:kill()
            skip_timer = nil
        end
        
        -- Clear the OSD
        mp.set_osd_ass(0, 0, "")
        
        -- Remove key bindings
        mp.remove_key_binding("skip-now")
        mp.remove_key_binding("skip-cancel")
        mp.remove_key_binding("countdown-up")
        mp.remove_key_binding("countdown-down")
        
        -- Reset state
        is_skip_active = false
        is_paused = false
        initial_prompt_duration = 0
        last_seek_time = nil
        skip_target_time = nil
        
        mp.msg.info("Active skip prompt cancelled (auto-skip disabled)")
    end
end

-- ============================================================
-- Chapter Analysis Functions
-- ============================================================

local function format_time(seconds)
    if not seconds then return "00:00" end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end

local function get_chapter_duration(start_time, end_time)
    if not start_time or not end_time then return 0 end
    return end_time - start_time
end

local function categorize_chapter(duration)
    if duration >= config.min_skip_duration and duration <= config.max_skip_duration then
        return "Skippable"
    else
        return "Normal"
    end
end

-- ============================================================
-- Case 2 & 3 Trigger Management
-- ============================================================

local case2_triggers = {}  -- List of {trigger_time, skip_chapter_index, skip_chapter_title, target_time, triggered}
local case3_trigger = nil  -- Single Case 3 trigger {trigger_time, target_time, chapter2_start, triggered, is_immediate}
local last_playback_time = 0

local function calculate_case2_triggers()
    case2_triggers = {}
    local chapter_count = mp.get_property_number("chapter-list/count", 0)
    
    if chapter_count < 2 then return end  -- Need at least 2 chapters
    
    for i = 0, chapter_count - 2 do  -- Check all transitions
        local current_time = mp.get_property_number(string.format("chapter-list/%d/time", i))
        local skip_time = mp.get_property_number(string.format("chapter-list/%d/time", i + 1))
        local end_time = mp.get_property_number("duration", 0)
        
        -- Calculate durations
        local current_duration = get_chapter_duration(current_time, skip_time)
        local skip_duration = 0
        
        if i + 1 < chapter_count - 1 then
            -- There's a chapter after the skippable one
            local next_time = mp.get_property_number(string.format("chapter-list/%d/time", i + 2))
            skip_duration = get_chapter_duration(skip_time, next_time)
        else
            -- Skippable chapter is the last one
            skip_duration = get_chapter_duration(skip_time, end_time)
        end
        
        -- Categorize chapters
        local current_category = categorize_chapter(current_duration)
        local skip_category = categorize_chapter(skip_duration)
        
        -- Check for Normal → Skippable pattern
        if current_category == "Normal" and skip_category == "Skippable" then
            local trigger_time = skip_time - 5  -- 5 seconds before skippable chapter
            
            if trigger_time > current_time then  -- Ensure trigger is within current chapter
                local skip_chapter_title = mp.get_property(string.format("chapter-list/%d/title", i + 1)) 
                    or string.format("Chapter %d", i + 2)
                
                -- Determine target time
                local target_time
                if i + 1 < chapter_count - 1 then
                    -- There's a chapter after the skippable one
                    target_time = mp.get_property_number(string.format("chapter-list/%d/time", i + 2))
                else
                    -- Skippable chapter is the last one - skip to end of file
                    target_time = end_time
                end
                
                table.insert(case2_triggers, {
                    time = trigger_time,
                    skip_chapter_index = i + 1,
                    skip_chapter_title = skip_chapter_title,
                    target_time = target_time,
                    triggered = false
                })
            end
        end
    end
end

local function calculate_case3_trigger()
    case3_trigger = nil
    local chapter_count = mp.get_property_number("chapter-list/count", 0)
    
    if chapter_count < 2 then return end  -- Need at least Chapter 1 and Chapter 2
    
    -- Get Chapter 1 info
    local chapter1_start = mp.get_property_number("chapter-list/0/time", 0)
    local chapter2_start = mp.get_property_number("chapter-list/1/time", 0)
    local end_time = mp.get_property_number("duration", 0)
    
    -- Calculate Chapter 1 duration
    local chapter1_duration = get_chapter_duration(chapter1_start, chapter2_start)
    local chapter1_category = categorize_chapter(chapter1_duration)
    
    -- Validate conditions for Case 3
    if chapter1_category == "Normal" and chapter1_duration > 90 then
        -- Calculate opening start time
        local opening_start = chapter2_start - config.opening_length - 5
        
        -- Ensure opening_start is within Chapter 1
        if opening_start >= chapter1_start and opening_start < chapter2_start then
            local final_seconds_start = chapter2_start - 10
            
            case3_trigger = {
                trigger_time = opening_start,
                target_time = chapter2_start,
                chapter2_start = chapter2_start,
                final_seconds_start = final_seconds_start,
                triggered = false,
                is_immediate = false  -- Will be set based on opening position
            }
        end
    end
end

local function analyze_chapters()
    local chapter_count = mp.get_property_number("chapter-list/count", 0)

    if chapter_count == 0 then
        mp.msg.info("No chapters found in this file")
        return
    end

    mp.msg.info("==============================================================")
    mp.msg.info(string.format("* Chapter-Skip - Session Summary   [ %d chapters ]", chapter_count))
    mp.msg.info("==============================================================")

    for i = 0, chapter_count - 1 do
        local chapter_time = mp.get_property_number(string.format("chapter-list/%d/time", i))
        local chapter_title = mp.get_property(string.format("chapter-list/%d/title", i)) or string.format("Chapter %d", i + 1)

        local next_time
        if i < chapter_count - 1 then
            next_time = mp.get_property_number(string.format("chapter-list/%d/time", i + 1))
        else
            next_time = mp.get_property_number("duration", 0)
        end

        local duration = get_chapter_duration(chapter_time, next_time)
        local duration_min = duration / 60
        local category = categorize_chapter(duration)

        -- Check if this is a skippable chapter that has a Case 2 trigger
        local trigger_info = ""
        for _, trigger in ipairs(case2_triggers) do
            if trigger.skip_chapter_index == i then
                trigger_info = string.format(" [Skip Trigger: %s]", format_time(trigger.time))
                break
            end
        end

        mp.msg.info(string.format("* %s (%.2f min) - [ %s -> %s ] - (%s)%s",
            chapter_title,
            duration_min,
            format_time(chapter_time),
            format_time(next_time),
            category,
            trigger_info
        ))
    end

    -- Log Case 2 triggers summary
    if #case2_triggers > 0 then
        mp.msg.info("--------------------------------------------------------------")
        mp.msg.info("* Case 2 Triggers (Skip upcoming skippable chapters):")
        for i, trigger in ipairs(case2_triggers) do
            local target_desc = format_time(trigger.target_time)
            if trigger.target_time == mp.get_property_number("duration", 0) then
                target_desc = target_desc .. " (end of file)"
            end
            mp.msg.info(string.format("  %d. At %s → Skip '%s' → Land at %s", 
                i, 
                format_time(trigger.time), 
                trigger.skip_chapter_title,
                target_desc))
        end
    end

    -- Log Case 3 trigger if exists
    if case3_trigger then
        mp.msg.info("--------------------------------------------------------------")
        mp.msg.info("* Case 3 Trigger (Opening detection):")
        mp.msg.info(string.format("  Opening starts at: %s", format_time(case3_trigger.trigger_time)))
        mp.msg.info(string.format("  Skip to: %s (Chapter 2)", format_time(case3_trigger.target_time)))
        mp.msg.info(string.format("  Final 10s start: %s", format_time(case3_trigger.final_seconds_start)))
    end

    -- Show auto-skip status in summary
    mp.msg.info("--------------------------------------------------------------")
    mp.msg.info(string.format("* Auto-skip: %s (Ctrl+y to toggle)", 
        auto_skip_enabled and "ENABLED" or "DISABLED"))

    mp.msg.info("==============================================================")
end

-- ============================================================
-- Skip Prompt Functions
-- ============================================================

local function perform_skip()
    if skip_target_time then
        -- Case 2 or Case 3: Skip to target time
        mp.commandv("seek", skip_target_time, "absolute", "exact")
        mp.osd_message(string.format("Skipped '%s'", current_chapter_title), 2)
    elseif current_chapter_index then
        -- Case 1: Skip to next chapter
        local chapter_count = mp.get_property_number("chapter-list/count", 0)
        if current_chapter_index < chapter_count - 1 then
            local next_chapter_time = mp.get_property_number(string.format("chapter-list/%d/time", current_chapter_index + 1))
            mp.commandv("seek", next_chapter_time, "absolute", "exact")
            mp.osd_message(string.format("Skipped '%s'", current_chapter_title), 2)
        end
    end
end

local function cancel_skip()
    if skip_timer then
        skip_timer:kill()
        skip_timer = nil
    end
    is_skip_active = false
    is_paused = false
    initial_prompt_duration = 0
    last_seek_time = nil
    skip_target_time = nil
    
    -- Remove the key bindings
    mp.remove_key_binding("skip-now")
    mp.remove_key_binding("skip-cancel")
    mp.remove_key_binding("countdown-up")
    mp.remove_key_binding("countdown-down")
    
    -- Clear OSD
    mp.set_osd_ass(0, 0, "")
end

local function update_skip_prompt()
    if not is_skip_active then
        mp.set_osd_ass(0, 0, "")
        return
    end
    
    -- Don't update countdown if paused
    if is_paused then
        -- Still show current countdown when paused
        local osd_text = string.format(
            '{\\an9}Skipping "%s" in %d...\\NPress "J" to skip now.\\NPress "j" to cancel.',
            current_chapter_title,
            skip_countdown
        )
        mp.set_osd_ass(0, 0, osd_text)
        return
    end
    
    skip_countdown = skip_countdown - 1
    
    if skip_countdown <= 0 then
        perform_skip()
        cancel_skip()
        return
    end
    
    -- Create ASS-formatted OSD message for right alignment
    -- \an9 = top-right alignment
    local osd_text = string.format(
        '{\\an9}Skipping "%s" in %d...\\NPress "J" to skip now.\\NPress "j" to cancel.',
        current_chapter_title,
        skip_countdown
    )
    
    -- Display with set_osd_ass for precise positioning
    mp.set_osd_ass(0, 0, osd_text)
end

local function force_update_osd()
    if not is_skip_active then
        mp.set_osd_ass(0, 0, "")
        return
    end
    
    -- Direct OSD update without countdown decrement
    local osd_text = string.format(
        '{\\an9}Skipping "%s" in %d...\\NPress "J" to skip now.\\NPress "j" to cancel.',
        current_chapter_title,
        skip_countdown
    )
    
    mp.set_osd_ass(0, 0, osd_text)
end

-- ============================================================
-- Countdown Adjustment Functions
-- ============================================================

local function adjust_countdown_up()
    if not is_skip_active then return end
    
    local old_countdown = skip_countdown
    local new_countdown = skip_countdown + 3
    
    -- Cap at maximum duration
    if new_countdown > initial_prompt_duration then
        new_countdown = initial_prompt_duration
    end
    
    if new_countdown ~= old_countdown then
        skip_countdown = new_countdown
        mp.msg.info(string.format("Countdown adjusted: %d → %d seconds (Ctrl+k: +3s)", 
            old_countdown, new_countdown))
        force_update_osd()
    end
end

local function adjust_countdown_down()
    if not is_skip_active then return end
    
    local old_countdown = skip_countdown
    local new_countdown = skip_countdown - 3
    
    -- Ensure minimum of 1 second
    if new_countdown < 1 then
        new_countdown = 1
    end
    
    if new_countdown ~= old_countdown then
        skip_countdown = new_countdown
        mp.msg.info(string.format("Countdown adjusted: %d → %d seconds (Ctrl+j: -3s)", 
            old_countdown, new_countdown))
        force_update_osd()
    end
end

local function skip_prompt(duration, chapter_title, target_time)
    -- Check if auto-skip is enabled
    if not auto_skip_enabled then
        mp.msg.info("Skip prompt blocked: Auto-skip is disabled")
        return
    end
    
    if is_skip_active then
        cancel_skip()
    end
    
    is_skip_active = true
    skip_countdown = duration
    initial_prompt_duration = duration
    current_chapter_title = chapter_title
    skip_target_time = target_time
    is_paused = false
    last_seek_time = mp.get_property_number("time-pos", 0)
    
    -- Start the countdown timer (updates every second)
    skip_timer = mp.add_periodic_timer(1, update_skip_prompt)
    
    -- Show initial prompt
    force_update_osd()
    
    -- Add key bindings for skip and cancel
    mp.add_key_binding("J", "skip-now", function()
        perform_skip()
        cancel_skip()
    end)
    
    mp.add_key_binding("j", "skip-cancel", cancel_skip)
    
    -- Add key bindings for countdown adjustment
    mp.add_key_binding("Ctrl+k", "countdown-up", adjust_countdown_up)
    mp.add_key_binding("Ctrl+j", "countdown-down", adjust_countdown_down)
end

-- ============================================================
-- Seek Adjustment Functions
-- ============================================================

local function adjust_countdown_for_seek(seek_amount)
    if not is_skip_active then
        return
    end
    
    -- Calculate new countdown: C - S (where S is positive for forward, negative for backward)
    local new_countdown = skip_countdown - seek_amount
    
    -- Check if new countdown is within valid range (1 to initial duration)
    if new_countdown <= 0 then
        -- Seeking forward past the skip point
        mp.msg.info(string.format("Seek forward by %ds: countdown would be %d (≤0) - cancelling prompt", 
            seek_amount, new_countdown))
        cancel_skip()
    elseif new_countdown > initial_prompt_duration then
        -- Seeking backward beyond initial duration
        mp.msg.info(string.format("Seek backward by %ds: countdown would be %d (>%d) - cancelling prompt", 
            math.abs(seek_amount), new_countdown, initial_prompt_duration))
        cancel_skip()
    else
        -- Valid seek adjustment
        skip_countdown = new_countdown
        mp.msg.info(string.format("Adjusted countdown: %d -> %d (seek: %ds)", 
            skip_countdown + seek_amount, skip_countdown, seek_amount))
        
        -- Force immediate OSD update to show new countdown
        force_update_osd()
    end
end

local function handle_seek()
    if not is_skip_active or not last_seek_time then
        last_seek_time = mp.get_property_number("time-pos", 0)
        return
    end
    
    local current_time = mp.get_property_number("time-pos", 0)
    local seek_amount = current_time - last_seek_time
    
    -- Only process if there was an actual seek (not just normal playback)
    -- We use a threshold to distinguish seeks from normal playback
    if math.abs(seek_amount) > 0.5 then  -- Increased threshold to be more reliable
        adjust_countdown_for_seek(seek_amount)
    end
    
    -- Update last seek time
    last_seek_time = current_time
end

-- ============================================================
-- Case 2 Trigger Detection
-- ============================================================

local function check_case2_triggers()
    local current_time = mp.get_property_number("time-pos", 0)
    
    -- Don't check on the very first call after file load
    if last_playback_time == 0 then
        last_playback_time = current_time
        return
    end
    
    -- Reset triggers if seeking backward past them
    if current_time < last_playback_time then
        for _, trigger in ipairs(case2_triggers) do
            if trigger.triggered and current_time < trigger.time then
                trigger.triggered = false
                mp.msg.info(string.format("Reset trigger at %s (seek backward)", format_time(trigger.time)))
            end
        end
        
        -- Reset Case 3 trigger if seeking backward past it
        if case3_trigger and case3_trigger.triggered and current_time < case3_trigger.trigger_time then
            case3_trigger.triggered = false
            case3_trigger.is_immediate = false
            mp.msg.info(string.format("Reset Case 3 trigger at %s (seek backward)", format_time(case3_trigger.trigger_time)))
        end
    end
    
    -- Check for triggers when moving forward
    if current_time > last_playback_time then
        -- Check Case 2 triggers first (they have priority)
        for _, trigger in ipairs(case2_triggers) do
            -- Only trigger if we're BEFORE the skippable chapter
            local skip_chapter_start = mp.get_property_number(
                string.format("chapter-list/%d/time", trigger.skip_chapter_index))
            
            if current_time < skip_chapter_start and not trigger.triggered and current_time >= trigger.time then
                -- Found a trigger!
                trigger.triggered = true
                
                local target_desc = format_time(trigger.target_time)
                if trigger.target_time == mp.get_property_number("duration", 0) then
                    target_desc = target_desc .. " (end of file)"
                end
                
                mp.msg.info(string.format("Case 2 trigger detected at %s → Skipping '%s' → Landing at %s", 
                    format_time(trigger.time), 
                    trigger.skip_chapter_title,
                    target_desc))
                
                -- Only start skip prompt if auto-skip is enabled
                if auto_skip_enabled then
                    mp.msg.info("Case 2: Starting skip prompt")
                    -- Start the skip prompt
                    skip_prompt(config.case2_duration, trigger.skip_chapter_title, trigger.target_time)
                else
                    mp.msg.info("Case 2: Skip prompt blocked (auto-skip disabled)")
                end
                return  -- Only trigger one at a time
            end
        end
        
        -- Check Case 3 trigger (if no Case 2 triggered)
        if case3_trigger and not case3_trigger.triggered and not case3_trigger.is_immediate then
            if current_time >= case3_trigger.trigger_time then
                -- Check if we're in the final 10 seconds
                if current_time < case3_trigger.final_seconds_start then
                    -- Not in final 10 seconds - trigger Case 3
                    case3_trigger.triggered = true
                    mp.msg.info(string.format("Case 3 trigger detected at %s → Skipping Opening → Landing at %s", 
                        format_time(case3_trigger.trigger_time),
                        format_time(case3_trigger.target_time)))
                    
                    -- Only start skip prompt if auto-skip is enabled
                    if auto_skip_enabled then
                        mp.msg.info("Case 3: Starting skip prompt")
                        -- Start the skip prompt (10 seconds)
                        skip_prompt(config.case2_duration, "Opening", case3_trigger.target_time)
                    else
                        mp.msg.info("Case 3: Skip prompt blocked (auto-skip disabled)")
                    end
                else
                    -- In final 10 seconds - mark as triggered but don't show prompt
                    case3_trigger.triggered = true
                    mp.msg.info(string.format("Case 3 skipped: In final 10s of opening (at %s)", 
                        format_time(current_time)))
                end
            end
        end
    end
    
    last_playback_time = current_time
end

-- ============================================================
-- Case 3 Immediate Trigger (on file load)
-- ============================================================

local function check_and_trigger_case3_immediate()
    if not case3_trigger or is_skip_active then
        return
    end
    
    local current_time = mp.get_property_number("time-pos", 0)
    
    -- Check if we're in the opening (after trigger_time but before chapter2_start)
    if current_time >= case3_trigger.trigger_time and current_time < case3_trigger.chapter2_start then
        -- Check if we're in the final 10 seconds
        if current_time < case3_trigger.final_seconds_start then
            -- Not in final 10 seconds - trigger immediate 5s prompt
            case3_trigger.triggered = true
            case3_trigger.is_immediate = true
            mp.msg.info(string.format("Case 3 immediate trigger: In opening at %s", 
                format_time(current_time)))
            
            -- Only start skip prompt if auto-skip is enabled
            if auto_skip_enabled then
                mp.msg.info("Case 3: Starting immediate 5s prompt")
                -- Start the skip prompt (5 seconds)
                skip_prompt(config.case1_duration, "Opening", case3_trigger.target_time)
            else
                mp.msg.info("Case 3: Immediate prompt blocked (auto-skip disabled)")
            end
        else
            -- In final 10 seconds - no prompt
            case3_trigger.triggered = true
            mp.msg.info(string.format("Case 3 skipped: In final 10s of opening (at %s)", 
                format_time(current_time)))
        end
    end
end

-- ============================================================
-- Pause/Resume Functions
-- ============================================================

local function handle_pause_change(name, value)
    if not is_skip_active then
        return
    end
    
    local was_paused = is_paused
    is_paused = (value == true or value == "yes" or value == "true")
    
    if was_paused and not is_paused then
        -- Resuming from pause
        mp.msg.info("Skip countdown resumed")
        -- Update last_seek_time when resuming to prevent false seek detection
        last_seek_time = mp.get_property_number("time-pos", 0)
        -- Force OSD update
        force_update_osd()
    elseif not was_paused and is_paused then
        -- Pausing
        mp.msg.info("Skip countdown paused")
        -- Force OSD update to show current countdown
        force_update_osd()
    end
end

-- ============================================================
-- Chapter Detection Functions (for Case 1)
-- ============================================================

local function get_current_chapter_info()
    local chapter_count = mp.get_property_number("chapter-list/count", 0)
    if chapter_count == 0 then return nil, nil end
    
    local current_time = mp.get_property_number("time-pos", 0)
    
    for i = 0, chapter_count - 1 do
        local chapter_time = mp.get_property_number(string.format("chapter-list/%d/time", i))
        local next_time
        
        if i < chapter_count - 1 then
            next_time = mp.get_property_number(string.format("chapter-list/%d/time", i + 1))
        else
            next_time = mp.get_property_number("duration", math.huge)
        end
        
        if current_time >= chapter_time and current_time < next_time then
            local chapter_title = mp.get_property(string.format("chapter-list/%d/title", i)) or string.format("Chapter %d", i + 1)
            local duration = get_chapter_duration(chapter_time, next_time)
            local category = categorize_chapter(duration)
            
            return i, chapter_title, category, chapter_time, next_time
        end
    end
    
    return nil, nil, nil, nil, nil
end

local function check_and_trigger_case1()
    -- Only trigger on initial load, not when seeking
    if not is_initial_load then
        return
    end
    
    local chapter_index, chapter_title, category, chapter_start, chapter_end = get_current_chapter_info()
    
    if chapter_index and category == "Skippable" then
        -- Check if we're in the final 10 seconds of the chapter
        local current_time = mp.get_property_number("time-pos", 0)
        local time_until_end = chapter_end - current_time
        local CASE1_FINAL_SECONDS = 10  -- Hardcoded exclusion threshold
        
        if time_until_end > CASE1_FINAL_SECONDS then
            -- Not in final 10 seconds - trigger Case 1
            current_chapter_index = chapter_index
            current_chapter_title = chapter_title
            
            -- Only start skip prompt if auto-skip is enabled
            if auto_skip_enabled then
                mp.msg.info(string.format("Case 1 trigger: In skippable chapter '%s' (%.1fs until end)", 
                    chapter_title, time_until_end))
                skip_prompt(config.case1_duration, chapter_title, nil)
            else
                mp.msg.info(string.format("Case 1 trigger blocked: In skippable chapter '%s' (auto-skip disabled)", 
                    chapter_title))
            end
        else
            -- In final 10 seconds - no prompt
            mp.msg.info(string.format("Case 1 skipped: In final %.1fs of skippable chapter '%s'", 
                time_until_end, chapter_title))
        end
    end
    
    -- Reset initial load flag after first check
    is_initial_load = false
end

-- ============================================================
-- Event Handlers
-- ============================================================

mp.register_event("file-loaded", function()
    if config.print_on_file_load then
        -- Calculate all triggers first
        calculate_case2_triggers()
        calculate_case3_trigger()
        analyze_chapters()
    else
        calculate_case2_triggers()
        calculate_case3_trigger()
    end
    
    -- Reset initial load flag for new file
    is_initial_load = true
    
    -- Initialize last_playback_time to current position (so we only detect FUTURE movement)
    last_playback_time = mp.get_property_number("time-pos", 0)
    last_seek_time = last_playback_time
    
    -- Reset all triggers
    for _, trigger in ipairs(case2_triggers) do
        trigger.triggered = false
    end
    
    if case3_trigger then
        case3_trigger.triggered = false
        case3_trigger.is_immediate = false
    end
    
    -- Cancel any active skip from previous file
    if is_skip_active then
        cancel_skip()
    end
    
    -- Check if we start playback inside a skippable chapter (Case 1)
    -- Use a small delay to ensure chapter data is loaded
    mp.add_timeout(0.1, function()
        check_and_trigger_case1()
        -- Check for Case 3 immediate trigger after Case 1 check
        check_and_trigger_case3_immediate()
    end)
end)

-- Observe pause property changes
mp.observe_property("pause", "bool", handle_pause_change)

-- Observe time position for seek detection and triggers
mp.observe_property("time-pos", "number", function(name, value)
    -- Use a small delay to ensure this runs after seek commands complete
    mp.add_timeout(0.05, function()
        handle_seek()
        check_case2_triggers()
    end)
end)

-- Add global toggle key binding (always active)
mp.add_key_binding("Ctrl+y", "toggle-auto-skip", toggle_auto_skip)

mp.msg.info("Chapter Skip script loaded. Auto-display on file load.")
