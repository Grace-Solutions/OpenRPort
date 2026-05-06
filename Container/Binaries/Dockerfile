# Container/Binaries/Dockerfile
# nginx-based static file server for pre-fetched rport agent binaries.
# Routing/proxying is the responsibility of the edge reverse proxy
# (sample at docs/nginx.sample.conf); this container does not proxy
# any other service.

ARG NGINX_IMAGE=nginx
ARG NGINX_VERSION=1.27-alpine
FROM ${NGINX_IMAGE}:${NGINX_VERSION}

# wget for healthcheck; gettext provides envsubst.
RUN apk add --no-cache wget gettext

# Templates are rendered into /etc/nginx/conf.d at container start so the
# listen port and base path are honoured at runtime without rebuilding.
COPY Container/Binaries/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY Container/Binaries/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
