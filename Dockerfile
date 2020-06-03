FROM opensciencegrid/software-base:fresh
LABEL maintainer "OSG Software <help@opensciencegrid.org>"

RUN yum install -y --enablerepo=osg-minefield \
                   --enablerepo=osg-upcoming-minefield \
                   osg-ce-bosco \
                   git \
                   openssh-clients \
                   sudo \
                   wget \
                   certbot \
                   patch && \
    yum clean all && \
    rm -rf /var/cache/yum/

COPY 25-hosted-ce-setup.sh /etc/osg/image-config.d/
COPY 30-remote-site-setup.sh /etc/osg/image-config.d/
COPY 50-nonroot-gratia-setup.sh /etc/osg/image-config.d/

COPY 99-container.conf /usr/share/condor-ce/config.d/

# do the bad thing of overwriting the existing cron job for fetch-crl
ADD fetch-crl /etc/cron.d/fetch-crl
RUN chmod 644 /etc/cron.d/fetch-crl

# HACK: override bosco_cluster so that it doesn't copy over the SSH
# pub key to the remote side. We set this up with the site out of band.
ADD bosco_cluster /usr/bin/bosco_cluster

# Include script to drain the CE and upload accounting data to prepare for container teardown
COPY drain-ce.sh /usr/local/bin/

COPY configure-nonroot-gratia.py /usr/local/bin/
COPY remote-wn-client-wrapper.sh /usr/local/bin/

# Use "ssh -q" in bosco_cluster and update-remote-wn-client until the changes have been
# upstreamed to condor and hosted-ce-tools packaging, respectively
COPY ssh_q.patch /tmp
RUN patch -d / -p0 < /tmp/ssh_q.patch

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

# Manage HTCondor-CE with supervisor
COPY 10-htcondor-ce.conf /etc/supervisord.d/

ENTRYPOINT ["/usr/local/sbin/supervisord_startup.sh"]
