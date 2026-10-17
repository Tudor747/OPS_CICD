FROM node:24-bookworm-slim AS base
ENV NODE_ENV=production
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --chown=node:node app.js ./
USER node
FROM base AS test
COPY --chown=node:node test ./test
RUN node --test
FROM base AS production
EXPOSE 3000
CMD ["node", "app.js"]
