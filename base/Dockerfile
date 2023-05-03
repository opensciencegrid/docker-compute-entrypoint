########
# base #
########

# Specify the opensciencegrid/software-base image tag
ARG BASE_YUM_REPO=release
ARG BASE_OSG_SERIES=3.6

FROM opensciencegrid/software-base:$BASE_OSG_SERIES-el7-$BASE_YUM_REPO
LABEL maintainer "OSG Software <help@opensciencegrid.org>"

# previous args have gone out of scope
ARG BASE_YUM_REPO=release
ARG BASE_OSG_SERIES=3.6

# Ensure that the 'condor' UID/GID matches across containers
RUN groupadd -g 64 -r condor && \
    useradd -r -g condor -d /var/lib/condor -s /sbin/nologin \
      -u 64 -c "Owner of HTCondor Daemons" condor

# FIXME: backversion HTCondor in release images to avoid SetEffectiveOwner bug
# (10.4.2 in dev/testing ostensibly fixes this issue)
RUN if [[ $BASE_YUM_REPO == 'release' ]]; then \
        yum install -y --enablerepo=osg-upcoming condor-9.12.0; \
    fi && \
    yum install -y osg-ce \
                   # FIXME: avoid htcondor-ce-collector conflict
                   htcondor-ce \
                   git \
                   openssh-clients \
                   sudo \
                   wget \
                   certbot \
                   perl-LWP-Protocol-https \
                   # ^^^ for fetch-crl, in the rare case that the CA forces HTTPS
                   patch && \
    yum clean all && \
    rm -rf /var/cache/yum/

COPY etc/osg/image-config.d/* /etc/osg/image-config.d/
COPY etc/condor-ce/config.d/* /usr/share/condor-ce/config.d/
COPY usr/local/bin/* /usr/local/bin/
COPY etc/supervisord.d/* /etc/supervisord.d/

# do the bad thing of overwriting the existing cron job for fetch-crl
COPY etc/cron.d/fetch-crl /etc/cron.d/fetch-crl
RUN chmod 644 /etc/cron.d/fetch-crl
