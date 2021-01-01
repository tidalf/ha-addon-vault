#!/usr/bin/env bashio
# from https://github.com/hashicorp/docker-vault/blob/master/0.X/docker-entrypoint.sh
set -e

ulimit -c 0

# init vars
CONFIG_PATH=/data/options.json
VAULT_TLS_CERTIFICATE="$(bashio::config 'tls_certificate')"
VAULT_TLS_PRIVKEY="$(bashio::config 'tls_private_key')"
DISABLE_TLS="$(bashio::config 'disable_tls')"
scheme="http://"

VAULT_CONFIG_DIR=/config/vault/config
# create vault data dirs (/data/vault/raft by default)
mkdir -p $VAULT_CONFIG_DIR /config/vault/logs /data/vault/raft /config/vault/raft /config/vault/file 2>/dev/null

# if a cert is available and tls is not disabled we copy the cert (to make it readble by wault) and we use it
if [ -f "$VAULT_TLS_PRIVKEY" ] && [ "$DISABLE_TLS" = false ] ; then
    mkdir -p /ssl/vault 2/>/dev/null
    cp "$VAULT_TLS_PRIVKEY" "$VAULT_TLS_CERTIFICATE" /ssl/vault
    # chown for vault uses
    chown -R vault /ssl/vault
    scheme="https://"
fi
VAULT_API_ADDR="${scheme}$(bashio::config 'vault_api_addr')"
VAULT_CLUSTER_ADDR="$(bashio::config 'vault_cluster_addr')"
export VAULT_API_ADDR VAULT_CLUSTER_ADDR

/usr/bin/tempio -conf $CONFIG_PATH -template /vault/config/vault.hcl.template -out $VAULT_CONFIG_DIR/vault.hcl

# You can also set the VAULT_LOCAL_CONFIG environment variable to pass some
# Vault configuration JSON without having to bind any volumes.
VAULT_LOCAL_CONFIG="$(bashio::config 'vault_local_config')"
if [ -n "$VAULT_LOCAL_CONFIG" ] && [[ "$VAULT_LOCAL_CONFIG" != "null" ]]; then
    echo "$VAULT_LOCAL_CONFIG" > "$VAULT_CONFIG_DIR/local.json"
fi
    
# If the config dir is bind mounted then chown it
if [ "$(stat -c %u /config/vault/config)" != "$(id -u vault)" ]; then
    chown -R vault:vault /config/vault/config
fi
if [ "$(stat -c %u /config/vault/logs)" != "$(id -u vault)" ]; then
    chown -R vault:vault /config/vault/logs
fi
if [ "$(stat -c %u /config/vault/file)" != "$(id -u vault)" ]; then
    chown -R vault:vault /config/vault/file
fi
if [ "$(stat -c %u /data/vault)" != "$(id -u vault)" ]; then
    chown -R vault:vault /data/vault
fi
if [ "$(stat -c %u /config/vault/raft)" != "$(id -u vault)" ]; then
    chown -R vault:vault /config/vault/raft
fi

# Allow mlock to avoid swapping Vault memory to disk
setcap cap_ipc_lock=+ep "$(readlink -f "$(which vault)")"

# In the case vault has been started in a container without IPC_LOCK privileges
if ! vault -version 1>/dev/null 2>/dev/null; then
    setcap cap_ipc_lock=-ep "$(readlink -f "$(which vault)")"
fi

# run as vault
if [ "$(id -u)" = "0" ]; then
    set -- su-exec vault vault server \
        -config="$VAULT_CONFIG_DIR" \
        -dev-listen-address="${VAULT_DEV_LISTEN_ADDRESS:-"0.0.0.0:8200"}" \
        "$@"
fi

exec "$@"
