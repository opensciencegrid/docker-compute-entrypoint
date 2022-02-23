#!/bin/bash

# OSG 3.6 uses non-root SchedD cron based gratia probes
pkg-cmp-gt osg-release 3.6 && exit 0

/usr/local/bin/configure-nonroot-gratia.py /etc/gratia/htcondor-ce/ProbeConfig

# fixups for OSG 3.5 gratia-probe; will not be needed in OSG 3.6
mkdir -p /var/lib/condor-ce/gratia/{data,tmp}
mkdir -p /var/log/condor-ce/gratia
chown -R condor:condor /var/{lib,log}/condor-ce/gratia

# if this file exists, it contains the wrong value for PER_JOB_HISTORY_DIR
rm -f /etc/condor-ce/config.d/99_gratia.conf

