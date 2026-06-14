ARG INCLUDE_DEV_TOOLS=false

FROM alpine:3.22

RUN apk add --no-cache --update \
    ca-certificates \
    postfix \
    postfix-doc \
    postfix-ldap \
    tzdata

RUN if [ "$INCLUDE_DEV_TOOLS" = "true" ]; then \
      apk add --no-cache bash bash-doc; \
    fi

EXPOSE 25 465 587

VOLUME [ "/var/spool/postfix" ]

COPY VERSION /
COPY entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]

