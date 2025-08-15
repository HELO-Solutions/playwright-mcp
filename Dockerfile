ARG PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# ------------------------------
# Base
# ------------------------------
# Base stage: Contains only the minimal dependencies required for runtime
# (node_modules and Playwright system dependencies)
FROM node:22-bookworm-slim AS base

ARG PLAYWRIGHT_BROWSERS_PATH
ENV PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_PATH}

# Set the working directory
WORKDIR /app

# Install VNC and X11 dependencies for headed browser support
RUN apt-get update && apt-get install -y \
    xvfb \
    x11vnc \
    fluxbox \
    x11-utils \
    xauth \
    dbus-x11 \
    python3 \
    python3-pip \
    python3-websockify \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set up VNC environment
ENV DISPLAY=:99
ENV VNC_PORT=5900
ENV VNC_PASSWORD=playwright

# Create VNC password file
RUN mkdir -p ~/.vnc && \
    echo "$VNC_PASSWORD" | x11vnc -storepasswd /root/.vncpasswd 2>/dev/null || true

RUN --mount=type=cache,target=/root/.npm,sharing=locked,id=npm-cache \
    --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
  npm ci --omit=dev && \
  # Install system dependencies for playwright
  npx -y playwright-core install-deps chromium

# ------------------------------
# Builder
# ------------------------------
FROM base AS builder

RUN --mount=type=cache,target=/root/.npm,sharing=locked,id=npm-cache \
    --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
  npm ci

# Copy the rest of the app
COPY *.json *.js *.ts ./
COPY src src/

# Build the app
RUN npm run build

# ------------------------------
# Browser
# ------------------------------
# Cache optimization:
# - Browser is downloaded only when node_modules or Playwright system dependencies change
# - Cache is reused when only source code changes
FROM base AS browser

RUN npx -y playwright-core install --no-shell chromium

# ------------------------------
# Runtime
# ------------------------------
FROM base

ARG PLAYWRIGHT_BROWSERS_PATH
ARG USERNAME=node
ENV NODE_ENV=production

# Set the correct ownership for the runtime user on production `node_modules`
RUN chown -R ${USERNAME}:${USERNAME} node_modules

# Create startup script for VNC and Playwright
COPY <<'EOF' /start.sh
#!/bin/bash
set -e

echo "Starting browser preview services..."

# Clean up any existing X lock files
rm -f /tmp/.X99-lock

# Start Xvfb
echo "Starting Xvfb..."
Xvfb :99 -screen 0 1280x720x16 &
sleep 3

# Start window manager
echo "Starting Fluxbox..."
DISPLAY=:99 fluxbox &
sleep 2

# Start VNC server without password (for development)
echo "Starting VNC server..."
x11vnc -display :99 -forever -nopw -shared -rfbport 5900 -bg -noxdamage

# Start websockify to bridge VNC to WebSocket
echo "Starting websockify..."
websockify 6080 localhost:5900 &

# Wait a bit for services to start
sleep 3

echo "Starting Playwright MCP server..."
# Start Playwright MCP server in headed mode
exec node cli.js --browser chromium --no-sandbox "$@"
EOF

RUN chmod +x /start.sh

COPY --from=browser --chown=${USERNAME}:${USERNAME} ${PLAYWRIGHT_BROWSERS_PATH} ${PLAYWRIGHT_BROWSERS_PATH}
COPY --chown=${USERNAME}:${USERNAME} cli.js package.json ./
COPY --from=builder --chown=${USERNAME}:${USERNAME} /app/lib /app/lib

USER ${USERNAME}

# Expose VNC and WebSocket ports
EXPOSE 5900 6080

# Run with headed browser and VNC
ENTRYPOINT ["/start.sh"]
