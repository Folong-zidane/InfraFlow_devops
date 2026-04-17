# syntax=docker/dockerfile:1
FROM nginx:alpine

RUN addgroup -S nginxgroup && adduser -S nginxuser -G nginxgroup && \
    chown -R nginxuser:nginxgroup /var/cache/nginx /var/log/nginx /etc/nginx/conf.d

COPY nginx.conf /etc/nginx/nginx.conf

USER nginxuser

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://127.0.0.1:80/status || exit 1

CMD ["nginx", "-g", "daemon off;"]
