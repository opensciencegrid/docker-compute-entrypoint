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
   # Separate CE View installation to work around Yum depsolving fail
   yum install -y --enablerepo=osg-minefield \
                   htcondor-ce-view && \
    yum clean all && \
    rm -rf /var/cache/yum/

COPY 25-hosted-ce-setup.sh /etc/osg/image-config.d/
COPY 50-nonroot-gratia-setup.sh /etc/osg/image-config.d/

COPY 99-container.conf /usr/share/condor-ce/config.d/

# do the bad thing of overwriting the existing cron job for fetch-crl
ADD fetch-crl /etc/cron.d/fetch-crl
RUN chmod 644 /etc/cron.d/fetch-crl

# HACK: override condor_ce_jobmetrics from SOFTWARE-4183 until it is released in
# HTCondor-CE.
ADD overrides/condor_ce_jobmetrics /usr/share/condor-ce/condor_ce_jobmetrics

# Include script to drain the CE and upload accounting data to prepare for container teardown
COPY drain-ce.sh /usr/local/bin/

COPY configure-nonroot-gratia.py /usr/local/bin/

# Manage HTCondor-CE with supervisor
COPY 10-htcondor-ce.conf /etc/supervisord.d/

ENTRYPOINT ["/usr/local/sbin/supervisord_startup.sh"]
