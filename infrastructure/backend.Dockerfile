FROM node:24-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY backend/package.json backend/package.json
COPY frontend/package.json frontend/package.json
COPY packages/rules/package.json packages/rules/package.json
COPY packages/protocol/package.json packages/protocol/package.json
RUN npm ci
COPY backend backend
COPY packages packages
RUN npm run build -w backend
RUN npm prune --omit=dev

FROM node:24-bookworm-slim AS runtime
ENV NODE_ENV=production HOST=0.0.0.0 PORT=4000
WORKDIR /app
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/backend/dist ./backend/dist
COPY --from=build --chown=node:node /app/backend/package.json ./backend/package.json
USER node
EXPOSE 4000
CMD ["node", "backend/dist/server.js"]
