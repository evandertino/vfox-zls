--- Returns download information for a specific version
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#preinstall-hook
--- @param ctx {version: string, runtimeVersion: string} Context
--- @return table Version and download information
function PLUGIN:PreInstall(ctx)
    local builtin = require("std.builtin")
    if not builtin.platform then
        error("Unsupported platform: " .. tostring(RUNTIME.osType) .. "/" .. tostring(RUNTIME.archType))
    end

    -- master: resolve against current Zig nightly via community mirrors,
    -- then download from releases.zigtools.org.
    local version = ctx.version
    local zls = require("std.zls")
    local format = require("std.format")
    if version == "master" then
        local zig = require("std.zig")
        local zig_nightly_version, err = zig.get_nightly_version()
        if not zig_nightly_version then
            error(
                "[PreInstall] Could not determine Zig nightly version. Check your internet connection. Details: "
                    .. tostring(err)
            )
        end

        local master_release, err = zls.get_master_release(zig_nightly_version)
        if not master_release then
            error(err or "Failed to resolve ZLS master build")
        end

        local master_artifact = master_release[builtin.platform]
        if not master_artifact then
            error(
                "No ZLS master build available for platform: "
                    .. builtin.platform
                    .. " (Zig nightly "
                    .. zig_nightly_version
                    .. ")"
            )
        end

        local tarball_url = master_artifact.tarball or nil
        if not tarball_url then
            error("ZLS master release for Zig nightly " .. zig_nightly_version .. " is missing a download URL")
        end

        local artifact_size = master_artifact.size or nil

        return {
            version = master_release.version,
            url = tarball_url,
            sha256 = master_artifact.shasum,
            note = "Downloading ZLS "
                .. master_release.version
                .. " for Zig nightly "
                .. zig_nightly_version
                .. (artifact_size and " (" .. format.bytes(artifact_size) .. ")" or ""),
        }
    end

    -- Stable releases: look up builds.zigtools.org/index.json
    local stable_releases = zls.get_stable_releases()
    if not stable_releases then
        error("Failed to fetch available stable releases for pre-installation")
    end

    local stable_release = stable_releases[version]
    if not stable_release then
        error("Requested stable release version not found: " .. version)
    end

    local release_date = stable_release.date or nil
    local supported_platforms = {}
    for platform, _ in pairs(stable_release) do
        if builtin.is_platform_supported(platform) then
            table.insert(supported_platforms, platform)
        end
    end

    if #supported_platforms == 0 then
        error("No supported platforms found for version: " .. version)
    end

    local stable_artifact = stable_release[builtin.platform]
    if not stable_artifact then
        error(
            "Unable to get a stable release version: "
                .. version
                .. " available for your platform: "
                .. builtin.platform
                .. ". Supported platforms for this version are: "
                .. table.concat(supported_platforms, ", ")
        )
    end

    local tarball_url = stable_artifact.tarball or nil
    if not tarball_url then
        error("No download URL found for version: " .. version .. " on platform: " .. builtin.platform)
    end

    local artifact_size = stable_artifact.size or nil

    return {
        version = version,
        url = tarball_url,
        sha256 = stable_artifact.shasum or nil,
        note = (
            "Downloading zls "
            .. version
            .. (release_date and " released on " .. release_date or "")
            .. (artifact_size and " of size (" .. format.bytes(artifact_size) .. ")" or "")
        ),
        -- NOTE: This doesnt seem to work
        addition = {
            {
                name = "minisig",
                url = tarball_url .. ".minisig",
            },
        },
    }
end
