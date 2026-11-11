#!/bin/bash
PORT=${SSHD_PORT:-22}

# Create a new directory to hold original SSH keys (if it doesn't yet exist)
mkdir -p /etc/ssh.orig/etc/ssh

# Assume SSH host keys have been configured in /etc/ssh.orig but mounted with improper permissions
# Copy the keys and then fix their permissions
cp -p /etc/ssh.orig/ssh_* /etc/ssh/
chmod 400 /etc/ssh/*key*

# Assume an authorized_keys file has been configured in /etc/ssh.orig/authorized_keys
mkdir -p /home/sshd-user/.ssh/
configure_authorized_keys.py /etc/ssh.orig/key-mappings.yaml /home/sshd-user/.ssh/authorized_keys
chown -R sshd-user /home/sshd-user/.ssh
chmod 600 /home/sshd-user/.ssh/authorized_keys

echo "Starting sshd on port $PORT"
# Start sshd
/usr/sbin/sshd -p $PORT -e -D
