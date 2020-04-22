#!/bin/bash

grep '^OSG_GRID="/cvmfs/oasis.opensciencegrid.org/osg-software/osg-wn-client' \
     /var/lib/osg/osg-job-environment*.conf || \
  /usr/bin/update-all-remote-wn-clients --log-dir /var/log/condor-ce/
