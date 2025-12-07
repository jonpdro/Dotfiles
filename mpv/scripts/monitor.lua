-- Monitor.lua - MPV Watch History Tracker
-- Phase 4: Category Cycling and Session Info

local mp = require 'mp'
local utils = require 'mp.utils'

-- ============================================================================
-- CONFIGURATION BLOCK
-- ============================================================================
local Config = {
    -- File paths
    csv_path = "/JP/watch_history.csv",

    -- Categories (order matters for cycling)
    categories = {"Anime", "TV Show", "Movie", "Unspecified"},

    -- Simple path-based categorization
    category_paths = {
        Anime = "/JP/Media/Anime/",
        ["TV Show"] = "/JP/Media/TV Show/",
        Movie = "/JP/Media/Movie/"
    },

    -- Anime4K shader configuration
    anime_shaders = {
        enabled = true,
        shader_paths = {
            "~~/shaders/Anime4K_Clamp_Highlights.glsl",
            "~~/shaders/Anime4K_Restore_CNN_VL.glsl",
            "~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl",
            "~~/shaders/Anime4K_AutoDownscalePre_x2.glsl",
            "~~/shaders/Anime4K_AutoDownscalePre_x4.glsl",
            "~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"
        }
    },

    -- Quality markers to remove
    quality_markers = {
        "1080p", "2160p", "720p", "4K", "8K",
        "WEB%-DL", "WEBRip", "BluRay", "Blu%-Ray", "HDTV", "WEB", "BDrip", "BDRip",
        "x265", "x264", "HEVC", "H%.264", "H%.265",
        "AAC", "AC3", "DTS", "DDP", "Atmos",
        "10bit", "8bit", "HDR", "SDR", "DV", "DoVi"
    },

    -- Protected abbreviations (won't convert dots after these)
    protected_abbreviations = {
        "Mr", "Dr", "Mrs", "Ms", "Prof", "Rev", "Gen", "Sen", "Rep", 
        "Capt", "Col", "Lt", "Sgt", "Gov", "Pres", "St", "Co", "Inc",
        "Ltd", "Corp", "Dept", "Univ", "Assn", "Bldg", "Ave", "Blvd", "Rd"
    }
}

-- ============================================================================
-- MONITOR CLASS
-- ============================================================================
local Monitor = {
    config = Config,

    -- ==========================================================================
    -- TRACKING VARIABLES
    -- ==========================================================================
    current_file = nil,           -- Current file path
    file_path = nil,              -- Full file path
    file_name = nil,              -- Cleaned filename
    category = nil,               -- Detected category

    -- Time tracking
    start_time = nil,             -- When tracking started (os.date("*t") format)
    playback_start_time = nil,    -- When actual playback started (os.time() format)
    total_playback_time = 0,      -- Total seconds of actual playback

    -- Position tracking
    start_position = 0,           -- Start position in seconds
    end_position = 0,             -- End position in seconds
    file_duration = 0,            -- Total file duration in seconds
    final_position_captured = false, -- Track if we've captured the final position

    -- State tracking
    is_tracking = false,          -- Whether we're currently tracking a session
    is_paused = false             -- Current pause state
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function Monitor:get_current_time()
    return os.time()
end

function Monitor:format_time(seconds)
    if seconds < 60 then
        return string.format("%.1f seconds", seconds)
    else
        local minutes = math.floor(seconds / 60)
        local remaining_seconds = seconds % 60
        return string.format("%d:%02d minutes", minutes, remaining_seconds)
    end
end

function Monitor:extract_filename(path)
    if not path then return "Unknown" end

    local filename = mp.get_property("filename")
    if filename and filename ~= "" then
        return filename
    end

    -- Fallback: extract from path
    local parts = {}
    for part in string.gmatch(path, "([^/]+)") do
        table.insert(parts, part)
    end

    return parts[#parts] or "Unknown"
end

function Monitor:get_category_from_path(path)
    if not path then return "Unspecified" end

    for category, category_path in pairs(self.config.category_paths) do
        if string.find(path, category_path, 1, true) then
            return category
        end
    end

    return "Unspecified"
end

-- ============================================================================
-- IMPROVED FILENAME CLEANING (from second script)
-- ============================================================================

function Monitor:convert_dots_to_spaces(text)
    if not text then return text end
    
    -- First, protect abbreviations by replacing them with placeholders
    local protected_map = {}
    for i, abbr in ipairs(self.config.protected_abbreviations) do
        local pattern = abbr .. "%."
        local placeholder = "PROTECTED_" .. i .. "_"
        text = string.gsub(text, pattern, placeholder)
        protected_map[placeholder] = abbr .. "."
    end
    
    -- Convert all remaining dots to spaces
    text = string.gsub(text, "%.", " ")
    
    -- Restore protected abbreviations
    for placeholder, original in pairs(protected_map) do
        text = string.gsub(text, placeholder, original)
    end
    
    return text
end

function Monitor:format_anime_title(title)
    -- Remove "V2", "v2" version indicators
    title = string.gsub(title, " v2", "")
    title = string.gsub(title, " V2", "")
    
    -- Clean up any remaining extra spaces
    title = string.gsub(title, "%s+", " ")
    title = string.gsub(title, "^%s*(.-)%s*$", "%1")
    
    return title
end

function Monitor:format_movie_title(title)
    -- Look for a 4-digit year (1900-2030)
    local year_match = string.match(title, ".*(%d%d%d%d)$")
    if year_match and tonumber(year_match) >= 1900 and tonumber(year_match) <= 2030 then
        -- Extract title without the year
        local movie_title = string.gsub(title, "%s*" .. year_match .. "$", "")
        title = movie_title .. " (" .. year_match .. ")"
    end
    
    return title
end

function Monitor:format_tv_title(title)
    -- Pattern 1: Show.Name.S01E04.Episode.Title
    local season_episode, episode_title = string.match(title, "(.*[Ss]%d+[Ee]%d+)[%s%.-]*(.*)$")
    
    if season_episode then
        -- Format as "Show Name (S01E04) - Episode Title"
        local show_name = string.gsub(season_episode, "[Ss](%d+)[Ee](%d+)", "")
        show_name = string.gsub(show_name, "^%s*(.-)%s*$", "%1")
        show_name = string.gsub(show_name, "%s+$", "") -- Remove trailing spaces
        
        local s_num, e_num = string.match(season_episode, "[Ss](%d+)[Ee](%d+)")
        local season_episode_str = "S" .. string.format("%02d", tonumber(s_num)) .. "E" .. string.format("%02d", tonumber(e_num))
        
        episode_title = string.gsub(episode_title, "^%s*(.-)%s*$", "%1")
        
        if episode_title and episode_title ~= "" then
            title = show_name .. " (" .. season_episode_str .. ") - " .. episode_title
        else
            title = show_name .. " (" .. season_episode_str .. ")"
        end
    else
        -- Pattern 2: Just Show.Name.S01E04
        local show_name, s_num, e_num = string.match(title, "(.*)[Ss](%d+)[Ee](%d+)$")
        if show_name then
            show_name = string.gsub(show_name, "^%s*(.-)%s*$", "%1")
            show_name = string.gsub(show_name, "%s+$", "") -- Remove trailing spaces
            local season_episode_str = "S" .. string.format("%02d", tonumber(s_num)) .. "E" .. string.format("%02d", tonumber(e_num))
            title = show_name .. " (" .. season_episode_str .. ")"
        end
    end
    
    return title
end

function Monitor:cleanup_filename(filename, category)
    if not filename then return "Unknown" end
    
    -- Remove file extension
    local name = string.gsub(filename, "%.[^%.]+$", "")
    
    -- Remove ALL square brackets and their content
    name = string.gsub(name, "%[[^%]]*%]", "")
    
    -- Remove quality markers and everything after them
    for _, marker in ipairs(self.config.quality_markers) do
        local pattern = "%s*" .. marker .. ".*"
        local match_start, match_end = string.find(name, pattern)
        if match_start then
            name = string.sub(name, 1, match_start - 1)
            break
        end
    end
    
    -- Convert dots to spaces (protecting abbreviations)
    name = self:convert_dots_to_spaces(name)
    
    -- Clean up any double spaces left by removals
    name = string.gsub(name, "%s+", " ")
    
    -- Trim whitespace from both ends and remove trailing dots/dashes
    name = string.gsub(name, "^%s*(.-)[%s%.%-]*$", "%1")
    
    -- Apply category-specific formatting
    if category == "Anime" then
        name = self:format_anime_title(name)
    elseif category == "Movie" then
        name = self:format_movie_title(name)
    elseif category == "TV Show" then
        name = self:format_tv_title(name)
    end
    
    return name
end

-- ============================================================================
-- PHASE 4: CATEGORY CYCLING AND SESSION INFO
-- ============================================================================

function Monitor:cycle_category()
    if not self.is_tracking then
        mp.osd_message("No video being tracked", 2)
        mp.msg.info("Category cycling: No active tracking session")
        return
    end

    -- Find current category index
    local current_index = 1
    for i, cat in ipairs(self.config.categories) do
        if cat == self.category then
            current_index = i
            break
        end
    end

    -- Cycle to next category
    local new_index = (current_index % #self.config.categories) + 1
    self.category = self.config.categories[new_index]

    -- Update shaders based on new category
    if self.category == "Anime" then
        self:setup_anime4k_shaders()
    else
        self:clear_shaders()
    end

    -- Show category change message
    local message = string.format("%s\nCategory: %s", self.file_name, self.category)
    mp.osd_message(message, 3)

    mp.msg.info(string.format("Category changed: %s â†’ %s", self.config.categories[current_index], self.category))
end

function Monitor:show_session_info()
    if not self.is_tracking then
        mp.osd_message("No active tracking session", 2)
        mp.msg.info("Session info: No active tracking session")
        return
    end

    local current_position = self:get_current_position()
    local position_percentage = (self.file_duration > 0 and (current_position / self.file_duration) * 100) or 0

    local message = string.format(
        "File: %s\nCategory: %s\nWatch Time: %s\nPosition: %.1f/%.1f (%.1f%%)",
        self.file_name,
        self.category,
        self:format_time(self.total_playback_time),
        current_position,
        self.file_duration,
        position_percentage
    )

    mp.osd_message(message, 4)
    mp.msg.info("Session info displayed: " .. self.file_name)
end

-- ============================================================================
-- PHASE 3: CSV DATA PERSISTENCE
-- ============================================================================

function Monitor:get_week_number(timestamp)
    -- Calculate ISO 8601 week number
    local date_table = os.date("*t", timestamp)

    -- Simple week calculation (can be improved for exact ISO 8601)
    local year_start = os.time{year=date_table.year, month=1, day=1}
    local day_of_year = math.floor((timestamp - year_start) / 86400) + 1
    local week_number = math.floor((day_of_year - date_table.wday + 10) / 7)

    -- Handle year boundaries
    if week_number == 0 then
        -- This is the last week of previous year
        local prev_year = date_table.year - 1
        local prev_year_end = os.time{year=prev_year, month=12, day=31}
        local prev_year_week = self:get_week_number(prev_year_end)
        return prev_year, prev_year_week
    elseif week_number == 53 then
        -- Check if this is actually week 1 of next year
        local next_week_date = timestamp + (7 * 86400)
        local next_week_table = os.date("*t", next_week_date)
        if next_week_table.year > date_table.year then
            return date_table.year + 1, 1
        end
    end

    return date_table.year, week_number
end

function Monitor:escape_csv_field(field)
    if not field then return "" end

    -- Convert to string if it's a number
    if type(field) == "number" then
        return tostring(field)
    end

    -- Escape quotes and wrap in quotes if contains comma or quote
    if string.find(field, '"') or string.find(field, ',') then
        return '"' .. string.gsub(field, '"', '""') .. '"'
    end

    return field
end

function Monitor:capture_final_position()
    -- Capture the final position before the file ends/resets
    if self.is_tracking and not self.final_position_captured then
        local current_pos = self:get_current_position()
        if current_pos > 0 then
            self.end_position = current_pos
            self.final_position_captured = true
            mp.msg.info(string.format("Final position captured: %.1f seconds", self.end_position))
        end
    end
end

function Monitor:save_to_csv()
    if not self.is_tracking or not self.start_time then
        mp.msg.warn("No active tracking session to save")
        return
    end

    -- Stop any running playback timer
    self:stop_playback_timer()

    -- Capture final position if not already done
    self:capture_final_position()

    -- Get end time
    local end_time_obj = os.date("*t")
    local start_time_obj = self.start_time

    -- Extract date and time components
    local start_date = os.date("%Y-%m-%d", os.time(start_time_obj))
    local start_time = os.date("%H:%M:%S", os.time(start_time_obj))
    local end_date = os.date("%Y-%m-%d", os.time(end_time_obj))
    local end_time = os.date("%H:%M:%S", os.time(end_time_obj))

    -- Calculate week number
    local year, week_number = self:get_week_number(os.time(start_time_obj))
    local week_field = year .. "-W" .. string.format("%02d", week_number)

    -- Prepare CSV entry with NEW column order
    local csv_entry = {
        self:escape_csv_field(self.file_name),        -- Cleaned filename
        self:escape_csv_field(self.category),         -- Category
        tostring(self.total_playback_time),           -- Watch time in seconds (MOVED UP)
        self:escape_csv_field(week_field),            -- Week (YYYY-W##)
        self:escape_csv_field(start_date),            -- Start date
        self:escape_csv_field(start_time),            -- Start time
        self:escape_csv_field(end_date),              -- End date
        self:escape_csv_field(end_time),              -- End time
        tostring(math.floor(self.start_position)),    -- Start position (seconds)
        tostring(math.floor(self.end_position))       -- End position (seconds)
    }

    local csv_line = table.concat(csv_entry, ",") .. "\n"

    -- Read existing content and prepend new entry
    local existing_content = ""
    local file, error = io.open(self.config.csv_path, "r")
    if file then
        existing_content = file:read("*a")
        file:close()
    end

    -- Write back to file with new entry at top
    file, error = io.open(self.config.csv_path, "w")
    if file then
        -- Check if file has header with NEW column order
        local has_header = string.match(existing_content, "^filename,category,watch_time_seconds,week,start_date,start_time,end_date,end_time,start_position,end_position\n")

        if has_header then
            -- Write header, then new entry, then the rest (without the duplicate header)
            local header = "filename,category,watch_time_seconds,week,start_date,start_time,end_date,end_time,start_position,end_position\n"
            local content_after_header = string.gsub(existing_content, "^filename,category,watch_time_seconds,week,start_date,start_time,end_date,end_time,start_position,end_position\n", "")
            file:write(header)
            file:write(csv_line)
            file:write(content_after_header)
        else
            -- Check for old header format and migrate
            local has_old_header = string.match(existing_content, "^filename,category,week,watch_time_seconds,start_date,start_time,end_date,end_time,start_position,end_position\n")
            if has_old_header then
                -- Migrate from old format to new format
                local header = "filename,category,watch_time_seconds,week,start_date,start_time,end_date,end_time,start_position,end_position\n"
                local content_after_header = string.gsub(existing_content, "^filename,category,week,watch_time_seconds,start_date,start_time,end_date,end_time,start_position,end_position\n", "")
                file:write(header)
                file:write(csv_line)
                file:write(content_after_header)
            else
                -- New file or no header found
                if existing_content == "" then
                    -- New file: write header first
                    local header = "filename,category,watch_time_seconds,week,start_date,start_time,end_date,end_time,start_position,end_position\n"
                    file:write(header)
                    file:write(csv_line)
                else
                    -- Existing file without proper header, just prepend with new header
                    local header = "filename,category,watch_time_seconds,week,start_date,start_time,end_date,end_time,start_position,end_position\n"
                    file:write(header)
                    file:write(csv_line)
                    file:write(existing_content)
                end
            end
        end

        file:close()
        mp.msg.info(string.format(
            "Watch history SAVED: %s | Week: %s | Watch time: %d seconds | Position: %dâ†’%d",
            self.file_name,
            week_field,
            self.total_playback_time,
            math.floor(self.start_position),
            math.floor(self.end_position)
        ))
    else
        mp.msg.error("Failed to save watch history: " .. (error or "unknown error"))
    end
end

-- ============================================================================
-- ANIME4K SHADER MANAGEMENT
-- ============================================================================

function Monitor:setup_anime4k_shaders()
    if not self.config.anime_shaders.enabled then return end

    local shader_list = table.concat(self.config.anime_shaders.shader_paths, ":")
    local command = 'change-list glsl-shaders set "' .. shader_list .. '"'

    mp.command(command)
    mp.msg.info("Anime4K shaders activated for anime content")
end

function Monitor:clear_shaders()
    -- FIX: Use proper command syntax to clear shaders
    mp.set_property("glsl-shaders", "")
    mp.msg.info("Shaders cleared")
end

-- ============================================================================
-- SESSION END AND FINAL LOGGING
-- ============================================================================

function Monitor:end_tracking_session(reason)
    if not self.is_tracking then return end

    -- Capture final position BEFORE stopping anything
    self:capture_final_position()

    -- Stop any running playback timer
    self:stop_playback_timer()

    -- Save to CSV (Phase 3)
    self:save_to_csv()

    -- Get end time for logging
    local end_time = os.date("*t")
    local session_duration = os.difftime(os.time(end_time), os.time(self.start_time))

    -- Log final session data
    mp.msg.info(string.format(
        "Tracking ENDED: %s | Reason: %s",
        self.file_name,
        reason
    ))

    mp.msg.info(string.format(
        "Session Summary: %s watched over %s (%.1f%% efficient)",
        self:format_time(self.total_playback_time),
        self:format_time(session_duration),
        (session_duration > 0 and (self.total_playback_time / session_duration) * 100) or 0
    ))

    mp.msg.info(string.format(
        "Position: %.1f â†’ %.1f seconds (%.1f%%)",
        self.start_position,
        self.end_position,
        (self.file_duration > 0 and (self.end_position / self.file_duration) * 100) or 0
    ))

    -- Final debug output
    self:debug_print_session_state("SESSION ENDED - " .. reason)

    -- Reset tracking state
    self.is_tracking = false
    self.current_file = nil
    self.final_position_captured = false
end

function Monitor:on_file_end(event)
    if self.is_tracking then
        local reason = event.reason or "unknown"
        mp.msg.info("File ended - saving watch history")
        self:end_tracking_session("File ended: " .. reason)
    end
end

function Monitor:on_shutdown()
    if self.is_tracking then
        mp.msg.info("MPV shutting down - saving watch history")
        self:end_tracking_session("MPV shutdown")
    end
end

function Monitor:on_file_loaded()
    -- If we were tracking a previous file, end that session first
    if self.is_tracking and self.current_file then
        self:end_tracking_session("File changed")
    end

    -- Reset for new file
    self.is_tracking = false
    self.current_file = nil
    self.final_position_captured = false

    -- Start tracking after a short delay
    mp.add_timeout(0.5, function()
        self:show_file_info()
    end)
end

-- ============================================================================
-- TIME TRACKING WITH PAUSE DETECTION
-- ============================================================================

function Monitor:start_playback_timer()
    if not self.is_paused and self.is_tracking then
        self.playback_start_time = self:get_current_time()
        mp.msg.info("Playback timer STARTED")
    end
end

function Monitor:stop_playback_timer()
    if self.playback_start_time and not self.is_paused then
        local current_time = self:get_current_time()
        local segment_duration = current_time - self.playback_start_time
        self.total_playback_time = self.total_playback_time + segment_duration
        self.playback_start_time = nil
        mp.msg.info(string.format(
            "Playback timer STOPPED | Segment: %s | Total: %s",
            self:format_time(segment_duration),
            self:format_time(self.total_playback_time)
        ))
    end
end

function Monitor:on_pause_change(name, paused)
    if not self.is_tracking then return end

    if paused then
        -- Video paused, stop playback timer
        self:stop_playback_timer()
        self.is_paused = true
        mp.msg.info(string.format(
            "Video PAUSED | Total watch time: %s",
            self:format_time(self.total_playback_time)
        ))
    else
        -- Video resumed, start playback timer
        self.is_paused = false
        self:start_playback_timer()
        mp.msg.info(string.format(
            "Video RESUMED | Total watch time: %s",
            self:format_time(self.total_playback_time)
        ))
    end
end

function Monitor:setup_pause_tracking()
    mp.observe_property("pause", "bool", function(name, value)
        self:on_pause_change(name, value)
    end)
    mp.msg.info("Pause tracking initialized")
end

-- ============================================================================
-- POSITION TRACKING
-- ============================================================================

function Monitor:get_current_position()
    return mp.get_property_number("time-pos", 0)
end

function Monitor:get_file_duration()
    return mp.get_property_number("duration", 0)
end

function Monitor:setup_position_tracking()
    -- Observe position changes to update end position
    mp.observe_property("time-pos", "number", function(name, value)
        if value and self.is_tracking then
            self.end_position = value
        end
    end)

    mp.msg.info("Position tracking initialized")
end

-- ============================================================================
-- SESSION MANAGEMENT
-- ============================================================================

function Monitor:start_tracking_session()
    local path = mp.get_property("path")
    if not path then
        mp.msg.warn("No file path available for tracking")
        return
    end

    -- Initialize tracking session
    self.current_file = path
    self.file_path = path
    local raw_filename = self:extract_filename(path)
    self.category = self:get_category_from_path(path)
    self.file_name = self:cleanup_filename(raw_filename, self.category)

    -- Initialize timing
    self.start_time = os.date("*t")
    self.playback_start_time = nil
    self.total_playback_time = 0

    -- Initialize positions
    self.file_duration = self:get_file_duration()
    self.start_position = self:get_current_position()
    self.end_position = self.start_position
    self.final_position_captured = false

    -- Set tracking state
    self.is_tracking = true
    self.is_paused = false

    -- Start playback timer if not paused
    if not mp.get_property_bool("pause", false) then
        self:start_playback_timer()
    end

    -- Log session start
    mp.msg.info(string.format(
        "Tracking STARTED: %s | Category: %s | Time: %s",
        self.file_name,
        self.category,
        os.date("%H:%M:%S")
    ))

    mp.msg.info(string.format(
        "Position: %.1f/%d seconds (%.1f%%)",
        self.start_position,
        self.file_duration,
        (self.file_duration > 0 and (self.start_position / self.file_duration) * 100) or 0
    ))

    -- Test: Print tracking state to console
    self:debug_print_session_state("SESSION STARTED")
end

function Monitor:debug_print_session_state(context)
    mp.msg.info(string.format("[DEBUG %s]", context))
    mp.msg.info(string.format("  File: %s", self.file_name or "nil"))
    mp.msg.info(string.format("  Category: %s", self.category or "nil"))
    mp.msg.info(string.format("  Tracking: %s", tostring(self.is_tracking)))
    mp.msg.info(string.format("  Paused: %s", tostring(self.is_paused)))
    mp.msg.info(string.format("  Start Time: %s", self.start_time and os.date("%H:%M:%S", os.time(self.start_time)) or "nil"))
    mp.msg.info(string.format("  Total Playback: %s", self:format_time(self.total_playback_time)))
    mp.msg.info(string.format("  Start Position: %.1f seconds", self.start_position))
    mp.msg.info(string.format("  End Position: %.1f seconds", self.end_position))
    mp.msg.info(string.format("  File Duration: %d seconds", self.file_duration))
end

-- ============================================================================
-- DISPLAY AND INITIALIZATION
-- ============================================================================

function Monitor:show_file_info()
    local path = mp.get_property("path")
    if not path then return end

    local raw_filename = self:extract_filename(path)
    local category = self:get_category_from_path(path)
    local cleaned_filename = self:cleanup_filename(raw_filename, category)

    -- Apply Anime4K shaders if category is Anime
    if category == "Anime" then
        self:setup_anime4k_shaders()
    else
        self:clear_shaders()
    end

    -- Start tracking session
    self:start_tracking_session()

    local message = string.format("%s\nCategory: %s", cleaned_filename, category)
    mp.osd_message(message, 4)
    mp.msg.info("File Info: " .. cleaned_filename .. " | Category: " .. category)
end

function Monitor:init()
    -- Setup tracking systems
    self:setup_position_tracking()
    self:setup_pause_tracking()

    -- Register event handlers
    mp.register_event("file-loaded", function()
        self:on_file_loaded()
    end)
    mp.register_event("shutdown", function()
        self:on_shutdown()
    end)
    mp.register_event("end-file", function(event)
        self:on_file_end(event)
    end)

    -- Register key bindings for Phase 4
    mp.add_key_binding("\"", "cycle-category", function()
        self:cycle_category()
    end)

    mp.add_key_binding("Ctrl+\"", "show-session-info", function()
        self:show_session_info()
    end)

    mp.msg.info("Monitor.lua Phase 4 loaded - Category cycling and session info enabled")
    mp.msg.info("Hotkeys: '\"' = Cycle category | Ctrl+'\"' = Show session info")
end

-- Initialize the monitor
Monitor:init()
