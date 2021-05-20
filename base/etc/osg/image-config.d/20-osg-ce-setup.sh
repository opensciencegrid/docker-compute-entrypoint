#!/bin/bash

. /etc/osg/image-config.d/ce-common-startup

set -xe

users=$(get_mapped_users)
for user in $users; do
    echo "Creating local user ($user)..."
    adduser --base-dir /home/ "$user"
done

#kubernetes configmaps arent writeable
stat /tmp/99-local.ini
if [[ $? -eq 0 ]]; then
  cp /tmp/99-local.ini /etc/osg/config.d/99-local.ini
fi

echo "Trying to populate hostname in 99-local.ini with a better value.."
pushd /etc/osg/config.d
  if [[ -z "$_CONDOR_NETWORK_HOSTNAME" ]]; then
    echo '$_CONDOR_NETWORK_HOSTNAME is empty, just using `hostname`'
    sed -i "s/localhost/$(hostname)/" 99-local.ini
  else
    echo '$_CONDOR_NETWORK_HOSTNAME is nonempty, substituting it in..'
    sed -i "s/localhost/$_CONDOR_NETWORK_HOSTNAME/" 99-local.ini
  fi
popd 

echo "Running OSG configure.."
# Run the OSG Configure script to set up bosco
osg-configure -c --verbose VERBOSE

# Cert stuff
if [ "${DEVELOPER,,}" == 'true' ]; then
    echo "Establishing OSG Test certificate.."
    # don't do this in the image to make it smaller for prod use
    yum install -y --enablerepo=devops-itb osg-ca-generator
    osg-ca-generator --host --vo osgtest
fi

hostcert_path=/etc/grid-security/hostcert.pem
hostkey_path=/etc/grid-security/hostkey.pem
hostcsr_path=/etc/grid-security/host.req

certbot_opts="--noninteractive --agree-tos --standalone --email $CE_CONTACT -d $CE_HOSTNAME"

[[ $LE_STAGING == "true" ]] && certbot_opts="$certbot_opts --dry-run"

if [ ! -f $hostcert_path ] || [ ! -f $hostkey_path ]; then
    echo "Establishing Let's Encrypt certificate.."
    if [ -f $hostkey_path ]; then
        openssl req -new -nodes -out $hostcsr_path -key $hostkey_path -subj "/CN=$CE_HOSTNAME"
        certbot_opts="$certbot_opts --csr $hostcsr_path --cert-path $hostcert_path"
    fi
    # this needs to be automated for renewal
    certbot certonly $certbot_opts
    [ -f $hostcert_path ] || ln -s /etc/letsencrypt/live/$CE_HOSTNAME/cert.pem $hostcert_path
    [ -f $hostkey_path ] ||  ln -s /etc/letsencrypt/live/$CE_HOSTNAME/privkey.pem $hostkey_path
fi

echo ">>>>> YOUR CERTIFICATE INFORMATION IS:"
openssl x509 -in $hostcert_path -text
echo "><><><><><><><><><><><><><><><><><><><"

# Ensure that PVC dirs and subdirs exist and have the proper
# ownership (SOFTWARE-4423)
pvc_dirs=(/var/log/condor-ce/
          /var/lib/condor-ce/execute
          /var/lib/condor-ce/spool/ceview/metrics
          /var/lib/condor-ce/spool/ceview/vos)
mkdir -p ${pvc_dirs[*]}

pvc_dirs+=(/var/lib/condor-ce
           /var/lib/condor-ce/spool
           /var/lib/condor-ce/spool/ceview)
chown condor:condor ${pvc_dirs[*]}

set +xe
