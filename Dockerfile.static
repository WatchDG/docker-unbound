FROM alpine:3 AS builder

ARG TARGETARCH
ARG UNBOUND_VERSION=1.24.2
ARG UPX_VERSION=5.1.0

RUN apk add --no-cache \
    build-base \
    git \
    autoconf \
    automake \
    libtool \
    musl-dev \
    linux-headers \
    openssl \
    openssl-dev \
    openssl-libs-static \
    libevent-dev \
    libevent-static \
    expat-dev \
    expat-static \
    wget \
    xz \
    curl \
    ca-certificates && \
    update-ca-certificates

WORKDIR /tmp
COPY unbound-${UNBOUND_VERSION}.tar.gz .
RUN tar xzf unbound-${UNBOUND_VERSION}.tar.gz

RUN curl -L -o /tmp/upx.tar.xz "https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-${TARGETARCH}_linux.tar.xz" && \
    tar -xJf /tmp/upx.tar.xz -C /tmp && \
    mv /tmp/upx-${UPX_VERSION}-${TARGETARCH}_linux/upx /usr/local/bin/upx && \
    chmod +x /usr/local/bin/upx && \
    rm -rf /tmp/upx*

RUN rm -f /usr/lib/libssl.so* /usr/lib/libcrypto.so* /usr/lib/libevent.so* /usr/lib/libexpat.so*

WORKDIR /tmp/unbound-${UNBOUND_VERSION}
RUN ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --with-pthreads \
    --with-libevent \
    --with-ssl=/usr \
    --enable-static \
    --disable-shared \
    --enable-fully-static \
    --disable-flto \
    --disable-rpath \
    CFLAGS="-Os -ffunction-sections -fdata-sections -static" \
    LDFLAGS="-static -Wl,--gc-sections -Wl,-s" && \
    make -j$(nproc) && \
    make install DESTDIR=/tmp/unbound-install && \
    strip -s /tmp/unbound-install/usr/sbin/unbound && \
    upx --best --lzma /tmp/unbound-install/usr/sbin/unbound

FROM --platform=$BUILDPLATFORM watchdg/zig:v0.15.2 AS builder-zig
ARG TARGETOS
ARG TARGETARCH
WORKDIR /build
COPY unbound-zig.zig .
RUN case "${TARGETARCH}" in \
    amd64) ARCH="x86_64" ;; \
    arm64) ARCH="aarch64" ;; \
    *) ARCH="${TARGETARCH}" ;; \
    esac && \
    zig build-exe \
        unbound-zig.zig \
        -O ReleaseSmall \
        -target ${ARCH}-${TARGETOS}-musl \
        -lc \
        -fstrip \
        --name unbound-zig && \
    cp unbound-zig /unbound-zig

FROM --platform=$BUILDPLATFORM alpine:3 AS scratch-prepare
RUN echo "unbound:x:1000:1000:unbound user:/:/sbin/nologin" > /etc/passwd && \
    echo "unbound:x:1000:" > /etc/group

FROM scratch
COPY --from=scratch-prepare /etc/passwd /etc/passwd
COPY --from=scratch-prepare /etc/group /etc/group
COPY --from=builder /tmp/unbound-install/usr/sbin/unbound /usr/sbin/unbound
COPY --from=builder-zig /unbound-zig /unbound-zig
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY unbound/unbound.conf /etc/unbound/unbound.conf.template
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_DIR=/etc/ssl/certs
EXPOSE 5353/udp 5353/tcp
ENTRYPOINT ["/unbound-zig"]
