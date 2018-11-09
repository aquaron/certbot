FROM alpine

ARG BUILD_DATE

LABEL maintainer="docker@aquaron.com" \
 org.label-schema.build-date=$BUILD_DATE \
 org.label-schema.docker.cmd="docker run --rm -t -v $PWD:/data aquaron/certbot" \
 org.label-schema.description="Get/renew Let's Encrypt Wildcard Certs with Certbot" \
 org.label-schema.name="certbot" \
 org.label-schema.url="https://certbot.eff.org" \
 org.label-schema.vcs-url="https://github.com/aquaron/certbot" \
 org.label-schema.vendor="aquaron" \
 org.label-schema.version="1.1"

COPY data/runme.sh /usr/bin/runme.sh
COPY data/cli.ini /etc/cli.ini

RUN apk add --no-cache bash git python3 python3-dev musl-dev libffi-dev openssl-dev gcc \
 && git clone https://github.com/certbot/certbot \
 && cd /certbot \
 && python3 setup.py install \
 && cd certbot-dns-google; python3 setup.py install; cd .. \
 && cd certbot-dns-digitalocean; python3 setup.py install; cd .. \
# && cd certbot-dns-route53; python3 setup.py install; cd .. \
 && cd certbot-dns-linode; python3 setup.py install; cd .. \
 && apk del --purge git python3-dev musl-dev libffi-dev gcc \
 && rm -rf /core /var/cache/apk/* /certbot

ENTRYPOINT [ "runme.sh" ]
CMD [ "help" ]
