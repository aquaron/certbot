#!/bin/bash

cls="\e(B\e[m"
yellow() { echo -en "\e[38;5;208m$1${cls}"; }
green() { echo -en "\e[38;5;112m$1${cls}"; }
red() { echo -en "\e[38;5;196m$1${cls}"; }
fade() { echo -en "\e[38;5;239m$1${cls}"; }

guess_volumes() {
    local _files=( "$1" )
    local _file="/proc/self/mountinfo"
    local _map=""

    for i in "${!_files[@]}"; do
        local _localpath=$(grep ${_files[$i]} ${_file} | grep -v '/volumes/' | cut -f 4,9 -d" ")
        local _arr=(${_localpath// / })
        if [[ "${_localpath}" ]]; then
            if [[ "${_arr[1]}" = "/dev/root" ]]; then
                _localpath="${_arr[0]}"
            else
                _localpath="${_arr[1]}${_arr[0]}"
            fi
            _map="${_map} ${_localpath}"
        fi
    done
    echo $_map
}

_VOL=$(guess_volumes "/data")

if [[ ! "${_VOL}" ]]; then
    echo "$(red "ERROR:") you need run Docker with the $(green "-v") parameter, try:"
    echo "    \$ docker run --rm -v /tmp:/data aquaron/certbot help"
    exit 1
fi

HELP=`cat <<EOT
Usage: docker run -t --rm -v $(green "<local-dir>"):/data aquaron/certbot [$(yellow "<options>")]
 $(fade "docker run -t --rm -v ${_VOL}:/data aquaron/certbot \\\\
  --host example.com --email me@example.com --dns google -get -test")

 $(green "<local-dir>") - directory on the host system to map to container

 $(yellow "<options>"):
   --host   - FQN to get domain certificate (eg $(fade "example.com"))
   --dns    - dns-01 challenge plugin (eg $(fade "digitalocean"))
   --email  - Email address of maintainer (eg $(fade "me@example.com"))

   -get     - Get new certificate
   -renew   - Renew all certificates
   -revoke  - Revoke certificate and delete it
   -clean   - Remove letsencrypt directory (careful with this)
   -test    - Use staging server instead of production
   -force   - Toggles forcing of renewal (for both get/renew)
   -verbose - Turn on talkative mode
EOT
`
if [[ $# -lt 1 ]] || [[ ! "${_VOL}" ]]; then echo "$HELP"; exit 1; fi

hint() {
    if [[ "${CONF[verbose]}" ]]; then
        local hint="| $* |"
        local stripped="${hint}"
        local edge=$(echo "$stripped" | sed -e 's/./-/g' -e 's/^./+/' -e 's/.$/+/')
        echo "$edge"
        echo "$hint"
        echo "$edge"
    fi
}

declare -A CONF=()

_DATADIR=/data
_LEDIR="${_DATADIR}/letsencrypt"
_LOCALLEDIR="${_VOL}/letsencrypt"
_CONFFILE="${_LEDIR}/cli.ini"

conf_assert() {
    local _name="$1"
    local _opt=$(echo "$_name" | tr '[:upper:]' '[:lower:]')
    if [[ ! "${CONF[$_name]}" ]]; then
        echo "$(red "ABORT"): Missing --$_opt"
        exit 1
    fi
}

certbot_wildcard() {
    check_dns
    conf_assert 'HOST'

    local _host="${CONF[HOST]}"

    hint "Create ${_host} wildcard certificate"
    local _result=$(certbot certonly --config "${_CONFFILE}" -d "${_host}" -d "*.${_host}" 2>&1)

    case "${_result}" in
        *'Congratulations'*)
            echo "$(green "SUCCESS:") ${_host} certificate created"
            ;;

        *'Certificate not yet due for renewal'*)
            echo "$(yellow "ABORT:") Certificate not yet due for renewal"
            ;;

        *'Unable to determine base domain'*)
            echo "$(red "ABORT:") Cannot find $(yellow "$_host") at $(yellow "${CONF[DNS]}")"
            ;;

        *'DNS problem: NXDOMAIN looking up TXT'*)
            echo "$(red "ABORT:") Lookup failed, try again later"
            ;;

        *)
            echo "$(red "ABORT:") Error encountered"
            echo -e "$_result"
            ;;
    esac
}

certbot_renew() {
    hint "Renew certificates"

    local _result=$(certbot renew --config "${_CONFFILE}" 2>&1 | grep 'fullchain.pem ')
    local _success=$(echo "${_result}" | grep '(success)' | cut -d"/" -f 5 | paste -s -d" ")
    local _skipped=$(echo "${_result}" | grep '(skipped)' | cut -d"/" -f 5 | paste -s -d" ")

    [[ "$_success" ]] && echo "$(green "RENEWED:") $_success"
    [[ "$_skipped" ]] && verbose "$(yellow "SKIPPED:") $_skipped"
}

