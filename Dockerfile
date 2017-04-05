FROM alpine
MAINTAINER Paul Pham <docker@aquaron.com>

COPY runme.sh /usr/bin/runme.sh

RUN apk add --no-cache certbot nginx \
 && rm -rf /core /var/cache/apk/* 

ENTRYPOINT [ "runme.sh" ]
CMD [ "help" ]
