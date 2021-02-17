#!/bin/bash
# Adapted from https://github.com/htcondor/htcondor

set -xe

prog=${0##*/}

fail () {
    echo "$prog:" "$@" >&2
    exit 1
}

add_values_to () {
    config=$1
    shift
    printf "%s=%s\n" >> "/etc/condor/config.d/$config" "$@"
}

# Create a config file from the environment.
# The config file needs to be on disk instead of referencing the env
# at run time so condor_config_val can work.
echo "# This file was created by $prog" > /etc/condor/config.d/01-env.conf
add_values_to 01-env.conf \
    CONDOR_HOST "${CONDOR_SERVICE_HOST:-${CONDOR_HOST:-\$(FULL_HOSTNAME)}}" \
    NUM_CPUS "${NUM_CPUS:-1}" \
    MEMORY "${MEMORY:-1024}" \
    RESERVED_DISK "${RESERVED_DISK:-1024}" \
    USE_POOL_PASSWORD "${USE_POOL_PASSWORD:-no}"


bash -x "/usr/local/bin/update-secrets" || fail "Failed to update secrets"
bash -x "/usr/local/bin/update-config" || fail "Failed to update config"


# Bug workaround: daemons will die if they can't raise the number of FD's;
# cap the request if we can't raise it.
hard_max=$(ulimit -Hn)

rm -f /etc/condor/config.d/01-fdfix.conf
# Try to raise the hard limit ourselves.  If we can't raise it, lower
# the limits in the condor config to the maximum allowable.
for attr in COLLECTOR_MAX_FILE_DESCRIPTORS \
            SHARED_PORT_MAX_FILE_DESCRIPTORS \
            SCHEDD_MAX_FILE_DESCRIPTORS \
            MAX_FILE_DESCRIPTORS; do
    config_max=$(condor_config_val -evaluate $attr ||: )
    if [[ $config_max =~ ^[0-9]+$ && $config_max -gt $hard_max ]]; then
        if ! ulimit -Hn "$config_max" &>/dev/null; then
            add_values_to 01-fdfix.conf "$attr" "$hard_max"
        fi
        ulimit -Hn "$hard_max"
    fi
done
[[ -s /etc/condor/config.d/01-fdfix.conf ]] && \
    echo "# This file was created by $prog" >> /etc/condor/config.d/01-fdfix.conf

chown -R condor:condor /var/log/condor /var/lib/condor/spool

set +xe
