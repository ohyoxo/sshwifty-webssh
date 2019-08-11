# Build the build base environment
FROM debian:sid as base
COPY . /tmp/.build/sshwifty
RUN set -ex && \
    cd / && \
    ls -l /tmp/.build/sshwifty && \
    echo 'res=0; for i in $(seq 0 36); do $@; res=$?; [ $res -eq 0 ] && exit $res || sleep 10; done; exit $res' > /try.sh && chmod +x /try.sh && \
    echo 'cpid=""; ret=0; i=0; for c in "$@"; do ( (((((eval $c; echo $? >&3) | sed "s/^/|-($i) /" >&4) 2>&1 | sed "s/^/|-($i)!/" >&2) 3>&1) | (read xs; exit $xs)) 4>&1) & ppid=$!; cpid="$cpid $ppid"; echo "+ Child $i (PID $ppid): $c ..."; i=$((i+1)); done; for c in $cpid; do wait $c; cret=$?; [ $cret -eq 0 ] && continue; echo "* Child PID $c has failed." >&2; ret=$cret; done; exit $ret' > /child.sh && chmod +x /child.sh && \
    export PATH=$PATH:/ && \
    echo 'apt-get update && apt-get install npm golang-go git -y' > /install.sh && chmod +x /install.sh && \
    ([ -z "$HTTP_PROXY" ] || (echo "Acquire::http::Proxy \"$HTTP_PROXY\";" >> /etc/apt/apt.conf)) && \
    ([ -z "$HTTPS_PROXY" ] || (echo "Acquire::https::Proxy \"$HTTPS_PROXY\";" >> /etc/apt/apt.conf)) && \
    try.sh install.sh && rm /install.sh

# Build the base environment for application libraries
FROM base as libbase
RUN set -ex && \
    cd / && \
    export PATH=$PATH:/ && \
    ([ -z "$HTTP_PROXY" ] || (git config --global http.proxy "$HTTP_PROXY" && npm config set proxy "$HTTP_PROXY")) && \
    ([ -z "$HTTPS_PROXY" ] || (git config --global https.proxy "$HTTPS_PROXY" && npm config set https-proxy "$HTTPS_PROXY")) && \
    child.sh \
        'cd /tmp/.build/sshwifty && try.sh npm install' \
        'cd /tmp/.build/sshwifty && try.sh go mod download'

# Main building environment
FROM libbase as builder
RUN set -ex && \
    cd / && \
    export PATH=$PATH:/ && \
    ([ -z "$HTTP_PROXY" ] || (git config --global http.proxy "$HTTP_PROXY" && npm config set proxy "$HTTP_PROXY")) && \
    ([ -z "$HTTPS_PROXY" ] || (git config --global https.proxy "$HTTPS_PROXY" && npm config set https-proxy "$HTTPS_PROXY")) && \
    (cd /tmp/.build/sshwifty && try.sh npm run build && mv ./sshwifty /)

# Build the final image for running
FROM alpine:latest
ENV SSHWIFTY_HOSTNAME= \
    SSHWIFTY_SHAREDKEY= \
    SSHWIFTY_SOCKS5= \
    SSHWIFTY_SOCKS5_USER= \
    SSHWIFTY_SOCKS5_PASSWORD= \
    SSHWIFTY_LISTENINTERFACE=0.0.0.0 \
    SSHWIFTY_LISTENPORT=8182 \
    SSHWIFTY_INITIALTIMEOUT=0 \
    SSHWIFTY_READTIMEOUT=0 \
    SSHWIFTY_WRITETIMEOUT=0 \
    SSHWIFTY_HEARTBEATTIMEOUT=0 \
    SSHWIFTY_READDELAY=0 \
    SSHWIFTY_WRITEELAY=0 \
    SSHWIFTY_TLSCERTIFICATEFILE= \
    SSHWIFTY_TLSCERTIFICATEKEYFILE= \
    SSHWIFTY_DOCKER_TLSCERT= \
    SSHWIFTY_DOCKER_TLSCERTKEY=
COPY --from=builder /sshwifty /
RUN set -ex && \
    adduser -D sshwifty && \
    chmod +x /sshwifty && \
    echo '#!/bin/sh' > /sshwifty.sh && echo >> /sshwifty.sh && echo '([ -z "$SSHWIFTY_DOCKER_TLSCERT" ] || echo "$SSHWIFTY_DOCKER_TLSCERT" > /cert); ([ -z "$SSHWIFTY_DOCKER_TLSCERTKEY" ] || echo "$SSHWIFTY_DOCKER_TLSCERTKEY" > /certkey); if [ -f "/cert" ] && [ -f "/certkey" ]; then SSHWIFTY_TLSCERTIFICATEFILE=/cert SSHWIFTY_TLSCERTIFICATEKEYFILE=/certkey /sshwifty; else /sshwifty; fi;' >> /sshwifty.sh && chmod +x /sshwifty.sh
USER sshwifty
EXPOSE 8182
ENTRYPOINT [ "/sshwifty.sh" ]
CMD []