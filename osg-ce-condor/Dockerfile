# Specify the opensciencegrid/compute-entrypoint image tag
ARG BASE_YUM_REPO=release

FROM opensciencegrid/compute-entrypoint:$BASE_YUM_REPO

ARG BASE_YUM_REPO=release

LABEL maintainer "OSG Software <help@opensciencegrid.org>"

RUN if [[ $BASE_YUM_REPO = release ]]; then \
       yumrepo=osg-upcoming; else \
       yumrepo=osg-upcoming-$BASE_YUM_REPO; fi && \
     yum install -y --enablerepo=$yumrepo \
                   osg-ce-condor && \
    yum clean all && \
    rm -rf /var/cache/yum/

COPY etc/osg/image-config.d/* /etc/osg/image-config.d/
COPY etc/condor/config.d/* /etc/condor/config.d/
COPY usr/local/bin/* /usr/local/bin/
COPY etc/supervisord.d/* /etc/supervisord.d/
