FROM alpine:3

RUN apk add --no-cache unbound ca-certificates drill && \
    update-ca-certificates

RUN getent group unbound >/dev/null 2>&1 || addgroup -S unbound && \
    getent passwd unbound >/dev/null 2>&1 || adduser -S -D -H -s /sbin/nologin -G unbound unbound && \
    mkdir -p /etc/unbound /var/unbound && \
    chown -R unbound:unbound /etc/unbound /var/unbound

COPY unbound/unbound.conf /etc/unbound/unbound.conf.template

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

USER unbound

EXPOSE 5353/udp 5353/tcp

ENTRYPOINT ["/entrypoint.sh"]
