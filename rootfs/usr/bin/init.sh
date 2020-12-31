#!/usr/bin/env bashio

# init vars
CONFIG_PATH=/data/options.json
DISABLE_TLS="$(bashio::config 'disable_tls')"
UNSAFE_SAVE_INI="$(bashio::config 'unsafe_auto_init')"
VAULT_ADMIN_USER="$(bashio::config 'vault_admin_user')"
VAULT_ADMIN_PASSWORD="$(bashio::config 'vault_admin_password')"
CREATE_ADMIN_USER="$(bashio::config 'create_admin_user')"
AUTO_PROVISION="$(bashio::config 'auto_provision')"
PROVISION_TOKEN="$(bashio::config 'provision_token')"
PGP_KEYS="$(bashio::config 'pgp_keys')"
INI_PATH="/data/vault/vault.ini"
VAULT_TOKEN=""
output=""

mkdir -p /config/vault/terraform 2>/dev/null || true

if [ "$DISABLE_TLS" = 'false' ] ; then 
  scheme="https://"
  export VAULT_SKIP_VERIFY=1
else
  scheme="http://"
fi
export VAULT_ADDR="${scheme}localhost:8200"

# ready
wait_ready() {
    echo -ne "* Waiting for vault to be ready: "
    while [ -z "$(vault status -format json 2>/dev/null)" ]; do 
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
            echo "$output" > $INI_PATH
        fi 
    fi
    else 
        echo "* vault already initialized"
        if [ -f $INI_PATH ] ; then
            output=$(cat $INI_PATH)
            if [ -z "$output" ]; then
                echo "* no ini file : error"
                echo "* sleep 120 seconds"
                sleep 120
                exit 1
            fi
        fi
    fi
}

# migrated
wait_migrated() {
    if [ "$(vault status -format json | jq .migration)" = "true" ] ; then
    echo "* migrating"
        for a in $(echo "$output" | jq -r '.unseal_keys_b64 | .[]') ; do 
        vault operator unseal -migrate "$a" >/dev/null
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
    bashio::log.info "Wait unsealead"
    local keys=""
    if [ "$(vault status -format json | jq .sealed)" = "true" ] ; then
        echo "* Vault is sealed"

        # if [ $output = "" ] && [ $UNSAFE_SAVE_INI = "true" ]; then 
        #     bashio::log.info "empty output rekey locally"
        #     vault operator rekey -format json -init

        keys=$(echo "$output" | jq -r '.unseal_keys_b64 | .[]')
        if [ -n "$keys" ]; then
            echo "* we have keys, unsealing vault"
            for a in $(echo "$output" | jq -r '.unseal_keys_b64 | .[]') ; do 
            vault operator unseal "$a" >/dev/null
            done
            if [ "$(vault status -format json | jq .sealed)" = "true" ] ; then
                echo "* unseal failed : exiting"
                exit 1
            else 
                echo "* unseal done"
            fi
        else 
            echo "* we wait until its manually (or auto) unsealed"
            while [ "$(vault status -format json | jq .sealed)" = "true" ] ; do
              sleep 10
              bashio::log.info "Waiting 10s for manual unseal"
            done
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
    bashio::log.info "Applying terraform"
    if [ ! -f /config/vault/terraform/vault.tf.template ]; then
        cp -a /vault/terraform/vault.tf.template /config/vault/terraform/vault.tf.template
    fi
    if [ ! -d /data/vault/terraform ]; then
        mkdir /data/vault/terraform
    fi
    /usr/bin/tempio -conf $CONFIG_PATH -template /config/vault/terraform/vault.tf.template -out /data/vault/terraform/vault.tf
    if [ -z "$VAULT_TOKEN" ]; then
        if [ -n "$PROVISION_TOKEN" ]; then
            bashio::log.info "Using provision token"
            VAULT_TOKEN=$PROVISION_TOKEN
            export VAULT_TOKEN
        else
            echo "* no provision token no terraform"
            return
        fi
    else
        bashio::log.info "We have a vault token $VAULT_TOKEN"
    fi
    cd /data/vault/terraform || return
    terraform init
    terraform apply -auto-approve
}

