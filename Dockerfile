FROM docker:dind

RUN apk add --no-cache \
    docker-cli-compose \
    git \
    curl \
    bash \
    jq \
    ripgrep \
    libgcc \
    libstdc++ \
    chromium \
    su-exec \
    coreutils \
    xfce4 \
    font-noto \
    font-noto-emoji \
    novnc \
    x11vnc \
    xvfb \
  && curl -fsSL https://claude.ai/install.sh | bash \
  && cp /root/.local/share/claude/versions/* /usr/local/bin/claude \
  && rm -rf /root/.local

ENV USE_BUILTIN_RIPGREP=0

# Create non-root user in the docker group
RUN addgroup -S docker 2>/dev/null; \
    adduser -D -u 1000 -G docker claude

# Chromium wrapper: --no-sandbox is required in containers
RUN printf '#!/bin/sh\nexec /usr/bin/chromium --no-first-run --disable-sync --disable-dev-shm-usage --disable-gpu --disable-infobars --disable-features=TabGroupsSave "$@"\n' > /usr/local/bin/browser \
  && chmod +x /usr/local/bin/browser \
  && ln -sf /usr/local/bin/browser /usr/local/bin/chromium

# Auto-install Claude Chrome extension via policy
RUN mkdir -p /etc/chromium/policies/managed \
  && printf '{"ExtensionInstallForcelist":["fcoeoabgfenejglbffodgkkbkcdhcgfn;https://clients2.google.com/service/update2/crx"]}\n' \
     > /etc/chromium/policies/managed/claude-extension.json

# XFCE background
COPY background.svg /usr/share/backgrounds/xfce/xfce-shapes.svg

ENV PATH="/home/claude/.local/bin:${PATH}"
ENV BROWSER=/usr/local/bin/browser
ENV USER=claude
ENV HOME=/home/claude
ENV DISPLAY=:0.0
ENV DISPLAY_WIDTH=1280
ENV DISPLAY_HEIGHT=1024
ENV NOVNC_PORT=8086

# Native messaging host for Chrome extension
COPY chrome-native-host /home/claude/.claude/chrome/chrome-native-host
RUN chmod +x /home/claude/.claude/chrome/chrome-native-host

RUN mkdir -p /etc/chromium/NativeMessagingHosts
COPY native-messaging-host.json /etc/chromium/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

COPY claude-shell /usr/local/bin/claude-shell
RUN chmod +x /usr/local/bin/claude-shell

# Host-side launcher script (extract with: docker run --rm IMAGE cat /macos-start)
COPY macos-start /macos-start
RUN chmod +x /macos-start

# Skip onboarding wizard and enable Chrome by default
RUN echo '{"hasCompletedOnboarding": true, "hasCompletedClaudeInChromeOnboarding": true, "cachedChromeExtensionInstalled": true, "claudeInChromeDefaultEnabled": true}' > /home/claude/.claude.json

# Set bash timeout to 30 minutes
RUN mkdir -p /home/claude/.claude \
  && echo '{"env":{"BASH_MAX_TIMEOUT_MS":"1800000"}}' > /home/claude/.claude/settings.json

RUN mkdir -p /home/claude/.local/bin \
  && ln -s /usr/local/bin/claude /home/claude/.local/bin/claude \
  && chown -R claude:docker /home/claude

EXPOSE 8086

WORKDIR /work
CMD ["start.sh"]
