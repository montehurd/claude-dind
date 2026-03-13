# Claude Code + Docker-in-Docker

Runs Claude Code in a container with full browser automation — Claude can see and interact with web pages through a Chromium instance running inside the container. A noVNC virtual display lets you watch what Claude is doing from any browser on the host.

This is useful when you want Claude to perform tasks that involve a browser — testing web UIs, filling out forms, scraping pages, debugging frontend issues — without giving it access to your host machine's browser or display. Everything runs isolated inside the container, and your project directory is mounted in so Claude can work on your code and use the browser side by side.

The container also includes Docker-in-Docker, so Claude can build and run containers as part of its work (e.g. spinning up dev servers, running containerized test suites).

The image ships with a **macOS launcher script** baked in. It handles credential retrieval, container lifecycle, and opening the noVNC viewer. Other platforms would need an equivalent script — the macOS one serves as a reference for what the host side needs to do.

## Quick start (macOS)

```bash
docker run --rm ghcr.io/montehurd/claude-dind:latest cat /macos-start | bash -s ~/my-project
```

This pulls the launcher script out of the image and pipes it to bash, passing your project directory as the sole argument. When you exit the Claude session, the container stops automatically.

## What the image contains

Built on `docker:dind` (Alpine), the image includes:

| Component | Purpose |
|---|---|
| Claude Code CLI | Installed from `claude.ai/install.sh`, placed at `/usr/local/bin/claude` |
| Docker daemon + Compose | Docker-in-Docker so Claude can run containers inside the container |
| Chromium | With `--no-sandbox` wrapper (required in containers), sync disabled |
| Claude Chrome extension | Force-installed via Chromium managed policy (`ExtensionInstallForcelist`) |
| Native messaging host | Bridges the Chrome extension to the Claude CLI over stdio |
| Xvfb + XFCE4 | Virtual framebuffer and desktop environment for Chromium to render into |
| x11vnc + noVNC + websockify | VNC server exposed as a web page on port 8086 (container-internal) |
| Noto fonts + emoji | So rendered pages don't show blank boxes |
| git, curl, jq, ripgrep | Common tools Claude Code expects to have available |

### Pre-configured Claude settings

The image ships with several Claude Code settings baked in so the container is ready to use immediately:

- **Onboarding skipped** — `hasCompletedOnboarding` and `hasCompletedClaudeInChromeOnboarding` are set to `true` in `/home/claude/.claude.json` so Claude doesn't prompt for setup
- **Chrome enabled by default** — `claudeInChromeDefaultEnabled` and `cachedChromeExtensionInstalled` are pre-set so `claude --chrome` works without manual extension activation
- **Bash timeout extended** — `BASH_MAX_TIMEOUT_MS` is set to 30 minutes (1,800,000 ms) in `/home/claude/.claude/settings.json`

### User and permissions

A non-root user `claude` (UID 1000) in the `docker` group runs Chromium and Claude Code. The container entry point runs as root (required for `dockerd`) but drops to `claude` for Chromium and interactive sessions.

## What the launcher script does

The macOS script (`macos-start`) handles everything needed on the host side:

### 1. Credential retrieval

Reads the Claude Code OAuth credentials from the macOS Keychain (`Claude Code-credentials`). If no credentials exist, it launches `claude setup-token` to trigger the browser-based OAuth flow, then reads the resulting token from the Keychain.

The credentials use your Max/Pro subscription (flat fee, not per-token).

### 2. Container lifecycle

- Removes any existing `claude` container
- Starts a new detached container with:
  - **Port 6924 -> 8086** — maps the host port to the container's noVNC port
  - **Project mount** — your project directory is mounted at `/work` inside the container
  - **Chromium profile volume** — `claude-chromium-profile` persists the browser profile across runs so the extension doesn't need to re-install each time
  - **Privileged mode** — required for Docker-in-Docker
  - **Credentials** — passed via `CLAUDE_CREDENTIALS` environment variable

### 3. noVNC readiness check

