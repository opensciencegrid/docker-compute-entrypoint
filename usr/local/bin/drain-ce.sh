#!/bin/sh
# Script to drain the CE and upload accounting data to prepare for container teardown

# Configure to refuse all incoming jobs
echo "SUBMIT_REQUIREMENT_DRAIN = False" > /usr/share/condor-ce/config.d/99-drain.conf
echo "SUBMIT_REQUIREMENT_NAMES = DRAIN" >> /usr/share/condor-ce/config.d/99-drain.conf

# Apply configuration
condor_ce_reconfig

# Remove all existing jobs
condor_ce_rm -all

# Upload accounting data
/usr/share/gratia/htcondor-ce/condor_meter -f /etc/gratia/htcondor-ce/ProbeConfig
