FROM almalinux:9

RUN yum install -y openssh-server python3-pyyaml && \
    yum clean all && \
    rm -rf /var/cache/yum/ && \
    adduser sshd-user

COPY init.sh configure_authorized_keys.py /usr/local/sbin/

CMD [ "/usr/local/sbin/init.sh" ]
