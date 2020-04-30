#!/bin/bash

# Populate the bosco override dir from a Git repo
# Expected Git repo layout:
#     RESOURCE_NAME_1/
#         bosco_override/
#         ...
#     RESOURCE_NAME_2/
#         bosco_override/
#         ...
#     ...

function errexit {
    echo "$1" >&2
    exit 1
}

[[ $# -eq 2 ]] || errexit "Usage: bosco-override-setup.sh <GIT ENDPOINT> <RESOURCE NAME>"

GIT_ENDPOINT=$1
RESOURCE_NAME=$2

# pre-scan the Git repo's host key
if [[ $GIT_ENDPOINT =~ ^[A-Za-z0-9_-]+@([^:]+): ]]; then
    ssh-keyscan "${BASH_REMATCH[1]}" >> ~/.ssh/known_hosts
fi

REPO_DIR=$(mktemp -d)
OVERRIDE_DIR=/etc/condor-ce/bosco_override/

git clone --depth=1 $GIT_ENDPOINT $REPO_DIR

# Bosco override dirs are expected in the following location in the git repo:
#   <RESOURCE NAME>/bosco_override/
RESOURCE_DIR="$REPO_DIR/$RESOURCE_NAME/"
[[ -d $RESOURCE_DIR ]] || errexit "Could not find $RESOURCE_NAME/ under $GIT_ENDPOINT"
rsync -az "$RESOURCE_DIR/bosco_override/"  $OVERRIDE_DIR
