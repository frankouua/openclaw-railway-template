#!/bin/bash
set -e

# Ensure /data and OpenClaw state paths are writable by openclaw
mkdir -p /data/.openclaw/identity /data/workspace
chown -R openclaw:openclaw /data 2>/dev/null || true
chmod 700 /data 2>/dev/null || true
chmod 700 /data/.openclaw 2>/dev/null || true
chmod 700 /data/.openclaw/identity 2>/dev/null || true

# Persist Homebrew to Railway volume so it survives container rebuilds
BREW_VOLUME="/data/.linuxbrew"
BREW_SYSTEM="/home/openclaw/.linuxbrew"

if [ -d "$BREW_VOLUME" ]; then
  # Volume already has Homebrew — symlink back to expected location
  if [ ! -L "$BREW_SYSTEM" ]; then
    rm -rf "$BREW_SYSTEM"
    ln -sf "$BREW_VOLUME" "$BREW_SYSTEM"
    echo "[entrypoint] Restored Homebrew from volume symlink"
  fi
else
  # First boot — move Homebrew install to volume for persistence
  if [ -d "$BREW_SYSTEM" ] && [ ! -L "$BREW_SYSTEM" ]; then
    mv "$BREW_SYSTEM" "$BREW_VOLUME"
    ln -sf "$BREW_VOLUME" "$BREW_SYSTEM"
    echo "[entrypoint] Persisted Homebrew to volume on first boot"
  fi
fi

# Start Xvfb (virtual display) + Fluxbox (window manager) + VNC + noVNC
export DISPLAY=:99
VNC_PORT=${VNC_PORT:-5900}
NOVNC_PORT=${NOVNC_PORT:-6080}
VNC_PASSWORD=${VNC_PASSWORD:-$SETUP_PASSWORD}

echo "[entrypoint] Starting virtual display + VNC..."
Xvfb :99 -screen 0 1280x720x24 -ac &
sleep 1
fluxbox -display :99 &
sleep 1

# Start VNC server with password
mkdir -p /tmp/.vnc
x11vnc -display :99 -rfbport $VNC_PORT -passwd "$VNC_PASSWORD" -shared -forever -bg -o /tmp/.vnc/x11vnc.log 2>/dev/null

# Start noVNC (web-based VNC client) - accessible via browser
websockify --web=/usr/share/novnc/ $NOVNC_PORT localhost:$VNC_PORT &
echo "[entrypoint] noVNC ready on port $NOVNC_PORT (password: same as SETUP_PASSWORD)"

# Pre-create Chromium user data dir on volume for cookie persistence
mkdir -p /data/.chromium-profile
chown openclaw:openclaw /data/.chromium-profile

exec gosu openclaw node src/server.js