certbot_revoke() {
    conf_assert 'HOST'

    local _host="${CONF[HOST]}"
    local _path="${_LEDIR}/live/${_host}/cert.pem"
    local _lpath="${_LOCALLEDIR}/live/${_host}/cert.pem"
    if [ ! -s "${_path}" ]; then
        echo "$(red "ERROR:") $(yellow "${_lpath}") does not exist"
        exit 1
    fi

    hint "Revoking ${_host}"
    local _result=$(certbot revoke --config ${_CONFFILE} --cert-path "${_path}" 2>&1)
    case "$_result" in
        *'Congratulations'*)
            echo "$(green "SUCCESS:") $_host certificate is revoked"
            ;;

        *)
            echo -e "$_result"
            ;;
    esac
}

check_dns() {
    conf_assert 'DNS'

    local _dns=${CONF[DNS]}
    local _credfile=

    case $_dns in
        google|digitalocean|linode|route53)
            _credfile="${_DATADIR}/${_dns}-dns.conf"
            verbose "+ got credential file: $(green "${_credfile}")"
            ;;

        *)
            echo "$(red "ERROR:") DNS $(yellow "${_dns}") not supported"
            exit 1
            ;;
    esac

    if [[ ! -s "${_credfile}" ]]; then
        echo "$(red "ERROR:") Credential file $(yellow "${_credfile}") not found"
        exit 1
    fi

    echo "dns-${_dns}-credentials = ${_credfile}"   >> ${_CONFFILE}
    echo "dns-${_dns} = true"                       >> ${_CONFFILE}

    verbose "+ add DNS $(green "${_dns}") to configuration"
}

remove_all() {
    if [[ -d "${_LEDIR}" ]]; then
        if [[ -z "$(ls -A ${_LEDIR}/live)" ]]; then
            rm -rf ${_LEDIR}
        else
            echo "$(red "ERROR:") $(yellow "${_LOCALLEDIR}/live") not empty"
        fi
    fi
    exit 1
}

setup_env() {
    conf_assert 'EMAIL'

    local _inifile="/etc/cli.ini"

    hint "Initializing"

    if [[ ! -s "${_inifile}" ]]; then
        echo "$(red "ERROR:") Cannot find $(yellow "${_inifile}")"
        exit 1
    fi

    if [[ ! -d "${_LEDIR}" ]]; then
        verbose "+ creating new $(green "${_LEDIR}") directory"
        mkdir -p ${_LEDIR}
    fi

    if [[ "${CONF[test]}" ]]; then
        verbose "+ using $(yellow "STAGING") server"
        sed -e 's/server =.*//' -e 's/server-stage/server/' ${_inifile} > ${_CONFFILE}
    else
        verbose "+ using $(green "PRODUCTION") server"
        sed -e 's/server-stage =.*//' ${_inifile} > ${_CONFFILE}
    fi

    if [[ "${CONF[force]}" ]]; then
        verbose "+ $(yellow "forcing") renewals"
        sed -i 's/keep-until-expiring.*//' ${_CONFFILE}
        echo "force-renewal = true"                 >> ${_CONFFILE}
    fi

    echo "config-dir = ${_LEDIR}"                   >> ${_CONFFILE}
    echo "email = ${CONF[EMAIL]}"                   >> ${_CONFFILE}

    if [[ ! -s "${_CONFFILE}" ]]; then
        echo "$(red "ERROR:") Cannot find $(yellow "${_CONFFILE}")"
        exit 1
    fi

    verbose "+ configuration file initialized: $(green "${_CONFFILE}")"
}

verbose() {
    if [[ "${CONF[verbose]}" ]]; then
        echo -e "$1"
    fi
}

while [[ $# -ge 1 ]]; do
    _key="$1"
    _opt=$(echo "${_key#--}" | tr '[:lower:]' '[:upper:]')
    case "$_key" in
        --dns|--email|--host)
            CONF[$_opt]="$2"
            shift
            ;;

        -clean|-test|-revoke|-renew|-force|-get|-verbose)
            CONF[${_key#-}]=1
            ;;

        help)
            echo -e "$HELP"
            exit 1
            ;;
        *)
            echo "$(red "ERROR:") Unknown option: $(yellow "$_key")"
            exit 1
            ;;
    esac
    shift
done

[[ "${CONF[clean]}" ]] && remove_all

setup_env

[[ "${CONF[get]}" ]] && certbot_wildcard
[[ "${CONF[renew]}" ]] && certbot_renew
[[ "${CONF[revoke]}" ]] && certbot_revoke

if [[ ! "${CONF[get]}" ]] && [[ ! "${CONF[renew]}" ]] && [[ ! "${CONF[revoke]}" ]]; then
    echo "$(yellow "ABORT"): Nothing is done. Use $(yellow "-get")?"
fi

