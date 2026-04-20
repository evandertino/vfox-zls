local M = {
    -- URL for fetching the index of stable ZLS versions with release dates
    stables_url = "https://builds.zigtools.org/index.json",
    -- URL for the ZLS version selector API (used for downloading specific versions)
    releases_url = "https://releases.zigtools.org/v1/zls/select-version",
    -- Public key for verifying ZLS releases with Minisign
    minisign_key = "RWR+9B91GBZ0zOjh6Lr17+zKf5BoSuFvrx2xSeDE57uIYvnKBGmMjOex",
}

--- Fetches the stable versions from the ZLS builds server.
--- @return table | nil
--- @throws error on network failure or invalid response
function M.get_stable_releases()
    local http = require("std.net.http")
    local body, err = http.get(M.stables_url)
    if err or not body then
        error("Failed to fetch stable releases: " .. tostring(err))
    end
    local json = require("json")
    local ok, data = pcall(json.decode, body)
    return (ok and type(data) == "table") and data or nil
end

--- Queries releases.zigtools.org for the ZLS build compatible with a given
--- Zig nightly version, using only-runtime compatibility.
---
--- On success returns (data, nil) where data is the decoded response table,
--- shaped like builds.zigtools.org/index.json version entries:
---   { version = "0.16.0-dev.X+Y", date = "...", ["aarch64-macos"] = { tarball, shasum, size }, ... }
---
--- On failure returns (nil, error_message). This includes the case where the
--- API returns code 2 ("Zig X has no compatible ZLS build yet") — callers
--- must decide whether to raise errors or degrade gracefully in this case.
---
--- @overload fun(zig_version: string): table, nil
--- @overload fun(zig_version: string): nil, string
--- @param zig_version string  e.g. "0.16.0-dev.3153+d6f43caad"
--- @return table|nil, string|nil
function M.get_master_release(zig_version)
    local http = require("std.net.http")
    local url = http.build_url(M.releases_url, {
        zig_version = zig_version,
        compatibility = "only-runtime",
    })

    local body, err = http.get(url)
    if err or not body then
        return nil, "Failed to query ZLS release API: " .. tostring(err)
    end

    local json = require("json")
    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= "table" then
        return nil, "Failed to parse ZLS release API response"
    end

    -- The API signals errors with a numeric `code` field and a human-readable
    -- `message`. Pass the message through so callers can surface it verbatim.
    if data.code then
        return nil, tostring(data.message or ("ZLS API error (code " .. tostring(data.code) .. ")"))
    end

    if not data.version then
        return nil, "ZLS release API response missing 'version' field"
    end

    return data, nil
end

return M
