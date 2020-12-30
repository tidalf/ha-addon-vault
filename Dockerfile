ARG VERSION=1.15.3
ARG VAULT_VERSION=1.6.1
ARG TERRAFORM_VERSION=0.14.3
ARG BUILD_FROM
FROM ${BUILD_FROM}

###
# Create a vault user and group first so the IDs get set the same way,
# even as the rest of this may change over time.
RUN addgroup vault && \
    adduser -S -G vault vault

###
# Set up certificates, our base tools, and Vault.
# from https://github.com/hashicorp/docker-vault/blob/master/0.X/Dockerfile
RUN set -eux; \
    export VAULT_VERSION=1.6.1; \
    export TERRAFORM_VERSION=0.14.3; \
    apk add --no-cache ca-certificates gnupg openssl libcap su-exec dumb-init tzdata && \
    apkArch="$(apk --print-arch)"; \
    case "$apkArch" in \
        armhf) ARCH='arm' ;; \
        aarch64) ARCH='arm64' ;; \
        x86_64) ARCH='amd64' ;; \
        x86) ARCH='386' ;; \
        *) echo >&2 "error: unsupported architecture: $apkArch"; exit 1 ;; \
    esac && \
    VAULT_GPGKEY=91A6E7F85D05C65630BEF18951852D87348FFC4C; \
    found=''; \
    for server in \
        hkp://p80.pool.sks-keyservers.net:80 \
        hkp://keyserver.ubuntu.com:80 \
        hkp://pgp.mit.edu:80 \
    ; do \
        echo "Fetching GPG key $VAULT_GPGKEY from $server"; \
        gpg --batch --keyserver "$server" --recv-keys "$VAULT_GPGKEY" && found=yes && break; \
    done; \
    test -z "$found" && echo >&2 "error: failed to fetch GPG key $VAULT_GPGKEY" && exit 1; \
    mkdir -p /tmp/build && \
    cd /tmp/build && \
    wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${ARCH}.zip && \
    wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS && \
    wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS.sig && \
    gpg --batch --verify vault_${VAULT_VERSION}_SHA256SUMS.sig vault_${VAULT_VERSION}_SHA256SUMS && \
    grep vault_${VAULT_VERSION}_linux_${ARCH}.zip vault_${VAULT_VERSION}_SHA256SUMS | sha256sum -c && \
    unzip -d /bin vault_${VAULT_VERSION}_linux_${ARCH}.zip && \
    wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip && \
    wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS && \
    wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS.sig && \
    gpg --batch --verify terraform_${TERRAFORM_VERSION}_SHA256SUMS.sig terraform_${TERRAFORM_VERSION}_SHA256SUMS && \
    grep terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip terraform_${TERRAFORM_VERSION}_SHA256SUMS | sha256sum -c && \
    unzip -d /bin terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip && \
    cd /tmp && \
    rm -rf /tmp/build && \
    gpgconf --kill dirmngr && \
    gpgconf --kill gpg-agent && \
    apk del gnupg openssl && \
    rm -rf /root/.gnupg

RUN mkdir -p /vault/logs && \
    mkdir -p /vault/file && \
    mkdir -p /vault/config && \
    mkdir -p /vault/raft && \
    chown -R vault:vault /vault

RUN mkdir -p /vault/terraform

COPY /terraform/* /vault/terraform/
###
# 8200/tcp is the primary interface that applications use to interact with
# Vault. 8021 for the cluster
EXPOSE 8200 8201

###
# vault config template
COPY vault.hcl.template  /vault/config/

# Copy root filesystem
COPY rootfs /


LABEL io.hass.version="VERSION" io.hass.type="addon" io.hass.arch="armhf|aarch64|i386|amd64"