local M = {}

-- Configuration
local BACKEND_URL = "https://api.game-events.io/v1/events"
local FLUSH_INTERVAL = 1.0 -- seconds
local MAX_BATCH_SIZE = 50

-- State
local api_key = nil
local user_properties = {}
local event_queue = {}
local is_initialized = false
local flush_timer = nil
local user_id = nil
local session_id = nil
local debug_mode = false

-- Helper: Log message if debug mode is enabled
local function log(message)
    if debug_mode then
        print("[GameEventsIO] " .. message)
    end
end

-- Helper: Generate UUID (Simple version)
local function generate_uuid()
    return tostring(os.time()) .. "-" .. tostring(math.random(10000, 99999)) .. "-" .. tostring(math.random(10000, 99999))
end

-- Internal: Get device info
local function get_device_info()
    local sys_info = sys.get_sys_info()
    local width, height = window.get_size()
    
    return {
        device_model = sys_info.device_model,
        device_name = sys_info.device_model, -- Defold doesn't expose device name directly like Unity
        device_type = sys_info.system_name, -- Approximate
        operating_system = sys_info.system_name .. " " .. sys_info.system_version,
        platform = sys_info.system_name,
        app_version = sys.get_config("project.version"),
        engine_version = "Defold " .. sys.get_engine_info().version, -- Adapting for Defold
        screen_width = width,
        screen_height = height,
        system_language = sys_info.device_language
    }
end

-- Internal: Flush events to backend
local function flush()
    if #event_queue == 0 then
        return
    end

    -- Take a batch of events
    local batch = {}
    local count = 0
    while count < MAX_BATCH_SIZE and #event_queue > 0 do
        table.insert(batch, table.remove(event_queue, 1))
        count = count + 1
    end

    if #batch == 0 then return end

    if #batch == 0 then return end

    -- Send batch directly as array
    local json_payload = json.encode(batch)
    
    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_key
    }

    http.request(BACKEND_URL, "POST", function(self, id, response)
        if response.status >= 200 and response.status < 300 then
            -- Success
            log("Batch sent successfully")
        else
            -- Failure
            log("Failed to send batch: " .. response.status .. " " .. response.response)
            
            -- Retry: Put items back in queue (prepend to maintain order)
            for i = #batch, 1, -1 do
                table.insert(event_queue, 1, batch[i])
            end
        end
    end, headers, json_payload)
end

-- Public: Initialize SDK
function M.init(key)
    if is_initialized then
        log("Already initialized.")
        return
    end

    api_key = key
    
    -- Load or generate User ID
    local file_path = sys.get_save_file("game_events_io", "user_data")
    local data = sys.load(file_path)
    if data and data.user_id then
        user_id = data.user_id
    else
        user_id = generate_uuid()
        sys.save(file_path, { user_id = user_id })
    end

    -- Generate Session ID
    session_id = generate_uuid()

    is_initialized = true
    log("Initialized. UserID: " .. user_id .. " SessionID: " .. session_id)

    -- Send session_start event
    M.log_event("session_start", get_device_info())

    -- Start flush timer
    flush_timer = timer.delay(FLUSH_INTERVAL, true, flush)
end

-- Public: Set Debug Mode
function M.set_debug_mode(enabled)
    debug_mode = enabled
end

-- Public: Log Event
function M.log_event(event_name, parameters)
    if not is_initialized then
        log("Not initialized. Call init() first.")
        return
    end

    local event = {
        event = event_name, -- Matches Unity's "event" key
        session_id = session_id,
        user_id = user_id,
        time = os.time(), -- Unix timestamp (seconds)
        user_properties = user_properties,
        event_properties = parameters or {} -- Matches Unity's "event_properties"
    }

    table.insert(event_queue, event)
end

-- Public: Set User Property
function M.set_user_property(key, value)
    if not is_initialized then
        log("Not initialized. Call init() first.")
        return
    end
    user_properties[key] = value
end

-- Public: Set User Properties
function M.set_user_properties(properties)
    if not is_initialized then
        log("Not initialized. Call init() first.")
        return
    end
    for k, v in pairs(properties) do
        user_properties[k] = v
    end
end

return M
