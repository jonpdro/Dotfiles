-- Chapter Auto-Skip Script for MPV
-- Automatically prompts to skip chapters based on length

local mp = require 'mp'
local msg = require 'mp.msg'

-- Configuration
local MIN_SKIP_LENGTH = 45  -- seconds
local MAX_SKIP_LENGTH = 140 -- seconds
local CASE1_DURATION = 5    -- seconds
local CASE2_DURATION = 10   -- seconds

-- State
local auto_skip_enabled = true
local chapters = {}
local transition_ranges = {}
local active_prompt = nil
local countdown_timer = nil
local position_monitor = nil
local last_range_check = nil
local cancelled_chapters = {}  -- Track chapters where user cancelled skip
local file_just_loaded = false  -- Track if file was just loaded to ignore initial seek

-- Categorize chapters and calculate transition ranges
local function categorize_chapters()
    chapters = {}
    transition_ranges = {}
    local chapter_list = mp.get_property_native("chapter-list")
    
    if not chapter_list or #chapter_list == 0 then
        msg.info("No chapters found in video")
        return
    end
    
    msg.info("=== Chapter Analysis ===")
    
    for i, chapter in ipairs(chapter_list) do
        local length
        if i < #chapter_list then
            length = chapter_list[i + 1].time - chapter.time
        else
            -- Last chapter: calculate from chapter start to video end
            local duration = mp.get_property_number("duration")
            if duration then
                length = duration - chapter.time
            else
                length = 0
            end
        end
        
        local is_skippable = length > MIN_SKIP_LENGTH and length < MAX_SKIP_LENGTH
        
        chapters[i] = {
            index = i,
            title = chapter.title,
            start_time = chapter.time,
            length = length,
            skippable = is_skippable
        }
        
        msg.info(string.format("Chapter %d: '%s' | Start: %.2fs | Length: %.2fs | %s",
                               i, chapter.title or "Untitled", chapter.time, length,
                               is_skippable and "SKIPPABLE" or "NORMAL"))
    end
    
    -- Calculate transition ranges (last 5s of normal + first 5s of skippable)
    msg.info("=== Transition Ranges ===")
    for i = 1, #chapters - 1 do
        local current = chapters[i]
        local next = chapters[i + 1]
        
        -- Only create transition range if current is normal and next is skippable
        if not current.skippable and next.skippable then
            local range_start = next.start_time - 5
            local range_end = next.start_time + 5
            
            table.insert(transition_ranges, {
                start_time = range_start,
                end_time = range_end,
                boundary_time = next.start_time,
                target_chapter = i + 1  -- Index of the skippable chapter
            })
            
            msg.info(string.format("Transition %d->%d: %.2fs to %.2fs (boundary: %.2fs)",
                                   i, i + 1, range_start, range_end, next.start_time))
        end
    end
    
    if #transition_ranges == 0 then
        msg.info("No transition ranges (no normal->skippable sequences)")
    end
end

-- Get chapter name for display
local function get_chapter_name(chapter_index)
    if chapters[chapter_index] and chapters[chapter_index].title and chapters[chapter_index].title ~= "" then
        return chapters[chapter_index].title
    else
        return "Chapter " .. chapter_index
    end
end

-- Show OSD message
local function show_osd(text, duration)
    mp.osd_message(text, duration or 2)
end

-- Update countdown display
local function update_osd()
    if not active_prompt then
        mp.set_osd_ass(0, 0, "")
        return
    end
    
    local chapter_name = get_chapter_name(active_prompt.chapter_index)
    local osd_text = string.format("{\\an9}Skipping \"%s\" in %d...\\NPress \"J\" to skip now.\\NPress \"j\" to cancel.",
                                   chapter_name, active_prompt.countdown)
    mp.set_osd_ass(0, 0, osd_text)
end

-- Cancel active prompt
local function cancel_prompt()
    if countdown_timer then
        countdown_timer:kill()
        countdown_timer = nil
    end
    
    -- Mark this chapter as cancelled by the user
    if active_prompt then
        msg.info(string.format("[CANCEL] User cancelled skip for chapter %d", active_prompt.chapter_index))
        cancelled_chapters[active_prompt.chapter_index] = true
    end
    
    active_prompt = nil
    last_range_check = nil
    mp.set_osd_ass(0, 0, "")
