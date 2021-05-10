#!/bin/bash

/usr/local/bin/configure-nonroot-gratia.py /etc/gratia/htcondor-ce/ProbeConfig

# if this file exists, it contains the wrong value for PER_JOB_HISTORY_DIR
rm -f /etc/condor-ce/config.d/99_gratia.conf

