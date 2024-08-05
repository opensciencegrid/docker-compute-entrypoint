#!/bin/bash

source /etc/osg/image-init.d/ce-common-startup

set -x

[[ ${HOSTED_CE_CONTINUE_ON_ERROR:=false} == 'true' ]] || set -e

# Ensure that PVC dirs and subdirs exist and have the proper
# ownership (SOFTWARE-4423)
user_log_dir=/var/log/condor-ce/user
pvc_dirs=(/etc/condor-ce/passwords.d
          /var/log/condor-ce/gratia
           $user_log_dir
          /var/lib/condor-ce/execute
          /var/lib/condor-ce/gratia/data/
          /var/lib/condor-ce/gratia/tmp/
          /var/lib/condor-ce/spool/ceview/metrics
          /var/lib/condor-ce/spool/ceview/vos)
mkdir -p ${pvc_dirs[*]}

pvc_dirs+=(/var/log/condor-ce
           /var/lib/condor-ce
           /var/lib/condor-ce/spool
           /var/lib/condor-ce/spool/ceview)
chown condor:condor ${pvc_dirs[*]}
chmod 1777 $user_log_dir

ce_idtoken_dir=/usr/share/condor-ce/glidein-tokens
users=$(get_mapped_users)
for user in $users; do
    echo "Creating local user ($user)..."
    adduser --base-dir /home/ "$user"
    # Create the per-user dir for CE-generated IDTOKENs (SOFTWARE-5556)
    user_idtoken_dir=$ce_idtoken_dir/$user
    mkdir -p "$user_idtoken_dir"
    chmod 700 "$user_idtoken_dir"
    chown "$user": "$user_idtoken_dir"
done

#kubernetes configmaps arent writeable
if stat /tmp/90-local.ini; then
  cp /tmp/90-local.ini /etc/osg/config.d/90-local.ini
  echo "Trying to populate hostname in 90-local.ini with a better value..."
  pushd /etc/osg/config.d
    if [[ -z "$_CONDOR_NETWORK_HOSTNAME" ]]; then
      echo '$_CONDOR_NETWORK_HOSTNAME is empty, just using `hostname`'
      sed -i "s/localhost/$(hostname)/" 90-local.ini
    else
      echo '$_CONDOR_NETWORK_HOSTNAME is nonempty, substituting it in...'
      sed -i "s/localhost/$_CONDOR_NETWORK_HOSTNAME/" 90-local.ini
    fi
  popd
fi

echo "Running OSG configure.."
# Run the OSG Configure script to set up bosco
osg-configure -c --verbose VERBOSE

# Cert stuff
if [ "${DEVELOPER,,}" == 'true' ]; then
    echo "Establishing OSG Test certificate..."
    # don't do this in the image to make it smaller for prod use
    git clone https://github.com/opensciencegrid/osg-ca-generator.git
    pushd osg-ca-generator
    make install
    osg-ca-generator --host
    popd
fi


# For host certs, we want to support the following use cases:
# 1. Support mounting of a cert/key pair to /etc/grid-security-orig.d/.
#    Useful for Kubernetes setups so that secret updates can be
#    propagated to the container without a restart
# 2. Support direct mounts of /etc/grid-security/host{cert,key}.pem
# 3. Requesting LE certs if no host cert/key pair is mounted using the above
hostcert_path=/etc/grid-security/hostcert.pem
hostkey_path=/etc/grid-security/hostkey.pem
hostcsr_path=/etc/grid-security/host.req
orig_hostcert_path=/etc/grid-security-orig.d/hostcert.pem
orig_hostkey_path=/etc/grid-security-orig.d/hostkey.pem

certbot_opts="--noninteractive --agree-tos --standalone --email $CE_CONTACT -d $CE_HOSTNAME"

[[ $LE_STAGING == "true" ]] && certbot_opts="$certbot_opts --test-cert"

if [ ! -f $hostcert_path ] || [ ! -f $hostkey_path ]; then
    if [[ -f $orig_hostcert_path && -f $orig_hostkey_path ]]; then
        echo "Using host cert/key mounted in /etc/grid-security-orig.d/"
        ln -s $orig_hostcert_path $hostcert_path
        ln -s $orig_hostkey_path $hostkey_path
    else
        echo "Establishing Let's Encrypt certificate..."
        if [ -f $hostkey_path ]; then
            openssl req -new -nodes -out $hostcsr_path -key $hostkey_path -subj "/CN=$CE_HOSTNAME"
            certbot_opts="$certbot_opts --csr $hostcsr_path --cert-path $hostcert_path"
        fi
        # this needs to be automated for renewal
        certbot certonly $certbot_opts
        [ -f $hostcert_path ] || ln -s /etc/letsencrypt/live/$CE_HOSTNAME/cert.pem $hostcert_path
        [ -f $hostkey_path ] ||  ln -s /etc/letsencrypt/live/$CE_HOSTNAME/privkey.pem $hostkey_path
    fi
fi

echo ">>>>> YOUR CERTIFICATE INFORMATION IS:"
openssl x509 -in $hostcert_path -text
echo "><><><><><><><><><><><><><><><><><><><"

[[ ${HOSTED_CE_CONTINUE_ON_ERROR} == 'true' ]] || set +e

set +x
