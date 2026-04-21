local M = {
    -- Base URL for the Zig programming language
    zig_url = "https://ziglang.org",
    -- URL for fetching the list of community download mirrors
    mirrors_url = "https://ziglang.org/download/community-mirrors.txt",
    -- Suffix appended to mirror URLs to get the version index JSON
    mirror_index_suffix = "/index.json",
    -- Suffix for the canonical ziglang.org endpoint to get the version index JSON
    zig_url_index_suffix = "/download/index.json",
}

math.randomseed(os.time())

--- Fisher-Yates in-place shuffle.
--- @param t table
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

--- Extracts the nightly version string from the given JSON response body.
--- @param body string|nil Raw JSON response body
--- @return string|nil  e.g. "0.16.0-dev.3153+d6f43caad", or nil on failure
local function extract_nightly_version(body)
    if not body then
        return nil
    end

    local json = require("json")
    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= "table" then
        return nil
    end

    local master = data["master"]
    if type(master) ~= "table" then
        return nil
    end

    local version = master["version"]
    return (type(version) == "string" and version ~= "") and version or nil
end

--- Fetches the current Zig nightly version string using community mirrors.
---
--- Results are cached to disk for 24 hours to avoid hammering the mirror
--- network on repeated invocations. The cache is stored under the system
--- temp directory at mise-zls-plugin/zig_nightly_version.json.
---
--- Strategy:
---   1. Fetch community-mirrors.txt
---   2. Shuffle the mirror list randomly
---   3. Try each mirror's download index in order, stop on first success
---   4. Fall back to the canonical ziglang.org endpoint if all mirrors fail
--- mirrors_body:gmatch("[^\r\n]+")
--- means:-
---     Check if it matches any sequence of characters that are not newline characters.
---         ^ inside [] means "not"
---         \r and \n are carriage return and newline characters, respectively
---         + means "one or more of the preceding element"
--- line:match("^%s*(.-)%s*$")
--- means:-
---     Remove whitespace at the beginning and end of the line.
---         ^ means "beginning of the string"
---         %s matches any whitespace character (space, tab, etc.)
---         * means "zero or more of the preceding element"
---         (.-) means "capture as few characters as possible until the next part of the pattern matches"
---         %s* means "zero or more whitespace characters"
---         $ means "end of the string"
--- local url = base_url:gsub("/$", "") .. M.index_suffix
--- means:-
---     It matches "/" at the end of the string and replaces it with an empty string, effectively removing
---     the trailing slash if it exists.
--- @return string|nil, string|nil The nightly version string, or nil on total failure
function M.get_nightly_version()
    local cache = require("std.cache")

    -- Return cached value if still fresh
    local entry = cache.get("zig_nightly_version")
    if entry and type(entry.data) == "string" then
        return entry.data, nil
    end

    local http = require("std.net.http")

    -- Fetch and parse the community mirror list
    local mirrors_body, _ = http.get(M.mirrors_url)
    local mirrors = {}

    if mirrors_body then
        for line in mirrors_body:gmatch("[^\r\n]+") do
            line = line:match("^%s*(.-)%s*$")
            if line ~= "" and line:sub(1, 4) == "http" then
                table.insert(mirrors, line)
            end
        end
    end

    shuffle(mirrors)

    local log = require("log")
    -- Log list of mirrors to attempt.
    log.debug("The following mirrors will be attempted in order: " .. table.concat(mirrors, ", "))

    -- Try each mirror in random order
    for _, base_url in ipairs(mirrors) do
        local url = base_url:gsub("/$", "") .. M.mirror_index_suffix
        log.debug("Attempting mirror: " .. url)
        local body, err = http.get(url)
        local nightly_version = extract_nightly_version(body)
        if nightly_version then
            cache.set("zig_nightly_version", { data = nightly_version, timestamp = os.time() })
            log.debug("Successfully fetched Zig nightly version from mirror: " .. url .. " Version: " .. nightly_version)
            return nightly_version, nil
        end
        log.debug("Failed to get nightly version from mirror: " .. url .. " Error: " .. tostring(err))
    end

    -- Fallback: canonical ziglang.org endpoint
    -- All mirrors failed or list was empty - try the canonical endpoint
    local url = M.zig_url .. M.zig_url_index_suffix
    local body, err = http.get(url)
    if err then
        return nil, "all mirrors failed and canonical ziglang.org unreachable: " .. err
    end

    local nightly_version = extract_nightly_version(body)
    if not nightly_version then
        return nil, "all mirrors failed and canonical ziglang.org returned unexpected response"
    end

    cache.set("zig_nightly_version", { data = nightly_version, timestamp = os.time() })
    return nightly_version, nil
end

return M
