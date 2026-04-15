local M = {}

-- Configuration
local BACKEND_URL = "https://api.game-events.io/v1/events"
local FLUSH_INTERVAL = 1.0 -- seconds
local MAX_BATCH_SIZE = 50
local MAX_RETRY_ATTEMPTS = 5
local INITIAL_BACKOFF = 1.0 -- seconds; doubled per attempt up to ~32s

-- State
local api_key = nil
local user_properties = {}
local event_queue = {}
local is_initialized = false
local flush_timer = nil
local user_id = nil
local session_id = nil
local debug_mode = false
-- failed_batches: { batch = {events}, attempts = N, retry_at = os.time() + delay }
local failed_batches = {}

local function log(message)
    if debug_mode then
        print("[GameEventsIO] " .. message)
    end
end

-- RFC 4122 v4 UUID using math.random. Defold seeds math.randomseed via socket.gettime
-- in init(); for cryptographic-grade randomness use platform extensions.
local function generate_uuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(template, "[xy]", function(c)
        local r = math.random(0, 15)
        if c == "y" then r = (r % 4) + 8 end
        return string.format("%x", r)
    end)
end

local function get_device_info()
    local sys_info = sys.get_sys_info()
    local width, height = window.get_size()

    return {
        device_model = sys_info.device_model,
        device_name = sys_info.device_model,
        device_type = sys_info.system_name,
        operating_system = sys_info.system_name .. " " .. sys_info.system_version,
        platform = sys_info.system_name,
        app_version = sys.get_config("project.version"),
        engine_version = "Defold " .. sys.get_engine_info().version,
        screen_width = width,
        screen_height = height,
        system_language = sys_info.device_language
    }
end

local function send_batch(batch, attempts)
    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_key,
        ["Idempotency-Key"] = generate_uuid()
    }

    local json_payload = json.encode(batch)

    http.request(BACKEND_URL, "POST", function(self, id, response)
        if response.status >= 200 and response.status < 300 then
            log("Batch sent successfully")
        elseif response.status >= 400 and response.status < 500 then
            -- Permanent client error: drop the batch (else we loop forever).
            log("Dropping batch on " .. response.status .. ": " .. (response.response or ""))
        else
            local next_attempts = (attempts or 1) + 1
            if next_attempts > MAX_RETRY_ATTEMPTS then
                log("Giving up on batch after " .. MAX_RETRY_ATTEMPTS .. " attempts")
                return
            end
            local delay = INITIAL_BACKOFF * (2 ^ (next_attempts - 1))
            log("Retry " .. next_attempts .. " in " .. delay .. "s (status " .. tostring(response.status) .. ")")
            table.insert(failed_batches, { batch = batch, attempts = next_attempts, retry_at = os.time() + delay })
        end
    end, headers, json_payload)
end

local function flush()
    -- Re-enqueue failed batches whose backoff has elapsed.
    local now = os.time()
    local still_pending = {}
    for _, entry in ipairs(failed_batches) do
        if entry.retry_at <= now then
            send_batch(entry.batch, entry.attempts)
        else
            table.insert(still_pending, entry)
        end
    end
    failed_batches = still_pending

    if #event_queue == 0 then
        return
    end

    local batch = {}
    while #batch < MAX_BATCH_SIZE and #event_queue > 0 do
        table.insert(batch, table.remove(event_queue, 1))
    end

    if #batch == 0 then return end
    send_batch(batch, 1)
end

function M.init(key)
    if is_initialized then
        log("Already initialized.")
        return
    end

    api_key = key
    -- Best-effort seed: Defold's math.random is otherwise deterministic across runs.
    math.randomseed(os.time() + (socket and socket.gettime and math.floor(socket.gettime() * 1e6) or 0))

    local file_path = sys.get_save_file("game_events_io", "user_data")
    local data = sys.load(file_path)
    if data and data.user_id then
        user_id = data.user_id
    else
        user_id = generate_uuid()
        sys.save(file_path, { user_id = user_id })
    end

    session_id = generate_uuid()

    is_initialized = true
    log("Initialized. UserID: " .. user_id .. " SessionID: " .. session_id)

    M.log_event("session_start", get_device_info())

    flush_timer = timer.delay(FLUSH_INTERVAL, true, flush)
end

function M.set_debug_mode(enabled)
    debug_mode = enabled
end

function M.log_event(event_name, parameters)
    if not is_initialized then
        log("Not initialized. Call init() first.")
        return
    end

    local event = {
        event = event_name,
        session_id = session_id,
        user_id = user_id,
        time = os.time(),
        user_properties = user_properties,
        event_properties = parameters or {}
    }

    table.insert(event_queue, event)
end

function M.set_user_property(key, value)
    if not is_initialized then
        log("Not initialized. Call init() first.")
        return
    end
    user_properties[key] = value
end

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
