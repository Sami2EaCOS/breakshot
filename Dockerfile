FROM node:24-alpine

WORKDIR /app/server

ENV NODE_ENV=production
ENV PORT=8787
ENV STATIC_ROOT=/app/web_export

COPY server/package*.json ./
RUN npm ci --omit=dev

COPY server/ ./
COPY web_export/ /app/web_export/

EXPOSE 8787

CMD ["node", "index.js"]
