# ── build stage: install Irys SDK dependencies (needs a toolchain for native deps) ──
FROM alpine:3.24.0@sha256:a2d49ea686c2adfe3c992e47dc3b5e7fa6e6b5055609400dc2acaeb241c829f4 AS deps

RUN apk add --no-cache nodejs npm python3 make g++ git

WORKDIR /opt/irys
COPY irys/package.json irys/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# ── final stage: runtime only ───────────────────────────────────────────────────
FROM alpine:3.24.0@sha256:a2d49ea686c2adfe3c992e47dc3b5e7fa6e6b5055609400dc2acaeb241c829f4

RUN apk add --no-cache \
    age \
    zstd \
    tar \
    bash \
    nodejs

COPY --from=deps /opt/irys/node_modules /opt/irys/node_modules
COPY irys/package.json irys/irys.mjs /opt/irys/

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]
CMD ["help"]
