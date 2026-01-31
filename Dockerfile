FROM alpine:3

RUN apk add --no-cache unbound ca-certificates drill && \
    update-ca-certificates

RUN mkdir -p /etc/unbound /var/unbound && \
    chown -R unbound:unbound /etc/unbound /var/unbound

COPY unbound/unbound.conf /etc/unbound/unbound.conf.template

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

USER unbound

EXPOSE 53/udp 53/tcp

HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD drill @127.0.0.1 google.com || exit 1

ENTRYPOINT ["/entrypoint.sh"]
