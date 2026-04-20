--- Returns a list of available versions for zls
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#available-hook
--- @param ctx {args: string[]} Context (args = user arguments)
--- @return table[] List of available versions
function PLUGIN:Available(ctx)
    -- Rolling master: resolves to the ZLS build compatible with Zig nightly.
    -- We fetch the Zig nightly version via community mirrors, then ask
    -- releases.zigtools.org which ZLS build is compatible with it.
    -- The platform-specific shasum is set as `checksum`
    -- so `mise upgrade` can detect when a new compatible build is available.
    -- All failures degrade gracefully — master is always listed.
    local zig = require("std.zig")
    local zig_nightly_version, _ = zig.get_nightly_version()
    local master_artifact_checksum = nil
    local master_note
    if zig_nightly_version then
        local zls = require("std.zls")
        local master_release, _ = zls.get_master_release(zig_nightly_version)
        local builtin = require("std.builtin")
        if master_release and builtin.platform then
            local master_artifact = master_release[builtin.platform]
            if master_artifact and master_artifact.shasum then
                master_artifact_checksum = master_artifact.shasum
            end
        end
        master_note = "Latest ZLS for Zig nightly (" .. zig_nightly_version .. ")"
    else
        master_note = "Latest ZLS compatible with Zig nightly (version lookup failed)"
    end

    local result = {}
    table.insert(result, {
        version = "master",
        note = master_note,
        rolling = true,
        alias = zig_nightly_version,
        checksum = master_artifact_checksum,
    })

    -- Stable releases from builds.zigtools.org
    local zls = require("std.zls")
    local stable_releases = zls.get_stable_releases()

    if not stable_releases then
        return result
    end

    local stable_versions = {}
    for stable_version in pairs(stable_releases) do
        table.insert(stable_versions, stable_version)
    end

    local semver = require("semver")
    table.sort(stable_versions, function(a, b)
        return semver.compare(a, b) > 0
    end)

    for _, stable_version in ipairs(stable_versions) do
        local stable_release = stable_releases[stable_version]
        table.insert(result, {
            version = stable_version,
            note = (stable_release.date and " Released on " .. stable_release.date),
        })
    end

    return result
end
