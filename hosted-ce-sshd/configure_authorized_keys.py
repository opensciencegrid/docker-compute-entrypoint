#!/usr/bin/env python3
'''
Util script to copy the public key given in a yaml ConfigMap into the
authorized_hosts file for the sshd daemon user. Assumes config in the
form of

public_keys:
  key_name_1: pubkey_1
  key_name_1: pubkey_2
'''
import yaml
from pathlib import Path
from os import environ
from sys import exit, argv

CONFIG_PATH = Path(argv[1])  # eg. /etc/ssh.orig/key-mappings.yaml
AUTHORIZED_KEYS_PATH = Path(argv[2]) # eg. /home/sshd-user/.ssh/authorized_keys
INSTANCE = environ['CE_INSTANCE']
AUTHORIZED_KEY = environ['AUTHORIZED_KEY']

with open(CONFIG_PATH) as f:
    config = yaml.load(f.read(), Loader=yaml.Loader)

AUTHORIZED_KEYS_PATH.parent.mkdir(parents=True, exist_ok=True)
pubkeys: dict[str, str] = config['public_keys']
pubkey = pubkeys.get(AUTHORIZED_KEY)

if not pubkey:
    print(f"Fatal: No public key found for key {AUTHORIZED_KEY}")
    exit(1)

with open(AUTHORIZED_KEYS_PATH, 'w') as keyf:
    keyf.write(pubkey)
