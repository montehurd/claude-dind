#!/bin/sh

cleanup() {
  pkill -TERM chromium 2>/dev/null
  wait
}
trap cleanup TERM INT

# Start the Docker daemon in the background (requires root)
export DOCKER_HOST=unix:///var/run/docker.sock
dockerd &
until docker info >/dev/null 2>&1; do
  sleep 1
done

# Start the display stack
Xvfb :0 -screen 0 ${DISPLAY_WIDTH:-1280}x${DISPLAY_HEIGHT:-1024}x24 -listen tcp -ac &
until [ -e /tmp/.X11-unix/X0 ]; do sleep 0.5; done
DISPLAY=:0 startxfce4 &
x11vnc -forever -shared -display :0 &
websockify --web /usr/share/novnc ${NOVNC_PORT:-8086} localhost:5900 &

# Fix ownership of home dir (volume mounts and cache dirs may be root-owned)
chown -R claude:docker /home/claude

# Remove stale Chromium lock files from persisted profile
rm -f /home/claude/.config/chromium/SingletonLock /home/claude/.config/chromium/SingletonCookie /home/claude/.config/chromium/SingletonSocket 2>/dev/null

# Clear session restore data so old "Claude (MCP)" tab groups don't accumulate
rm -rf /home/claude/.config/chromium/Default/Sessions 2>/dev/null

# Launch Chromium on the display
su-exec claude /usr/local/bin/browser &

# Seed credentials file from host keychain if provided
if [ -n "$CLAUDE_CREDENTIALS" ] && [ ! -f /home/claude/.claude/.credentials.json ]; then
  mkdir -p /home/claude/.claude
  printf '%s' "$CLAUDE_CREDENTIALS" > /home/claude/.claude/.credentials.json
  chown claude:docker /home/claude/.claude/.credentials.json
  chmod 600 /home/claude/.claude/.credentials.json
fi

# Clear credentials from environment and keep container alive
unset CLAUDE_CREDENTIALS
while true; do sleep 86400; done &
wait