end

-- Skip to next chapter immediately
local function skip_now()
    if not active_prompt then
        msg.warn("[SKIP NOW] No active prompt to skip")
        return
    end
    
    local next_chapter = active_prompt.chapter_index
    msg.info(string.format("[SKIP NOW] Immediately skipping to chapter %d", next_chapter))
    cancel_prompt()
    mp.set_property_number("chapter", next_chapter)
end

-- Handle countdown tick
local function countdown_tick()
    if not active_prompt then
        return
    end
    
    -- Check if paused
    local paused = mp.get_property_bool("pause")
    if paused then
        active_prompt.paused = true
        return
    end
    
    -- If was paused and now resumed, just update display
    if active_prompt.paused then
        active_prompt.paused = false
        msg.info(string.format("[COUNTDOWN] Resumed at %d seconds", active_prompt.countdown))
        update_osd()
        return
    end
    
    -- Decrement countdown
    active_prompt.countdown = active_prompt.countdown - 1
    msg.info(string.format("[COUNTDOWN] Chapter %d countdown: %d", 
                           active_prompt.chapter_index, active_prompt.countdown))
    
    if active_prompt.countdown <= 0 then
        -- Time to skip
        msg.info(string.format("[AUTO-SKIP] Countdown reached 0, skipping chapter %d", 
                               active_prompt.chapter_index))
        skip_now()
        return
    end
    
    update_osd()
end

-- Start countdown timer
local function start_countdown()
    if countdown_timer then
        countdown_timer:kill()
    end
    
    update_osd()
    countdown_timer = mp.add_periodic_timer(1.0, countdown_tick)
end

-- Trigger skip prompt
local function trigger_prompt(chapter_index, prompt_type, countdown_duration)
    if not auto_skip_enabled then
        msg.info(string.format("[TRIGGER] Auto-skip disabled, not triggering for chapter %d", chapter_index))
        return
    end
    
    -- Don't trigger if user already cancelled this chapter
    if cancelled_chapters[chapter_index] then
        msg.info(string.format("[TRIGGER] Chapter %d was cancelled by user, not re-triggering", chapter_index))
        return
    end
    
    if active_prompt then
        -- Don't retrigger if already showing prompt for same chapter
        if active_prompt.chapter_index == chapter_index then
            msg.info(string.format("[TRIGGER] Prompt already active for chapter %d, skipping", chapter_index))
            return
        end
        cancel_prompt()
    end
    
    msg.info(string.format("[TRIGGER] Starting %s prompt for chapter %d ('%s') with %ds countdown",
                           prompt_type, chapter_index, get_chapter_name(chapter_index), countdown_duration))
    
    active_prompt = {
        chapter_index = chapter_index,
        type = prompt_type,
        countdown = countdown_duration,
        paused = mp.get_property_bool("pause")
    }
    
    start_countdown()
end

-- Find which transition range we're in (if any)
local function find_transition_range(time_pos)
    for _, range in ipairs(transition_ranges) do
        if time_pos >= range.start_time and time_pos < range.end_time then
            return range
        end
    end
    return nil
end

-- Monitor playback position for transitions
local function monitor_position()
    if not auto_skip_enabled or #chapters == 0 then
        return
    end
    
    local current_time = mp.get_property_number("time-pos")
    if not current_time then
        return
    end
    
    -- Check if we're in a transition range
    local range = find_transition_range(current_time)
    
    if range then
        -- We're in a transition range
        if not active_prompt or active_prompt.chapter_index ~= range.target_chapter then
            msg.info(string.format("[MONITOR] Entered transition range at %.2fs, targeting chapter %d",
                                   current_time, range.target_chapter))
            -- Trigger case 2 prompt
            trigger_prompt(range.target_chapter, "case2", CASE2_DURATION)
            last_range_check = range
        end
    else
        -- We left the transition range
        if active_prompt and active_prompt.type == "case2" and last_range_check then
            msg.info(string.format("[MONITOR] Left transition range at %.2fs, cancelling case2 prompt",
                                   current_time))
            -- User seeked out of the transition range
            cancel_prompt()
        end
        last_range_check = nil
    end
