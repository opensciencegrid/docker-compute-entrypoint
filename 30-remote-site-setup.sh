#!/bin/bash -x

BOSCO_KEY=/etc/osg/bosco.key
# $REMOTE_HOST needs to be specified in the environment
REMOTE_HOST_KEY=`ssh-keyscan -H "$REMOTE_HOST"`
ENDPOINT_CONFIG=/etc/endpoints.ini

setup_ssh_config () {
  echo "Adding user ${ruser}"
  ssh_dir="/home/${ruser}/.ssh"
  # setup user and SSH dir
  adduser --base-dir /home/ "${ruser}"
  mkdir -p $ssh_dir
  chown "${ruser}": $ssh_dir
  chmod 700 $ssh_dir

  # copy Bosco key
  ssh_key=$ssh_dir/bosco.key
  cp $BOSCO_KEY $ssh_key
  chmod 600 $ssh_key
  chown "${ruser}": $ssh_key
  cat <<EOF > $ssh_dir/config
IdentitiesOnly yes
IdentityFile ${ssh_key}
EOF

  # setup known hosts
  echo $REMOTE_HOST_KEY >> $ssh_dir/known_hosts

  for ssh_file in $ssh_dir/config $ssh_dir/known_hosts; do
      chown "${ruser}": $ssh_file
  done

  # debugging
  ls -l "$ssh_dir"
}

# Install the WN client, CAs, and CRLs on the remote host
# Store logs in /var/log/condor-ce/ to simplify serving logs via Kubernetes
setup_endpoints_ini () {
    remote_home_dir=$(ssh -q -i $BOSCO_KEY "${ruser}@$REMOTE_HOST" pwd)
    remote_os_ver=$(ssh -q -i $BOSCO_KEY "${ruser}@$REMOTE_HOST" "rpm -E %rhel")
    osg_ver=3.4
    if [[ $remote_os_ver -gt 6 ]]; then
        osg_ver=3.5
    fi
    cat <<EOF >> $ENDPOINT_CONFIG
[Endpoint ${RESOURCE_NAME}-${ruser}]
local_user = ${ruser}
remote_host = $REMOTE_HOST
remote_user = ${ruser}
remote_dir = $remote_home_dir/bosco-osg-wn-client
upstream_url = https://repo.opensciencegrid.org/tarball-install/${osg_ver}/osg-wn-client-latest.el${remote_os_ver}.x86_64.tar.gz
EOF
}

# Set the appropriate SSH key for bosco_cluster commands
root_ssh_dir=/root/.ssh/
mkdir -p $root_ssh_dir
chmod 700 $root_ssh_dir
echo "IdentityFile ${BOSCO_KEY}" > $root_ssh_dir/config
echo $REMOTE_HOST_KEY >> $root_ssh_dir/known_hosts

# Populate the bosco override dir from a Git repo
if [[ -n $BOSCO_GIT_ENDPOINT && -n $BOSCO_DIRECTORY ]]; then
    OVERRIDE_DIR=/etc/condor-ce/bosco_override
    /usr/local/bin/bosco-override-setup.sh "$BOSCO_GIT_ENDPOINT" "$BOSCO_DIRECTORY" /etc/osg/git.key
fi
unset GIT_SSH_COMMAND

users=$(cat /etc/grid-security/grid-mapfile /etc/grid-security/voms-mapfile | \
            awk '/^"[^"]+" +[a-zA-Z0-9\-\._]+$/ {print $NF}' | \
            sort -u)
[[ -n $users ]] || exit 1

# Allow the condor user to run the WN client updater as the local users
CONDOR_SUDO_FILE=/etc/sudoers.d/10-condor-ssh
condor_sudo_users=`tr ' ' ',' <<< $users`
echo "condor ALL = ($condor_sudo_users) NOPASSWD: /usr/bin/update-remote-wn-client" \
      > $CONDOR_SUDO_FILE
chmod 644 $CONDOR_SUDO_FILE

grep '^OSG_GRID="/cvmfs/oasis.opensciencegrid.org/osg-software/osg-wn-client' \
     /var/lib/osg/job-environment*.conf > /dev/null 2>&1
cvmfs_wn_client=$?

override_opts=()
if [[ -n $OVERRIDE_DIR ]]; then
    if [[ -d $OVERRIDE_DIR ]]; then
        override_opts=(-o "$OVERRIDE_DIR")
    else
        echo "WARNING: $OVERRIDE_DIR is not a directory. Skipping Bosco override."
    fi
fi

echo "Using Bosco tarball: $(bosco_findplatform --url)"
for ruser in $users; do
    setup_ssh_config
    [[ $cvmfs_wn_client -eq 0 ]] || setup_endpoints_ini
    # $REMOTE_BATCH needs to be specified in the environment
    bosco_cluster "${override_opts[@]}" -a "${ruser}@$REMOTE_HOST" "$REMOTE_BATCH"
done

[[ $cvmfs_wn_client -eq 0 ]] || sudo -u condor update-all-remote-wn-clients --log-dir /var/log/condor-ce/