admin_user () {
    if [ "$CREATE_ADMIN_USER" = "true" ]; then
        bashio::log.info "Creating user ${VAULT_ADMIN_USER}"
        vault write "auth/userpass/users/${VAULT_ADMIN_USER}" password="${VAULT_ADMIN_PASSWORD}" policies=super-admin
    else
        if [ -n "${VAULT_ADMIN_USER}" ] ; then
            bashio::log.info "Deleting user ${VAULT_ADMIN_USER}" #fixme me yeah it won't work if the user change in the meantime
            vault delete "auth/userpass/users/${VAULT_ADMIN_USER}"
        fi
    fi
}

vault_rekey () {
    echo "* starting vault rekey"
    vault operator rekey -cancel 2>/dev/null >/dev/null || true
    nonce=$(vault operator rekey -format json -pgp-keys "${PGP_KEYS}" -key-shares=1 -key-threshold=1 -init | jq .nonce -r)
    for unseal_key in $(echo "$output" | jq -r '.unseal_keys_b64 | .[]') ; do 
        answer=$(vault operator rekey -format json -nonce "$nonce" "$unseal_key")
        vault_answer=$(echo "$answer"| jq .keys_base64)
        if [ "$vault_answer" != "null" ]; then
          echo "* rekey done"
          echo "$answer" > /data/vault/vault-ini.json
          return
        fi
    done
}

vault_retoken () {
    echo "* starting vault retoken"
    vault operator generate-root -cancel 2>/dev/null >/dev/null || true
    nonce=$(vault operator generate-root -format json -pgp-key "${PGP_KEYS}" -init | jq .nonce -r)
    for unseal_key in $(echo "$output" | jq -r '.unseal_keys_b64 | .[]') ; do 
        answer=$(vault operator generate-root -format json -nonce "$nonce" "$unseal_key")
        vault_answer=$(echo "$answer"| jq -r .encoded_root_token)
        complete=$(echo "$answer"| jq -r .complete)
        if [ "$vault_answer" != "" ] && [ "$complete" = "true" ]; then
          echo "* retoken done"
          echo "$answer" > /data/vault/vault-ini-token.json
          echo "* revoke old token (!)"
          VAULT_TOKEN="$(echo "$output" | jq -r .root_token)"
          export VAULT_TOKEN
          vault token revoke "$VAULT_TOKEN"
          # unset token it won't work anymore
          VAULT_TOKEN=""
          # delete the file it won't work anymore
          rm $INI_PATH
          return
        fi
    done
}

main() {
    # bashio::log.trace "${FUNCNAME[0]}"
    # bashio::log.info "Seconds between each quotes is set to: ${sleep}"
    if [ "$UNSAFE_SAVE_INI" = "true" ] && [ "$PGP_KEYS" = "null" ] ; then
        wait_ready
        wait_initialized
        wait_migrated
        wait_unsealed
        wait_root_token
        VAULT_TOKEN="$(echo "$output" | jq -r .root_token)"
        export VAULT_TOKEN
        echo "* wait 10 seconds (raft election)"
        sleep 10
    fi
    if [ ! "$PGP_KEYS" = "null" ]; then
        wait_ready
        if [ "$(vault status -format json | jq .initialized)" = "false" ] ; then 
           vault operator init -format json -pgp-keys "${PGP_KEYS}" -root-token-pgp-key "${PGP_KEYS}" -key-shares=1 -key-threshold=1 > /data/vault/vault-ini.json
           # fixme check output        
        else
           if [ -f /data/vault/vault-ini.json ]; then
             echo "* already initialized, nothing to do"
           else 
             echo "* already initialized, but no vault-ini found, try migrating"
             wait_initialized
             wait_unsealed
             # wait election
             echo "* wait for the raft election (15s)"
             sleep 15
             vault_retoken
             vault_rekey
           fi
        fi
        bashio::log.info "unseal keys and root token should be in /data/vault/vault-ini.json and  /data/vault/vault-ini-token.json (encrypted for $PGP_KEYS) :"
        bashio::log.info "$(cat /data/vault/vault-ini.json)"
        bashio::log.info "$(cat /data/vault/vault-ini-token.json)"
    fi
    if [ "$AUTO_PROVISION" = "true" ]; then
        wait_initialized
        wait_unsealed
        terraform_vault
        admin_user
    fi
    while true; do
        sleep 120
    done
}
main "$@"

