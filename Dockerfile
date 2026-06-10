FROM alpine:3.22

RUN apk add --no-cache --update \
    bash \
    ca-certificates \
    postfix \
    postfix-doc \
    postfix-ldap \
    tzdata

EXPOSE 25 465 587

VOLUME [ "/var/spool/postfix" ]

COPY VERSION /

ENTRYPOINT ["/usr/sbin/postfix", "start-fg"]

