FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    golang \
    ffmpeg \
    python3-pip \
    python3-venv \
    python3-full \
    git \
    $OPENCLAW_DOCKER_APT_PACKAGES && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Install uv (fast python package installer)
RUN python3 -m pip install --break-system-packages uv

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production


# Install Google Gemini CLI globally
RUN npm install -g @google/gemini-cli

# Install ClawdHub CLI globally (used by Moltbot skills tooling)
RUN npm install -g clawdhub undici

# Security hardening: Run as non-root user
# The node:22-bookworm image includes a 'node' user (uid 1000)
# This reduces the attack surface by preventing container escape via root privileges
USER node

# Configure NPM for the non-root user
ENV NPM_CONFIG_PREFIX=/home/node/.npm-global
ENV PATH=$PATH:/home/node/.npm-global/bin
ENV PATH=$PATH:/home/node/go/bin
RUN mkdir -p /home/node/.npm-global && \
    npm config set prefix '/home/node/.npm-global' && \
    git config --global --add safe.directory /app

CMD ["node", "dist/index.js"]
