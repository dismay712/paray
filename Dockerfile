ARG ALPINE_IMAGE=alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8

FROM --platform=$BUILDPLATFORM ${ALPINE_IMAGE} AS downloads
RUN apk add --no-cache \
    curl=8.14.1-r3 \
    jq=1.8.2-r0 \
    unzip=6.0-r15
WORKDIR /src
COPY versions.lock.json fetch.sh ./

FROM downloads AS core
ARG TARGETARCH
RUN sh fetch.sh xray "$TARGETARCH" /tmp/xray.zip \
    && unzip -p /tmp/xray.zip xray > /out/xray \
    && unzip -p /tmp/xray.zip LICENSE > /out/xray-LICENSE \
    && rm /tmp/xray.zip \
    && sh fetch.sh geoip any /out/geoip.dat \
    && sh fetch.sh cloudflared "$TARGETARCH" /out/cloudflared \
    && chmod 755 /out/xray /out/cloudflared

FROM downloads AS agent
ARG TARGETARCH
RUN sh fetch.sh komari "$TARGETARCH" /out/komari-agent \
    && chmod 755 /out/komari-agent

FROM ${ALPINE_IMAGE} AS runtime
RUN apk add --no-cache \
        ca-certificates-bundle=20260909-r0 \
        jq=1.8.2-r0 \
        oniguruma=6.9.10-r0 \
        s6=2.13.2.0-r0 \
    && addgroup -g 10001 paray \
    && adduser -D -H -u 10001 -G paray \
        -h /run/paray/home \
        -s /sbin/nologin paray

COPY --from=core /out/xray /out/cloudflared /usr/local/bin/
COPY --from=core /out/geoip.dat /usr/local/share/xray/geoip.dat
COPY --from=core /out/xray-LICENSE /usr/local/share/paray/xray-LICENSE

COPY rootfs/ /
COPY config.json /etc/paray/config.json
COPY versions.lock.json LICENSE /usr/local/share/paray/

RUN chmod 755 \
    /usr/local/bin/paray-entrypoint \
    /usr/local/libexec/paray-config \
    /etc/services.d/*/run \
    /usr/local/bin/healthcheck

ENV PATH=/usr/local/bin:/usr/bin:/bin \
    XRAY_LOCATION_ASSET=/usr/local/share/xray

EXPOSE 8488

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD ["/usr/local/bin/healthcheck"]

ENTRYPOINT ["/usr/local/bin/paray-entrypoint"]

FROM runtime AS lite
LABEL org.opencontainers.image.title="paray lite"

FROM runtime AS full
COPY --from=agent /out/komari-agent /usr/local/bin/komari-agent
LABEL org.opencontainers.image.title="paray full"