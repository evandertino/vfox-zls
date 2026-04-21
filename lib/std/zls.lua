local M = {
    -- URL for fetching the index of stable ZLS versions with release dates
    stables_url = "https://builds.zigtools.org/index.json",
    -- URL for the ZLS version selector API (used for downloading specific versions)
    releases_url = "https://releases.zigtools.org/v1/zls/select-version",
    -- Public key for verifying ZLS releases with Minisign
    minisign_key = "RWR+9B91GBZ0zOjh6Lr17+zKf5BoSuFvrx2xSeDE57uIYvnKBGmMjOex",
}

--- Fetches the stable ZLS release index from builds.zigtools.org.
---
--- Results are cached to disk for 24 hours. Stable releases change at most
--- a few times per year, so hitting the network more often than that is waste.
---
--- @return table|nil  Decoded index table, or nil on parse failure
--- @throws error on network failure with no cache available
function M.get_stable_releases()
    local cache = require("std.cache")

    -- Return cached value if still fresh
    local entry = cache.get("zls_stable_releases")
    if entry and type(entry.data) == "table" then
        return entry.data
    end

    local http = require("std.net.http")
    local body, err = http.get(M.stables_url)
    if err or not body then
        error("Failed to fetch stable releases: " .. tostring(err))
    end

    local json = require("json")
    local ok, data = pcall(json.decode, body)
    if not (ok and type(data) == "table") then
        return nil
    end

    cache.set("zls_stable_releases", { data = data, timestamp = os.time() })
    return data
end

--- Queries releases.zigtools.org for the ZLS build compatible with a given
--- Zig nightly version, using only-runtime compatibility.
---
--- Results are cached to disk for 24 hours, keyed by the Zig nightly version.
--- If the cached entry was fetched for a different Zig nightly version (i.e.
--- the nightly has been updated since the last cache write), the entry is
--- treated as a miss and the API is re-queried. This means the cache is
--- effectively invalidated automatically when Zig nightly changes.
---
--- On success returns (data, nil) where data is the decoded response table,
--- shaped like builds.zigtools.org/index.json version entries:
---   { version = "0.16.0-dev.X+Y", date = "...", ["aarch64-macos"] = { tarball, shasum, size }, ... }
---
--- On failure returns (nil, error_message). This includes the case where the
--- API returns code 2 ("Zig X has no compatible ZLS build yet") — callers
--- must decide whether to raise errors or degrade gracefully in this case.
---
--- @overload fun(zig_nightly_version: string): table, nil
--- @overload fun(zig_nightly_version: string): nil, string
--- @param zig_nightly_version string  e.g. "0.16.0-dev.3153+d6f43caad"
--- @return table|nil, string|nil
function M.get_master_release(zig_nightly_version)
    local cache = require("std.cache")

    -- Return cached value if still fresh AND for the same Zig nightly version.
    -- zig_version is stored in the envelope (not inside data) so it can be
    -- checked without knowing the shape of the ZLS API response.
    local entry = cache.get("zls_master_release")
    if entry and entry.zig_version == zig_nightly_version and type(entry.data) == "table" then
        return entry.data, nil
    end

    local http = require("std.net.http")
    local url = http.build_url(M.releases_url, {
        zig_version = zig_nightly_version,
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
    -- Do not cache error responses — the situation may resolve on the next call.
    if data.code then
        return nil, tostring(data.message or ("ZLS API error (code " .. tostring(data.code) .. ")"))
    end

    if not data.version then
        return nil, "ZLS release API response missing 'version' field"
    end

    -- Store zig_version in the envelope alongside data so future reads can
    -- detect when the Zig nightly has changed and invalidate accordingly.
    cache.set("zls_master_release", { data = data, zig_version = zig_nightly_version, timestamp = os.time() })
    return data, nil
end

return M
