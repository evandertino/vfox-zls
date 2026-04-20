# vfox-zls

A [mise](https://mise.jdx.dev) tool plugin for [ZLS](https://github.com/zigtools/zls) — the Zig Language Server.

This plugin supersedes the default aqua registry entry for ZLS, which only exposes stable releases. It provides access to every build published by the zigtools team, including a rolling `master` alias that automatically resolves to the ZLS build compatible with your current Zig nightly.

## Features

- All stable ZLS releases from [builds.zigtools.org](https://builds.zigtools.org)
- Rolling `master` version that tracks the ZLS build compatible with the current Zig nightly
- Community mirror rotation when resolving the Zig nightly version — distributes load across the mirror network and falls back to `ziglang.org` if all mirrors fail
- SHA256 checksum verification for every download
- `mise upgrade` support for `master` — the plugin sets a platform-specific checksum so mise can detect when a new compatible build is available
- Graceful degradation — `mise ls-remote zls` never crashes, even when network requests fail

## Requirements

- [mise](https://mise.jdx.dev) v0.2.0 or later

## Installation

```bash
mise plugin install zls https://github.com/evandertino/vfox-zls
```

## Usage

### List all available versions

```bash
mise ls-remote zls
```

This lists every stable ZLS release sorted oldest-first, plus the `master` alias at the bottom. The note on each stable release shows its publish date. The note on `master` shows the current Zig nightly version it resolves to.

### Install a stable version

```bash
mise use zls@0.14.0
mise use zls@0.13.0
```

### Install the nightly-compatible build

```bash
mise use zls@master
```

This resolves the current Zig nightly version via community mirrors, queries `releases.zigtools.org` for the compatible ZLS build, and installs it. The installed version is recorded as the actual ZLS dev version string (e.g. `0.16.0-dev.263+fa650ca`), not the string `master`.

### Upgrade master

```bash
mise upgrade zls
```

Because `master` is declared as a rolling release with a platform-specific checksum, mise can detect when a new ZLS nightly build has been published for your platform and will upgrade automatically.

## Platform Support

| OS | Architecture | Platform Key |
|---|---|---|
| Linux | x86 (32-bit) | `x86-linux` |
| Linux | x86_64 | `x86_64-linux` |
| Linux | ARM (32-bit) | `arm-linux` |
| Linux | aarch64 | `aarch64-linux` |
| Linux | RISC-V 64 | `riscv64-linux` |
| macOS | x86_64 | `x86_64-macos` |
| macOS | aarch64 (Apple Silicon) | `aarch64-macos` |
| Windows | x86 (32-bit) | `x86-windows` |
| Windows | x86_64 | `x86_64-windows` |
| Windows | aarch64 | `aarch64-windows` |

## How It Works

### Version Sources

| Source | Purpose |
|---|---|
| `https://builds.zigtools.org/index.json` | Index of all stable ZLS releases |
| `https://ziglang.org/download/community-mirrors.txt` | List of community mirrors |
| `https://ziglang.org/download/index.json` | Canonical fallback for Zig nightly version |
| `https://releases.zigtools.org/v1/zls/select-version` | Resolve compatible ZLS build for a given Zig nightly |

### Stable Versions

The `Available` hook fetches `builds.zigtools.org/index.json`, extracts all version keys, sorts them using semver comparison, and returns them as a flat list. The `PreInstall` hook re-fetches the same index, looks up the requested version, and returns the platform-specific tarball URL and SHA256 checksum.

### Rolling `master`

Installing `master` involves three steps:

1. **Resolve Zig nightly** — fetch `community-mirrors.txt`, shuffle the list using Fisher-Yates, try each mirror's `index.json` in random order until one succeeds, then fall back to `ziglang.org/download/index.json` if all mirrors fail. This produces a version string like `0.16.0-dev.3153+d6f43caad`.

2. **Resolve compatible ZLS build** — call `releases.zigtools.org/v1/zls/select-version?zig_version=<nightly>&compatibility=only-runtime`. The `zig_version` parameter is percent-encoded to safely handle the `+` character in Zig nightly version strings. The API returns a response shaped like a `builds.zigtools.org` index entry, containing per-platform tarballs and checksums.

3. **Error handling for code 2** — when Zig nightly is ahead of ZLS (a common transient state on `main`), the API returns `{"code": 2, "message": "Zig X has no compatible ZLS build (yet)"}`. The plugin surfaces this message verbatim and aborts installation cleanly.

The `checksum` field on the `master` version entry is populated with the SHA256 of the platform-specific tarball from step 2. This is what enables `mise upgrade` to detect changes.

### Caching

mise automatically caches the return value of the `Available` hook and refreshes it daily. The plugin does not implement any manual caching on top of this.

## Project Structure

```
vfox-zls/
├── metadata.lua              # Plugin name, version, author, update URL
├── hooks/
│   ├── available.lua         # Powers `mise ls-remote zls`
│   ├── pre_install.lua       # Resolves download URL and checksum for a version
│   ├── post_install.lua      # Moves binary into bin/ and verifies it runs
│   └── env_keys.lua          # Adds bin/ to PATH
├── lib/
│   └── std/
│       ├── builtin.lua       # Platform detection (RUNTIME → ZLS platform key)
│       ├── format.lua        # Human-readable byte sizes
│       ├── zig.lua           # Zig nightly version resolution via mirrors
│       ├── zls.lua           # ZLS index and select-version API calls
│       └── net/
│           └── http.lua      # HTTP GET wrapper, URL encoding, query builder
└── types/
    └── mise-plugin.lua       # LuaCATS type definitions for IDE support
```

### `lib/std/builtin.lua`

Builds a static platform map from `RUNTIME.osType` and `RUNTIME.archType` (the globals injected by mise into every hook) to the ZLS platform key format (`<arch>-<os>`). The map is computed once at module load time. Also exports `is_platform_supported(platform)` for filtering the platform list from an index entry.

### `lib/std/zig.lua`

Contains `get_nightly_version()` which implements the mirror rotation strategy. The mirror list is fetched from `ziglang.org`, shuffled in-place with Fisher-Yates seeded by `os.time()`, and tried in order. Each mirror's index.json URL is constructed by appending `/index.json` to the mirror base URL (stripping any trailing slash). The nightly version is extracted from `data["master"]["version"]`.

### `lib/std/zls.lua`

Contains two functions:
- `get_stable_releases()` — fetches and decodes `builds.zigtools.org/index.json`
- `get_master_release(zig_version)` — calls the `select-version` API and returns `(data, nil)` on success or `(nil, error_message)` on any failure, including API-level error codes

### `lib/std/net/http.lua`

A thin wrapper around mise's built-in `http` module. Provides `M.get(url)` returning `(body, nil)` or `(nil, err)`, `M.percent_encode(value)` for [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986.html) unreserved character encoding, and `M.build_url(base, params)` for constructing query strings with per-value encoding.

**Important:** the built-in `http.get` is asynchronous and uses Lua coroutines internally. It must never be wrapped in `pcall` — doing so blocks coroutine yields and causes all HTTP requests to fail with "attempt to yield across metamethod/C-call boundary".

## Development

### Setup

```bash
mise install
```

This installs all development tools declared in `mise.toml`: `lua`, `lua-language-server`, `stylua`, `hk`, `actionlint`, and `pkl`.

### Format

```bash
mise run format
```

Runs `stylua` over `metadata.lua` and all files in `hooks/`.

### Lint

```bash
mise run lint
```

Runs `hk check` which covers Lua linting and GitHub Actions validation.

### Test

```bash
mise run test
```

Runs the integration test in `mise-tasks/test` against the locally linked plugin.

### Local development

```bash
# Link the plugin from your working directory
mise plugin link zls /path/to/vfox-zls

# Test ls-remote
mise ls-remote zls

# Test stable install
mise install zls@0.14.0

# Test master install
mise install zls@master
```

## Acknowledgements

- [zigtools/zls](https://github.com/zigtools/zls) — the Zig Language Server
- [zigtools/release-worker](https://github.com/zigtools/release-worker) — the API powering nightly ZLS resolution
- [mise-en-place](https://mise.jdx.dev) — the runtime manager this plugin is built for
- The Zig community mirror operators listed at [ziglang.org/download/community-mirrors](https://ziglang.org/download/community-mirrors/)

## License

MIT