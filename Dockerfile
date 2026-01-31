FROM alpine:3.19

RUN apk add --no-cache unbound ca-certificates drill && \
    update-ca-certificates

RUN mkdir -p /etc/unbound /var/unbound && \
    chown -R unbound:unbound /etc/unbound /var/unbound

COPY unbound/unbound.conf /etc/unbound/unbound.conf

USER unbound

EXPOSE 53/udp 53/tcp

HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD drill @127.0.0.1 google.com || exit 1

ENTRYPOINT ["/usr/sbin/unbound", "-d", "-c", "/etc/unbound/unbound.conf"]
