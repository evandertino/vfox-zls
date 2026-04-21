--- Disk-backed cache for network responses.
---
--- Cache files are stored as JSON envelopes:
---   { cached_at = <unix_timestamp>, data = <payload>, [extra fields...] }
---
--- The `data` field holds the caller's payload. Extra envelope fields may be
--- added by callers to support domain-specific cache validation (e.g. storing
--- a `zig_version` field alongside `data` so the caller can invalidate the
--- entry when the Zig nightly version changes).
---
--- All write operations are best-effort and fail silently. A failed write
--- does not affect the return value of the calling function — the freshly
--- fetched data is still returned, just not persisted.
---
--- Usage:
---   local cache = require("std.cache")
---
---   -- Read
---   local entry = cache.get("my_key")
---   if entry then
---       return entry.data  -- cache hit
---   end
---
---   -- Fetch fresh data, then write
---   local data = fetch_something()
---   cache.set("my_key", { data = data })
---
---   -- With extra context for validation
---   cache.set("my_key", { data = data, zig_version = zig_version })
---   local entry = cache.get("my_key")
---   if entry and entry.zig_version == zig_version then
---       return entry.data  -- cache hit, context still valid
---   end
 
local M = {}

--- Cache TTL in seconds (24 hours).
M.TTL = 24 * 60 * 60

--- Returns the base cache directory path, resolved from the environment.
--- @return string
local function get_cache_dir()
    -- TMPDIR is the standard on macOS and most Linux distributions.
    -- TEMP / TMP are the Windows equivalents.
    local tmpdir = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    -- Remove trailing slashes
    tmpdir = tmpdir:gsub("[/\\]+$", "")
    local file = require("file")
    return file.join_path(tmpdir, "mise-zls-plugin")
end

--- Returns the full path for a given cache key.
--- @param key string
--- @return string
local function cache_path(key)
    local file = require("file")
    return file.join_path(get_cache_dir(), key .. ".json")
end

--- Ensures the cache directory exists. Best-effort — errors are silently ignored.
local function ensure_cache_dir()
    local dir = get_cache_dir()
    local cmd = require("cmd")
    -- pcall is safe here: cmd.exec is synchronous and does not use coroutines.
    pcall(cmd.exec, "mkdir -p '" .. dir .. "'")
end

--- Writes content to a file. Returns true on success, false on failure.
--- @param path string
--- @param content string
--- @return boolean
local function write_file(path, content)
    -- io.open is standard Lua 5.1 and is synchronous — safe to call directly.
    local fh, _ = io.open(path, "w")
    if not fh then
        return false
    end
    fh:write(content)
    fh:close()
    return true
end

--- Reads and validates a cache entry for the given key.
---
--- Returns the full envelope table (including `cached_at` and `data`) if the
--- entry exists and is younger than TTL. Returns nil on any failure: missing
--- file, corrupt JSON, or expired TTL.
---
--- @param key string
--- @return table|nil
function M.get(key)
    local file = require("file")
    local path = cache_path(key)

    local log = require("log")
    log.debug("Attempting to read cache entry for key '" .. key .. "' at path: " .. path)
 
    if not file.exists(path) then
        return nil
    end
 
    -- file.read is synchronous — pcall is safe.
    local ok, content = pcall(file.read, path)
    if not ok or not content or content == "" then
        return nil
    end
 
    local json = require("json")
    local ok2, entry = pcall(json.decode, content)
    if not ok2 or type(entry) ~= "table" then
        return nil
    end
 
    if not entry.cached_at or not entry.data then
        return nil
    end

    local age = os.time() - (tonumber(entry.cached_at) or 0)
    if age > M.TTL then
        return nil
    end
 
    log.debug("Cache hit for key '" .. key .. "'. Entry age: " .. age .. " seconds.")
    return entry
end

--- Writes an envelope to disk under the given key.
---
--- `cached_at` is injected automatically. Any fields already present in
--- `entry` are preserved — callers use this to embed extra context:
---
---   cache.set("zls_master_release", { data = data, zig_version = zig_version })
---
--- @param key string
--- @param entry table  Must contain at minimum a `data` field.
function M.set(key, entry)
    entry.cached_at = os.time()
 
    local json = require("json")
    local ok, encoded = pcall(json.encode, entry)
    if not ok then
        return
    end
 
    ensure_cache_dir()
    write_file(cache_path(key), encoded)
end

return M