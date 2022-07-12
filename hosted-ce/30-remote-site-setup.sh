#!/bin/bash

set -x

# save old -e status
if [[ $- = *e* ]]; then
    olde=-e
else
    olde=+e
fi

source /etc/osg/image-init.d/ce-common-startup

[[ ${HOSTED_CE_CONTINUE_ON_ERROR:=false} == 'true' ]] || set -e

BOSCO_KEY=/etc/osg/bosco.key
# Optional SSH certificate
BOSCO_CERT=${BOSCO_KEY}-cert.pub
ENDPOINT_CONFIG=/etc/endpoints.ini
KNOWN_HOSTS=/etc/osg/ssh_known_hosts
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
    ssh -q "$ruser@$rhost" "cat /etc/os-release"
}

setup_ssh_config () {
  extra_config="$1"
  echo "Setting up SSH for user ${ruser}"
  ssh_dir=$(eval echo "~${ruser}/.ssh")
  # setup user and SSH dir
  mkdir -p $ssh_dir
  chown "${ruser}": $ssh_dir
  chmod 700 $ssh_dir

  # copy Bosco key
  ssh_key=$ssh_dir/id_rsa
  cp $BOSCO_KEY $ssh_key
  chmod 600 $ssh_key
  chown "${ruser}": $ssh_key
  # HACK: Symlink the Bosco key to the location expected by
  # bosco_cluster so it doesn't go and try to generate a new one
  ln -s $ssh_key $ssh_dir/bosco_key.rsa

  # copy Bosco certificate
  if [[ -f $BOSCO_CERT ]]; then
      ssh_cert=${ssh_key}-cert.pub
      cp $BOSCO_CERT $ssh_cert
      chmod 600 $ssh_cert
      chown "${ruser}": $ssh_cert
  fi

  ssh_config=$ssh_dir/config
  cat <<EOF > "$ssh_config"
Host $remote_fqdn
  Port $remote_port
  IdentityFile ${ssh_key}
  IdentitiesOnly yes
  ${extra_config}
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
    # The WN client updater uses "remote_dir" for WN client
    # configuration and remote copy. We need the absolute path
    # specifically for fetch-crl
    remote_home_dir=$(ssh -q "${ruser}@$remote_fqdn" pwd)
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

if [[ -f $KNOWN_HOSTS ]]; then
    REMOTE_HOST_KEY=$(cat $KNOWN_HOSTS)
else
    REMOTE_HOST_KEY=`ssh-keyscan -p "$remote_port" "$remote_fqdn"`
fi
[[ -n $REMOTE_HOST_KEY ]] || errexit "Failed to determine host key for $remote_fqdn:$remote_port"

extra_user_ssh_config=""
extra_root_ssh_config="ControlMaster auto
  ControlPath /tmp/cm-%i-%r@%h:%p
  ControlPersist  15m
"

if [[ -n $SSH_PROXY_JUMP ]]; then
    proxyjump_config="ProxyJump $SSH_PROXY_JUMP"
    extra_root_ssh_config+="  $proxyjump_config"
    extra_user_ssh_config+=$proxyjump_config
fi

ruser=root
setup_ssh_config "$extra_root_ssh_config"

# Populate the bosco override dir from a Git repo
if [[ -n $BOSCO_GIT_ENDPOINT && -n $BOSCO_DIRECTORY ]]; then
    OVERRIDE_DIR=/etc/condor-ce/bosco_override
    /usr/local/bin/bosco-override-setup.sh "$BOSCO_GIT_ENDPOINT" "$BOSCO_DIRECTORY" /etc/osg/git.key
fi
unset GIT_SSH_COMMAND

users=$(get_mapped_users)
[[ -n $users ]] || errexit "Did not find any HTCondor-CE SCITOKENS user mappings"

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
# Remote site admins set up SSH key access out-of-band
bosco_cluster_opts+=(--copy-ssh-key no)

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
    setup_ssh_config "$extra_user_ssh_config"
done

###################
# REMOTE COMMANDS #
###################

test_remote_connect () {
    ssh "$1@$2" true
}

test_remote_forward_once () {
    # pick a random unprivileged port for remote side; test that a remote
    # port forward back to the local side works.  For the purpose of this
    # test, it doesn't actually matter whether sshd is running locally on
    # port 22, since we are not testing a reverse ssh connection--just the
    # port forward itself.
    local port=$(( RANDOM % 60000 + 1024 ))
    ssh "$1@$2" -o ExitOnForwardFailure=yes -R $port:localhost:22 true
}

test_remote_forward () {
    # try remote forward with a random port a few times ... we might get
    # unlucky and hit a remote port that is in use (being listened on),
    # but we'd have to be extremely unlucky for this to happen thrice
    retries=0
    until test_remote_forward_once "$1" "$2"; do
        (( ++retries < 3 )) || return 1
    done
}

# We have to pick a user for SSH, may as well be the first one
first_user=$(printf "%s\n" $users | head -n1)

test_remote_connect "$first_user" "$remote_fqdn" ||
    errexit "remote ssh connection to $remote_fqdn:$remote_port failed"

test_remote_forward "$first_user" "$remote_fqdn" ||
    errexit "remote ssh forward from $remote_fqdn failed"

remote_os_info=$(fetch_remote_os_info "$first_user" "$remote_fqdn")
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
    bosco_cluster "${bosco_cluster_opts[@]}" -a "${ruser}@$remote_fqdn" "$REMOTE_BATCH"

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
