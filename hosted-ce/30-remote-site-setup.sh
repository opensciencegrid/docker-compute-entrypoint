#!/bin/bash

. /etc/osg/image-config.d/ce-common-startup

set -x

# save old -e status
if [[ $- = *e* ]]; then
    olde=-e
else
    olde=+e
fi

set -e

DEFAULT_BOSCO_KEY=/etc/osg/bosco.key
BOSCOKEYS_DIR=/etc/osg/boscokeys
ENDPOINT_CONFIG=/etc/endpoints.ini
SKIP_WN_INSTALL=no

function errexit {
    echo "$1" >&2
    exit 1
}


function debug_file_contents {
    filename=$1
    echo "Contents of $filename"
    echo "===================="
    cat "$filename"
    echo "===================="
}

function fetch_remote_os_info {
    ruser=$1
    rhost=$2
    ssh -q -i "$(get_bosco_key "$ruser")" "$ruser@$rhost" "cat /etc/os-release"
}

function get_bosco_key {
    ruser=$1
    if [[ -f $BOSCOKEYS_DIR/${ruser}.key ]]; then
        echo "$BOSCOKEYS_DIR/${ruser}.key"
    else
        echo "$DEFAULT_BOSCO_KEY"
    fi
}

setup_ssh_config () {
  echo "Setting up SSH for user ${ruser}"
  ssh_dir="/home/${ruser}/.ssh"
  # setup user and SSH dir
  mkdir -p $ssh_dir
  chown "${ruser}": $ssh_dir
  chmod 700 $ssh_dir

  # copy Bosco key
  ssh_key=$ssh_dir/bosco_key.rsa
  cp "$(get_bosco_key "$ruser")" $ssh_key
  chmod 600 $ssh_key
  chown "${ruser}": $ssh_key

  ssh_config=$ssh_dir/config
  cat <<EOF > "$ssh_config"
Host $remote_fqdn
  Port $remote_port
  IdentityFile ${ssh_key}
  IdentitiesOnly yes
EOF
  debug_file_contents "$ssh_config"

  # setup known hosts
  known_hosts=$ssh_dir/known_hosts
  echo "$REMOTE_HOST_KEY" >> "$known_hosts"
  debug_file_contents $known_hosts

  for ssh_file in $ssh_dir/config $ssh_dir/known_hosts; do
      chown "${ruser}": "$ssh_file"
  done

  # debugging
  ls -l "$ssh_dir"
}


# Install the WN client, CAs, and CRLs on the remote host
# Store logs in /var/log/condor-ce/ to simplify serving logs via Kubernetes
setup_endpoints_ini () {
    echo "Setting up endpoint.ini entry for ${ruser}@$remote_fqdn..."
    remote_os_major_ver=$1
    ssh_key=$(get_bosco_key "$ruser")
    # The WN client updater uses "remote_dir" for WN client
    # configuration and remote copy. We need the absolute path
    # specifically for fetch-crl
    remote_home_dir=$(ssh -q -i $ssh_key "${ruser}@$remote_fqdn" pwd)
    osg_ver=3.4
    if [[ $remote_os_major_ver -gt 6 ]]; then
        osg_ver=3.5
    fi
    cat <<EOF >> $ENDPOINT_CONFIG
[Endpoint ${RESOURCE_NAME}-${ruser}]
local_user = ${ruser}
remote_host = $remote_fqdn
remote_user = ${ruser}
remote_dir = $remote_home_dir/bosco-osg-wn-client
ssh_key = $ssh_key
upstream_url = https://repo.opensciencegrid.org/tarball-install/${osg_ver}/osg-wn-client-latest.el${remote_os_major_ver}.x86_64.tar.gz
EOF
}

