# Runtime image only: deploy.sh builds server.mjs first and uploads it next to this file.
FROM gcr.io/distroless/nodejs22-debian12:nonroot
WORKDIR /app
COPY server.mjs /app/server.mjs
ENV NODE_ENV=production
CMD ["/app/server.mjs"]
