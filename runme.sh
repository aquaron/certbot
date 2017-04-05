#!/bin/sh

getvol() { echo $(grep ' /data ' /proc/self/mountinfo | cut -f 4 -d" "); }
_vol=$(getvol)
_ports="-p 80:80"

if [ ! "${_vol}" ]; then 
    echo "ERROR: you need run Docker with the -v parameter, try:"
    echo "    \$ docker run --rm -v /tmp:/data aquaron/certbot help"
    exit 1
fi

_run="docker run -t --rm -v ${_vol}:/data ${_ports} aquaron/certbot"

HELP=`cat <<EOT
Usage: docker run -t --rm -v <local-dir>:/data ${_ports} aquaron/certbot <command> <host> <email>

 <local-dir> - directory on the host system to map to container

 <command>   certbot    - create/renew certificate
             dry-run    - run through Certbot's command w/o creating any files
             test-cert  - Certbot's test cert
             clean      - clears all data to test init

 <host>     - FDN (eg example.com) to act on
 <email>    - Certificate email account

`

if [[ $# -lt 1 ]] || [[ ! "${_vol}" ]]; then echo "$HELP"; exit 1; fi

hint() {
    local hint="| $* |"
    local stripped="${hint//${bold}}"
    stripped="${stripped//${normal}}"
    local edge=$(echo "$stripped" | sed -e 's/./-/g' -e 's/^./+/' -e 's/.$/+/')
    echo "$edge"
    echo "$hint"
    echo "$edge"
}

_CMD=$1
_HOST=$2
_EMAIL=$3

_DATADIR=/data

### making nginx.conf in tmp
write_temp_nginx_conf() {
    local _filename=$1
    echo "
        user nginx;
        events { worker_connections 10; }
        pid /var/run/nginx.pid;
        http { server { listen 80; location / { root /tmp; } } }
    " > ${_filename}
}

var_assert() {
    local _var="$1"
    if [ ! "$1" ]; then
        echo "ABORT: ${_CMD} <host> <email>"
        exit 1
    fi
}

### install nginx and certbot to get Let's Encrypt
setup_nginx_certbot() {
    var_assert "$_HOST"
    var_assert "$_EMAIL"

    local _cmd="$1"
    if [ "${_cmd}" ]; then _istest="--${_cmd}"; fi

    write_temp_nginx_conf "/tmp/nginx.conf"

    ### start up server
    nginx -c /tmp/nginx.conf

    set +e

    ### get certificate
    local _result=$(certbot certonly ${_istest} \
        --webroot \
        --webroot-path /tmp \
        --config-dir ${_DATADIR}/letsencrypt \
        --no-self-upgrade \
        --agree-tos \
        --email "${_EMAIL}" \
        --manual-public-ip-logging-ok \
        --non-interactive \
        --must-staple \
        --staple-ocsp \
        --keep \
        -d "${_HOST}")

    set -e

    ### stop server
    nginx -c /tmp/nginx.conf -s stop

    case "${_result}" in
        *'no action taken'*|\
        *'No renewals were attempted'*)
            echo "Nothing done"
            ;;

        *'Congratulations'*)
            hint "${_HOST}"
            echo "Success!"
            ;;
 
        *)
            echo -e $_res
            ;;
    esac
}


conf_assert() {
    if [ ! -s "${CONFIG_FILE}" ]; then
        hint "SoftEther not setup"
    fi
}

case "${_CMD}" in
    certbot)
        setup_nginx_certbot
        ;;

    test-cert|dry-run)
        if [ -d "${_DATADIR}/letsencrypt" ]; then
            hint "Abort"
            echo "${_DATADIR}/letsencrypt already exists!"
            exit 1
        fi
        setup_nginx_certbot "${_CMD}"
        ;;

    clean)
        rm -rf ${_DATADIR}/letsencrypt
        ;;

    help)
        echo "$HELP"
        ;;

    *) echo "ERROR: Command '${_CMD}' not recognized"
        ;;
esac

