FROM base AS osg-ce-condor
ARG BASE_YUM_REPO=release
LABEL maintainer "OSG Software <help@opensciencegrid.org>"
LABEL name "osg-ce-condor"

RUN yum install -y osg-ce-condor && \
    yum clean all && \
    rm -rf /var/cache/yum/

COPY etc/osg/image-config.d/* /etc/osg/image-config.d/
COPY etc/condor/config.d/* /etc/condor/config.d/
COPY usr/local/bin/* /usr/local/bin/
COPY etc/supervisord.d/* /etc/supervisord.d/
