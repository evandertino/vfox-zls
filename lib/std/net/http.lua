local M = {}

--- Performs an HTTP GET request and returns the response body or error.
--- On success, returns (body, nil). On failure, returns (nil, error_message).
---
--- Uses http.try_get which is the non-raising variant of http.get. The standard
--- http.get raises a Lua error on transport failures and, since it is async and
--- uses coroutines internally, cannot be caught with pcall. try_get returns the
--- error as a value instead, which is the correct pattern for this environment.
--- @param url string The URL to fetch
--- @return string|nil body HTTP response body on success, nil on failure
--- @return nil|string err nil on success, error message on failure
function M.get(url)
    local http = require("http")
    local log = require("log")
    log.debug("HTTP GET: " .. url)
    local resp, err = http.try_get({ url = url })
    if err ~= nil then
        return nil, tostring(err)
    end
    if resp.status_code ~= 200 then
        return nil, string.format("HTTP %d: %s", resp.status_code, resp.body)
    end
    return resp.body, nil
end

--- Percent-encodes a string for safe use as a URL query parameter value.
--- Encodes all characters except unreserved ones: A-Z a-z 0-9 - _ . ~
--- @param value string
--- @return string
function M.percent_encode(value)
    return (value:gsub("[^%w%-_%.~]", function(char)
        return string.format("%%%02X", char:byte())
    end))
end

--- Builds a URL with encoded query parameters.
--- @param base string  The base URL without a query string
--- @param params table  Key-value pairs to append as query parameters
--- @return string
function M.build_url(base, params)
    local parts = {}
    for k, v in pairs(params) do
        table.insert(parts, M.percent_encode(k) .. "=" .. M.percent_encode(v))
    end
    return base .. "?" .. table.concat(parts, "&")
end

return M
