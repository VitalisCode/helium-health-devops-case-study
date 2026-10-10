# syntax=docker/dockerfile:1.7
# Build from the repo root:  docker build -f docker/Dockerfile app/
# (context is app/; BuildKit picks up docker/Dockerfile.dockerignore automatically)

# ---- deps: production-only node_modules ----
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev --ignore-scripts

# ---- runtime ----
FROM node:22-alpine AS runtime
ENV NODE_ENV=production \
    PORT=8080
WORKDIR /app

# node:alpine ships an unprivileged "node" user (uid 1000); use it, numerically,
# so Kubernetes runAsNonRoot can verify it.
COPY --from=deps --chown=1000:1000 /app/node_modules ./node_modules
COPY --chown=1000:1000 package.json ./
COPY --chown=1000:1000 src ./src

USER 1000:1000
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

# Run node directly (not via npm) so SIGTERM reaches the process.
CMD ["node", "src/server.js"]
