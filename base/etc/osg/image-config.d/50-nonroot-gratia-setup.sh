#!/bin/bash

/usr/local/bin/configure-nonroot-gratia.py /etc/gratia/htcondor-ce/ProbeConfig

# fixups for OSG 3.5 gratia-probe; not needed in OSG 3.6
mkdir -p /var/lib/condor-ce/gratia/data
chown condor:condor /var/lib/condor-ce/gratia/data
chmod 1777 /var/lib/condor-ce/gratia/data

# if this file exists, it contains the wrong value for PER_JOB_HISTORY_DIR
rm -f /etc/condor-ce/config.d/99_gratia.conf

