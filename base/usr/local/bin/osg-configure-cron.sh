#!/bin/bash

# Run osg-configure if we detect config changes

echoerr() { printf "%s\n" "$*" >&2; }

if [[ $(ps -eo cmd | grep 'osg-configure -c' | grep -qv grep)  ]]; then
    echoerr "ERROR: osg-configure already running, exiting."
    exit 1
fi

cached_checksum_dir=/var/cache/osg/
cached_checksum_path=$cached_checksum_dir/config-sha256.txt

config_dir=/etc/osg/config.d/
config_checksum=$(sha256sum "$config_dir/*")
cached_config_checksum=$(cat "$cached_checksum_path" 2> /dev/null)

if [[ -z $cached_config_checksum ]]; then
    echoerr "WARNING: no existing config checksum found. Writing new checksum to '/var/cache/osg/config-sha256.txt'."
    mkdir -p $cached_checksum_dir
    echo "$config_checksum" > "$cached_checksum_path"
fi

if [[ $config_checksum == "$cached_config_checksum" ]]; then
    echoerr "No changes detected in $config_dir, exiting."
   exit 0
fi

cp "/tmp/$config_dir/*.ini" /etc/osg/config.d
osg-configure -c
condor_ce_reconfig
