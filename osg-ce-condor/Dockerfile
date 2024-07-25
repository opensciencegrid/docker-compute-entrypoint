FROM base:latest
ARG BASE_YUM_REPO=release
LABEL maintainer "OSG Software <help@osg-htc.org>"
LABEL name "osg-ce-condor"

RUN if [[ $BASE_YUM_REPO == 'release' ]]; then \
        yum install -y --enablerepo=osg-upcoming-testing osg-ce-condor; \
    else \
        yum install -y osg-ce-condor; \
    fi && \
    yum clean all && \
    rm -rf /var/cache/yum/

COPY etc/osg/image-config.d/* /etc/osg/image-config.d/
COPY etc/condor/config.d/* /etc/condor/config.d/
COPY usr/local/bin/* /usr/local/bin/
COPY etc/supervisord.d/* /etc/supervisord.d/
