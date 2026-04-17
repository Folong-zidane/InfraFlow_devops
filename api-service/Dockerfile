# syntax=docker/dockerfile:1
FROM nginx:alpine

RUN addgroup -S appgroup && adduser -S appuser -G appgroup && \
    chown -R appuser:appgroup /var/cache/nginx /var/log/nginx /etc/nginx/conf.d

COPY api.conf /etc/nginx/nginx.conf

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8080/get || exit 1

CMD ["nginx", "-g", "daemon off;"]
