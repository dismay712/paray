FROM alpine:3.22

RUN apk add curl openrc sed supervisor unzip && \
    apk cache clean && \
    rm -rf /var/cache/apk/* && \
    mkdir -p /run/openrc && touch /run/openrc/softlevel

WORKDIR /apps

COPY * .

RUN chmod +x /apps/entrypoint.sh

EXPOSE 8080

CMD [""]
ENTRYPOINT ["/apps/entrypoint.sh"]