# $REMOTE_HOST needs to be specified in the environment
remote_fqdn=${REMOTE_HOST%:*}
if [[ $REMOTE_HOST =~ :[0-9]+$ ]]; then
    remote_port=${REMOTE_HOST#*:}
else
    remote_port=22
fi

REMOTE_HOST_KEY=`ssh-keyscan -p "$remote_port" "$remote_fqdn"`
[[ -n $REMOTE_HOST_KEY ]] || errexit "Failed to determine host key for $remote_fqdn:$remote_port"


users=$(get_mapped_users)
[[ -n $users ]] || errexit "Did not find any user mappings"

# Use the first user for things we only need once
firstuser=$(printf "%s\n" "$users" | head -n1)
id -u "$firstuser" &>/dev/null || errexit "Expected user $firstuser doesn't exist"

firstuser_key=$(get_bosco_key "$firstuser")
[[ -f $firstuser_key ]] || errexit "Failed to get SSH key for $firstuser"

# HACK: Copy the Bosco key to the location expected by
# bosco_cluster so it doesn't go and try to generate a new one
root_ssh_dir=/root/.ssh/
mkdir -p $root_ssh_dir
chmod 700 $root_ssh_dir
install -o root -g root -m 0600 "$firstuser_key" $root_ssh_dir/bosco_key.rsa

cat <<EOF > /etc/ssh/ssh_config
Host $remote_fqdn
  Port $remote_port
  ControlMaster auto
  ControlPath /tmp/cm-%i-%r@%h:%p
  ControlPersist  15m
EOF
debug_file_contents /etc/ssh/ssh_config

echo "$REMOTE_HOST_KEY" >> /etc/ssh/ssh_known_hosts
debug_file_contents /etc/ssh/ssh_known_hosts

# Populate the bosco override dir from a Git repo
if [[ -n $BOSCO_GIT_ENDPOINT && -n $BOSCO_DIRECTORY ]]; then
    OVERRIDE_DIR=/etc/condor-ce/bosco_override
    /usr/local/bin/bosco-override-setup.sh "$BOSCO_GIT_ENDPOINT" "$BOSCO_DIRECTORY" /etc/osg/git.key
fi
unset GIT_SSH_COMMAND


# Allow the condor user to run the WN client updater as the local users
CONDOR_SUDO_FILE=/etc/sudoers.d/10-condor-ssh
condor_sudo_users=`tr ' ' ',' <<< $users`
echo "condor ALL = ($condor_sudo_users) NOPASSWD: /usr/bin/update-remote-wn-client" \
      > $CONDOR_SUDO_FILE
chmod 644 $CONDOR_SUDO_FILE

grep -qs '^OSG_GRID="/cvmfs/oasis.opensciencegrid.org/osg-software/osg-wn-client' \
     /var/lib/osg/osg-job-environment*.conf && SKIP_WN_INSTALL=yes

# Enable bosco_cluster debug output
bosco_cluster_opts=(-d )
if [[ -n $OVERRIDE_DIR ]]; then
    if [[ -d $OVERRIDE_DIR ]]; then
        bosco_cluster_opts+=(-o "$OVERRIDE_DIR")
    else
        echo "WARNING: $OVERRIDE_DIR is not a directory. Skipping Bosco override."
    fi
fi

[[ $REMOTE_BOSCO_DIR ]] && bosco_cluster_opts+=(-b "$REMOTE_BOSCO_DIR") \
        || REMOTE_BOSCO_DIR=bosco

# Add the ability for admins to override the default Bosco tarball URL (SOFTWARE-4537)
[[ $BOSCO_TARBALL_URL ]] && bosco_cluster_opts+=(--url "$BOSCO_TARBALL_URL")

for ruser in $users; do
    setup_ssh_config
done

###################
# REMOTE COMMANDS #
###################

# We have to pick a user for SSH, may as well be the first one
remote_os_info=$(fetch_remote_os_info "$firstuser" "$remote_fqdn")
remote_os_ver=$(echo "$remote_os_info" | awk -F '=' '/^VERSION_ID/ {print $2}' | tr -d '"')

# Skip WN client installation for non-RHEL-based remote clusters
[[ $remote_os_info =~ (^|$'\n')ID_LIKE=.*(rhel|centos|fedora) ]] || SKIP_WN_INSTALL=yes

# HACK: By default, Singularity containers don't specify $HOME and
# bosco_cluster needs it
[[ -n $HOME ]] || HOME=/root

for ruser in $users; do
    echo "Installing remote Bosco installation for ${ruser}@$remote_fqdn"
    [[ $SKIP_WN_INSTALL == 'no' ]] && setup_endpoints_ini "${remote_os_ver%%.*}"
    # $REMOTE_BATCH needs to be specified in the environment
    sudo -u $ruser bosco_cluster "${bosco_cluster_opts[@]}" -a "${ruser}@$remote_fqdn" "$REMOTE_BATCH"

    echo "Installing environment files for $ruser@$remote_fqdn..."
    # Copy over environment files to allow for dynamic WN variables (SOFTWARE-4117)
    rsync -av /var/lib/osg/osg-*job-environment.conf \
          "${ruser}@$remote_fqdn:$REMOTE_BOSCO_DIR/glite/etc"
done

if [[ $SKIP_WN_INSTALL == 'no' ]]; then
    echo "Installing remote WN client tarballs..."
    sudo -u condor update-all-remote-wn-clients --log-dir /var/log/condor-ce/
else
    echo "SKIP_WNCLIENT = True" > /etc/condor-ce/config.d/50-skip-wnclient-cron.conf
    echo "Skipping remote WN client tarball installation, using CVMFS..."
fi

set $olde
