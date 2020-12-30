#!/usr/bin/env bashio

# init vars
CONFIG_PATH=/data/options.json
DISABLE_TLS="$(bashio::config 'disable_tls')"
UNSAFE_SAVE_INI="$(bashio::config 'unsafe_auto_init')"
AWS_UNSEAL="$(bashio::config 'aws_unseal')"
VAULT_ADMIN_USER="$(bashio::config 'vault_admin_user')"
VAULT_ADMIN_PASSWORD="$(bashio::config 'vault_admin_password')"
CREATE_ADMIN_USER="$(bashio::config 'create_admin_user')"
INI_PATH="/data/vault/vault.ini"
output=""

mkdir -p /config/vault/terraform 2>/dev/null || true

if [ $DISABLE_TLS = 'false' ] ; then 
  scheme="https://"
else
  scheme="http://"
fi
export VAULT_ADDR="${scheme}localhost:8200"

# ready
wait_ready() {
    echo -ne "* Waiting for vault to be ready: "
    while [ ! -n "$(vault status -format json 2>/dev/null)" ]; do 
        sleep 2
        echo -ne .
    done
    echo "ok!"
}

# initialized
wait_initialized() {
    if [ "$(vault status -format json | jq .initialized)" = "false" ] ; then 
    echo "* the vault is not initialized, let's do it"
    output="$(vault operator init -format json)"
    if ! echo "$output" | jq .root_token 2>/dev/null >/dev/null; then 
        echo "* Can't initialized : exiting"
        exit 1
    else
        echo "* vault initialized successfully"
        if [ "$UNSAFE_SAVE_INI" = "true" ] ; then
            echo $output > $INI_PATH
        fi 
    fi
    else 
        echo "* vault already initialized"
        output=$(cat $INI_PATH 2>/dev/null)
        if [ -z "$output" ]; then
            echo "* no ini file : exiting"
            exit 1
        fi
    fi
}

# migrated
wait_migrated() {
    if [ "$(vault status -format json | jq .migration)" = "true" ] ; then
    echo "* migrating"
        for a in $(echo $output | jq -r '.unseal_keys_b64 | .[]') ; do 
        vault operator unseal -migrate $a >/dev/null
        done
        if [ "$(vault status -format json | jq .initialized)" = "false" ] ; then
            echo "* migration failed : exiting"
            exit 1
        else 
            echo "* migration done"
        fi
    fi
}
# unsealed
wait_unsealed() {
    if [ "$(vault status -format json | jq .sealed)" = "true" ] ; then
        echo "* Vault is sealed"
        echo "* unsealing vault"
        for a in $(echo $output | jq -r '.unseal_keys_b64 | .[]') ; do 
        vault operator unseal $a >/dev/null
        done
        if [ "$(vault status -format json | jq .initialized)" = "false" ] ; then
            echo "* unseal failed : exiting"
            exit 1
        else 
            echo "* unseal done"
        fi
    else 
        echo "* Vault already unsealed"
    fi
}


# root token available
wait_root_token () {
    if echo "$output" | jq -r .root_token >/dev/null 2>/dev/null ; then
    echo "* root token available"
    echo "* start provisioning" 
    else
    echo "* root token unavailable, exiting"
    exit 1
    fi
}

terraform_vault () {
    if [ ! -f /config/vault/terraform/vault.tf.template ]; then
        cp -a /vault/terraform/vault.tf.template /config/vault/terraform/vault.tf.template
    fi
    if [ ! -d /data/vault/terraform ]; then
        mkdir /data/vault/terraform
    fi
    /usr/bin/tempio -conf $CONFIG_PATH -template /config/vault/terraform/vault.tf.template -out /data/vault/terraform/vault.tf

    cd /data/vault/terraform
    terraform init
    terraform apply -auto-approve
}

admin_user () {
    if [ "$CREATE_ADMIN_USER" = "true" ]; then
        bashio::log.info "Creating user ${VAULT_ADMIN_USER}"
        vault write auth/userpass/users/${VAULT_ADMIN_USER} password=${VAULT_ADMIN_PASSWORD} policies=super-admin
    else
        bashio::log.info "Deleting user ${VAULT_ADMIN_USER}" #fixme me yeah it won't work if the user change in the meantime
        vault delete auth/userpass/users/${VAULT_ADMIN_USER}
    fi
}

main() {
    # bashio::log.trace "${FUNCNAME[0]}"
    # bashio::log.info "Seconds between each quotes is set to: ${sleep}"
    if [ "$UNSAFE_SAVE_INI" = "true" ] ; then
        wait_ready
        wait_initialized
        wait_migrated
        wait_unsealed
        wait_root_token
        export VAULT_TOKEN="$(echo $output | jq -r .root_token)"
        echo "* wait 5 seconds (raft election)"
        sleep 5
        terraform_vault
        admin_user
    fi
    
    while true; do
        sleep 120
    done
}
main "$@"

