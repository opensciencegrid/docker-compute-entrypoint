#!/usr/bin/env python2

import sys
import xml.etree.ElementTree as ET


def usage():
    """Print usage to stdout
    """
    print "Usage: configure-nonroot-gratia.py <PATH TO PROBE CONFIG>"


def main():
    """main function
    """
    if len(sys.argv) != 2:
        usage()
        sys.exit(1)

    config_path = sys.argv[1]

    try:
        probe_et = ET.parse(config_path)
    except IOError:
        usage()
        sys.exit(1)

    probe_config = probe_et.getroot()

    probe_config.attrib['Lockfile'] = '/var/lock/condor-ce/gratia.lock'
    probe_config.attrib['WorkingFolder'] = '/var/lib/condor-ce/gratia/tmp/'
    probe_config.attrib['DataFolder'] = '/var/lib/condor-ce/gratia/data/'
    probe_config.attrib['LogFolder'] = '/var/log/condor-ce/'

    with open(config_path, 'w') as config_file:
        probe_et.write(config_file)


if __name__ == "__main__":
    main()
