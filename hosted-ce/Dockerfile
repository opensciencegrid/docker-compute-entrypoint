#############
# hosted-ce #
#############

FROM base:latest
LABEL maintainer "OSG Software <help@opensciencegrid.org>"
LABEL name "hosted-ce"

ARG BASE_YUM_REPO=release

RUN yum install -y osg-ce-bosco && \
    rm -rf /var/cache/yum/

COPY 30-remote-site-setup.sh /etc/osg/image-config.d/

# HACK: override condor_ce_jobmetrics from SOFTWARE-4183 until it is released in
# HTCondor-CE.
COPY overrides/condor_ce_jobmetrics /usr/share/condor-ce/condor_ce_jobmetrics

# Use "ssh -q" in bosco_cluster until the chang has been upstreamed to condor
COPY overrides/ssh_q.patch /tmp

# Enable bosco_cluster xtrace
COPY overrides/bosco_cluster_xtrace.patch /tmp

# SOFTWARE-5613: override package versions of remote WN client scripts
# to allow for a faster dev -> ops turnaround
COPY overrides/update-*-remote-wn-client*-override /usr/bin

# Handle bosco_cluster -> condor_remote_cluster symlink
RUN sed -i 's/bosco_cluster/condor_remote_cluster/g' /tmp/*.patch && \
    patch -d / -p0 < /tmp/ssh_q.patch && \
    patch -d / -p0 < /tmp/bosco_cluster_xtrace.patch


COPY ssh-to-login-node /usr/local/bin
COPY condor_ce_q_project /usr/local/bin
COPY condor_ce_history_project /usr/local/bin

# Set up Bosco override dir from Git repo (SOFTWARE-3903)
# Expects a Git repo with the following directory structure:
#     RESOURCE_NAME_1/
#         bosco_override/
#         ...
#     RESOURCE_NAME_2/
#         bosco_override/
#         ...
#     ...
COPY bosco-override-setup.sh /usr/local/bin