end

-- Start position monitor
local function start_position_monitor()
    if position_monitor then
        return
    end
    position_monitor = mp.add_periodic_timer(0.2, monitor_position)
end

-- Stop position monitor
local function stop_position_monitor()
    if position_monitor then
        position_monitor:kill()
        position_monitor = nil
    end
end

-- Handle file loaded
local function on_file_loaded()
    msg.info("=== FILE LOADED ===")
    cancel_prompt()
    stop_position_monitor()
    cancelled_chapters = {}  -- Reset cancelled chapters for new file
    file_just_loaded = true  -- Mark that file just loaded
    categorize_chapters()
    
    if #chapters == 0 or not auto_skip_enabled then
        msg.info("Skipping initialization (no chapters or auto-skip disabled)")
        return
    end
    
    -- Start monitoring positions
    start_position_monitor()
    msg.info("Position monitor started")
    
    local current_time = mp.get_property_number("time-pos")
    local current_chapter_index = mp.get_property_number("chapter")
    
    if not current_time or not current_chapter_index then
        msg.info("Could not get current position/chapter")
        return
    end
    
    current_chapter_index = current_chapter_index + 1  -- Convert to 1-based
    msg.info(string.format("Opened at chapter %d, position %.2fs", current_chapter_index, current_time))
    
    -- Check if opened in skippable chapter
    local current_chapter = chapters[current_chapter_index]
    if not current_chapter or not current_chapter.skippable then
        msg.info("Current chapter is not skippable, no prompt needed")
        return
    end
    
    -- Don't trigger if it's the last chapter
    if current_chapter_index == #chapters then
        msg.info("Current chapter is the last chapter, no prompt")
        return
    end
    
    -- Calculate time in chapter
    local time_in_chapter = current_time - current_chapter.start_time
    msg.info(string.format("Time in chapter: %.2fs / %.2fs", time_in_chapter, current_chapter.length))
    
    -- Don't trigger if in last 5 seconds of chapter
    if time_in_chapter >= current_chapter.length - 5 then
        msg.info("In last 5 seconds of chapter, no prompt")
        return
    end
    
    -- Trigger case 1 (always 5 second prompt)
    msg.info("Triggering case1 prompt (opened in skippable chapter)")
    trigger_prompt(current_chapter_index, "case1", CASE1_DURATION)
end

-- Handle chapter change
local function on_chapter_change()
    if #chapters == 0 or not auto_skip_enabled then
        return
    end
    
    local current_chapter_index = mp.get_property_number("chapter")
    if not current_chapter_index then
        return
    end
    
    current_chapter_index = current_chapter_index + 1  -- Convert to 1-based
    msg.info(string.format("[CHAPTER CHANGE] Entered chapter %d", current_chapter_index))
    
    local current_chapter = chapters[current_chapter_index]
    
    if not current_chapter or not current_chapter.skippable then
        -- Entered a normal chapter, cancel any active prompts
        -- Also clear cancelled_chapters when entering a normal chapter
        if next(cancelled_chapters) ~= nil then
            msg.info("[CHAPTER CHANGE] Entered normal chapter, clearing cancelled chapters list")
            cancelled_chapters = {}
        end
        
        if active_prompt then
            msg.info("[CHAPTER CHANGE] Entered normal chapter, clearing prompt without marking as cancelled")
            -- Don't mark as cancelled since we're just changing chapters naturally
            if countdown_timer then
                countdown_timer:kill()
                countdown_timer = nil
            end
            active_prompt = nil
            last_range_check = nil
            mp.set_osd_ass(0, 0, "")
        end
        return
    end
    
    -- Don't trigger if it's the last chapter
    if current_chapter_index == #chapters then
        msg.info("[CHAPTER CHANGE] This is the last chapter, no prompt")
        if active_prompt then
            if countdown_timer then
                countdown_timer:kill()
                countdown_timer = nil
            end
            active_prompt = nil
            last_range_check = nil
            mp.set_osd_ass(0, 0, "")
        end
        return
    end
    
    -- Check previous chapter
    local prev_chapter = chapters[current_chapter_index - 1]
    
    if not prev_chapter then
        msg.info("[CHAPTER CHANGE] No previous chapter found")
        return
    end
    
    if prev_chapter.skippable then
        -- Case 1: Back-to-back skippable chapters
        msg.info("[CHAPTER CHANGE] Back-to-back skippable (case1)")
        trigger_prompt(current_chapter_index, "case1", CASE1_DURATION)
    else
        msg.info("[CHAPTER CHANGE] Transitioned from normal chapter (case2 handled by monitor)")
    end
    -- Note: Normal->Skippable is handled by position monitor (case 2)