Polls `http://localhost:6924/vnc.html` until it returns HTTP 200, then opens it in your default browser with `autoconnect=true`.

### 4. Interactive shell

Shells into the container as the `claude` user via `docker exec`, running `claude-shell` — a small wrapper that presents a pre-filled command:

```
$ claude --chrome --dangerously-skip-permissions
```

Press Enter to launch Claude with browser automation enabled, or edit the command first. After Claude exits, you're dropped into a regular bash shell. When you exit that shell, the container stops.

## What happens inside the container at startup

The entry point (`start.sh`) runs the following in order:

1. **Docker daemon** — starts `dockerd` in the background and waits for it to be ready
2. **Display stack** — starts Xvfb (virtual display), XFCE4 (desktop), x11vnc (VNC server), and websockify (WebSocket-to-VNC bridge for noVNC)
3. **Ownership fix** — `chown -R claude:docker /home/claude` to fix permissions on volume-mounted directories
4. **Chromium cleanup** — removes stale lock files (`SingletonLock`, `SingletonCookie`, `SingletonSocket`) and old session restore data to prevent accumulating "Claude (MCP)" tab groups across runs
5. **Chromium launch** — starts Chromium on the virtual display as the `claude` user
6. **Credential seeding** — if `CLAUDE_CREDENTIALS` is set and no credentials file exists yet, writes it to `/home/claude/.claude/.credentials.json` with restricted permissions (600)
7. **Environment cleanup** — unsets `CLAUDE_CREDENTIALS` from the environment so it's not visible to child processes

## How the Chrome extension works

The Claude Chrome extension (`fcoeoabgfenejglbffodgkkbkcdhcgfn`) is what enables `claude --chrome` to automate the browser. The connection path is:

```
Claude CLI  <-->  native messaging host (stdio)  <-->  Chrome extension  <-->  Chromium
```

- **Managed policy** (`/etc/chromium/policies/managed/claude-extension.json`) forces Chromium to install the extension from the Chrome Web Store on first launch
- **Native messaging manifest** (`/etc/chromium/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json`) tells Chromium where to find the native host binary and which extension is allowed to use it
- **Native host** (`/home/claude/.claude/chrome/chrome-native-host`) is a shell wrapper that runs `claude --chrome-native-host`, completing the bridge

## Writing a launcher for another platform

The macOS launcher is baked into the image at `/macos-start` so it can be extracted without cloning the repo. A launcher for another platform (Linux, Windows/WSL) would need to handle the same responsibilities:

1. **Obtain credentials** — the macOS script uses `security find-generic-password` to read from the Keychain. On Linux you'd use a keyring, `pass`, or a file. On WSL you might use `cmdkey` or a file
2. **Start the container** — the `docker run` command is platform-agnostic; only the credential retrieval differs
3. **Wait for noVNC** — the `curl` polling loop works anywhere
4. **Open the browser** — `open` on macOS, `xdg-open` on Linux, `wslview` or `cmd.exe /c start` on WSL
5. **Interactive shell** — `docker exec -it` works everywhere; the `</dev/tty` redirect may need adjustment on some platforms

## Volumes

| Volume | Mount point | Purpose |
|---|---|---|
| `claude-chromium-profile` | `/home/claude/.config/chromium` | Persists the Chromium profile so the extension doesn't re-install on every launch |
| (bind mount) | `/work` | Your project directory |

## Ports

| Host | Container | Service |
|---|---|---|
| 6924 | 8086 | noVNC web interface |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_IMAGE` | `ghcr.io/montehurd/claude-dind:latest` | Override the Docker image used by the launcher |
| `CLAUDE_CREDENTIALS` | (from Keychain) | Pre-supply credentials instead of reading from Keychain |
| `DISPLAY_WIDTH` | `1280` | Virtual display width in pixels |
| `DISPLAY_HEIGHT` | `1024` | Virtual display height in pixels |
| `NOVNC_PORT` | `8086` | Container-internal port for the noVNC web server |
