FROM node:24-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY apps/server/package.json apps/server/package.json
COPY apps/web/package.json apps/web/package.json
RUN npm ci --ignore-scripts
RUN npm rebuild ffmpeg-static
COPY apps/server apps/server
COPY apps/web apps/web
RUN npm run build
RUN npm prune --omit=dev --ignore-scripts

FROM node:24-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production HOST=0.0.0.0 PORT=4000
COPY --from=build /app /app
RUN mkdir -p /app/var && chown -R node:node /app/var
USER node
EXPOSE 4000
CMD ["node", "apps/server/src/index.js"]