end

-- Handle seek
local function on_seek()
    if #chapters == 0 or not auto_skip_enabled then
        return
    end
    
    -- Ignore the initial seek event after file load (mpv resume position)
    if file_just_loaded then
        msg.info("[SEEK] Ignoring initial seek (file resume position)")
        file_just_loaded = false
        return
    end
    
    local current_time = mp.get_property_number("time-pos")
    if not current_time then
        return
    end
    
    msg.info(string.format("[SEEK] User seeked to %.2fs", current_time))
    
    if active_prompt then
        if active_prompt.type == "case1" then
            -- Check if still in the skippable chapter's first 5 seconds
            local chapter = chapters[active_prompt.chapter_index]
            local time_in_chapter = current_time - chapter.start_time
            
            msg.info(string.format("[SEEK] Case1 active, time in chapter: %.2fs", time_in_chapter))
            
            if time_in_chapter < 0 or time_in_chapter >= CASE1_DURATION then
                -- Seeked out of range
                msg.info("[SEEK] Seeked out of case1 range, cancelling")
                cancel_prompt()
            else
                msg.info("[SEEK] Still in case1 range, prompt continues")
            end
        elseif active_prompt.type == "case2" then
            -- Check if still in transition range
            local range = find_transition_range(current_time)
            
            if not range or range.target_chapter ~= active_prompt.chapter_index then
                -- Seeked out of transition range
                msg.info("[SEEK] Seeked out of case2 transition range, cancelling")
                cancel_prompt()
            else
                msg.info("[SEEK] Still in case2 transition range, prompt continues")
            end
        end
    else
        msg.info("[SEEK] No active prompt during seek")
    end
end

-- Handle pause/unpause
local function on_pause_change(name, paused)
    if active_prompt then
        active_prompt.paused = paused
        if paused then
            msg.info(string.format("[PAUSE] Countdown frozen at %d", active_prompt.countdown))
        else
            msg.info(string.format("[UNPAUSE] Countdown resuming from %d", active_prompt.countdown))
        end
        if not paused then
            update_osd()
        end
    end
end

-- Toggle auto-skip functionality
local function toggle_auto_skip()
    auto_skip_enabled = not auto_skip_enabled
    
    if auto_skip_enabled then
        msg.info("[TOGGLE] Auto-skip ENABLED")
        show_osd("Auto-skip: enabled", 2)
        if #chapters > 0 then
            start_position_monitor()
        end
    else
        msg.info("[TOGGLE] Auto-skip DISABLED")
        show_osd("Auto-skip: disabled", 2)
        cancel_prompt()
        stop_position_monitor()
    end
end

-- Register event listeners
mp.register_event("file-loaded", on_file_loaded)
mp.observe_property("chapter", "number", on_chapter_change)
mp.observe_property("seeking", "bool", function(name, seeking)
    if seeking == false then
        on_seek()
    end
end)
mp.observe_property("pause", "bool", on_pause_change)

-- Register key bindings
mp.add_key_binding("y", "toggle-auto-skip", toggle_auto_skip)
mp.add_key_binding("j", "cancel-skip", cancel_prompt)
mp.add_key_binding("J", "skip-now", skip_now)

msg.info("Chapter Auto-Skip script loaded")
