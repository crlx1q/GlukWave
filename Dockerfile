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
COPY --from=denoland/deno:bin-2.9.7 /deno /usr/local/bin/deno
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-venv ca-certificates \
    && python3 -m venv /opt/extractors/ytdlp \
    && /opt/extractors/ytdlp/bin/pip install --no-cache-dir -r apps/server/extractors/requirements-ytdlp.txt \
    && python3 -m venv /opt/extractors/spotdl \
    && /opt/extractors/spotdl/bin/pip install --no-cache-dir -r apps/server/extractors/requirements-spotdl.txt \
    && rm -rf /var/lib/apt/lists/*
ENV EXTRACTOR_PYTHON=/opt/extractors/ytdlp/bin/python \
    SPOTDL_PYTHON=/opt/extractors/spotdl/bin/python \
    EXTRACTOR_DENO=/usr/local/bin/deno
RUN mkdir -p /app/var && chown -R node:node /app/var
USER node
EXPOSE 4000
CMD ["node", "apps/server/src/index.js"]
