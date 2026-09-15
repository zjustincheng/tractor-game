FROM node:24-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY backend/package.json backend/package.json
COPY frontend/package.json frontend/package.json
COPY packages/rules/package.json packages/rules/package.json
COPY packages/protocol/package.json packages/protocol/package.json
RUN npm ci
COPY frontend frontend
COPY packages packages
COPY tsconfig.json ./
RUN npm run build -w frontend

FROM nginx:stable-alpine
COPY infrastructure/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/frontend/dist /usr/share/nginx/html
EXPOSE 80
